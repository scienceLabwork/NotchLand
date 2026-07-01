//
//  HUDController.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Detects system volume + brightness changes and exposes a transient HUD state
//  (`current`) that the floating notch view renders as a drawer below the pill.
//
//  Volume:     CoreAudio property listeners on the default output device.
//  Brightness: DisplayServices.loginPlugin (private), polled at 150 ms.
//  HUD on Notch: CGEvent tap consumes Apple HUD-style level keys when enabled.
//

import AppKit
import Combine
import CoreAudio
import IOKit.hidsystem
import IOKit.graphics
import SwiftUI
import Darwin

@MainActor
final class HUDController: ObservableObject {
    enum Kind: Equatable {
        case volume(level: Double, muted: Bool)
        case brightness(level: Double)
        case keyboardBrightness(level: Double)
        case contrast(level: Double)
    }

    /// Visible duration after the last change before the HUD auto-hides.
    static let dismissDelay: TimeInterval = 1.5
    /// Minimum visible width of the HUD drawer.
    static let drawerMinWidth: CGFloat = 260
    /// Height of the HUD drawer below the collapsed notch.
    static let drawerHeight: CGFloat = 28
    private static let brightnessRampDuration: TimeInterval = 0.14
    private static let brightnessRampFrameInterval: TimeInterval = 1.0 / 60.0
    private static let volumeStep = 1.0 / 16.0
    private static let brightnessStep: Float = 1.0 / 16.0
    private static let keyboardBrightnessStep = 1.0 / 16.0
    private static let contrastStep = 1.0 / 16.0

    @Published private(set) var current: Kind?
    @Published private(set) var isAccessibilityTrusted = AXIsProcessTrusted()

    private let settings: NotchSettings
    private var defaultDeviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
    private var volumeBlocks: [(AudioObjectPropertyElement, AudioObjectPropertyListenerBlock)] = []
    private var muteBlocks: [(AudioObjectPropertyElement, AudioObjectPropertyListenerBlock)] = []
    private var deviceBlock: AudioObjectPropertyListenerBlock?

    private var brightnessTimer: Timer?
    private var lastBrightness: Float = -1
    private var displayServicesHandle: UnsafeMutableRawPointer?
    private typealias GetBrightnessFn = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetBrightnessFn = @convention(c) (CGDirectDisplayID, Float) -> Int32

    private var getBrightnessFn: GetBrightnessFn?
    private var setBrightnessFn: SetBrightnessFn?
    private var brightnessDisplayID: CGDirectDisplayID?
    private var brightnessTarget: Float?
    private var brightnessRampGeneration = 0
    private var brightnessRampTask: Task<Void, Never>?

    private var dismissTask: Task<Void, Never>?
    private var mediaKeyTap: CFMachPort?
    private var mediaKeyRunLoopSource: CFRunLoopSource?
    private var accessibilityRetryTimer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var volumeBeforeMute = 0.5
    private var keyboardBrightnessLevel = 0.5
    private var contrastLevel = 0.5
    private var cancellables: Set<AnyCancellable> = []

    init(settings: NotchSettings) {
        self.settings = settings
    }

    func start() {
        setupVolume()
        setupBrightness()
        observeSettings()
        observeAppActivation()
        applySystemHUDHidingPreference()
    }

    func stop() {
        stopMediaKeyInterception()
        stopAccessibilityRetryTimer()
        if let activationObserver {
            NotificationCenter.default.removeObserver(activationObserver)
            self.activationObserver = nil
        }
        teardownVolume()
        teardownBrightness()
        dismissTask?.cancel()
        dismissTask = nil
        brightnessRampTask?.cancel()
        brightnessRampTask = nil
        cancellables.removeAll()
    }

    // MARK: - State plumbing

    private func observeSettings() {
        Publishers.CombineLatest(settings.$showHUDOnNotch, settings.$showNotch)
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated { self?.applySystemHUDHidingPreference() }
            }
            .store(in: &cancellables)
    }

    private func observeAppActivation() {
        guard activationObserver == nil else { return }

        activationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refreshAccessibilityTrust()
                self?.applySystemHUDHidingPreference()
            }
        }
    }

    func setShowHUDOnNotch(_ isEnabled: Bool) {
        settings.showHUDOnNotch = isEnabled
        if isEnabled {
            requestAccessibilityPermissionIfNeeded()
        } else {
            stopAccessibilityRetryTimer()
        }
        applySystemHUDHidingPreference()
    }

    func requestAccessibilityPermissionIfNeeded() {
        guard !refreshAccessibilityTrust() else { return }

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        isAccessibilityTrusted = AXIsProcessTrustedWithOptions(options)

        if !isAccessibilityTrusted {
            startAccessibilityRetryTimer()
        }
    }

    private func show(_ kind: Kind) {
        current = kind
        scheduleDismiss()
    }

    func debugShow(_ kind: Kind) {
        show(kind)
    }

    func dismissCurrent() {
        dismissTask?.cancel()
        dismissTask = nil
        current = nil
    }

    private func scheduleDismiss() {
        dismissTask?.cancel()
        let delayNanos = UInt64(Self.dismissDelay * 1_000_000_000)
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard let self, !Task.isCancelled else { return }
            self.current = nil
        }
    }

    // MARK: - Volume

    private func setupVolume() {
        defaultDeviceID = readDefaultOutputDevice()
        installVolumeListeners(on: defaultDeviceID)

        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            guard let self else { return }
            MainActor.assumeIsolated { self.handleDefaultDeviceChange() }
        }
        deviceBlock = block
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &addr, .main, block
        )
    }

    private func teardownVolume() {
        removeVolumeListeners(from: defaultDeviceID)
        if let b = deviceBlock {
            var addr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain
            )
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &addr, .main, b
            )
        }
        deviceBlock = nil
    }

    private func handleDefaultDeviceChange() {
        removeVolumeListeners(from: defaultDeviceID)
        defaultDeviceID = readDefaultOutputDevice()
        installVolumeListeners(on: defaultDeviceID)
    }

    private func installVolumeListeners(on device: AudioObjectID) {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }

        for element in volumeElements(on: device) {
            var volAddr = volumeAddress(element: element)
            let volBlock: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self else { return }
                MainActor.assumeIsolated { self.handleVolumeOrMuteChange() }
            }
            if AudioObjectAddPropertyListenerBlock(device, &volAddr, .main, volBlock) == noErr {
                volumeBlocks.append((element, volBlock))
            }
        }

        for element in muteElements(on: device) {
            var muteAddr = muteAddress(element: element)
            let muteBlk: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                guard let self else { return }
                MainActor.assumeIsolated { self.handleVolumeOrMuteChange() }
            }
            if AudioObjectAddPropertyListenerBlock(device, &muteAddr, .main, muteBlk) == noErr {
                muteBlocks.append((element, muteBlk))
            }
        }
    }

    private func removeVolumeListeners(from device: AudioObjectID) {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return }
        for (element, block) in volumeBlocks {
            var address = volumeAddress(element: element)
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, block)
        }
        for (element, block) in muteBlocks {
            var address = muteAddress(element: element)
            AudioObjectRemovePropertyListenerBlock(device, &address, .main, block)
        }
        volumeBlocks.removeAll()
        muteBlocks.removeAll()
    }

    private func handleVolumeOrMuteChange() {
        guard settings.showHUDOnNotch, settings.showNotch else { return }

        let (level, muted) = readVolume()
        show(.volume(level: level, muted: muted))
    }

    private func readVolume() -> (Double, Bool) {
        let levels = volumeElements(on: defaultDeviceID).compactMap { readVolume(element: $0) }
        let level = levels.isEmpty ? 0 : levels.reduce(0, +) / Double(levels.count)
        let muted = muteElements(on: defaultDeviceID).contains { readMute(element: $0) == true }

        return (clamp(level), muted)
    }

    private func readDefaultOutputDevice() -> AudioObjectID {
        var deviceID: AudioObjectID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, &size, &deviceID
        )
        return deviceID
    }

    private func volumeAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private func muteAddress(element: AudioObjectPropertyElement) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element
        )
    }

    private func volumeElements(on device: AudioObjectID) -> [AudioObjectPropertyElement] {
        propertyElements(on: device, selector: kAudioDevicePropertyVolumeScalar)
    }

    private func muteElements(on device: AudioObjectID) -> [AudioObjectPropertyElement] {
        propertyElements(on: device, selector: kAudioDevicePropertyMute)
    }

    private func propertyElements(
        on device: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) -> [AudioObjectPropertyElement] {
        guard device != AudioObjectID(kAudioObjectUnknown) else { return [] }

        let main = AudioObjectPropertyElement(kAudioObjectPropertyElementMain)
        let candidates: [AudioObjectPropertyElement] = [main, 1, 2]
        let available = candidates.filter { element in
            var address = AudioObjectPropertyAddress(
                mSelector: selector,
                mScope: kAudioDevicePropertyScopeOutput,
                mElement: element
            )
            return AudioObjectHasProperty(device, &address)
        }

        if available.contains(main) {
            return [main]
        }
        return available
    }

    private func readVolume(element: AudioObjectPropertyElement) -> Double? {
        var level: Float32 = 0
        var size = UInt32(MemoryLayout<Float32>.size)
        var address = volumeAddress(element: element)
        guard AudioObjectGetPropertyData(defaultDeviceID, &address, 0, nil, &size, &level) == noErr else {
            return nil
        }
        return clamp(Double(level))
    }

    @discardableResult
    private func setVolume(_ level: Double) -> Bool {
        let clampedLevel = Float32(clamp(level))
        var didSet = false

        for element in volumeElements(on: defaultDeviceID) {
            var value = clampedLevel
            var address = volumeAddress(element: element)
            let size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectSetPropertyData(defaultDeviceID, &address, 0, nil, size, &value) == noErr {
                didSet = true
            }
        }

        let state = readVolume()
        show(.volume(level: state.0, muted: state.1))
        return didSet
    }

    private func readMute(element: AudioObjectPropertyElement) -> Bool? {
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        var address = muteAddress(element: element)
        guard AudioObjectGetPropertyData(defaultDeviceID, &address, 0, nil, &size, &muted) == noErr else {
            return nil
        }
        return muted != 0
    }

    @discardableResult
    private func setMuted(_ muted: Bool) -> Bool {
        var didSet = false
        for element in muteElements(on: defaultDeviceID) {
            var value: UInt32 = muted ? 1 : 0
            var address = muteAddress(element: element)
            let size = UInt32(MemoryLayout<UInt32>.size)
            if AudioObjectSetPropertyData(defaultDeviceID, &address, 0, nil, size, &value) == noErr {
                didSet = true
            }
        }
        return didSet
    }

    private func adjustVolume(by delta: Double) {
        let state = readVolume()
        if state.1, delta > 0 {
            setMuted(false)
        }
        setVolume(state.0 + delta)
    }

    private func toggleMute() {
        let state = readVolume()
        if state.1 {
            if setMuted(false) {
                let newState = readVolume()
                show(.volume(level: newState.0, muted: newState.1))
            } else {
                setVolume(max(volumeBeforeMute, Self.volumeStep))
            }
        } else {
            volumeBeforeMute = max(state.0, Self.volumeStep)
            if setMuted(true) {
                show(.volume(level: state.0, muted: true))
            } else {
                setVolume(0)
            }
        }
    }

    private func controllableDisplays() -> [CGDirectDisplayID] {
        var displayCount: UInt32 = 0

        CGGetActiveDisplayList(0, nil, &displayCount)

        guard displayCount > 0 else {
            return [CGMainDisplayID()]
        }

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(displayCount))
        CGGetActiveDisplayList(displayCount, &displays, &displayCount)

        // Prefer built-in display first.
        let builtIn = displays.filter { CGDisplayIsBuiltin($0) != 0 }
        let others = displays.filter { CGDisplayIsBuiltin($0) == 0 }

        return builtIn + others
    }

    // MARK: - Brightness

    private func setupBrightness() {
        loadDisplayServices()

        lastBrightness = readBrightness() ?? -1

        let timer = Timer(timeInterval: 0.15, repeats: true) { [weak self] _ in
            guard let self else { return }
            MainActor.assumeIsolated {
                self.pollBrightness()
            }
        }

        brightnessTimer = timer
        RunLoop.main.add(timer, forMode: .common)

        NSLog("NotchLand: Brightness polling started. Initial level: \(lastBrightness)")
    }
    
    private func teardownBrightness() {
        brightnessRampTask?.cancel()
        brightnessRampTask = nil
        brightnessTarget = nil
        brightnessTimer?.invalidate()
        brightnessTimer = nil
        getBrightnessFn = nil
        setBrightnessFn = nil
        brightnessDisplayID = nil
        if let displayServicesHandle {
            dlclose(displayServicesHandle)
        }
        displayServicesHandle = nil
    }
    
    private func loadDisplayServices() {
        guard displayServicesHandle == nil else { return }

        guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_NOW) else {
            NSLog("NotchLand: Failed to dlopen DisplayServices")
            return
        }
        displayServicesHandle = handle

        if let getSym = dlsym(handle, "DisplayServicesGetBrightness") {
            getBrightnessFn = unsafeBitCast(getSym, to: GetBrightnessFn.self)
        }
        if let setSym = dlsym(handle, "DisplayServicesSetBrightness") {
            setBrightnessFn = unsafeBitCast(setSym, to: SetBrightnessFn.self)
        }

        if getBrightnessFn == nil || setBrightnessFn == nil {
            NSLog("NotchLand: Could not resolve DisplayServices brightness symbols")
        }
    }

    private func readBrightness() -> Float? {
        guard let getFn = getBrightnessFn else { return nil }

        if let brightnessDisplayID,
           let brightness = readBrightness(displayID: brightnessDisplayID, using: getFn) {
            return brightness
        }

        for displayID in brightnessDisplayCandidates() {
            if let brightness = readBrightness(displayID: displayID, using: getFn) {
                brightnessDisplayID = displayID
                return brightness
            }
        }

        return nil
    }

    private func readBrightness(
        displayID: CGDirectDisplayID,
        using getFn: GetBrightnessFn
    ) -> Float? {
        var brightness: Float = 0
        guard getFn(displayID, &brightness) == 0 else { return nil }
        return clamp(brightness)
    }

    private func pollBrightness() {
        guard brightnessRampTask == nil else { return }
        guard let level = readBrightness() else { return }
        if abs(level - lastBrightness) > 0.005 {
            // macOS auto-brightness can drift this value in the background.
            // Keep our baseline current, but only explicit NotchLand brightness
            // actions should present the HUD.
            lastBrightness = level
            brightnessTarget = nil
        }
    }

    @discardableResult
    private func setBrightness(_ level: Float) -> Bool {
        let clampedLevel = clamp(level)
        brightnessTarget = clampedLevel
        show(.brightness(level: Double(clampedLevel)))
        return rampBrightness(to: clampedLevel)
    }

    @discardableResult
    private func applyBrightness(_ level: Float) -> Bool {
        guard let setFn = setBrightnessFn else { return false }

        let clampedLevel = clamp(level)
        if setBrightness(clampedLevel, using: setFn) {
            lastBrightness = clampedLevel
            return true
        }

        NSLog("NotchLand: DisplayServicesSetBrightness failed")
        return false
    }

    @discardableResult
    private func setBrightness(_ level: Float, using setFn: SetBrightnessFn) -> Bool {
        if let brightnessDisplayID, setFn(brightnessDisplayID, level) == 0 {
            return true
        }

        for displayID in brightnessDisplayCandidates() {
            if setFn(displayID, level) == 0 {
                brightnessDisplayID = displayID
                return true
            }
        }

        return false
    }

    private func brightnessDisplayCandidates() -> [CGDirectDisplayID] {
        var seen: Set<CGDirectDisplayID> = []
        let candidates = controllableDisplays() + [CGMainDisplayID(), 1]
        return candidates.filter { seen.insert($0).inserted }
    }

    @discardableResult
    private func rampBrightness(to targetLevel: Float) -> Bool {
        guard setBrightnessFn != nil else { return false }

        brightnessRampGeneration += 1
        let generation = brightnessRampGeneration
        let targetLevel = clamp(targetLevel)
        let fallbackStart = lastBrightness >= 0 ? lastBrightness : targetLevel
        let startLevel = readBrightness() ?? fallbackStart

        brightnessRampTask?.cancel()
        brightnessRampTask = Task { @MainActor [weak self] in
            guard let self else { return }

            let startedAt = ProcessInfo.processInfo.systemUptime
            while !Task.isCancelled {
                guard self.brightnessRampGeneration == generation else { return }

                let elapsed = ProcessInfo.processInfo.systemUptime - startedAt
                let progress = min(1, elapsed / Self.brightnessRampDuration)
                let eased = Self.easeOutCubic(progress)
                let level = startLevel + (targetLevel - startLevel) * Float(eased)

                guard self.applyBrightness(level) else {
                    self.finishBrightnessRamp(generation: generation, targetLevel: targetLevel)
                    return
                }

                guard progress < 1 else { break }

                let delay = UInt64(Self.brightnessRampFrameInterval * 1_000_000_000)
                try? await Task.sleep(nanoseconds: delay)
            }

            guard !Task.isCancelled else { return }
            _ = self.applyBrightness(targetLevel)
            self.finishBrightnessRamp(generation: generation, targetLevel: targetLevel)
        }

        return true
    }

    private func finishBrightnessRamp(generation: Int, targetLevel: Float) {
        guard brightnessRampGeneration == generation else { return }
        lastBrightness = targetLevel
        brightnessTarget = nil
        brightnessRampTask = nil
    }

    private static func easeOutCubic(_ progress: Double) -> Double {
        let clamped = min(max(progress, 0), 1)
        return 1 - pow(1 - clamped, 3)
    }

    private func adjustBrightness(by delta: Float) {
        let current = brightnessTarget ?? readBrightness() ?? max(lastBrightness, 0)
        let newLevel = clamp(current + delta)

        if !setBrightness(newLevel) {
            // Even if setting fails, still show HUD based on fake internal level.
            lastBrightness = newLevel
            show(.brightness(level: Double(newLevel)))
        }
    }

    // MARK: - Apple HUD suppression

    private func applySystemHUDHidingPreference() {
        if settings.showHUDOnNotch, settings.showNotch {
            startMediaKeyInterception()
        } else {
            stopMediaKeyInterception()
        }
    }

    private func startMediaKeyInterception() {
        guard mediaKeyTap == nil else { return }

        guard refreshAccessibilityTrust() else {
            startAccessibilityRetryTimer()
            return
        }

        let mask = CGEventMask(1 << Self.systemDefinedEventType.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: Self.mediaKeyTapCallback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            NSLog("NotchLand failed to install media-key event tap. Check Accessibility/Input Monitoring permission.")
            return
        }

        guard let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0) else {
            CFMachPortInvalidate(tap)
            return
        }

        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        stopAccessibilityRetryTimer()
        mediaKeyTap = tap
        mediaKeyRunLoopSource = source
    }

    private func stopMediaKeyInterception() {
        if let source = mediaKeyRunLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        if let tap = mediaKeyTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            CFMachPortInvalidate(tap)
        }
        mediaKeyRunLoopSource = nil
        mediaKeyTap = nil
    }

    private func reenableMediaKeyTap() {
        if let tap = mediaKeyTap {
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }

    @discardableResult
    private func refreshAccessibilityTrust() -> Bool {
        let trusted = AXIsProcessTrusted()
        if isAccessibilityTrusted != trusted {
            isAccessibilityTrusted = trusted
        }
        return trusted
    }

    private func startAccessibilityRetryTimer() {
        guard accessibilityRetryTimer == nil else { return }

        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if self.refreshAccessibilityTrust() {
                    self.stopAccessibilityRetryTimer()
                    self.applySystemHUDHidingPreference()
                }
            }
        }
        accessibilityRetryTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func stopAccessibilityRetryTimer() {
        accessibilityRetryTimer?.invalidate()
        accessibilityRetryTimer = nil
    }

    private nonisolated static let mediaKeyTapCallback: CGEventTapCallBack = { _, type, event, userInfo in
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let userInfo {
                MainActor.assumeIsolated {
                    Unmanaged<HUDController>.fromOpaque(userInfo)
                        .takeUnretainedValue()
                        .reenableMediaKeyTap()
                }
            }
            return Unmanaged.passUnretained(event)
        }

        guard let userInfo else {
            return Unmanaged.passUnretained(event)
        }

        return MainActor.assumeIsolated {
            let controller = Unmanaged<HUDController>.fromOpaque(userInfo).takeUnretainedValue()
            return controller.handleMediaKeyEvent(type: type, event: event)
        }
    }

    private func handleMediaKeyEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard type == Self.systemDefinedEventType,
              let nsEvent = NSEvent(cgEvent: event),
              nsEvent.subtype.rawValue == Int16(NX_SUBTYPE_AUX_CONTROL_BUTTONS)
        else {
            return Unmanaged.passUnretained(event)
        }

        let data = nsEvent.data1
        let keyCode = Int((data & 0xFFFF0000) >> 16)
        let keyState = (data & 0x0000FF00) >> 8
        let isKeyDown = keyState == 0xA

        guard handlesMediaKey(keyCode) else {
            return Unmanaged.passUnretained(event)
        }

        if isKeyDown {
            performMediaKeyAction(keyCode)
        }

        return nil
    }

    private func handlesMediaKey(_ keyCode: Int) -> Bool {
        switch keyCode {
        case Int(NX_KEYTYPE_SOUND_UP),
             Int(NX_KEYTYPE_SOUND_DOWN),
             Int(NX_KEYTYPE_MUTE),
             Int(NX_KEYTYPE_BRIGHTNESS_UP),
             Int(NX_KEYTYPE_BRIGHTNESS_DOWN),
             Int(NX_KEYTYPE_CONTRAST_UP),
             Int(NX_KEYTYPE_CONTRAST_DOWN),
             Int(NX_KEYTYPE_ILLUMINATION_UP),
             Int(NX_KEYTYPE_ILLUMINATION_DOWN),
             Int(NX_KEYTYPE_ILLUMINATION_TOGGLE):
            return true
        default:
            return false
        }
    }
    
    @discardableResult
    private func adjustBrightnessSafely(by delta: Float) -> Bool {
        let current = brightnessTarget ?? readBrightness() ?? max(lastBrightness, 0)
        return setBrightness(current + delta)
    }

    private func performMediaKeyAction(_ keyCode: Int) {
        switch keyCode {
        case Int(NX_KEYTYPE_SOUND_UP):
            adjustVolume(by: Self.volumeStep)
        case Int(NX_KEYTYPE_SOUND_DOWN):
            adjustVolume(by: -Self.volumeStep)
        case Int(NX_KEYTYPE_MUTE):
            toggleMute()
        case Int(NX_KEYTYPE_BRIGHTNESS_UP):
            if !adjustBrightnessSafely(by: Self.brightnessStep) { return }
        case Int(NX_KEYTYPE_BRIGHTNESS_DOWN):
            if !adjustBrightnessSafely(by: -Self.brightnessStep) { return }
        case Int(NX_KEYTYPE_CONTRAST_UP):
            adjustContrast(by: Self.contrastStep)
        case Int(NX_KEYTYPE_CONTRAST_DOWN):
            adjustContrast(by: -Self.contrastStep)
        case Int(NX_KEYTYPE_ILLUMINATION_UP):
            adjustKeyboardBrightness(by: Self.keyboardBrightnessStep)
        case Int(NX_KEYTYPE_ILLUMINATION_DOWN):
            adjustKeyboardBrightness(by: -Self.keyboardBrightnessStep)
        case Int(NX_KEYTYPE_ILLUMINATION_TOGGLE):
            toggleKeyboardBrightness()
        default:
            break
        }
    }

    private func adjustKeyboardBrightness(by delta: Double) {
        keyboardBrightnessLevel = clamp(keyboardBrightnessLevel + delta)
        show(.keyboardBrightness(level: keyboardBrightnessLevel))
    }

    private func toggleKeyboardBrightness() {
        keyboardBrightnessLevel = keyboardBrightnessLevel > 0 ? 0 : 0.5
        show(.keyboardBrightness(level: keyboardBrightnessLevel))
    }

    private func adjustContrast(by delta: Double) {
        contrastLevel = clamp(contrastLevel + delta)
        show(.contrast(level: contrastLevel))
    }

    // MARK: - Helpers

    private nonisolated static let systemDefinedEventType = CGEventType(
        rawValue: CGEventType.RawValue(NSEvent.EventType.systemDefined.rawValue)
    )!

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }

    private func clamp(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
