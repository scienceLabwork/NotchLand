//
//  BehaviorSettingsView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//

import AppKit
import SwiftUI

struct BehaviorSettingsView: View {
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var hud: HUDController

    var body: some View {
        Form {
            Section("Hover") {
                Toggle("Hover to Expand", isOn: $settings.hoverToExpand)
                Toggle("Click to Expand", isOn: $settings.openOnClick)
                Toggle("Auto-collapse on Mouse Exit", isOn: $settings.autoCollapse)
            }

            Section("Screen Lock") {
                Toggle("Lock & Unlock Animation", isOn: $settings.lockUnlockAnimationEnabled)
                Text("Flashes a padlock in the notch when you lock your Mac, then plays an unlock animation when you return.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("HUD") {
                Toggle("Show HUD on Notch", isOn: showHUDOnNotchBinding)

                if settings.showHUDOnNotch, !hud.isAccessibilityTrusted {
                    HStack(spacing: 8) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                        Text("Accessibility permission is required for volume, brightness, and keyboard brightness keys.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button("Open Settings") {
                            openAccessibilitySettings()
                        }
                        .buttonStyle(.bordered)
                    }
                } else {
                    Text("Shows volume, brightness, keyboard brightness, and contrast changes inside the notch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var showHUDOnNotchBinding: Binding<Bool> {
        Binding {
            settings.showHUDOnNotch
        } set: { isEnabled in
            hud.setShowHUDOnNotch(isEnabled)
        }
    }

    private func openAccessibilitySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

#if DEBUG
#Preview("Behavior Settings") {
    NotchPreviewContainer {
        BehaviorSettingsView()
            .frame(width: 510, height: 520)
    }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
