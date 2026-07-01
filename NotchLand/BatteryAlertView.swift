//
//  BatteryAlertView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Compact Dynamic-Island-style battery content for the notch branch.
//

import SwiftUI

enum BatteryAlertMetrics {
    nonisolated static let chargingWidth: CGFloat = 270
    nonisolated static let fullPercentChargingWidth: CGFloat = 290
    nonisolated static let chargingFallbackHeight: CGFloat = 32
    nonisolated static let lowBatterySize = CGSize(width: chargingWidth, height: chargingFallbackHeight)

    nonisolated static var maxWidth: CGFloat {
        max(lowBatterySize.width, fullPercentChargingWidth)
    }

    nonisolated static var maxHeight: CGFloat {
        max(lowBatterySize.height, chargingFallbackHeight)
    }

    nonisolated static func size(forBranchKey key: String) -> CGSize {
        key == "battery-charging"
            ? CGSize(width: chargingWidth, height: chargingFallbackHeight)
            : lowBatterySize
    }

    nonisolated static func size(for presentation: BatteryAlertController.Presentation) -> CGSize {
        switch presentation {
        case .lowBattery(let alert):
            CGSize(width: width(forPercent: alert.percent), height: chargingFallbackHeight)
        case .charging(let status):
            CGSize(width: width(forPercent: status.percent), height: chargingFallbackHeight)
        }
    }

    nonisolated static func width(for presentation: BatteryAlertController.Presentation) -> CGFloat {
        size(for: presentation).width
    }

    nonisolated static func width(forPercent percent: Int) -> CGFloat {
        percent >= 100 ? fullPercentChargingWidth : chargingWidth
    }
}

struct BatteryAlertView: View {
    let presentation: BatteryAlertController.Presentation

    @State private var isContentVisible = false
    @State private var isPulsing = false
    @State private var revealTask: Task<Void, Never>?

    var body: some View {
        Group {
            switch presentation {
            case .lowBattery(let alert):
                lowBatteryContent(alert)
            case .charging(let status):
                chargingContent(status)
            }
        }
        .scaleEffect(isContentVisible ? 1 : 0.72, anchor: .center)
        .blur(radius: isContentVisible ? 0 : 8)
        .opacity(isContentVisible ? 1 : 0)
        .animation(
            .easeOut(duration: BatteryPresentationTiming.contentRevealDuration),
            value: isContentVisible
        )
        .onAppear {
            scheduleContentReveal()
        }
        .onDisappear {
            revealTask?.cancel()
            revealTask = nil
        }
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

    private func lowBatteryContent(_ alert: BatteryAlertController.Alert) -> some View {
        HStack(spacing: 0) {
            lowBatteryIcon(alert)
                .padding(.leading, NowPlayingMetrics.collapsedSidePadding)

            Spacer(minLength: 0)

            Text("\(alert.percent)%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(alertAccentColor(alert))
                .lineLimit(1)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, NowPlayingMetrics.collapsedSidePadding + 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    private func chargingContent(_ status: BatteryAlertController.ChargingStatus) -> some View {
        HStack(spacing: 0) {
            chargingIcon
                .padding(.leading, NowPlayingMetrics.collapsedSidePadding)

            Spacer(minLength: 0)

            Text("\(status.percent)%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(chargingGreen)
                .lineLimit(1)
                .frame(width: 44, alignment: .trailing)
                .padding(.trailing, NowPlayingMetrics.collapsedSidePadding + 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear {
            withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                isPulsing = true
            }
        }
    }

    private var chargingIcon: some View {
        ZStack {
//            Circle()
//                .fill(chargingGreen.opacity(0.18))
//                .frame(width: 23, height: 23)

            Image(systemName: "bolt.fill")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(chargingGreen)
                .scaleEffect(isPulsing ? 1.10 : 0.94)
        }
        .frame(width: NowPlayingMetrics.collapsedArtSize, height: NowPlayingMetrics.collapsedArtSize)
    }

    private func lowBatteryIcon(_ alert: BatteryAlertController.Alert) -> some View {
        let color = alertAccentColor(alert)

        return ZStack {
//            Circle()
//                .fill(color.opacity(0.18))
//                .frame(width: 23, height: 23)

            Image(systemName: "exclamationmark")
                .font(.system(size: 15, weight: .heavy, design: .rounded))
                .foregroundStyle(color)
                .scaleEffect(isPulsing ? 1.10 : 0.94)
        }
        .frame(width: NowPlayingMetrics.collapsedArtSize, height: NowPlayingMetrics.collapsedArtSize)
    }

    private var chargingGreen: Color {
        Color(red: 0.23, green: 0.86, blue: 0.33)
    }

    private func alertAccentColor(_ alert: BatteryAlertController.Alert) -> Color {
        alert.milestone <= 10
            ? Color(red: 1.0, green: 0.28, blue: 0.22)
            : Color(red: 1.0, green: 0.78, blue: 0.18)
    }
}

#if DEBUG
#Preview("Low Battery Alert") {
    BatteryAlertView(
        presentation: .lowBattery(
            BatteryAlertController.Alert(
                percent: 10,
                timeRemaining: nil,
                milestone: 10
            )
        )
    )
    .notchPreviewSurface(width: BatteryAlertMetrics.chargingWidth, height: 32)
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
