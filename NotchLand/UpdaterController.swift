//
//  UpdaterController.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Thin wrapper around Sparkle's standard updater so settings UI and the
//  menu bar item can trigger checks. Update installation requires a
//  Developer ID-signed build; until then "Check for Updates" still works
//  (it will report a feed error until the appcast is published).
//

import Combine
import Foundation
import Sparkle

@MainActor
final class UpdaterController: ObservableObject {
    private let controller: SPUStandardUpdaterController?
    private let settings: NotchSettings

    init(settings: NotchSettings) {
        self.settings = settings
        guard !AppRuntime.isXcodePreview else {
            controller = nil
            return
        }
        controller = SPUStandardUpdaterController(
            startingUpdater: true,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )
        controller?.updater.automaticallyChecksForUpdates = settings.autoUpdateCheckEnabled
    }

    var canCheckForUpdates: Bool { controller?.updater.canCheckForUpdates ?? false }

    func checkForUpdates() {
        controller?.checkForUpdates(nil)
    }

    func setAutomaticChecks(_ enabled: Bool) {
        controller?.updater.automaticallyChecksForUpdates = enabled
        settings.autoUpdateCheckEnabled = enabled
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
