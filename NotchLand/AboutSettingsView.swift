//
//  AboutSettingsView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Apple-style About pane. Centered presentation, no Form chrome,
//  no external links. Copyright is read from Info.plist so it stays
//  in sync with the build settings entry.
//

import AppKit
import SwiftUI

struct AboutSettingsView: View {
    var onIconClick: () -> Void = {}

    @EnvironmentObject private var updater: UpdaterController
    @EnvironmentObject private var settings: NotchSettings

    private var versionLine: String {
        let dict = Bundle.main.infoDictionary
        let short = dict?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = dict?["CFBundleVersion"] as? String ?? "1"
        return "Version \(short) (\(build))"
    }

    private var copyrightLine: String {
        let raw = Bundle.main.infoDictionary?["NSHumanReadableCopyright"] as? String
        let trimmed = raw?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let trimmed, !trimmed.isEmpty { return trimmed }
        return "Copyright © 2026 Rudra Shah. All rights reserved."
    }

    private var appIcon: NSImage {
        let iconNames = [
            Bundle.main.object(forInfoDictionaryKey: "CFBundleIconName") as? String,
            Bundle.main.object(forInfoDictionaryKey: "CFBundleIconFile") as? String,
            "NotchLand-logo",
            NSImage.applicationIconName
        ].compactMap { $0 }

        for name in iconNames {
            if let image = NSImage(named: NSImage.Name(name)), image.isValid {
                return image
            }
        }

        for name in iconNames {
            let resourceName = name.replacingOccurrences(of: ".icns", with: "")
            if let url = Bundle.main.url(forResource: resourceName, withExtension: "icns"),
               let image = NSImage(contentsOf: url),
               image.isValid {
                return image
            }
        }

        if let fallback = NSApp.applicationIconImage, fallback.isValid {
            return fallback
        }

        return NSImage(systemSymbolName: "app.fill", accessibilityDescription: "NotchLand") ?? NSImage()
    }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 24)

            Image(nsImage: appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 96, height: 96)
                .onTapGesture(perform: onIconClick)
                .accessibilityHidden(true)

            Text("NotchLand")
                .font(.title2.weight(.semibold))
                .padding(.top, 14)

            Text("Expand what your notch can do.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Text(versionLine)
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .padding(.top, 10)

            Button("Check for Updates…") {
                updater.checkForUpdates()
            }
            .controlSize(.small)
            .padding(.top, 14)

            Toggle("Automatically check for updates", isOn: Binding(
                get: { settings.autoUpdateCheckEnabled },
                set: { updater.setAutomaticChecks($0) }
            ))
            .toggleStyle(.checkbox)
            .controlSize(.small)
            .padding(.top, 6)

            Spacer(minLength: 24)

            Text(copyrightLine)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.bottom, 20)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .multilineTextAlignment(.center)
    }
}

#if DEBUG
#Preview("About Settings") {
    NotchPreviewContainer {
        AboutSettingsView()
            .frame(width: 510, height: 520)
    }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
