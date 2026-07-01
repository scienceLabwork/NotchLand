//
//  DebugSettingsView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Debug test surface. Compiled out unless NOTCHLAND_ENABLE_DEBUG_UI is
//  explicitly added to Swift Active Compilation Conditions.
//
//

#if NOTCHLAND_ENABLE_DEBUG_UI

import SwiftUI

struct DebugSettingsView: View {
    @EnvironmentObject var settings: NotchSettings
    @EnvironmentObject var appState: AppState
    @EnvironmentObject var hud: HUDController
    @EnvironmentObject var batteryAlerts: BatteryAlertController
    @EnvironmentObject var focusMode: FocusModeController
    @EnvironmentObject var screenLock: ScreenLockController
    @EnvironmentObject var countdown: EventCountdownController
    @EnvironmentObject var airDrop: AirDropController
    @EnvironmentObject var liveActivities: LiveActivityController
    @EnvironmentObject var notchTimer: NotchTimerController

    var body: some View {
        Form {
            Section("Factory") {
                Button(role: .destructive) {
                    resetToFactory()
                } label: {
                    Label("Reset to Factory", systemImage: "arrow.counterclockwise.circle.fill")
                        .frame(minWidth: 160)
                }
                .buttonStyle(.bordered)
            }

            Section("Battery") {
                HStack {
                    testButton("Charging", systemImage: "bolt.fill") {
                        showNotchIfNeeded()
                        batteryAlerts.debugShowCharging(percent: 50)
                    }

                    testButton("Charging 100%", systemImage: "bolt.fill") {
                        showNotchIfNeeded()
                        batteryAlerts.debugShowCharging(percent: 100)
                    }
                }

                HStack {
                    testButton("Low 20%", systemImage: "exclamationmark.circle.fill") {
                        showNotchIfNeeded()
                        batteryAlerts.debugShowLowBattery(percent: 20)
                    }

                    testButton("Low 10%", systemImage: "exclamationmark.triangle.fill") {
                        showNotchIfNeeded()
                        batteryAlerts.debugShowLowBattery(percent: 10)
                    }
                }
            }

            Section("Focus") {
                HStack {
                    testButton("Focus On", systemImage: "moon.fill") {
                        showNotchIfNeeded()
                        focusMode.debugShowFocusOn()
                    }
                }
            }

            Section("Screen Lock") {
                HStack {
                    testButton("Lock Flash", systemImage: "lock.fill") {
                        showNotchIfNeeded()
                        screenLock.debugShowLock()
                    }

                    testButton("Unlock", systemImage: "lock.open.fill") {
                        showNotchIfNeeded()
                        screenLock.debugShowUnlock()
                    }
                }
            }

            Section("AirDrop") {
                HStack {
                    testButton("Drop Zone", systemImage: "dot.radiowaves.left.and.right") {
                        showNotchIfNeeded()
                        airDrop.debugShowDropTarget()
                    }

                    testButton("Test Share", systemImage: "square.and.arrow.up") {
                        airDrop.shareViaAirDrop([debugShareFileURL()])
                    }

                    testButton("Close", systemImage: "xmark") {
                        airDrop.dragEnded()
                    }
                }
            }

            Section("HUD") {
                HStack {
                    testButton("Volume", systemImage: "speaker.wave.2.fill") {
                        showNotchIfNeeded()
                        hud.debugShow(.volume(level: 0.66, muted: false))
                    }

                    testButton("Muted", systemImage: "speaker.slash.fill") {
                        showNotchIfNeeded()
                        hud.debugShow(.volume(level: 0.4, muted: true))
                    }

                    testButton("Brightness", systemImage: "sun.max.fill") {
                        showNotchIfNeeded()
                        hud.debugShow(.brightness(level: 0.72))
                    }
                }

                HStack {
                    testButton("Keyboard", systemImage: "keyboard") {
                        showNotchIfNeeded()
                        hud.debugShow(.keyboardBrightness(level: 0.58))
                    }

                    testButton("Contrast", systemImage: "circle.lefthalf.filled") {
                        showNotchIfNeeded()
                        hud.debugShow(.contrast(level: 0.48))
                    }
                }
            }
        }
        .formStyle(.grouped)
    }

    private func resetToFactory() {
        hud.dismissCurrent()
        batteryAlerts.dismissCurrentPresentation()
        focusMode.dismissCurrentPresentation()
        screenLock.dismissCurrentPresentation()
        airDrop.dragEnded()
        notchTimer.cancel()
        liveActivities.endAll()
        countdown.clearDetail()
        appState.resetToCollapsed()
        settings.resetToFactoryDefaults()
    }

    private func showNotchIfNeeded() {
        if !settings.showNotch {
            settings.showNotch = true
        }
    }

    private func debugShareFileURL() -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("NotchLand-AirDrop-Test.txt")
        try? "NotchLand AirDrop test file".write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    private func testButton(
        _ title: String,
        systemImage: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .frame(minWidth: 112)
        }
        .buttonStyle(.bordered)
    }
}

#Preview("Debug Settings") {
    NotchPreviewContainer {
        DebugSettingsView()
            .frame(width: 510, height: 580)
    }
}

#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
