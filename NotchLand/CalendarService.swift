//
//  CalendarService.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  EventKit-backed source for today's calendar events in the expanded notch.
//

import AppKit
import Combine
import EventKit
import Foundation

@MainActor
final class CalendarService: ObservableObject {
    struct Event: Identifiable {
        struct Accent {
            let red: Double
            let green: Double
            let blue: Double
        }

        let id: String
        let title: String
        let calendarTitle: String
        let location: String?
        let notes: String?
        let url: URL?
        let startDate: Date
        let endDate: Date
        let isAllDay: Bool
        let accent: Accent
    }

    nonisolated static let holidayKeywords: [String] = ["holiday", "holidays", "birthdays"]

    private static let refreshInterval: TimeInterval = 60
    private static let connectionEnabledKey = "calendar.connectionEnabled"

    @Published private(set) var authorizationStatus: EKAuthorizationStatus =
        EKEventStore.authorizationStatus(for: .event)
    @Published private(set) var isConnectionEnabled: Bool =
        UserDefaults.standard.object(forKey: connectionEnabledKey) as? Bool ?? true
    @Published private(set) var events: [Event] = []
    @Published private(set) var monthEvents: [Event] = []
    @Published private(set) var currentDate = Date()
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage: String?

    private let eventStore = EKEventStore()
    private var refreshTimer: Timer?
    private var storeChangedObserver: NSObjectProtocol?

    var canReadEvents: Bool {
        guard isConnectionEnabled else { return false }

        switch authorizationStatus {
        case .authorized, .fullAccess:
            return true
        default:
            return false
        }
    }

    var needsConnection: Bool {
        isConnectionEnabled && authorizationStatus == .notDetermined
    }

    var isDisconnected: Bool {
        !isConnectionEnabled
    }

    var connectionTitle: String {
        guard isConnectionEnabled else { return "Disconnected" }

        switch authorizationStatus {
        case .authorized, .fullAccess:
            return "Connected"
        case .notDetermined:
            return "Not Connected"
        case .denied:
            return "Access Denied"
        case .restricted:
            return "Restricted"
        case .writeOnly:
            return "Write Only"
        @unknown default:
            return "Unavailable"
        }
    }

    func start() {
        refreshAuthorizationStatus()
        observeEventStoreChanges()
        refreshEvents()
        startRefreshTimer()
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil

        if let storeChangedObserver {
            NotificationCenter.default.removeObserver(storeChangedObserver)
            self.storeChangedObserver = nil
        }
    }

    func requestAccess() {
        setConnectionEnabled(true)
        refreshAuthorizationStatus()

        guard authorizationStatus == .notDetermined else {
            refreshEvents()
            return
        }

        isLoading = true
        errorMessage = nil

        eventStore.requestFullAccessToEvents { [weak self] granted, error in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isLoading = false
                    if let error {
                        self.errorMessage = error.localizedDescription
                    } else if !granted {
                        self.errorMessage = "Calendar access was not granted."
                    }
                    self.refreshEvents()
                }
            }
        }
    }

    func disconnect() {
        setConnectionEnabled(false)
        events = []
        monthEvents = []
        errorMessage = nil
        isLoading = false
    }

    func refreshEvents() {
        currentDate = Date()
        refreshAuthorizationStatus()

        guard canReadEvents else {
            events = []
            monthEvents = []
            isLoading = false
            return
        }

        isLoading = true
        errorMessage = nil

        let calendar = Foundation.Calendar.current
        let startOfDay = calendar.startOfDay(for: currentDate)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            events = []
            monthEvents = []
            isLoading = false
            return
        }

        events = fetchEvents(from: startOfDay, to: endOfDay)
        monthEvents = fetchMonthEvents(containing: currentDate)
        isLoading = false
    }

    func events(on date: Date) -> [Event] {
        let calendar = Foundation.Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        guard let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay) else {
            return []
        }

        return monthEvents.filter { event in
            event.startDate < endOfDay && event.endDate > startOfDay
        }
    }

    func hasEvents(on date: Date) -> Bool {
        !events(on: date).isEmpty
    }

    /// The next countdown-eligible event starting within the next 12 hours,
    /// if any — used by compact event surfaces.
    func nextUpcomingEvent() -> Event? {
        let now = Date.now
        guard let horizon = Foundation.Calendar.current.date(byAdding: .hour, value: 12, to: now) else {
            return nil
        }
        return events(on: now)
            .filter { $0.isCountdownEligible && $0.startDate > now && $0.startDate < horizon }
            .min { $0.startDate < $1.startDate }
    }

    private func fetchMonthEvents(containing date: Date) -> [Event] {
        let calendar = Foundation.Calendar.current
        guard let monthInterval = calendar.dateInterval(of: .month, for: date) else {
            return []
        }

        return fetchEvents(from: monthInterval.start, to: monthInterval.end)
    }

    private func fetchEvents(from startDate: Date, to endDate: Date) -> [Event] {
        let predicate = eventStore.predicateForEvents(
            withStart: startDate,
            end: endDate,
            calendars: nil
        )

        return eventStore.events(matching: predicate)
            .filter { $0.status != .canceled }
            .sorted { lhs, rhs in
                if lhs.isAllDay != rhs.isAllDay {
                    return lhs.isAllDay && !rhs.isAllDay
                }
                return lhs.startDate < rhs.startDate
            }
            .map(makeEvent(from:))
    }

    private func refreshAuthorizationStatus() {
        authorizationStatus = EKEventStore.authorizationStatus(for: .event)
    }

    private func observeEventStoreChanges() {
        guard storeChangedObserver == nil else { return }

        storeChangedObserver = NotificationCenter.default.addObserver(
            forName: .EKEventStoreChanged,
            object: eventStore,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshEvents()
            }
        }
    }

    private func startRefreshTimer() {
        refreshTimer?.invalidate()
        let timer = Timer(timeInterval: Self.refreshInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshEvents()
            }
        }
        refreshTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func makeEvent(from event: EKEvent) -> Event {
        Event(
            id: stableIdentifier(for: event),
            title: event.title?.isEmpty == false ? event.title : "Untitled Event",
            calendarTitle: event.calendar.title,
            location: event.location?.isEmpty == false ? event.location : nil,
            notes: event.notes?.isEmpty == false ? event.notes : nil,
            url: event.url,
            startDate: event.startDate,
            endDate: event.endDate,
            isAllDay: event.isAllDay,
            accent: accent(from: event.calendar.cgColor)
        )
    }

    private func stableIdentifier(for event: EKEvent) -> String {
        if let identifier = event.eventIdentifier, !identifier.isEmpty {
            return identifier
        }

        return [
            event.title ?? "event",
            String(event.startDate.timeIntervalSinceReferenceDate),
            String(event.endDate.timeIntervalSinceReferenceDate),
        ].joined(separator: "-")
    }

    private func accent(from cgColor: CGColor?) -> Event.Accent {
        let nsColor = cgColor.flatMap(NSColor.init(cgColor:)) ?? .systemBlue
        let rgb = nsColor.usingColorSpace(.sRGB) ?? .systemBlue
        return Event.Accent(
            red: Double(rgb.redComponent),
            green: Double(rgb.greenComponent),
            blue: Double(rgb.blueComponent)
        )
    }

    private func setConnectionEnabled(_ isEnabled: Bool) {
        isConnectionEnabled = isEnabled
        UserDefaults.standard.set(isEnabled, forKey: Self.connectionEnabledKey)
    }
}

extension CalendarService.Event {
    /// True when the event's calendar title matches one of the holiday keywords.
    /// Case-insensitive substring match against `CalendarService.holidayKeywords`.
    var isFromHolidayCalendar: Bool {
        let lowered = calendarTitle.lowercased()
        return CalendarService.holidayKeywords.contains { lowered.contains($0) }
    }

    /// True when this event is eligible to drive the countdown chip.
    var isCountdownEligible: Bool {
        !isAllDay && !isFromHolidayCalendar
    }

    /// Apple Maps query URL for the event's location, if present.
    var mapsURL: URL? {
        guard let location, !location.isEmpty,
              let encoded = location.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed)
        else { return nil }
        return URL(string: "https://maps.apple.com/?q=\(encoded)")
    }

    /// Detected meeting URL from `url`, `notes`, or `location` (in that order).
    /// Matches Zoom, Google Meet, and Microsoft Teams join links.
    var meetingURL: URL? {
        let candidates: [String?] = [url?.absoluteString, notes, location]
        for case let raw? in candidates {
            if let match = Self.detectMeetingURL(in: raw) {
                return match
            }
        }
        return nil
    }

    private static let meetingURLRegex: NSRegularExpression? = {
        let pattern = #"https?://(?:[\w-]+\.)*(?:zoom\.us/j/[^\s\"<>]+|meet\.google\.com/[^\s\"<>]+|teams\.microsoft\.com/l/meetup-join/[^\s\"<>]+)"#
        return try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
    }()

    private static func detectMeetingURL(in text: String) -> URL? {
        guard let regex = meetingURLRegex else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = regex.firstMatch(in: text, options: [], range: range),
              let swiftRange = Range(match.range, in: text)
        else { return nil }
        return URL(string: String(text[swiftRange]))
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
