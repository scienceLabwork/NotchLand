//
//  HoverTracker.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  NSTrackingArea-backed hover wrapper. SwiftUI's `.onHover` is unreliable inside
//  borderless non-activating panels — this gives consistent enter/exit events.
//

import AppKit
import SwiftUI

struct HoverTracker: NSViewRepresentable {
    let onEntered: () -> Void
    let onExited: () -> Void

    func makeNSView(context: Context) -> TrackingView {
        TrackingView(onEntered: onEntered, onExited: onExited)
    }

    func updateNSView(_ nsView: TrackingView, context: Context) {
        nsView.onEntered = onEntered
        nsView.onExited = onExited
    }

    final class TrackingView: NSView {
        var onEntered: () -> Void
        var onExited: () -> Void
        private var trackingArea: NSTrackingArea?

        init(onEntered: @escaping () -> Void, onExited: @escaping () -> Void) {
            self.onEntered = onEntered
            self.onExited = onExited
            super.init(frame: .zero)
        }

        required init?(coder: NSCoder) { fatalError("init(coder:) not used") }

        override func updateTrackingAreas() {
            super.updateTrackingAreas()
            if let trackingArea {
                removeTrackingArea(trackingArea)
            }
            let area = NSTrackingArea(
                rect: bounds,
                options: [.activeAlways, .mouseEnteredAndExited, .inVisibleRect],
                owner: self,
                userInfo: nil
            )
            addTrackingArea(area)
            trackingArea = area
        }

        override func mouseEntered(with event: NSEvent) { onEntered() }
        override func mouseExited(with event: NSEvent) { onExited() }
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
