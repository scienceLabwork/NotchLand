//
//  SettingsSidebar.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//

import SwiftUI

enum SettingsSection: String, CaseIterable, Identifiable, Hashable {
    case general, calendar, behavior, appearance
    #if DEBUG
    case debug
    #endif
    case about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: "General"
        case .calendar: "Calendar"
        case .behavior: "Behavior"
        case .appearance: "Appearance"
        #if DEBUG
        case .debug: "Debug"
        #endif
        case .about: "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: "gearshape"
        case .calendar: "calendar"
        case .behavior: "hand.point.up.left"
        case .appearance: "paintpalette"
        #if DEBUG
        case .debug: "wrench.and.screwdriver"
        #endif
        case .about: "info.circle"
        }
    }
}

struct SettingsSidebar: View {
    @Binding var selection: SettingsSection
    let showsDebug: Bool

    var body: some View {
        List(sections, selection: $selection) { section in
            Label(section.title, systemImage: section.systemImage)
                .tag(section)
        }
        .listStyle(.sidebar)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var sections: [SettingsSection] {
        SettingsSection.allCases.filter { section in
            #if DEBUG
            if section == .debug {
                return showsDebug
            }
            #endif
            return true
        }
    }
}

#if DEBUG
private struct SettingsSidebarPreview: View {
    @State private var selection: SettingsSection = .general

    var body: some View {
        SettingsSidebar(selection: $selection, showsDebug: true)
            .frame(width: 190, height: 420)
    }
}

#Preview("Settings Sidebar") {
    SettingsSidebarPreview()
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
