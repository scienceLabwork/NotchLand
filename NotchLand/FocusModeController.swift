//
//  FocusModeController.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Exposes the compact Focus alert presentation. Uses the system distributed
//  Do Not Disturb notifications instead of INFocusStatusCenter so the app does
//  not need Apple's Communication Notifications entitlement.
//

import Combine
import Foundation

@MainActor
final class FocusModeController: NSObject, ObservableObject {
    enum AuthorizationStatus {
        case monitoring
        case stopped
    }

    struct Presentation: Equatable {
        let isActive: Bool

        var branchKey: String {
            "focus-mode"
        }
    }

    private static let totalPresentationDuration: TimeInterval = 3.4
    private static let dismissDelay = max(
        0,
        totalPresentationDuration - BatteryPresentationTiming.collapseDuration
    )

    @Published private(set) var currentPresentation: Presentation?
    @Published private(set) var isFocusActive = false
    @Published private(set) var authorizationStatus: AuthorizationStatus = .stopped

    private let notificationCenter = DistributedNotificationCenter.default()
    private var dismissTask: Task<Void, Never>?

    override init() {
        super.init()
    }

    deinit {
        notificationCenter.removeObserver(self)
    }

    func start() {
        guard authorizationStatus != .monitoring else { return }

        notificationCenter.addObserver(
            self,
            selector: #selector(handleFocusEnabled(_:)),
            name: .focusModeEnabled,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        notificationCenter.addObserver(
            self,
            selector: #selector(handleFocusDisabled(_:)),
            name: .focusModeDisabled,
            object: nil,
            suspensionBehavior: .deliverImmediately
        )

        authorizationStatus = .monitoring
    }

    func stop() {
        notificationCenter.removeObserver(self, name: .focusModeEnabled, object: nil)
        notificationCenter.removeObserver(self, name: .focusModeDisabled, object: nil)
        dismissTask?.cancel()
        dismissTask = nil
        currentPresentation = nil
        isFocusActive = false
        authorizationStatus = .stopped
    }

    func debugShowFocusOn() {
        showFocus(isActive: true)
    }

    func requestAuthorization() {
        start()
    }

    func dismissCurrentPresentation() {
        dismissTask?.cancel()
        dismissTask = nil
        currentPresentation = nil
    }

    @objc private func handleFocusEnabled(_ notification: Notification) {
        showFocus(isActive: true)
    }

    @objc private func handleFocusDisabled(_ notification: Notification) {
        showFocus(isActive: false)
    }

    private func showFocus(isActive: Bool) {
        dismissTask?.cancel()
        dismissTask = nil

        self.isFocusActive = isActive
        currentPresentation = Presentation(isActive: isActive)
        scheduleDismiss()
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        let delayNanos = UInt64(Self.dismissDelay * 1_000_000_000)
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard let self, !Task.isCancelled else { return }
            self.currentPresentation = nil
            self.dismissTask = nil
        }
    }
}

private extension Notification.Name {
    static let focusModeEnabled = Notification.Name("_NSDoNotDisturbEnabledNotification")
    static let focusModeDisabled = Notification.Name("_NSDoNotDisturbDisabledNotification")
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
