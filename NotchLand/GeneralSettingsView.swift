//
//  GeneralSettingsView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//

import SwiftUI

struct GeneralSettingsView: View {
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var focusMode: FocusModeController

    var body: some View {
        Form {
            Section {
                Toggle("Show NotchLand", isOn: $settings.showNotch)
                Toggle("Launch at Login", isOn: $settings.launchAtLogin)
            }

            Section("Features") {
                Toggle("AirDrop", isOn: $settings.airDropEnabled)
                Text("Drag files onto the notch to AirDrop them.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Focus") {
                LabeledContent("Focus Detection") {
                    Text(focusDetectionLabel)
                        .foregroundStyle(focusDetectionColor)
                }

                LabeledContent("Current Focus") {
                    Text(focusMode.isFocusActive ? "On" : "Off")
                        .foregroundStyle(focusMode.isFocusActive ? .blue : .secondary)
                }

                Button("Restart Focus Monitor") {
                    focusMode.stop()
                    focusMode.start()
                }
            }
        }
        .formStyle(.grouped)
    }

    private var focusDetectionLabel: String {
        switch focusMode.authorizationStatus {
        case .monitoring: "Listening"
        case .stopped: "Stopped"
        }
    }

    private var focusDetectionColor: Color {
        switch focusMode.authorizationStatus {
        case .monitoring: .green
        case .stopped: .secondary
        }
    }
}

#if DEBUG
#Preview("General Settings") {
    NotchPreviewContainer {
        GeneralSettingsView()
            .frame(width: 510, height: 520)
    }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
