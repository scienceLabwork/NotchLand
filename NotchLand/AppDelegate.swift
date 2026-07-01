//
//  AppDelegate.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Bootstraps the singletons (NotchSettings, AppState, WindowManager) and
//  exposes settings/appState to the SwiftUI Settings scene.
//

import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    let settings = NotchSettings()
    lazy var appState = AppState(settings: settings)
    lazy var hud = HUDController(settings: settings)
    lazy var nowPlaying = NowPlayingService()
    lazy var batteryAlerts = BatteryAlertController()
    lazy var focusMode = FocusModeController()
    lazy var screenLock = ScreenLockController(settings: settings)
    lazy var calendar = CalendarService()
    lazy var eventCountdown = EventCountdownController(calendar: calendar, settings: settings)
    lazy var airDrop = AirDropController(settings: settings)
    lazy var liveActivities = LiveActivityController(settings: settings)
    lazy var audioActivity = AudioDeviceActivitySource(activities: liveActivities)
    lazy var notchTimer = NotchTimerController(activities: liveActivities)
    lazy var downloadsActivity = DownloadsActivitySource(activities: liveActivities)
    lazy var updater = UpdaterController(settings: settings)
    private var didStartServices = false
    private lazy var windowManager = WindowManager(
        settings: settings,
        appState: appState,
        hud: hud,
        nowPlaying: nowPlaying,
        batteryAlerts: batteryAlerts,
        focusMode: focusMode,
        screenLock: screenLock,
        calendar: calendar,
        eventCountdown: eventCountdown,
        airDrop: airDrop,
        liveActivities: liveActivities,
        notchTimer: notchTimer,
        updater: updater
    )

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard !AppRuntime.isXcodePreview else { return }
        NSApp.setActivationPolicy(.accessory)
        windowManager.start()
        hud.start()
        batteryAlerts.start()
        focusMode.start()
        screenLock.start()
        calendar.start()
        eventCountdown.start()
        // Live Activities (audio-device connect, timer, downloads) is
        // temporarily unwired from the UI — leave its sources stopped so
        // they don't run in the background for a feature that can't be seen.
        didStartServices = true
    }

    func applicationWillTerminate(_ notification: Notification) {
        guard didStartServices else { return }
        hud.stop()
        batteryAlerts.stop()
        focusMode.stop()
        screenLock.stop()
        calendar.stop()
        eventCountdown.stop()
        notchTimer.cancel()
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
