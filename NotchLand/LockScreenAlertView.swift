//
//  LockScreenAlertView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Compact padlock content for the screen lock/unlock notch branch. Content
//  flanks the physical notch: animated lock glyph on the left wing, state text
//  on the right wing, with a center gap the width of the hardware notch.
//

import SwiftUI

enum LockScreenAlertMetrics {
    /// Wide enough for left/right wings around the physical notch gap.
    nonisolated static let width: CGFloat = 260
    nonisolated static let fallbackHeight: CGFloat = 32

    nonisolated static var maxWidth: CGFloat { width }
    nonisolated static var maxHeight: CGFloat { fallbackHeight }
}

struct LockScreenAlertView: View {
    let presentation: ScreenLockController.Presentation

    @EnvironmentObject private var settings: NotchSettings
    @State private var isContentVisible = false
    @State private var isPulsing = false
    @State private var isOpen = false
    @State private var revealTask: Task<Void, Never>?
    @State private var openTask: Task<Void, Never>?

    private var notchGap: CGFloat { CGFloat(settings.collapsedWidth) }

    var body: some View {
        HStack(spacing: 0) {
            lockIcon
                .padding(.leading, NowPlayingMetrics.collapsedSidePadding - 5)
                .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: notchGap - 20)

            Text(statusText)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .foregroundStyle(iconColor)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .scaleEffect(isContentVisible ? 1 : 0.72, anchor: .center)
        .blur(radius: isContentVisible ? 0 : 8)
        .opacity(isContentVisible ? 1 : 0)
        .animation(
            .easeOut(duration: BatteryPresentationTiming.contentRevealDuration),
            value: isContentVisible
        )
        .onAppear {
            scheduleContentReveal()
            // Already-unlocking on appear (e.g. unlock with no prior locked
            // branch shown): open once the fresh reveal has played.
            if presentation.phase == .unlocking {
                scheduleUnlock(afterReveal: true)
            }
        }
        .onChange(of: presentation.phase) { _, phase in
            // The persisted locked branch flips to .unlocking in place —
            // same view identity, so onAppear won't fire again. Spring the
            // shackle open shortly after the flip.
            if phase == .unlocking {
                scheduleUnlock(afterReveal: false)
            }
        }
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
            openTask?.cancel()
            openTask = nil
        }
    }

    private var lockIcon: some View {
        ZStack {
//            Circle()
//                .fill(iconColor.opacity(0.18))
//                .frame(width: 30, height: 30)

            Image(systemName: isOpen ? "lock.open.fill" : "lock.fill")
                .font(.system(size: 16, weight: .heavy, design: .rounded))
                .foregroundStyle(iconColor)
//                .contentTransition(.symbolEffect(.replace.downUp))
//                .symbolEffect(.bounce, value: isOpen)
//                .scaleEffect(isPulsing ? 1.08 : 0.94)
        }
        .frame(width: 32, height: 32)
    }

    private var statusText: String {
        switch presentation.phase {
        case .locked:
            ""
        case .unlocking:
            isOpen ? "" : ""
        }
    }

    /// Muted grey while locked; a confident green the moment it springs open.
    private var iconColor: Color {
        isOpen
        ? Color.white.opacity(0.9)
        : Color.white.opacity(0.9)
    }

    private func scheduleContentReveal() {
        revealTask?.cancel()
        if presentation.phase == .locked {
            isContentVisible = true
            return
        }
        isContentVisible = false
        let delayNanos = UInt64(BatteryPresentationTiming.expandDuration * 1_000_000_000)
        revealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard !Task.isCancelled else { return }
            isContentVisible = true
        }
    }

    /// Springs the padlock open. `afterReveal` waits for the fresh pop/reveal to
    /// finish (used when the branch appears already unlocking); otherwise it uses
    /// a short delay for the in-place flip from a persisted locked padlock.
    private func scheduleUnlock(afterReveal: Bool) {
        openTask?.cancel()
        let delay: TimeInterval = afterReveal
            ? BatteryPresentationTiming.expandDuration
                + BatteryPresentationTiming.contentRevealDuration
                + 0.18
            : 0.25
        let delayNanos = UInt64(delay * 1_000_000_000)
        openTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.4, dampingFraction: 0.55)) {
                isOpen = true
            }
        }
    }
}

#if DEBUG
#Preview("Lock Screen Alert") {
    NotchPreviewContainer {
        LockScreenAlertView(
            presentation: ScreenLockController.Presentation(phase: .locked)
        )
        .notchPreviewSurface(width: LockScreenAlertMetrics.width, height: 32)
    }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
