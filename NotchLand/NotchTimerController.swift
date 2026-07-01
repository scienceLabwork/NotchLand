//
//  NotchTimerController.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Quick timer started from the expanded notch. Posts/updates one chip per
//  second; plays a system sound when done.
//

import AppKit
import Combine
import Foundation

@MainActor
final class NotchTimerController: ObservableObject {
    @Published private(set) var endDate: Date?

    private let activities: LiveActivityController
    private var activityID = UUID()
    private var tick: Task<Void, Never>?

    init(activities: LiveActivityController) {
        self.activities = activities
    }

    var isRunning: Bool { endDate != nil }

    func start(minutes: Int) {
        cancel()
        endDate = Date.now.addingTimeInterval(TimeInterval(minutes * 60))
        activityID = UUID()
        tick = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                guard let self, let end = self.endDate else { return }
                let remaining = end.timeIntervalSinceNow
                if remaining <= 0 {
                    self.finish()
                    return
                }
                self.postChip(remaining: remaining)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
            }
        }
    }

    func cancel() {
        tick?.cancel()
        tick = nil
        activities.end(activityID)
        endDate = nil
    }

    private func postChip(remaining: TimeInterval) {
        let total = Int(remaining.rounded())
        let detail = String(format: "%d:%02d", total / 60, total % 60)
        activities.post(LiveActivity(
            id: activityID,
            kind: .timer(remaining: remaining),
            title: "Timer",
            detail: detail,
            progress: nil
        ))
    }

    private func finish() {
        endDate = nil
        let finishedID = activityID
        activities.post(LiveActivity(
            id: finishedID,
            kind: .timer(remaining: 0),
            title: "Time's up",
            detail: nil,
            progress: nil
        ))
        NSSound(named: "Glass")?.play()
        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            self?.activities.end(finishedID)
        }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
