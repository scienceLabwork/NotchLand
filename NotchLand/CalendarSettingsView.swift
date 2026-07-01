//
//  CalendarSettingsView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//

import AppKit
import EventKit
import SwiftUI

struct CalendarSettingsView: View {
    @EnvironmentObject var calendar: CalendarService
    @EnvironmentObject var settings: NotchSettings

    var body: some View {
        Form {
            Section("Connection") {
                HStack(alignment: .center, spacing: 12) {
                    statusIcon

                    VStack(alignment: .leading, spacing: 3) {
                        Text(calendar.connectionTitle)
                            .font(.headline)
                        Text(connectionDescription)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer(minLength: 0)

                    connectionButton
                }
                .padding(.vertical, 4)

                if let errorMessage = calendar.errorMessage {
                    Text(errorMessage)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            Section("Countdown") {
                Toggle("Show event countdown in notch", isOn: $settings.eventCountdownEnabled)

                Picker("Show countdown when event is within", selection: $settings.eventCountdownThresholdMinutes) {
                    ForEach(NotchSettings.eventCountdownThresholdOptions, id: \.self) { minutes in
                        Text(thresholdLabel(for: minutes)).tag(minutes)
                    }
                }
                .disabled(!settings.eventCountdownEnabled)

                Text("Skips all-day events and calendars named 'Holidays' or 'Birthdays'.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Today") {
                if calendar.canReadEvents {
                    if calendar.events.isEmpty {
                        Label("No events scheduled for today.", systemImage: "sparkles")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(calendar.events.prefix(6)) { event in
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(eventAccent(event))
                                    .frame(width: 8, height: 8)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(event.title)
                                        .font(.subheadline.weight(.medium))
                                        .lineLimit(1)
                                    Text("\(timeText(for: event)) - \(event.calendarTitle)")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .lineLimit(1)
                                }

                                Spacer(minLength: 0)
                            }
                            .padding(.vertical, 2)
                        }

                        if calendar.events.count > 6 {
                            Text("\(calendar.events.count - 6) more shown in the notch scroll list.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    Text("Connect Calendar to let NotchLand show the date and today's events in the expanded notch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var statusIcon: some View {
        Image(systemName: calendar.canReadEvents ? "calendar.badge.checkmark" : "calendar.badge.exclamationmark")
            .font(.system(size: 24, weight: .semibold))
            .foregroundStyle(calendar.canReadEvents ? .green : .secondary)
            .frame(width: 34, height: 34)
    }

    @ViewBuilder
    private var connectionButton: some View {
        if calendar.canReadEvents {
            HStack(spacing: 8) {
                Button {
                    calendar.refreshEvents()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .buttonStyle(.bordered)
                .disabled(calendar.isLoading)

                Button(role: .destructive) {
                    calendar.disconnect()
                } label: {
                    Label("Disconnect", systemImage: "xmark.circle")
                }
                .buttonStyle(.bordered)
            }
        } else if calendar.isDisconnected {
            Button {
                calendar.requestAccess()
            } label: {
                Label("Connect", systemImage: "link")
            }
            .buttonStyle(.borderedProminent)
            .disabled(calendar.isLoading)
        } else if calendar.needsConnection {
            Button {
                calendar.requestAccess()
            } label: {
                Label("Connect", systemImage: "link")
            }
            .buttonStyle(.borderedProminent)
            .disabled(calendar.isLoading)
        } else {
            Button {
                openCalendarPrivacySettings()
            } label: {
                Label("Open Settings", systemImage: "gearshape")
            }
            .buttonStyle(.bordered)
        }
    }

    private var connectionDescription: String {
        if calendar.isDisconnected {
            return "Calendar is disconnected in NotchLand. System permission is unchanged."
        }

        switch calendar.authorizationStatus {
        case .authorized, .fullAccess:
            return "NotchLand can read today's events and show them in the expanded notch."
        case .notDetermined:
            return "Allow Calendar access to replace the placeholder notch content."
        case .denied:
            return "Calendar access is blocked. Enable it in Privacy & Security."
        case .restricted:
            return "Calendar access is restricted by this Mac."
        case .writeOnly:
            return "NotchLand needs full access to read today's events."
        @unknown default:
            return "Calendar status is unavailable."
        }
    }

    private func openCalendarPrivacySettings() {
        guard let url = URL(
            string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars"
        ) else { return }
        NSWorkspace.shared.open(url)
    }

    private func thresholdLabel(for minutes: Int) -> String {
        if minutes >= 60 {
            let h = minutes / 60
            return h == 1 ? "1 hour" : "\(h) hours"
        }
        return "\(minutes) minutes"
    }

    private func timeText(for event: CalendarService.Event) -> String {
        if event.isAllDay {
            return "All-day"
        }

        let start = event.startDate.formatted(.dateTime.hour().minute())
        let end = event.endDate.formatted(.dateTime.hour().minute())
        return "\(start)-\(end)"
    }

    private func eventAccent(_ event: CalendarService.Event) -> Color {
        Color(
            red: event.accent.red,
            green: event.accent.green,
            blue: event.accent.blue
        )
    }
}

#if DEBUG
#Preview("Calendar Settings") {
    NotchPreviewContainer {
        CalendarSettingsView()
            .frame(width: 510, height: 520)
    }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
