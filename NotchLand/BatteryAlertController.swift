//
//  BatteryAlertController.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Watches the internal battery and exposes transient battery presentations for
//  the floating notch.
//

import Combine
import Foundation
import IOKit.ps

enum BatteryPresentationTiming {
    static let expandDuration: TimeInterval = 0.32
    static let contentRevealDuration: TimeInterval = 0.22
    static let holdDuration: TimeInterval = 2.6
    static let collapseDuration: TimeInterval = 0.30

    static let activeDuration = expandDuration + contentRevealDuration + holdDuration
}

@MainActor
final class BatteryAlertController: ObservableObject {
    enum Presentation: Equatable {
        case lowBattery(Alert)
        case charging(ChargingStatus)

        var branchKey: String {
            switch self {
            case .lowBattery:
                "battery-low"
            case .charging:
                "battery-charging"
            }
        }
    }

    struct Alert: Equatable {
        let percent: Int
        let timeRemaining: Int?
        let milestone: Int

        var title: String {
            milestone <= 5 ? "Critical Battery" : "Low Battery"
        }

        var subtitle: String {
            if let timeRemaining {
                return "\(timeRemaining) min remaining"
            }
            return "Connect power"
        }
    }

    struct ChargingStatus: Equatable {
        let percent: Int
        let isCharging: Bool

        var title: String {
            percent >= 100 && !isCharging ? "Charged" : "Charging"
        }
    }

    private struct Snapshot: Equatable {
        let percent: Int
        let isCharging: Bool
        let isOnBatteryPower: Bool
        let timeRemaining: Int?

        var isConnectedToPower: Bool {
            isCharging || !isOnBatteryPower
        }
    }

    static let dismissDelay: TimeInterval = BatteryPresentationTiming.activeDuration
    private static let pollInterval: TimeInterval = 30.0
    private static let resetPercent = 25
    private static let milestones = [20, 10]

    @Published private(set) var currentPresentation: Presentation?

    private var pollTimer: Timer?
    private var powerSourceRunLoopSource: CFRunLoopSource?
    private var dismissTask: Task<Void, Never>?
    private var shownMilestones: Set<Int> = []
    private var lastSnapshot: Snapshot?
    private var lastValidPercent: Int?

    func start() {
        guard pollTimer == nil else { return }

        pollBattery()
        installPowerSourceObserver()

        let timer = Timer(timeInterval: Self.pollInterval, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.pollBattery()
            }
        }
        pollTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        removePowerSourceObserver()
        dismissTask?.cancel()
        dismissTask = nil
        currentPresentation = nil
        shownMilestones.removeAll()
        lastSnapshot = nil
        lastValidPercent = nil
    }

    func debugShowCharging(percent: Int) {
        currentPresentation = .charging(
            ChargingStatus(
                percent: min(max(percent, 0), 100),
                isCharging: true
            )
        )
        scheduleDismiss()
    }

    func debugShowLowBattery(percent: Int) {
        currentPresentation = .lowBattery(
            Alert(
                percent: min(max(percent, 0), 100),
                timeRemaining: nil,
                milestone: percent <= 10 ? 10 : 20
            )
        )
        scheduleDismiss()
    }

    func dismissCurrentPresentation() {
        clearCurrentPresentation()
    }

    private func pollBattery() {
        guard let snapshot = readInternalBatterySnapshot() else {
            clearCurrentPresentation()
            shownMilestones.removeAll()
            lastSnapshot = nil
            return
        }

        let previousSnapshot = lastSnapshot
        lastSnapshot = snapshot

        if snapshot.isConnectedToPower {
            if previousSnapshot?.isConnectedToPower == false {
                showChargingStatus(for: snapshot)
            } else if case .charging = currentPresentation {
                updateChargingStatus(for: snapshot)
            } else if case .lowBattery = currentPresentation {
                showChargingStatus(for: snapshot)
            }
            shownMilestones.removeAll()
            return
        }

        if previousSnapshot?.isConnectedToPower == true {
            clearCurrentPresentation()
        }

        if snapshot.percent > Self.resetPercent {
            shownMilestones.removeAll()
            return
        }

        guard let milestone = milestoneToPresent(for: snapshot, previousSnapshot: previousSnapshot),
              !shownMilestones.contains(milestone)
        else {
            return
        }

        shownMilestones.insert(milestone)
        showAlert(for: snapshot, milestone: milestone)
    }

    private func milestoneToPresent(
        for snapshot: Snapshot,
        previousSnapshot: Snapshot?
    ) -> Int? {
        for milestone in Self.milestones.reversed() {
            guard !shownMilestones.contains(milestone) else { continue }

            if let previousPercent = previousSnapshot?.percent {
                if previousPercent > milestone, snapshot.percent <= milestone {
                    return milestone
                }
            } else if snapshot.percent == milestone {
                return milestone
            }
        }

        return nil
    }

    private func showAlert(for snapshot: Snapshot, milestone: Int) {
        currentPresentation = .lowBattery(
            Alert(
                percent: snapshot.percent,
                timeRemaining: snapshot.timeRemaining,
                milestone: milestone
            )
        )
        scheduleDismiss()
    }

    private func showChargingStatus(for snapshot: Snapshot) {
        currentPresentation = .charging(
            ChargingStatus(
                percent: snapshot.percent,
                isCharging: snapshot.isCharging
            )
        )
        scheduleDismiss()
    }

    private func updateChargingStatus(for snapshot: Snapshot) {
        currentPresentation = .charging(
            ChargingStatus(
                percent: snapshot.percent,
                isCharging: snapshot.isCharging
            )
        )
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        let delayNanos = UInt64(Self.dismissDelay * 1_000_000_000)
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard let self, !Task.isCancelled else { return }
            self.currentPresentation = nil
            self.dismissTask = nil
        }
    }

    private func clearCurrentPresentation() {
        dismissTask?.cancel()
        dismissTask = nil
        currentPresentation = nil
    }

    private func installPowerSourceObserver() {
        guard powerSourceRunLoopSource == nil,
              let sourceRef = IOPSNotificationCreateRunLoopSource(
                Self.powerSourceCallback,
                Unmanaged.passUnretained(self).toOpaque()
              )
        else {
            return
        }

        let source = sourceRef.takeRetainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        powerSourceRunLoopSource = source
    }

    private func removePowerSourceObserver() {
        guard let source = powerSourceRunLoopSource else { return }
        CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        CFRunLoopSourceInvalidate(source)
        powerSourceRunLoopSource = nil
    }

    private nonisolated static let powerSourceCallback: IOPowerSourceCallbackType = { context in
        guard let context else { return }
        MainActor.assumeIsolated {
            Unmanaged<BatteryAlertController>
                .fromOpaque(context)
                .takeUnretainedValue()
                .pollBattery()
        }
    }

    private func readInternalBatterySnapshot() -> Snapshot? {
        guard let infoRef = IOPSCopyPowerSourcesInfo() else { return nil }
        let info = infoRef.takeRetainedValue()

        guard let sourcesRef = IOPSCopyPowerSourcesList(info) else { return nil }
        let sources = sourcesRef.takeRetainedValue() as [AnyObject]

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?
                .takeUnretainedValue() as? [String: Any],
                  let type = description[kIOPSTypeKey] as? String,
                  type == kIOPSInternalBatteryType,
                  description[kIOPSIsPresentKey] as? Bool != false,
                  let percent = batteryPercent(from: description)
            else {
                continue
            }

            let powerState = description[kIOPSPowerSourceStateKey] as? String
            let rawTimeRemaining = intValue(description[kIOPSTimeToEmptyKey])
            let timeRemaining = rawTimeRemaining.flatMap { $0 >= 0 ? $0 : nil }
            lastValidPercent = percent

            return Snapshot(
                percent: percent,
                isCharging: description[kIOPSIsChargingKey] as? Bool ?? false,
                isOnBatteryPower: powerState == kIOPSBatteryPowerValue,
                timeRemaining: timeRemaining
            )
        }

        return nil
    }

    private func batteryPercent(from description: [String: Any]) -> Int? {
        guard let currentCapacity = doubleValue(description[kIOPSCurrentCapacityKey]),
              currentCapacity >= 0
        else {
            return lastValidPercent
        }

        let maxCapacity = doubleValue(description[kIOPSMaxCapacityKey])
        let percent: Int

        if let maxCapacity, maxCapacity > 0 {
            let ratioPercent = Int((currentCapacity / maxCapacity * 100).rounded())
            if currentCapacity <= 100, maxCapacity > 100 {
                percent = Int(currentCapacity.rounded())
            } else if ratioPercent == 0, currentCapacity > 0, currentCapacity <= 100 {
                percent = Int(currentCapacity.rounded())
            } else {
                percent = ratioPercent
            }
        } else if currentCapacity <= 100 {
            percent = Int(currentCapacity.rounded())
        } else {
            return lastValidPercent
        }

        let clamped = min(max(percent, 0), 100)
        if clamped == 0, let lastValidPercent, lastValidPercent > 0 {
            return lastValidPercent
        }
        return clamped
    }

    private func intValue(_ value: Any?) -> Int? {
        guard let value else { return nil }
        if let int = value as? Int { return int }
        if let number = value as? NSNumber { return number.intValue }
        if let double = value as? Double { return Int(double.rounded()) }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        guard let value else { return nil }
        if let double = value as? Double { return double }
        if let int = value as? Int { return Double(int) }
        if let number = value as? NSNumber { return number.doubleValue }
        return nil
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
