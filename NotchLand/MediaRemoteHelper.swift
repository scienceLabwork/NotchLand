//
//  MediaRemoteHelper.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  macOS 15.4+ stripped Now-Playing dict contents from any non-Apple-signed
//  process — our app gets `keys=0` from `MRMediaRemoteGetNowPlayingInfo`
//  even with sandbox/Hardened Runtime off. The standard workaround used by
//  Sleeve / Soundbox / nowplaying-cli is to spawn an Apple-signed subprocess
//  (the swift driver) that inherits Apple's code-signing identity and gets
//  the data, then pipe a JSON stream back.
//
//  This class:
//    * Writes a small Swift helper script to a temp file at startup.
//    * Spawns `/usr/bin/swift <script>` and reads JSON lines from its stdout.
//    * Republishes each parsed dict on the main actor for NowPlayingService.
//    * Restarts the helper if it dies (e.g. swift toolchain restart).
//

import AppKit
import Combine
import Foundation

@MainActor
final class MediaRemoteHelper: ObservableObject {
    /// Most recently received now-playing dict, normalized to `String: Any`.
    /// Empty dict (or never-emitted) means nothing playing.
    @Published private(set) var info: [String: Any] = [:]

    private var process: Process?
    private var stdoutPipe: Pipe?
    private var stdinPipe: Pipe?
    private var buffer = Data()
    private var restartTask: Task<Void, Never>?
    private var isStopping = false

    init() {
        guard !AppRuntime.isXcodePreview else { return }
        spawn()
    }

    deinit {
        isStopping = true
        process?.terminate()
    }

    func stop() {
        isStopping = true
        restartTask?.cancel()
        process?.terminate()
        process = nil
    }

    // MARK: - Subprocess

    private func spawn() {
        let scriptURL: URL
        do {
            scriptURL = try writeScript()
        } catch {
            NSLog("[NotchLand] helper writeScript failed: \(error)")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/bin/swift")
        proc.arguments = [scriptURL.path]

        let outPipe = Pipe()
        let errPipe = Pipe()
        let inPipe = Pipe()  // we never write — closed by kernel when we die, helper sees EOF
        proc.standardOutput = outPipe
        proc.standardError = errPipe
        proc.standardInput = inPipe

        outPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty else { return }
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.consume(chunk)
                }
            }
        }

        // Drain stderr so the pipe doesn't fill and block the helper. Surface only.
        errPipe.fileHandleForReading.readabilityHandler = { handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty,
                  let text = String(data: chunk, encoding: .utf8)?
                    .trimmingCharacters(in: .whitespacesAndNewlines),
                  !text.isEmpty else { return }
            NSLog("[NotchLand] helper stderr: \(text)")
        }

        proc.terminationHandler = { [weak self] _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.handleTermination()
                }
            }
        }

        do {
            try proc.run()
            process = proc
            stdoutPipe = outPipe
            stdinPipe = inPipe
            NSLog("[NotchLand] helper spawned pid=\(proc.processIdentifier)")
        } catch {
            NSLog("[NotchLand] helper spawn failed: \(error)")
            scheduleRestart()
        }
    }

    /// Send a transport command to the helper. Recognized: "play", "pause",
    /// "toggle", "stop", "next", "previous", and "seek:<seconds>". Silently
    /// no-ops if the helper is restarting.
    func send(_ command: String) {
        guard let pipe = stdinPipe else { return }
        let line = command + "\n"
        guard let data = line.data(using: .utf8) else { return }
        do {
            try pipe.fileHandleForWriting.write(contentsOf: data)
        } catch {
            NSLog("[NotchLand] helper send failed: \(error)")
        }
    }

    private func handleTermination() {
        process = nil
        stdoutPipe = nil
        stdinPipe = nil
        buffer.removeAll()
        guard !isStopping else { return }
        scheduleRestart()
    }

    private func scheduleRestart() {
        restartTask?.cancel()
        restartTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 1_500_000_000)
            guard !Task.isCancelled, let self, !self.isStopping else { return }
            self.spawn()
        }
    }

    // MARK: - Stream parsing

    private func consume(_ chunk: Data) {
        buffer.append(chunk)
        let newline: UInt8 = 0x0A
        while let idx = buffer.firstIndex(of: newline) {
            let lineRange = buffer.startIndex..<idx
            let line = buffer.subdata(in: lineRange)
            buffer.removeSubrange(buffer.startIndex...idx)
            guard !line.isEmpty else { continue }
            handleLine(line)
        }
    }

    private func handleLine(_ data: Data) {
        guard let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return
        }
        info = dict
    }

    // MARK: - Helper script

    private func writeScript() throws -> URL {
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("NotchLand_now_playing_helper.swift")
        try Self.helperSource.write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// Helper script source. Runs in a separate Apple-signed `swift` process
    /// so mediaremoted releases the full Now-Playing dict. Emits one JSON
    /// object per stdout line on every change.
    private static let helperSource: String = #"""
    import AppKit
    import Foundation

    setlinebuf(stdout)

    let url = URL(fileURLWithPath: "/System/Library/PrivateFrameworks/MediaRemote.framework")
    guard let bundle = CFBundleCreate(kCFAllocatorDefault, url as CFURL) else {
        FileHandle.standardError.write(Data("NotchLand-helper: bundle nil\n".utf8))
        exit(1)
    }

    typealias GetInfoFn = @convention(c) (DispatchQueue, @escaping ([String: Any]) -> Void) -> Void
    typealias RegisterFn = @convention(c) (DispatchQueue) -> Void
    typealias IsPlayingFn = @convention(c) (DispatchQueue, @escaping (Bool) -> Void) -> Void
    typealias SendCommandFn = @convention(c) (Int, [AnyHashable: Any]?) -> Bool
    typealias SetElapsedTimeFn = @convention(c) (Double) -> Void

    guard let infoSym = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteGetNowPlayingInfo" as CFString),
          let regSym = CFBundleGetFunctionPointerForName(bundle, "MRMediaRemoteRegisterForNowPlayingNotifications" as CFString) else {
        FileHandle.standardError.write(Data("NotchLand-helper: missing symbols\n".utf8))
        exit(2)
    }

    let getInfo = unsafeBitCast(infoSym, to: GetInfoFn.self)
    let register = unsafeBitCast(regSym, to: RegisterFn.self)
    let getIsPlaying: IsPlayingFn? = CFBundleGetFunctionPointerForName(
        bundle, "MRMediaRemoteGetNowPlayingApplicationIsPlaying" as CFString
    ).map { unsafeBitCast($0, to: IsPlayingFn.self) }
    let sendCommand: SendCommandFn? = CFBundleGetFunctionPointerForName(
        bundle, "MRMediaRemoteSendCommand" as CFString
    ).map { unsafeBitCast($0, to: SendCommandFn.self) }
    let setElapsedTime: SetElapsedTimeFn? = CFBundleGetFunctionPointerForName(
        bundle, "MRMediaRemoteSetElapsedTime" as CFString
    ).map { unsafeBitCast($0, to: SetElapsedTimeFn.self) }

    let commandMap: [String: Int] = [
        "play": 0, "pause": 1, "toggle": 2, "stop": 3, "next": 4, "previous": 5
    ]

    @Sendable
    func number(_ value: Any?) -> Double? {
        switch value {
        case let value as Double:
            return value.isFinite ? value : nil
        case let value as NSNumber:
            let number = value.doubleValue
            return number.isFinite ? number : nil
        case let value as String:
            guard let number = Double(value), number.isFinite else { return nil }
            return number
        default:
            return nil
        }
    }

    @Sendable
    func referenceTimestamp(_ value: Any?) -> Double? {
        if let date = value as? Date {
            return date.timeIntervalSinceReferenceDate
        }

        guard let raw = number(value) else { return nil }
        if raw > Date.timeIntervalBetween1970AndReferenceDate {
            return raw - Date.timeIntervalBetween1970AndReferenceDate
        }
        return raw
    }

    @Sendable
    func emit() {
        getInfo(.main) { info in
            var out: [String: Any] = [:]
            if let v = info["kMRMediaRemoteNowPlayingInfoTitle"] as? String { out["title"] = v }
            if let v = info["kMRMediaRemoteNowPlayingInfoArtist"] as? String { out["artist"] = v }
            if let v = info["kMRMediaRemoteNowPlayingInfoAlbum"] as? String { out["album"] = v }
            if let v = number(info["kMRMediaRemoteNowPlayingInfoDuration"]) { out["duration"] = v }
            if let v = number(info["kMRMediaRemoteNowPlayingInfoElapsedTime"]) { out["elapsed"] = v }
            if let v = referenceTimestamp(info["kMRMediaRemoteNowPlayingInfoTimestamp"]) { out["timestamp"] = v }
            if let v = number(info["kMRMediaRemoteNowPlayingInfoPlaybackRate"]) { out["rate"] = v }
            if let v = info["kMRMediaRemoteNowPlayingInfoArtworkData"] as? Data {
                out["artwork"] = v.base64EncodedString()
            }
            // Track an `isPlaying` flag too — useful when rate is missing.
            getIsPlaying?(.main) { playing in
                out["isPlaying"] = playing
                if let json = try? JSONSerialization.data(withJSONObject: out),
                   let str = String(data: json, encoding: .utf8) {
                    print(str)
                }
            }
        }
    }

    register(.main)

    let names: [String] = [
        "kMRMediaRemoteNowPlayingInfoDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationIsPlayingDidChangeNotification",
        "kMRMediaRemoteNowPlayingApplicationDidChangeNotification",
        "kMRMediaRemoteNowPlayingPlaybackQueueChangedNotification",
    ]
    for name in names {
        NotificationCenter.default.addObserver(
            forName: Notification.Name(name), object: nil, queue: .main
        ) { _ in emit() }
    }

    // Periodic poll so the host keeps live elapsed/timestamp without depending
    // entirely on broadcasts (some sources don't fire frequently).
    let timer = Timer(timeInterval: 1.0, repeats: true) { _ in emit() }
    RunLoop.main.add(timer, forMode: .common)

    // Read stdin: each line is a command name. EOF == parent dead → exit.
    DispatchQueue.global().async {
        let stdin = FileHandle.standardInput
        var buf = Data()
        while true {
            let chunk = stdin.availableData
            if chunk.isEmpty { exit(0) }
            buf.append(chunk)
            while let idx = buf.firstIndex(of: 0x0A) {
                let line = buf.subdata(in: buf.startIndex..<idx)
                buf.removeSubrange(buf.startIndex...idx)
                let cmd = (String(data: line, encoding: .utf8) ?? "")
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                if cmd.hasPrefix("seek:"),
                   let seconds = Double(cmd.dropFirst(5)),
                   seconds.isFinite {
                    setElapsedTime?(max(0, seconds))
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.08) {
                        emit()
                    }
                } else if let code = commandMap[cmd] {
                    _ = sendCommand?(code, nil)
                }
            }
        }
    }

    emit()
    RunLoop.main.run()
    """#
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
