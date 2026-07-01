//
//  AudioDeviceActivitySource.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Posts a chip when the default audio output device changes to a different
//  physical device (AirPods connect moment). Ignores the built-in speakers
//  switchback so only external connects get the celebration.
//

import CoreAudio
import Foundation

@MainActor
final class AudioDeviceActivitySource {
    private let activities: LiveActivityController
    private var lastDeviceID: AudioDeviceID = 0
    private var listenerBlock: AudioObjectPropertyListenerBlock?
    private var address = AudioObjectPropertyAddress(
        mSelector: kAudioHardwarePropertyDefaultOutputDevice,
        mScope: kAudioObjectPropertyScopeGlobal,
        mElement: kAudioObjectPropertyElementMain
    )

    init(activities: LiveActivityController) {
        self.activities = activities
    }

    func start() {
        guard listenerBlock == nil else { return }
        lastDeviceID = currentDefaultDevice()
        let handler: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.defaultDeviceChanged() }
            }
        }
        listenerBlock = handler
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject), &address, .main, handler
        )
    }

    func stop() {
        if let block = listenerBlock {
            AudioObjectRemovePropertyListenerBlock(
                AudioObjectID(kAudioObjectSystemObject), &address, .main, block
            )
            listenerBlock = nil
        }
    }

    func debugPostSample() {
        postConnectChip(name: "Rudra's AirPods Pro")
    }

    private func defaultDeviceChanged() {
        let device = currentDefaultDevice()
        guard device != lastDeviceID, device != 0 else { return }
        lastDeviceID = device
        let name = deviceName(device)
        // Skip the built-in speaker switchback — only celebrate external connects.
        guard !name.localizedCaseInsensitiveContains("speaker") else { return }
        postConnectChip(name: name)
    }

    private func postConnectChip(name: String) {
        let activity = LiveActivity(
            kind: .audioDevice(name: name, batteryPercent: nil),
            title: name,
            detail: "Connected",
            progress: nil
        )
        activities.post(activity)
        Task { @MainActor [weak activities] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            activities?.end(activity.id)
        }
    }

    private func currentDefaultDevice() -> AudioDeviceID {
        var deviceID = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID
        )
        return deviceID
    }

    private func deviceName(_ id: AudioDeviceID) -> String {
        var nameAddress = AudioObjectPropertyAddress(
            mSelector: kAudioObjectPropertyName,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var name: CFString = "" as CFString
        var size = UInt32(MemoryLayout<CFString>.size)
        let status = withUnsafeMutablePointer(to: &name) { ptr -> OSStatus in
            AudioObjectGetPropertyData(id, &nameAddress, 0, nil, &size, ptr)
        }
        return status == noErr ? (name as String) : "Audio Device"
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
