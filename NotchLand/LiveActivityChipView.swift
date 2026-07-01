//
//  LiveActivityChipView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Dynamic Island-style live activity: content flanks the physical notch —
//  icon (and short title) on the left wing, detail/progress on the right —
//  with a center gap the width of the hardware notch. Audio-device connects
//  get a short "connecting → done" flourish: the glyph bounces in with a
//  pulsing ring, then settles with a checkmark once paired.
//

import SwiftUI

enum LiveActivityChipMetrics {
    /// Total body width: a left wing + notch gap + right wing. Wide enough to
    /// flank the hardware notch without the content sliding under it.
    nonisolated static let flankWidth: CGFloat = 332
}

struct LiveActivityChipView: View {
    let activity: LiveActivity

    @EnvironmentObject private var settings: NotchSettings
    @State private var didBounce = false
    @State private var isConnecting: Bool

    init(activity: LiveActivity) {
        self.activity = activity
        _isConnecting = State(initialValue: Self.isAudioDeviceConnect(activity))
    }

    private var notchGap: CGFloat { CGFloat(settings.collapsedWidth) }

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 6) {
                iconGlyph
                Text(activity.title)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .minimumScaleFactor(0.75)
            }
            .padding(.leading, 14)

            Spacer(minLength: notchGap)

            Group {
                if let progress = activity.progress {
                    ProgressView(value: progress)
                        .progressViewStyle(.circular)
                        .controlSize(.mini)
                } else if let detail = detailText {
                    Text(detail)
                        .font(.system(size: 11, weight: .medium).monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .contentTransition(.identity)
                }
            }
            .padding(.trailing, 14)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.top, 6)
        .onAppear { playConnectSequenceIfNeeded() }
    }

    @ViewBuilder
    private var iconGlyph: some View {
        ZStack(alignment: .bottomTrailing) {
            ZStack {
                if isConnecting {
                    connectingRing(delay: 0)
                    connectingRing(delay: 0.5)
                }
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(tint)
                    .symbolEffect(.bounce, value: didBounce)
            }
            .frame(width: 20, height: 20)

            if isAudioDeviceKind, !isConnecting {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(.white, .green)
                    .background(Circle().fill(.black))
                    .offset(x: 4, y: 3)
                    .transition(.scale(scale: 0.4).combined(with: .opacity))
            }
        }
    }

    private func connectingRing(delay: Double) -> some View {
        Circle()
            .stroke(tint.opacity(0.55), lineWidth: 1.2)
            .frame(width: 16, height: 16)
            .scaleEffect(isConnecting ? 1.9 : 1)
            .opacity(isConnecting ? 0 : 0.7)
            .animation(
                .easeOut(duration: 1.1).repeatForever(autoreverses: false).delay(delay),
                value: isConnecting
            )
    }

    private var detailText: String? {
        isAudioDeviceKind && isConnecting ? "Connecting…" : activity.detail
    }

    private var isAudioDeviceKind: Bool { Self.isAudioDeviceConnect(activity) }

    private static func isAudioDeviceConnect(_ activity: LiveActivity) -> Bool {
        if case .audioDevice = activity.kind { return true }
        return false
    }

    private func playConnectSequenceIfNeeded() {
        didBounce = true
        guard isAudioDeviceKind else { return }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 650_000_000)
            withAnimation(.spring(response: 0.3, dampingFraction: 0.62)) {
                isConnecting = false
            }
        }
    }

    private var symbol: String {
        switch activity.kind {
        case .audioDevice: "airpods.gen3"
        case .timer: "timer"
        case .download: "arrow.down.circle.fill"
        }
    }

    private var tint: Color {
        switch activity.kind {
        case .audioDevice: .blue
        case .timer: .orange
        case .download: .green
        }
    }
}

#if DEBUG
#Preview("Live Activity") {
    NotchPreviewContainer {
        LiveActivityChipView(activity: PreviewSamples.timerActivity)
            .notchPreviewSurface(width: LiveActivityChipMetrics.flankWidth, height: 40)
    }
}

#Preview("Live Activity - AirPods Connect") {
    NotchPreviewContainer {
        LiveActivityChipView(activity: LiveActivity(
            kind: .audioDevice(name: "Rudra's AirPods Pro", batteryPercent: 80),
            title: "Rudra's AirPods Pro",
            detail: "Connected",
            progress: nil
        ))
        .notchPreviewSurface(width: LiveActivityChipMetrics.flankWidth, height: 40)
    }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
