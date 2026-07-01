//
//  ScreenLockController.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Exposes a compact lock/unlock alert presentation for the notch. Listens for
//  both session-active notifications and the system screen-lock distributed
//  notifications, so the locked glyph appears before the secure screen finishes
//  taking over and remains ready for the unlock animation.
//

import AppKit
import Combine
import Foundation

@MainActor
final class ScreenLockController: NSObject, ObservableObject {
    enum AuthorizationStatus {
        case monitoring
        case stopped
    }

    struct Presentation: Equatable {
        enum Phase: Equatable {
            /// Closed padlock held while the screen is locked.
            case locked
            /// Padlock springs open as the screen unlocks, then the notch retracts.
            case unlocking
        }

        let phase: Phase

        var branchKey: String {
            "screen-lock"
        }
    }

    /// How long the unlock branch stays up so the open-padlock bounce can play
    /// before the notch retracts in.
    private static let unlockHold: TimeInterval = 2.0

    @Published private(set) var currentPresentation: Presentation?
    @Published private(set) var authorizationStatus: AuthorizationStatus = .stopped

    private let settings: NotchSettings
    private let notificationCenter = DistributedNotificationCenter.default()
    private let workspaceCenter = NSWorkspace.shared.notificationCenter
    private var dismissTask: Task<Void, Never>?

    init(settings: NotchSettings) {
        self.settings = settings
        super.init()
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    func start() {
        guard authorizationStatus != .monitoring else { return }

        notificationCenter.addObserver(
            self,
            selector: #selector(handleScreenLocked(_:)),
            name: .screenIsLocked,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(handleScreenUnlocked(_:)),
            name: .screenIsUnlocked,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        workspaceCenter.addObserver(
            self,
            selector: #selector(handleSessionDidResignActive(_:)),
            name: NSWorkspace.sessionDidResignActiveNotification,
            object: nil
        )

        workspaceCenter.addObserver(
            self,
            selector: #selector(handleSessionDidBecomeActive(_:)),
            name: NSWorkspace.sessionDidBecomeActiveNotification,
            object: nil
        )

        authorizationStatus = .monitoring
    }

    func stop() {
        notificationCenter.removeObserver(self, name: .screenIsLocked, object: nil)
        notificationCenter.removeObserver(self, name: .screenIsUnlocked, object: nil)
        workspaceCenter.removeObserver(self, name: NSWorkspace.sessionDidResignActiveNotification, object: nil)
        workspaceCenter.removeObserver(self, name: NSWorkspace.sessionDidBecomeActiveNotification, object: nil)
        dismissTask?.cancel()
        dismissTask = nil
        currentPresentation = nil
        authorizationStatus = .stopped
    }

    func dismissCurrentPresentation() {
        dismissTask?.cancel()
        dismissTask = nil
        currentPresentation = nil
    }

    func debugShowLock() {
        // Mirrors the real lock: persists until an unlock (debug or system).
        presentLocked()
    }

    func debugShowUnlock() {
        presentUnlockFlow()
    }

    @objc private func handleScreenLocked(_ notification: Notification) {
        guard settings.lockUnlockAnimationEnabled else { return }
        presentLocked()
    }

    @objc private func handleScreenUnlocked(_ notification: Notification) {
        guard settings.lockUnlockAnimationEnabled else {
            // Feature off mid-cycle: make sure a lingering locked branch clears.
            dismissCurrentPresentation()
            return
        }
        presentUnlockFlow()
    }

    @objc private func handleSessionDidResignActive(_ notification: Notification) {
        guard settings.lockUnlockAnimationEnabled else { return }
        presentLocked()
    }

    @objc private func handleSessionDidBecomeActive(_ notification: Notification) {
        guard settings.lockUnlockAnimationEnabled else {
            dismissCurrentPresentation()
            return
        }
        presentUnlockFlow()
    }

    private func presentLocked() {
        present(Presentation(phase: .locked), hold: nil)
    }

    /// Unlock choreography: the held padlock springs open, then the notch
    /// returns to the normal collapsed surface.
    private func presentUnlockFlow() {
        if currentPresentation?.phase == .unlocking { return }
        present(Presentation(phase: .unlocking), hold: nil)
        let delayNanos = UInt64(Self.unlockHold * 1_000_000_000)
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard let self, !Task.isCancelled else { return }
            guard self.currentPresentation?.phase == .unlocking else { return }
            self.currentPresentation = nil
            self.dismissTask = nil
        }
    }

    /// Shows `presentation`; a non-nil `hold` schedules an automatic dismiss
    /// after that many seconds, while `nil` keeps it up until replaced/cleared.
    private func present(_ presentation: Presentation, hold: TimeInterval?) {
        dismissTask?.cancel()
        dismissTask = nil
        currentPresentation = presentation
        if let hold {
            scheduleDismiss(after: hold)
        }
    }

    private func scheduleDismiss(after hold: TimeInterval) {
        let delayNanos = UInt64(max(0, hold) * 1_000_000_000)
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard let self, !Task.isCancelled else { return }
            self.currentPresentation = nil
            self.dismissTask = nil
        }
    }
}

private extension Notification.Name {
    static let screenIsLocked = Notification.Name("com.apple.screenIsLocked")
    static let screenIsUnlocked = Notification.Name("com.apple.screenIsUnlocked")
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
