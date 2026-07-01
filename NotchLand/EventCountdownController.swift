//
//  EventCountdownController.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Picks the calendar event the notch should currently surface (upcoming inside
//  the user-configured threshold, or actively running) and republishes a
//  presentation that drives the chip + hero. Runs a 1s ticker only while a
//  tracked event exists.
//

import Combine
import Foundation

@MainActor
final class EventCountdownController: ObservableObject {
    enum Presentation: Equatable {
        case upcoming(eventID: String, secondsUntilStart: TimeInterval)
        case active(eventID: String, secondsUntilEnd: TimeInterval)

        var eventID: String {
            switch self {
            case .upcoming(let id, _), .active(let id, _): id
            }
        }

        var isActive: Bool {
            if case .active = self { return true }
            return false
        }
    }

    @Published private(set) var presentation: Presentation?
    @Published private(set) var isDetailPresented = false

    private let calendar: CalendarService
    private let settings: NotchSettings
    private var cancellables: Set<AnyCancellable> = []
    private var ticker: Timer?

    init(calendar: CalendarService, settings: NotchSettings) {
        self.calendar = calendar
        self.settings = settings
    }

    func start() {
        calendar.$events
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.recompute() }
            }
            .store(in: &cancellables)

        settings.$eventCountdownEnabled
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.recompute() }
            }
            .store(in: &cancellables)

        settings.$eventCountdownThresholdMinutes
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.recompute() }
            }
            .store(in: &cancellables)

        recompute()
    }

    func stop() {
        cancellables.removeAll()
        stopTicker()
        presentation = nil
        isDetailPresented = false
    }

    /// The event that the countdown is tracking, if any. Used by hero + agenda
    /// list to keep them in sync with the chip.
    var trackedEvent: CalendarService.Event? {
        guard let id = presentation?.eventID else { return nil }
        return calendar.events.first { $0.id == id }
    }

    func showDetail() {
        guard trackedEvent != nil else { return }
        isDetailPresented = true
    }

    func clearDetail() {
        isDetailPresented = false
    }

    private func recompute() {
        guard settings.eventCountdownEnabled else {
            updatePresentation(nil)
            isDetailPresented = false
            return
        }

        let now = Date()
        let threshold = TimeInterval(settings.eventCountdownThresholdMinutes * 60)
        let eligible = calendar.events.filter { $0.isCountdownEligible }

        let activeEvents = eligible
            .filter { $0.startDate <= now && now < $0.endDate }
            .sorted { $0.endDate < $1.endDate }

        if let active = activeEvents.first {
            let secondsLeft = active.endDate.timeIntervalSince(now)
            updatePresentation(.active(eventID: active.id, secondsUntilEnd: max(0, secondsLeft)))
            return
        }

        let upcoming = eligible
            .filter { $0.startDate > now }
            .sorted { $0.startDate < $1.startDate }

        if let next = upcoming.first {
            let secondsToStart = next.startDate.timeIntervalSince(now)
            if secondsToStart <= threshold {
                updatePresentation(.upcoming(eventID: next.id, secondsUntilStart: secondsToStart))
                return
            }
        }

        updatePresentation(nil)
    }

    private func updatePresentation(_ new: Presentation?) {
        if presentation != new {
            presentation = new
        }
        if new == nil {
            isDetailPresented = false
            stopTicker()
        } else {
            ensureTicker()
        }
    }

    private func ensureTicker() {
        guard ticker == nil else { return }
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.recompute() }
        }
        ticker = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopTicker() {
        ticker?.invalidate()
        ticker = nil
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
