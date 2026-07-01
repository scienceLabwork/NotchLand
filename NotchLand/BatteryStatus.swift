//
//  BatteryStatus.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  One-shot battery snapshot for notch surfaces.
//

import Foundation
import IOKit.ps

struct BatteryStatus {
    let percent: Int
    let isCharging: Bool

    /// nil on Macs with no battery.
    nonisolated static func read() -> BatteryStatus? {
        guard let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef],
              let source = sources.first,
              let info = IOPSGetPowerSourceDescription(blob, source)?.takeUnretainedValue() as? [String: Any],
              let capacity = info[kIOPSCurrentCapacityKey] as? Int
        else { return nil }
        let charging = (info[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
        return BatteryStatus(percent: capacity, isCharging: charging)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
