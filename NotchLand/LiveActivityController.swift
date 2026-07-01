//
//  LiveActivityController.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  One compact chip beside the notch at a time, newest wins (same policy as
//  the HUD queue). Sources (audio connect, timer, downloads) post,
//  update by re-posting the same id, and end activities.
//

import Combine
import Foundation

struct LiveActivity: Identifiable, Equatable {
    enum Kind: Equatable {
        case audioDevice(name: String, batteryPercent: Int?)
        case timer(remaining: TimeInterval)
        case download(fileName: String)
    }

    let id: UUID
    let kind: Kind
    var title: String
    var detail: String?
    var progress: Double?

    init(id: UUID = UUID(), kind: Kind, title: String, detail: String?, progress: Double?) {
        self.id = id
        self.kind = kind
        self.title = title
        self.detail = detail
        self.progress = progress
    }

    var branchKey: String { "activity" }
}

@MainActor
final class LiveActivityController: ObservableObject {
    @Published private(set) var current: LiveActivity?

    private let settings: NotchSettings

    init(settings: NotchSettings) {
        self.settings = settings
    }

    func post(_ activity: LiveActivity) {
        guard settings.liveActivitiesEnabled else { return }
        current = activity
    }

    func end(_ id: UUID) {
        if current?.id == id {
            current = nil
        }
    }

    func endAll() {
        current = nil
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
