//
//  NotchSettings.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Single source of truth for user-configurable settings.
//  Each property reads its initial value from UserDefaults and writes back via didSet,
//  so persistence is centralized here and views/window-management can simply observe.
//

import Combine
import Foundation
import SwiftUI

nonisolated final class NotchSettings: ObservableObject {
    enum Theme: String, CaseIterable, Identifiable, Hashable {
        case system, dark, light

        var id: String { rawValue }
        var label: String {
            switch self {
            case .system: "System"
            case .dark: "Dark"
            case .light: "Light"
            }
        }
        var colorScheme: ColorScheme? {
            switch self {
            case .system: nil
            case .dark: .dark
            case .light: .light
            }
        }
    }

    enum Defaults {
        static let showNotch = true
        static let launchAtLogin = false
        static let showMenuBarItem = true

        static let collapsedWidth: Double = 184 // ideal 184
        static let collapsedHeight: Double = 32 //ideal 32
        static let expandedWidth: Double = 520
        static let expandedHeight: Double = 140

        static let hoverToExpand = true
        static let collapseDelay: Double = 0.25
        static let autoCollapse = true
        static let openOnClick = true
        static let showHUDOnNotch = false
        static let lockUnlockAnimationEnabled = true

        static let theme: Theme = .system
        static let cornerRadius: Double = 20
        static let shadowIntensity: Double = 0
        static let useBlurMaterial = false

        static let eventCountdownEnabled = true
        static let eventCountdownThresholdMinutes = 30

        static let airDropEnabled = true
        static let liveActivitiesEnabled = true
        static let autoUpdateCheckEnabled = true

        static let hasCompletedOnboarding = false
    }

    enum Limits {
        static let collapsedWidth: ClosedRange<Double> = 120...400
        static let collapsedHeight: ClosedRange<Double> = 32...80
        static let expandedWidth: ClosedRange<Double> = 320...900
        static let expandedHeight: ClosedRange<Double> = 160...600
        static let collapseDelay: ClosedRange<Double> = 0.05...1.0
        static let cornerRadius: ClosedRange<Double> = 6...40
        static let shadowIntensity: ClosedRange<Double> = 0...1
    }

    private enum Keys {
        static let showNotch = "notch.showNotch"
        static let launchAtLogin = "notch.launchAtLogin"
        static let showMenuBarItem = "notch.showMenuBarItem"
        static let collapsedWidth = "notch.collapsedWidth"
        static let collapsedHeight = "notch.collapsedHeight"
        static let expandedWidth = "notch.expandedWidth"
        static let expandedHeight = "notch.expandedHeight"
        static let hoverToExpand = "notch.hoverToExpand"
        static let collapseDelay = "notch.collapseDelay"
        static let autoCollapse = "notch.autoCollapse"
        static let openOnClick = "notch.openOnClick"
        static let showHUDOnNotch = "notch.showHUDOnNotch"
        static let lockUnlockAnimationEnabled = "notch.lockUnlockAnimationEnabled"
        static let legacyHideSystemHUD = "notch.hideSystemHUD"
        static let theme = "notch.theme"
        static let cornerRadius = "notch.cornerRadius"
        static let shadowIntensity = "notch.shadowIntensity"
        static let useBlurMaterial = "notch.useBlurMaterial"
        static let eventCountdownEnabled = "notch.eventCountdownEnabled"
        static let eventCountdownThresholdMinutes = "notch.eventCountdownThresholdMinutes"
        static let airDropEnabled = "notch.airDropEnabled"
        static let liveActivitiesEnabled = "notch.liveActivitiesEnabled"
        static let autoUpdateCheckEnabled = "notch.autoUpdateCheckEnabled"
        static let hasCompletedOnboarding = "notch.hasCompletedOnboarding"
    }

    static let eventCountdownThresholdOptions: [Int] = [5, 15, 30, 60, 120]

    // General
    @Published var showNotch: Bool = read(Keys.showNotch, Defaults.showNotch) {
        didSet { Self.write(showNotch, Keys.showNotch) }
    }
    @Published var launchAtLogin: Bool = read(Keys.launchAtLogin, Defaults.launchAtLogin) {
        didSet { Self.write(launchAtLogin, Keys.launchAtLogin) }
    }
    @Published var showMenuBarItem: Bool = read(Keys.showMenuBarItem, Defaults.showMenuBarItem) {
        didSet { Self.write(showMenuBarItem, Keys.showMenuBarItem) }
    }

    // Sizes
    @Published var collapsedWidth: Double = read(Keys.collapsedWidth, Defaults.collapsedWidth) {
        didSet { Self.write(collapsedWidth, Keys.collapsedWidth) }
    }
    @Published var collapsedHeight: Double = read(Keys.collapsedHeight, Defaults.collapsedHeight) {
        didSet { Self.write(collapsedHeight, Keys.collapsedHeight) }
    }
    @Published var expandedWidth: Double = read(Keys.expandedWidth, Defaults.expandedWidth) {
        didSet { Self.write(expandedWidth, Keys.expandedWidth) }
    }
    @Published var expandedHeight: Double = read(Keys.expandedHeight, Defaults.expandedHeight) {
        didSet { Self.write(expandedHeight, Keys.expandedHeight) }
    }

    // Behavior
    @Published var hoverToExpand: Bool = read(Keys.hoverToExpand, Defaults.hoverToExpand) {
        didSet { Self.write(hoverToExpand, Keys.hoverToExpand) }
    }
    @Published var collapseDelay: Double = read(Keys.collapseDelay, Defaults.collapseDelay) {
        didSet { Self.write(collapseDelay, Keys.collapseDelay) }
    }
    @Published var autoCollapse: Bool = read(Keys.autoCollapse, Defaults.autoCollapse) {
        didSet { Self.write(autoCollapse, Keys.autoCollapse) }
    }
    @Published var openOnClick: Bool = read(Keys.openOnClick, Defaults.openOnClick) {
        didSet { Self.write(openOnClick, Keys.openOnClick) }
    }
    @Published var showHUDOnNotch: Bool = readShowHUDOnNotch() {
        didSet { Self.write(showHUDOnNotch, Keys.showHUDOnNotch) }
    }
    @Published var lockUnlockAnimationEnabled: Bool = read(Keys.lockUnlockAnimationEnabled, Defaults.lockUnlockAnimationEnabled) {
        didSet { Self.write(lockUnlockAnimationEnabled, Keys.lockUnlockAnimationEnabled) }
    }

    // Appearance
    @Published var theme: Theme = readTheme() {
        didSet { Self.write(theme.rawValue, Keys.theme) }
    }
    @Published var cornerRadius: Double = read(Keys.cornerRadius, Defaults.cornerRadius) {
        didSet { Self.write(cornerRadius, Keys.cornerRadius) }
    }
    @Published var shadowIntensity: Double = read(Keys.shadowIntensity, Defaults.shadowIntensity) {
        didSet { Self.write(shadowIntensity, Keys.shadowIntensity) }
    }
    @Published var useBlurMaterial: Bool = read(Keys.useBlurMaterial, Defaults.useBlurMaterial) {
        didSet { Self.write(useBlurMaterial, Keys.useBlurMaterial) }
    }

    // Calendar countdown
    @Published var eventCountdownEnabled: Bool = read(Keys.eventCountdownEnabled, Defaults.eventCountdownEnabled) {
        didSet { Self.write(eventCountdownEnabled, Keys.eventCountdownEnabled) }
    }
    @Published var eventCountdownThresholdMinutes: Int = read(Keys.eventCountdownThresholdMinutes, Defaults.eventCountdownThresholdMinutes) {
        didSet { Self.write(eventCountdownThresholdMinutes, Keys.eventCountdownThresholdMinutes) }
    }

    // AirDrop, activities, updates
    @Published var airDropEnabled: Bool = read(Keys.airDropEnabled, Defaults.airDropEnabled) {
        didSet { Self.write(airDropEnabled, Keys.airDropEnabled) }
    }
    @Published var liveActivitiesEnabled: Bool = read(Keys.liveActivitiesEnabled, Defaults.liveActivitiesEnabled) {
        didSet { Self.write(liveActivitiesEnabled, Keys.liveActivitiesEnabled) }
    }
    @Published var autoUpdateCheckEnabled: Bool = read(Keys.autoUpdateCheckEnabled, Defaults.autoUpdateCheckEnabled) {
        didSet { Self.write(autoUpdateCheckEnabled, Keys.autoUpdateCheckEnabled) }
    }

    // Onboarding — flipped to true the first time the user taps GET STARTED.
    @Published var hasCompletedOnboarding: Bool = read(Keys.hasCompletedOnboarding, Defaults.hasCompletedOnboarding) {
        didSet { Self.write(hasCompletedOnboarding, Keys.hasCompletedOnboarding) }
    }

    func resetToDefaults() {
        showNotch = Defaults.showNotch
        launchAtLogin = Defaults.launchAtLogin
        showMenuBarItem = Defaults.showMenuBarItem
        collapsedWidth = Defaults.collapsedWidth
        collapsedHeight = Defaults.collapsedHeight
        expandedWidth = Defaults.expandedWidth
        expandedHeight = Defaults.expandedHeight
        hoverToExpand = Defaults.hoverToExpand
        collapseDelay = Defaults.collapseDelay
        autoCollapse = Defaults.autoCollapse
        openOnClick = Defaults.openOnClick
        showHUDOnNotch = Defaults.showHUDOnNotch
        lockUnlockAnimationEnabled = Defaults.lockUnlockAnimationEnabled
        theme = Defaults.theme
        cornerRadius = Defaults.cornerRadius
        shadowIntensity = Defaults.shadowIntensity
        useBlurMaterial = Defaults.useBlurMaterial
        eventCountdownEnabled = Defaults.eventCountdownEnabled
        eventCountdownThresholdMinutes = Defaults.eventCountdownThresholdMinutes
        airDropEnabled = Defaults.airDropEnabled
        liveActivitiesEnabled = Defaults.liveActivitiesEnabled
        autoUpdateCheckEnabled = Defaults.autoUpdateCheckEnabled
    }

    func resetToFactoryDefaults() {
        resetToDefaults()
        hasCompletedOnboarding = Defaults.hasCompletedOnboarding
    }

    func resetSizesToDefaults() {
        collapsedWidth = Defaults.collapsedWidth
        collapsedHeight = Defaults.collapsedHeight
        expandedWidth = Defaults.expandedWidth
        expandedHeight = Defaults.expandedHeight
    }

    private static func read<T>(_ key: String, _ fallback: T) -> T {
        UserDefaults.standard.object(forKey: key) as? T ?? fallback
    }

    private static func write<T>(_ value: T, _ key: String) {
        UserDefaults.standard.set(value, forKey: key)
    }

    private static func readTheme() -> Theme {
        if let raw = UserDefaults.standard.string(forKey: Keys.theme),
           let theme = Theme(rawValue: raw) {
            return theme
        }
        return Defaults.theme
    }

    private static func readShowHUDOnNotch() -> Bool {
        if let value = UserDefaults.standard.object(forKey: Keys.showHUDOnNotch) as? Bool {
            return value
        }
        return UserDefaults.standard.object(forKey: Keys.legacyHideSystemHUD) as? Bool ?? Defaults.showHUDOnNotch
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
