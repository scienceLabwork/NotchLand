//
//  NotchLandPreviewGallery.swift
//  NotchLand
//
//  Central SwiftUI preview harness. Keep previews here lightweight and
//  sample-driven so Xcode can render UI changes without launching app services.
//

import AppKit
import SwiftUI

@MainActor
struct NotchPreviewContainer<Content: View>: View {
    @StateObject private var settings: NotchSettings
    @StateObject private var appState: AppState
    @StateObject private var hud: HUDController
    @StateObject private var nowPlaying: NowPlayingService
    @StateObject private var batteryAlerts: BatteryAlertController
    @StateObject private var focusMode: FocusModeController
    @StateObject private var screenLock: ScreenLockController
    @StateObject private var calendar: CalendarService
    @StateObject private var eventCountdown: EventCountdownController
    @StateObject private var airDrop: AirDropController
    @StateObject private var liveActivities: LiveActivityController
    @StateObject private var notchTimer: NotchTimerController
    @StateObject private var updater: UpdaterController

    private let content: () -> Content

    init(
        isExpanded: Bool = false,
        configure: (NotchPreviewContext) -> Void = { _ in },
        @ViewBuilder content: @escaping () -> Content
    ) {
        let settings = NotchSettings()
        let appState = AppState(settings: settings)
        let hud = HUDController(settings: settings)
        let nowPlaying = NowPlayingService()
        let batteryAlerts = BatteryAlertController()
        let focusMode = FocusModeController()
        let screenLock = ScreenLockController(settings: settings)
        let calendar = CalendarService()
        let eventCountdown = EventCountdownController(calendar: calendar, settings: settings)
        let liveActivities = LiveActivityController(settings: settings)
        let airDrop = AirDropController(settings: settings)
        let notchTimer = NotchTimerController(activities: liveActivities)
        let updater = UpdaterController(settings: settings)

        appState.isExpanded = isExpanded
        configure(
            NotchPreviewContext(
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
        )

        _settings = StateObject(wrappedValue: settings)
        _appState = StateObject(wrappedValue: appState)
        _hud = StateObject(wrappedValue: hud)
        _nowPlaying = StateObject(wrappedValue: nowPlaying)
        _batteryAlerts = StateObject(wrappedValue: batteryAlerts)
        _focusMode = StateObject(wrappedValue: focusMode)
        _screenLock = StateObject(wrappedValue: screenLock)
        _calendar = StateObject(wrappedValue: calendar)
        _eventCountdown = StateObject(wrappedValue: eventCountdown)
        _airDrop = StateObject(wrappedValue: airDrop)
        _liveActivities = StateObject(wrappedValue: liveActivities)
        _notchTimer = StateObject(wrappedValue: notchTimer)
        _updater = StateObject(wrappedValue: updater)
        self.content = content
    }

    var body: some View {
        content()
            .environmentObject(settings)
            .environmentObject(appState)
            .environmentObject(hud)
            .environmentObject(nowPlaying)
            .environmentObject(batteryAlerts)
            .environmentObject(focusMode)
            .environmentObject(screenLock)
            .environmentObject(calendar)
            .environmentObject(eventCountdown)
            .environmentObject(airDrop)
            .environmentObject(liveActivities)
            .environmentObject(notchTimer)
            .environmentObject(updater)
    }
}

@MainActor
struct NotchPreviewContext {
    let settings: NotchSettings
    let appState: AppState
    let hud: HUDController
    let nowPlaying: NowPlayingService
    let batteryAlerts: BatteryAlertController
    let focusMode: FocusModeController
    let screenLock: ScreenLockController
    let calendar: CalendarService
    let eventCountdown: EventCountdownController
    let airDrop: AirDropController
    let liveActivities: LiveActivityController
    let notchTimer: NotchTimerController
    let updater: UpdaterController
}

extension View {
    func notchPreviewSurface(width: CGFloat, height: CGFloat) -> some View {
        self
            .frame(width: width, height: height)
            .background(Color.black)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(24)
            .background(Color(red: 0.12, green: 0.12, blue: 0.13))
    }
}

enum PreviewSamples {
    static var track: NowPlayingService.Track {
        NowPlayingService.Track(
            title: "Midnight City",
            artist: "M83",
            album: "Hurry Up, We're Dreaming",
            artwork: NSImage(systemSymbolName: "music.note.list", accessibilityDescription: nil),
            duration: 244,
            elapsedAtTimestamp: 86,
            timestamp: Date(),
            playbackRate: 1
        )
    }

    static var event: CalendarService.Event {
        let start = Date.now.addingTimeInterval(12 * 60)
        return CalendarService.Event(
            id: "preview-event",
            title: "Product Design Review",
            calendarTitle: "Work",
            location: "Studio Room",
            notes: "Review notch interactions and preview coverage.",
            url: URL(string: "https://meet.example.com/notchland"),
            startDate: start,
            endDate: start.addingTimeInterval(45 * 60),
            isAllDay: false,
            accent: CalendarService.Event.Accent(red: 1.0, green: 0.25, blue: 0.22)
        )
    }

    static var timerActivity: LiveActivity {
        LiveActivity(
            kind: .timer(remaining: 18 * 60),
            title: "Focus",
            detail: "18:00",
            progress: 0.42
        )
    }
}

#Preview("Settings") {
    NotchPreviewContainer {
        SettingsView()
            .frame(width: 720, height: 520)
    }
}

#Preview("Settings - General") {
    NotchPreviewContainer {
        GeneralSettingsView()
            .frame(width: 510, height: 520, alignment: .topLeading)
            .padding()
    }
}

#Preview("Settings - Calendar") {
    NotchPreviewContainer {
        CalendarSettingsView()
            .frame(width: 510, height: 520, alignment: .topLeading)
            .padding()
    }
}

#Preview("Settings - Behavior") {
    NotchPreviewContainer {
        BehaviorSettingsView()
            .frame(width: 510, height: 520, alignment: .topLeading)
            .padding()
    }
}

#Preview("Settings - Appearance") {
    NotchPreviewContainer {
        AppearanceSettingsView()
            .frame(width: 510, height: 520, alignment: .topLeading)
            .padding()
    }
}

#Preview("Settings - About") {
    NotchPreviewContainer {
        AboutSettingsView()
            .frame(width: 510, height: 520, alignment: .topLeading)
            .padding()
    }
}

#if DEBUG
#Preview("Settings - Debug") {
    NotchPreviewContainer {
        DebugSettingsView()
            .frame(width: 510, height: 580, alignment: .topLeading)
            .padding()
    }
}
#endif

#Preview("Floating Notch - Collapsed") {
    NotchPreviewContainer {
        FloatingNotchView()
            .frame(width: 360, height: 120)
            .background(Color(red: 0.12, green: 0.12, blue: 0.13))
    }
}

#Preview("Floating Notch - Expanded") {
    NotchPreviewContainer(isExpanded: true) {
        FloatingNotchView()
            .frame(width: 640, height: 260)
            .background(Color(red: 0.12, green: 0.12, blue: 0.13))
    }
}

#Preview("Now Playing - Collapsed") {
    NowPlayingCollapsedView(track: PreviewSamples.track, isHovering: true)
        .notchPreviewSurface(width: NowPlayingMetrics.collapsedWidth, height: 56)
}

#Preview("Now Playing - Expanded") {
    NotchPreviewContainer {
        NowPlayingExpandedView(track: PreviewSamples.track)
            .notchPreviewSurface(
                width: NowPlayingMetrics.expandedSize.width,
                height: NowPlayingMetrics.expandedSize.height
            )
    }
}

#Preview("HUD - Volume") {
    HUDBarView(kind: .volume(level: 0.72, muted: false))
        .notchPreviewSurface(width: 280, height: HUDController.drawerHeight)
}

#Preview("Battery - Low") {
    BatteryAlertView(
        presentation: .lowBattery(
            BatteryAlertController.Alert(percent: 10, timeRemaining: nil, milestone: 10)
        )
    )
    .notchPreviewSurface(width: BatteryAlertMetrics.chargingWidth, height: 32)
}

#Preview("Battery - Charging") {
    BatteryAlertView(
        presentation: .charging(
            BatteryAlertController.ChargingStatus(percent: 82, isCharging: true)
        )
    )
    .notchPreviewSurface(width: BatteryAlertMetrics.chargingWidth, height: 32)
}

#Preview("Focus Alert") {
    FocusModeAlertView(presentation: FocusModeController.Presentation(isActive: true))
        .notchPreviewSurface(width: FocusModeAlertMetrics.width, height: 32)
}

#Preview("Lock Screen Alert") {
    NotchPreviewContainer {
        LockScreenAlertView(presentation: ScreenLockController.Presentation(phase: .locked))
            .notchPreviewSurface(width: LockScreenAlertMetrics.width, height: 32)
    }
}

#Preview("Calendar Countdown") {
    EventCountdownCollapsedView(
        presentation: .upcoming(eventID: PreviewSamples.event.id, secondsUntilStart: 12 * 60),
        event: PreviewSamples.event
    )
    .notchPreviewSurface(width: EventCountdownChipMetrics.eventOnlyCollapsedWidth, height: 40)
}

#Preview("Event Detail") {
    FocusedEventDetailView(event: PreviewSamples.event)
        .notchPreviewSurface(
            width: EventDetailMetrics.eventOnlySize.width,
            height: EventDetailMetrics.eventOnlySize.height
        )
}

#Preview("Live Activity") {
    NotchPreviewContainer {
        LiveActivityChipView(activity: PreviewSamples.timerActivity)
            .notchPreviewSurface(width: LiveActivityChipMetrics.flankWidth, height: 40)
    }
}

#Preview("AirDrop Drop Zone") {
    NotchPreviewContainer {
        AirDropZoneView()
            .notchPreviewSurface(width: AirDropZoneMetrics.width, height: AirDropZoneMetrics.height)
    }
}
