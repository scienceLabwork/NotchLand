//
//  SettingsView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Native macOS settings shell with a fixed sidebar. Avoid NavigationSplitView
//  because it recreates the sidebar toolbar button during selection changes.
//

import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var settings: NotchSettings
    @State private var selection: SettingsSection = .general
    #if DEBUG
    @AppStorage("settings.debugMenuUnlocked") private var debugMenuUnlocked = false
    @State private var aboutIconTapCount = 0
    #endif

    var body: some View {
        HStack(spacing: 0) {
            SettingsSidebar(selection: $selection, showsDebug: showsDebug)
                .frame(width: 210)

            Divider()

            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(width: 720, height: 520)
        .preferredColorScheme(settings.theme.colorScheme)
    }

    private var showsDebug: Bool {
        #if DEBUG
        debugMenuUnlocked
        #else
        false
        #endif
    }

    @ViewBuilder
    private var detailView: some View {
        switch selection {
        case .general:
            GeneralSettingsView()

        case .calendar:
            CalendarSettingsView()

        case .behavior:
            BehaviorSettingsView()

        case .appearance:
            AppearanceSettingsView()

        #if DEBUG
        case .debug:
            if debugMenuUnlocked {
                DebugSettingsView()
            } else {
                AboutSettingsView(onIconClick: handleAboutIconClick)
                    .onAppear { selection = .about }
            }
        #endif

        case .about:
            AboutSettingsView(onIconClick: handleAboutIconClick)
        }
    }

    private func handleAboutIconClick() {
        #if DEBUG
        guard !debugMenuUnlocked else { return }
        aboutIconTapCount += 1
        if aboutIconTapCount >= 7 {
            debugMenuUnlocked = true
            selection = .debug
        }
        #endif
    }
}

#if DEBUG
#Preview("Settings") {
    NotchPreviewContainer {
        SettingsView()
            .frame(width: 900, height: 620)
    }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
