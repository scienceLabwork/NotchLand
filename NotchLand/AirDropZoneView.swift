//
//  AirDropZoneView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Drop surface shown while a file drag hovers near the notch: a full-width
//  dotted zone with the AirDrop glyph centered in it, offset well below the
//  physical camera notch so nothing renders under it. Idle state is a plain
//  dotted outline (with AirDrop's own "searching" ring/glyph animation);
//  once the drag is directly over the zone, it fills with a light,
//  translucent blue to confirm the drop.
//

import SwiftUI

enum AirDropZoneMetrics {
    nonisolated static let width: CGFloat = 260
    // Tall enough that the zone clears the physical camera notch (which sits
    // in the top `NotchSettings.Defaults.collapsedHeight`, ~32pt) instead of
    // rendering underneath it.
    nonisolated static let height: CGFloat = 130
}

struct AirDropZoneView: View {
    @EnvironmentObject private var airDrop: AirDropController
    @State private var isPulsing = false

    private static let tint = Color(red: 0.24, green: 0.58, blue: 1.0)

    var body: some View {
        let isHovered = airDrop.isHoveringDropZone

        dropZone(isHovered: isHovered)
            .padding(.horizontal, 14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .padding(.bottom, 12)
            .onAppear { isPulsing = true }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("AirDrop")
            .accessibilityHint("Shares dropped files with AirDrop")
            .accessibilityAddTraits(isHovered ? [.isSelected] : [])
    }

    private func dropZone(isHovered: Bool) -> some View {
        VStack(spacing: 6) {
            glyph(isHovered: isHovered)

            Text(isHovered ? "Release to AirDrop" : "AirDrop")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(isHovered ? Self.tint : Color.white.opacity(0.8))
                .lineLimit(1)
                .contentTransition(.identity)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 84)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(isHovered ? Self.tint.opacity(0.22) : Color.clear)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(
                    isHovered ? Self.tint.opacity(0.9) : Color.white.opacity(0.4),
                    style: StrokeStyle(lineWidth: isHovered ? 1.8 : 1.6, lineCap: .round, dash: [1, 7])
                )
        )
        .animation(.easeOut(duration: 0.2), value: isHovered)
    }

    @ViewBuilder
    private func glyph(isHovered: Bool) -> some View {
        ZStack {
            if !isHovered {
                ring(delay: 0)
                ring(delay: 0.7)
            }

            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 26, weight: .semibold))
                .foregroundStyle(isHovered ? Self.tint : Color.white.opacity(0.9))
                .symbolEffect(
                    .variableColor.iterative.dimInactiveLayers,
                    options: .repeating,
                    isActive: !isHovered
                )
        }
        .frame(width: 40, height: 40)
        .animation(.easeOut(duration: 0.2), value: isHovered)
    }

    private func ring(delay: Double) -> some View {
        Circle()
            .stroke(Self.tint.opacity(0.55), lineWidth: 1.4)
            .frame(width: 32, height: 32)
            .scaleEffect(isPulsing ? 1.7 : 1)
            .opacity(isPulsing ? 0 : 0.6)
            .animation(
                .easeOut(duration: 1.7).repeatForever(autoreverses: false).delay(delay),
                value: isPulsing
            )
    }
}

#if DEBUG
#Preview("AirDrop Drop Zone") {
    NotchPreviewContainer {
        AirDropZoneView()
            .notchPreviewSurface(
                width: AirDropZoneMetrics.width,
                height: AirDropZoneMetrics.height
            )
    }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
