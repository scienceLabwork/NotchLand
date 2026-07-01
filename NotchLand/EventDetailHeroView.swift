//
//  EventDetailHeroView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Dynamic Island-style featured event view. It uses the notch's black chrome
//  directly, with pills only for actions.
//

import AppKit
import SwiftUI

enum EventDetailMetrics {
    nonisolated static let eventOnlySize = CGSize(width: 360, height: 190)
    nonisolated static let eventColumnWidth: CGFloat = 330
}

struct FocusedEventDetailView: View {
    let event: CalendarService.Event

    var body: some View {
        EventDetailHeroView(event: event)
            .frame(width: EventDetailMetrics.eventColumnWidth)
            .padding(.horizontal, 18)
            .padding(.vertical, 16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

struct EventDetailHeroView: View {
    let event: CalendarService.Event

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .center, spacing: 9) {
                ZStack {
                    Circle()
                        .fill(accent.opacity(0.22))
                    Image(systemName: event.isAllDay ? "calendar" : "calendar.badge.clock")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .foregroundStyle(accent)
                }
                .frame(width: 27, height: 27)

                statusLabel
                Spacer(minLength: 0)
                if event.isAllDay {
                    Text("ALL DAY")
                        .font(.system(size: 9, weight: .bold, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.5))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background {
                            Capsule(style: .continuous)
                                .fill(Color.white.opacity(0.08))
                        }
                }
            }

            Text(event.title)
                .font(.system(size: 21, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
                .lineLimit(2)
                .minimumScaleFactor(0.76)
                .multilineTextAlignment(.leading)

            HStack(spacing: 6) {
                Text(timeRangeText)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.78))
                Circle()
                    .fill(Color.white.opacity(0.28))
                    .frame(width: 3, height: 3)
                Text(event.calendarTitle)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            actionRow
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private var accent: Color {
        Color(red: event.accent.red, green: event.accent.green, blue: event.accent.blue)
    }

    @ViewBuilder
    private var statusLabel: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let now = ctx.date
            Text(statusText(at: now))
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.92))
        }
    }

    private func statusText(at now: Date) -> String {
        if event.isAllDay {
            return "Today"
        }
        if event.startDate <= now && now < event.endDate {
            let s = event.endDate.timeIntervalSince(now)
            return "Ends in \(EventCountdownChipView.format(seconds: s, prefix: ""))"
        }
        if event.startDate > now {
            let s = event.startDate.timeIntervalSince(now)
            if s <= 60 { return "Starting now" }
            return "Starts in \(EventCountdownChipView.format(seconds: s, prefix: ""))"
        }
        return "Ended"
    }

    private var timeRangeText: String {
        if event.isAllDay { return "All-day" }
        let start = event.startDate.formatted(.dateTime.hour().minute())
        let end = event.endDate.formatted(.dateTime.hour().minute())
        return "\(start) – \(end)"
    }

    @ViewBuilder
    private var actionRow: some View {
        let location = event.location
        let mapsURL = event.mapsURL
        let meetingURL = event.meetingURL

        if location != nil || meetingURL != nil {
            HStack(spacing: 6) {
                if let location, !location.isEmpty {
                    locationButton(location: location, mapsURL: mapsURL)
                }
                if let meetingURL {
                    joinButton(url: meetingURL)
                }
            }
        }
    }

    private func locationButton(location: String, mapsURL: URL?) -> some View {
        Button {
            if let mapsURL { NSWorkspace.shared.open(mapsURL) }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(location)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .foregroundStyle(Color.white.opacity(0.88))
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(Color.white.opacity(0.11))
            }
        }
        .buttonStyle(.plain)
        .disabled(mapsURL == nil)
    }

    private func joinButton(url: URL) -> some View {
        Button {
            NSWorkspace.shared.open(url)
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "video.fill")
                    .font(.system(size: 10, weight: .bold))
                Text("Join")
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background {
                Capsule(style: .continuous)
                    .fill(accent.opacity(0.92))
            }
        }
        .buttonStyle(.plain)
    }
}

#if DEBUG
#Preview("Event Detail") {
    FocusedEventDetailView(event: PreviewSamples.event)
        .notchPreviewSurface(
            width: EventDetailMetrics.eventOnlySize.width,
            height: EventDetailMetrics.eventOnlySize.height
        )
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
