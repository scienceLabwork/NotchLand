//
//  AppState.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Runtime (non-persisted) state for the floating notch — currently the
//  expanded/collapsed flag plus the hover state machine that drives it.
//

import Combine
import SwiftUI

nonisolated final class AppState: ObservableObject {
    /// Spring tuned to feel like Dynamic Island / Apple "fluid" — the same parameters
    /// `WindowManager` uses to drive the NSPanel resize, so the panel and the SwiftUI
    /// shape settle together.
    static let expansionAnimation: Animation = .spring(
        response: 0.5,
        dampingFraction: 0.78,
        blendDuration: 0
    )
    /// Delay before hover triggers full expansion, so the small "peek" scale is visible first.
    static let hoverExpandDelay: TimeInterval = 0.35

    @Published var isExpanded: Bool = false
    @Published var isHovering: Bool = false

    private let settings: NotchSettings
    private var collapseTask: Task<Void, Never>?
    private var expandTask: Task<Void, Never>?

    init(settings: NotchSettings) {
        self.settings = settings
    }

    @MainActor
    func mouseEntered() {
        isHovering = true
        cancelCollapse()
        guard settings.hoverToExpand, !isExpanded else { return }
        scheduleExpand()
    }

    @MainActor
    func mouseExited() {
        isHovering = false
        cancelExpand()
        guard settings.autoCollapse, isExpanded else { return }
        cancelCollapse()
        let delayNanos = UInt64(max(0, settings.collapseDelay) * 1_000_000_000)
        collapseTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard let self, !Task.isCancelled else { return }
            withAnimation(Self.expansionAnimation) { self.isExpanded = false }
        }
    }

    @MainActor
    func toggle() {
        cancelCollapse()
        cancelExpand()
        withAnimation(Self.expansionAnimation) { isExpanded.toggle() }
    }

    @MainActor
    func expand() {
        cancelCollapse()
        cancelExpand()
        guard !isExpanded else { return }
        withAnimation(Self.expansionAnimation) { isExpanded = true }
    }

    @MainActor
    func collapse() {
        cancelCollapse()
        cancelExpand()
        guard isExpanded else { return }
        withAnimation(Self.expansionAnimation) { isExpanded = false }
    }

    @MainActor
    func resetToCollapsed() {
        cancelCollapse()
        cancelExpand()
        withTransaction(Transaction(animation: nil)) {
            isHovering = false
            isExpanded = false
        }
    }

    @MainActor
    private func scheduleExpand() {
        cancelExpand()
        let delayNanos = UInt64(Self.hoverExpandDelay * 1_000_000_000)
        expandTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard let self, !Task.isCancelled, self.isHovering, !self.isExpanded else { return }
            withAnimation(Self.expansionAnimation) { self.isExpanded = true }
        }
    }

    private func cancelCollapse() {
        collapseTask?.cancel()
        collapseTask = nil
    }

    private func cancelExpand() {
        expandTask?.cancel()
        expandTask = nil
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
