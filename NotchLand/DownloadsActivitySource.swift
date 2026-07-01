//
//  DownloadsActivitySource.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Watches ~/Downloads for in-progress browser downloads (.download/
//  .crdownload/.part) and shows a single chip while any exist; ends it when
//  they finish. DispatchSource on the directory FD — no FSEvents complexity.
//

import Foundation

@MainActor
final class DownloadsActivitySource {
    private let activities: LiveActivityController
    private var source: (any DispatchSourceFileSystemObject)?
    private var activityID: UUID?
    private let downloadsURL = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first

    init(activities: LiveActivityController) {
        self.activities = activities
    }

    func start() {
        guard source == nil, let downloadsURL else { return }
        let fd = open(downloadsURL.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd, eventMask: .write, queue: .main
        )
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.scan() }
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        self.source = source
        scan()
    }

    func stop() {
        source?.cancel()
        source = nil
        if let activityID {
            activities.end(activityID)
        }
        activityID = nil
    }

    private func scan() {
        guard let downloadsURL else { return }
        let partials = ((try? FileManager.default.contentsOfDirectory(atPath: downloadsURL.path)) ?? [])
            .filter { name in
                name.hasSuffix(".download") || name.hasSuffix(".crdownload") || name.hasSuffix(".part")
            }
        if let first = partials.first {
            let display = (first as NSString).deletingPathExtension
            let id = activityID ?? UUID()
            activityID = id
            activities.post(LiveActivity(
                id: id,
                kind: .download(fileName: display),
                title: display,
                detail: partials.count > 1 ? "+\(partials.count - 1) more" : "Downloading",
                progress: nil
            ))
        } else if let id = activityID {
            activities.end(id)
            activityID = nil
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
