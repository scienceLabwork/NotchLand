//
//  FocusModeAlertView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Compact Dynamic-Island-style Focus mode content for the notch branch.
//

import SwiftUI

enum FocusModeAlertMetrics {
    nonisolated static let width: CGFloat = 270
    nonisolated static let fallbackHeight: CGFloat = 32

    nonisolated static var maxWidth: CGFloat { width }
    nonisolated static var maxHeight: CGFloat { fallbackHeight }
}

struct FocusModeAlertView: View {
    let presentation: FocusModeController.Presentation

    @State private var isContentVisible = false
    @State private var isPulsing = false
    @State private var revealTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 0) {
            focusIcon
                .padding(.leading, NowPlayingMetrics.collapsedSidePadding)

            Spacer(minLength: 0)

            Text(presentation.isActive ? "On" : "Off")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundStyle(focusColor)
                .lineLimit(1)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, NowPlayingMetrics.collapsedSidePadding + 2)
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
            withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
        }
    }

    private var focusIcon: some View {
        ZStack {
//            Circle()
//                .fill(focusColor.opacity(0.18))
//                .frame(width: 23, height: 23)

            Image(systemName: "moon.fill")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(focusColor)
                .scaleEffect(isPulsing ? 1.10 : 0.94)
        }
        .frame(width: NowPlayingMetrics.collapsedArtSize, height: NowPlayingMetrics.collapsedArtSize)
    }

    private var focusColor: Color {
        presentation.isActive
            ? Color(red: 0.47, green: 0.64, blue: 1.0)
            : Color.gray.opacity(0.72)
    }

    private func scheduleContentReveal() {
        revealTask?.cancel()
        isContentVisible = false
        let delayNanos = UInt64(BatteryPresentationTiming.expandDuration * 1_000_000_000)
        revealTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: delayNanos)
            guard !Task.isCancelled else { return }
            isContentVisible = true
        }
    }
}

#if DEBUG
#Preview("Focus Alert") {
    FocusModeAlertView(
        presentation: FocusModeController.Presentation(isActive: true)
    )
    .notchPreviewSurface(width: FocusModeAlertMetrics.width, height: 32)
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
