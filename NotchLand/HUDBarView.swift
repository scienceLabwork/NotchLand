//
//  HUDBarView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Renders the level HUD as a compact icon + filled bar, sized
//  to sit in the drawer below the collapsed notch.
//

import SwiftUI

struct HUDBarView: View {
    let kind: HUDController.Kind

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: iconName)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 14, alignment: .center)

            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.18))
                    Capsule()
                        .fill(Color.white)
                        .frame(width: max(0, geo.size.width * clampedLevel))
                        .animation(.easeOut(duration: 0.14), value: clampedLevel)
                }
            }
            .frame(height: 4)
        }
        .padding(.top, 12)
        .padding(.horizontal, 14)
        .frame(height: HUDController.drawerHeight)
    }

    private var iconName: String {
        switch kind {
        case .volume(_, let muted):
            muted ? "speaker.slash.fill" : "speaker.wave.2.fill"
        case .brightness:
            "sun.max.fill"
        case .keyboardBrightness:
            "keyboard"
        case .contrast:
            "circle.lefthalf.filled"
        }
    }

    private var level: Double {
        switch kind {
        case .volume(let l, let muted): muted ? 0 : l
        case .brightness(let l): l
        case .keyboardBrightness(let l): l
        case .contrast(let l): l
        }
    }

    private var clampedLevel: Double {
        min(max(level, 0), 1)
    }
}

#if DEBUG
#Preview("Volume HUD") {
    HUDBarView(kind: .volume(level: 0.72, muted: false))
        .notchPreviewSurface(width: 280, height: HUDController.drawerHeight)
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
