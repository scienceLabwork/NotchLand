//
//  NowPlayingService.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Observable wrapper around MediaRemote. Tracks the current "Now Playing"
//  item across the system (Music, Spotify, Safari, Chrome, Podcasts, …) and
//  publishes a normalized `Track` that the UI can render.
//
//  All MediaRemote IPC is proxied through `MediaRemoteHelper`, an
//  Apple-signed swift subprocess — see that file for the why.
//

import AppKit
import Combine
import Foundation

@MainActor
final class NowPlayingService: ObservableObject {
    struct Track: Equatable {
        var title: String
        var artist: String
        var album: String?
        var artwork: NSImage?
        var duration: TimeInterval
        var elapsedAtTimestamp: TimeInterval
        var timestamp: Date
        var playbackRate: Double

        var isPlaying: Bool { playbackRate > 0.01 }

        /// Live-extrapolated elapsed time at the moment of the call.
        func elapsed(at instant: Date = Date()) -> TimeInterval {
            let drift = isPlaying
                ? max(0, instant.timeIntervalSince(timestamp)) * playbackRate
                : 0
            let raw = elapsedAtTimestamp + drift
            if duration > 0 {
                return min(max(0, raw), duration)
            }
            return max(0, raw)
        }

        func progress(at instant: Date = Date()) -> Double {
            guard duration > 0 else { return 0 }
            return min(1, max(0, elapsed(at: instant) / duration))
        }
    }

    @Published private(set) var track: Track?

    private static let futureTimestampTolerance: TimeInterval = 2

    private let helper = MediaRemoteHelper()
    private var cancellable: AnyCancellable?
    private var lastArtworkBase64: String?
    private var pendingSeek: PendingSeek?

    private static let seekReconciliationWindow: TimeInterval = 0.9

    private struct PendingSeek {
        var elapsed: TimeInterval
        var timestamp: Date
    }

    init() {
        cancellable = helper.$info
            .receive(on: DispatchQueue.main)
            .sink { [weak self] info in
                MainActor.assumeIsolated {
                    self?.applyInfo(info)
                }
            }
    }

    private func applyInfo(_ info: [String: Any]) {
        let now = Date()
        let title = (info["title"] as? String) ?? ""
        let artist = (info["artist"] as? String) ?? ""

        if title.isEmpty && artist.isEmpty {
            if track != nil { track = nil }
            return
        }

        let album = info["album"] as? String
        let previousTrack = track
        let isSameItem = previousTrack.map {
            Self.isSameMediaItem(
                $0,
                title: title,
                artist: artist,
                album: album
            )
        } ?? false

        let incomingDuration = Self.timeInterval(from: info["duration"])
        let incomingElapsed = Self.timeInterval(from: info["elapsed"])
        let duration: TimeInterval
        if let incomingDuration, incomingDuration > 0 {
            duration = incomingDuration
        } else if isSameItem, let previousTrack, previousTrack.duration > 0 {
            duration = previousTrack.duration
        } else {
            duration = 0
        }

        // Helper sends timestamp as seconds since reference date.
        let incomingTimestamp = Self.timeInterval(from: info["timestamp"])
            .map { Date(timeIntervalSinceReferenceDate: $0) }
        let rawRate = Self.timeInterval(from: info["rate"]) ?? 1
        let isPlayingFlag = (info["isPlaying"] as? Bool) ?? (rawRate > 0)
        let playbackRate = isPlayingFlag ? max(rawRate, 1) : 0

        var timestamp = Self.timelineTimestamp(incomingTimestamp, now: now)
        var elapsed: TimeInterval
        if let incomingElapsed, incomingElapsed.isFinite, incomingElapsed >= 0 {
            elapsed = Self.clampedElapsed(incomingElapsed, duration: duration)
        } else if isSameItem, let previousTrack {
            elapsed = Self.clampedElapsed(previousTrack.elapsed(at: now), duration: duration)
        } else {
            elapsed = 0
        }

        reconcilePendingSeek(
            now: now,
            isSameItem: isSameItem,
            duration: duration,
            playbackRate: playbackRate,
            elapsed: &elapsed,
            timestamp: &timestamp
        )

        let artwork: NSImage?
        if let b64 = info["artwork"] as? String {
            if b64 == lastArtworkBase64 {
                artwork = track?.artwork  // unchanged — reuse the existing image
            } else if let data = Data(base64Encoded: b64), let img = NSImage(data: data) {
                lastArtworkBase64 = b64
                artwork = img
            } else {
                artwork = track?.artwork
            }
        } else {
            lastArtworkBase64 = nil
            artwork = nil
        }

        track = Track(
            title: title,
            artist: artist,
            album: (album?.isEmpty == false) ? album : nil,
            artwork: artwork,
            duration: duration,
            elapsedAtTimestamp: elapsed,
            timestamp: timestamp,
            playbackRate: playbackRate
        )
    }

    private static func isSameMediaItem(
        _ track: Track,
        title: String,
        artist: String,
        album: String?
    ) -> Bool {
        track.title == title
            && track.artist == artist
            && track.album == ((album?.isEmpty == false) ? album : nil)
    }

    private static func timeInterval(from value: Any?) -> TimeInterval? {
        switch value {
        case let value as TimeInterval:
            value.isFinite ? value : nil
        case let value as NSNumber:
            value.doubleValue.isFinite ? value.doubleValue : nil
        case let value as String:
            Double(value).flatMap { $0.isFinite ? $0 : nil }
        default:
            nil
        }
    }

    private static func timelineTimestamp(_ timestamp: Date?, now: Date) -> Date {
        guard let timestamp else { return now }
        guard timestamp.timeIntervalSinceReferenceDate > 0 else { return now }
        guard timestamp.timeIntervalSince(now) <= futureTimestampTolerance else { return now }
        return timestamp
    }

    private static func clampedElapsed(
        _ elapsed: TimeInterval,
        duration: TimeInterval
    ) -> TimeInterval {
        guard duration > 0 else { return max(0, elapsed) }
        return min(max(0, elapsed), duration)
    }

    // MARK: - Commands

    func togglePlayPause() {
        helper.send("toggle")
    }

    func nextTrack() {
        helper.send("next")
    }

    func previousTrack() {
        helper.send("previous")
    }

    func seek(to elapsedTime: TimeInterval) {
        guard var current = track, current.duration > 0 else { return }
        let elapsed = Self.clampedElapsed(elapsedTime, duration: current.duration)
        current.elapsedAtTimestamp = elapsed
        current.timestamp = Date()
        pendingSeek = PendingSeek(elapsed: elapsed, timestamp: current.timestamp)
        track = current
        helper.send("seek:\(elapsed)")
    }

    private func reconcilePendingSeek(
        now: Date,
        isSameItem: Bool,
        duration: TimeInterval,
        playbackRate: Double,
        elapsed: inout TimeInterval,
        timestamp: inout Date
    ) {
        guard let pendingSeek else { return }
        guard isSameItem,
              duration > 0,
              now.timeIntervalSince(pendingSeek.timestamp) < Self.seekReconciliationWindow else {
            self.pendingSeek = nil
            return
        }

        let drift = playbackRate > 0.01
            ? max(0, now.timeIntervalSince(pendingSeek.timestamp)) * playbackRate
            : 0
        let optimisticElapsed = Self.clampedElapsed(
            pendingSeek.elapsed + drift,
            duration: duration
        )

        if abs(elapsed - optimisticElapsed) > 0.45 {
            elapsed = optimisticElapsed
            timestamp = now
        } else {
            self.pendingSeek = nil
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
