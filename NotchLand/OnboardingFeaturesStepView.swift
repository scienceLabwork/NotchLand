//
//  OnboardingFeaturesStepView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Second onboarding step: a compact highlight reel of the shipped
//  features, shown between the welcome animation and the permissions step.
//

import SwiftUI

private struct OnboardingFeatureRow: Identifiable {
    let id = UUID()
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
}

struct OnboardingFeaturesStepView: View {
    private let rows: [OnboardingFeatureRow] = [
        OnboardingFeatureRow(
            symbol: "music.note",
            tint: .pink,
            title: "Now Playing",
            detail: "Media controls right in the notch."
        ),
        OnboardingFeatureRow(
            symbol: "dot.radiowaves.left.and.right",
            tint: Color(red: 0.24, green: 0.58, blue: 1.0),
            title: "AirDrop",
            detail: "Drag a file near the notch to share it."
        ),
        OnboardingFeatureRow(
            symbol: "slider.horizontal.3",
            tint: .orange,
            title: "System HUDs",
            detail: "Volume and brightness overlays."
        ),
        OnboardingFeatureRow(
            symbol: "bolt.fill",
            tint: .green,
            title: "Battery & Focus",
            detail: "Quick alerts when they change."
        ),
        OnboardingFeatureRow(
            symbol: "calendar",
            tint: .red,
            title: "Calendar",
            detail: "Today's events and countdowns."
        ),
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("What NotchLand does")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(rows) { row in
                    HStack(spacing: 10) {
                        Image(systemName: row.symbol)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(row.tint)
                            .frame(width: 20)

                        VStack(alignment: .leading, spacing: 1) {
                            Text(row.title)
                                .font(.system(size: 12, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            Text(row.detail)
                                .font(.system(size: 10.5, weight: .medium, design: .rounded))
                                .foregroundStyle(.white.opacity(0.6))
                        }

                        Spacer(minLength: 0)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#if DEBUG
#Preview("Onboarding Features Step") {
    OnboardingFeaturesStepView()
        .padding(20)
        .frame(
            width: OnboardingMetrics.expandedStepSize.width,
            height: OnboardingMetrics.expandedStepSize.height
        )
        .background(Color.black)
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
