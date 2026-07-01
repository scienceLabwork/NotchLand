//
//  AppRuntime.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Process-level runtime checks used to keep Xcode previews from launching
//  menu-bar panels, system monitors, and update services.
//

import Foundation

enum AppRuntime {
    static var isXcodePreview: Bool {
        let environment = ProcessInfo.processInfo.environment

        if isEnabled(environment["XCODE_RUNNING_FOR_PREVIEWS"])
            || isEnabled(environment["XCODE_RUNNING_FOR_PLAYGROUNDS"]) {
            return true
        }

        if containsPreviewMarker(CommandLine.arguments.joined(separator: " ")) {
            return true
        }

        if let bundlePath = Bundle.main.bundleURL.path.removingPercentEncoding,
           containsPreviewMarker(bundlePath) {
            return true
        }

        return environment.contains { key, value in
            key.hasPrefix("XCODE_PREVIEW")
                || containsPreviewMarker(value)
        }
    }

    private static func isEnabled(_ value: String?) -> Bool {
        guard let value else { return false }
        switch value.lowercased() {
        case "1", "true", "yes":
            return true
        default:
            return false
        }
    }

    private static func containsPreviewMarker(_ value: String) -> Bool {
        let normalized = value.lowercased()
        return normalized.contains("__preview")
            || normalized.contains("/previews/")
            || normalized.contains("xcode previews")
            || normalized.contains("com.apple.dt.xcode.previews")
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
