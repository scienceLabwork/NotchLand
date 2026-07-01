//
//  OnboardingPermissionsStepView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Final onboarding step: Calendar and Accessibility permissions, both
//  skippable. "Get Started" finishes onboarding regardless of their state.
//

import AppKit
import EventKit
import SwiftUI

struct OnboardingPermissionsStepView: View {
    let onFinish: () -> Void

    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var hud: HUDController

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("A couple of permissions")
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)

            VStack(spacing: 10) {
                permissionRow(
                    symbol: "calendar",
                    title: "Calendar",
                    detail: "Show today's events and countdowns.",
                    isGranted: calendar.canReadEvents,
                    actionTitle: calendarActionTitle,
                    action: calendarAction
                )

                permissionRow(
                    symbol: "accessibility",
                    title: "Accessibility",
                    detail: "Replace the system volume/brightness HUD.",
                    isGranted: hud.isAccessibilityTrusted,
                    actionTitle: "Enable",
                    action: { hud.requestAccessibilityPermissionIfNeeded() }
                )
            }

            Spacer(minLength: 0)

            Button(action: onFinish) {
                Text("GET STARTED")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .tracking(1.2)
                    .foregroundStyle(Color.black)
                    .frame(maxWidth: .infinity, maxHeight: 32)
                    .background(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .fill(Color(red: 0.36, green: 0.86, blue: 0.45))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .strokeBorder(Color.white.opacity(0.18), lineWidth: 0.5)
                    )
                    .shadow(color: Color.green.opacity(0.35), radius: 10, x: 0, y: 4)
            }
            .buttonStyle(.plain)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private func permissionRow(
        symbol: String,
        title: String,
        detail: String,
        isGranted: Bool,
        actionTitle: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(isGranted ? Color(red: 0.23, green: 0.86, blue: 0.33) : .white.opacity(0.8))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 1) {
                Text(title)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text(detail)
                    .font(.system(size: 10.5, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }

            Spacer(minLength: 8)

            if isGranted {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color(red: 0.23, green: 0.86, blue: 0.33))
            } else {
                Button(action: action) {
                    Text(actionTitle)
                        .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.14))
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var calendarActionTitle: String {
        calendar.authorizationStatus == .denied || calendar.authorizationStatus == .restricted
            ? "Open Settings"
            : "Enable"
    }

    private func calendarAction() {
        switch calendar.authorizationStatus {
        case .denied, .restricted:
            openCalendarPrivacySettings()
        default:
            calendar.requestAccess()
        }
    }

    private func openCalendarPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        ) else { return }
        NSWorkspace.shared.open(url)
    }
}

#if DEBUG
#Preview("Onboarding Permissions Step") {
    NotchPreviewContainer {
        OnboardingPermissionsStepView(onFinish: {})
            .padding(20)
            .frame(
                width: OnboardingMetrics.expandedStepSize.width,
                height: OnboardingMetrics.expandedStepSize.height
            )
            .background(Color.black)
    }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
