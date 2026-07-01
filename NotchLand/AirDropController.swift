//
//  AirDropController.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Owns the drag-over drop-target presentation and the AirDrop share action.
//  WindowManager's drag monitors call dragApproached()/dragEnded(); the
//  hosting view's NSDraggingDestination calls handleDrop(urls:).
//

import AppKit
import Combine

@MainActor
final class AirDropController: ObservableObject {
    /// A file drag is near the notch: show the drop zone.
    @Published private(set) var isDropTargetVisible = false
    /// Whether the drag is directly over the drop zone, for highlight feedback.
    @Published private(set) var isHoveringDropZone = false

    private let settings: NotchSettings

    init(settings: NotchSettings) {
        self.settings = settings
    }

    func dragApproached() {
        guard settings.airDropEnabled else { return }
        isDropTargetVisible = true
    }

    func dragEnded() {
        isDropTargetVisible = false
        isHoveringDropZone = false
    }

    func setHoveringDropZone(_ isHovering: Bool) {
        guard isDropTargetVisible else { return }
        isHoveringDropZone = isHovering
    }

    func handleDrop(urls: [URL]) {
        defer { dragEnded() }
        guard !urls.isEmpty else { return }
        shareViaAirDrop(urls)
    }

    func shareViaAirDrop(_ urls: [URL]) {
        guard let service = Self.sharingService(for: urls) else {
            NSSound.beep()
            return
        }
        // NotchLand runs as a non-activating accessory panel (LSUIElement), so
        // it's never the frontmost app. NSSharingService's AirDrop picker won't
        // surface from a background process — bring the app forward first.
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
    }

    /// Whether AirDrop can actually accept these items — used to gate the
    /// drop zone so it only opens for content that's genuinely shareable.
    nonisolated static func canShareViaAirDrop(_ urls: [URL]) -> Bool {
        sharingService(for: urls) != nil
    }

    private nonisolated static func sharingService(for urls: [URL]) -> NSSharingService? {
        guard !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls)
        else { return nil }
        return service
    }

    func debugShowDropTarget() {
        isDropTargetVisible = true
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
