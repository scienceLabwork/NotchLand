//
//  EventCountdownChipView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Compact pill rendered next to the hardware notch in the collapsed state.
//  Shows only the live countdown text so it can fit beside the notch.
//

import SwiftUI

enum EventCountdownChipMetrics {
    /// Width bounds for the collapsed countdown body. The max fits values like
    /// `1h 05m` without letting the text bleed toward the hardware notch.
    nonisolated static let minWidth: CGFloat = 38
    nonisolated static let maxWidth: CGFloat = 66
    nonisolated static let height: CGFloat = 22
    nonisolated static let horizontalPadding: CGFloat = 8
    nonisolated static let musicComboCollapsedWidth: CGFloat = 316
    // Keeps the music + calendar countdown's right edge aligned with the
    // calendar-only collapsed countdown while preserving enough room for music.
    nonisolated static let musicComboLeftAnchorWidth: CGFloat = 292
    nonisolated static let eventOnlyCollapsedWidth: CGFloat = 300
    nonisolated static let eventOnlyLeftAnchorWidth: CGFloat = 260
    nonisolated static let calendarIconSize: CGFloat = 24

    nonisolated static func eventOnlyBodyWidth(baseWidth: CGFloat) -> CGFloat {
        max(baseWidth, eventOnlyCollapsedWidth)
    }

    nonisolated static func musicComboBodyWidth(baseWidth: CGFloat) -> CGFloat {
        max(baseWidth, musicComboCollapsedWidth)
    }

    nonisolated static func rightBiasedContainerBodyWidth(
        bodyWidth: CGFloat,
        leftAnchorWidth: CGFloat
    ) -> CGFloat {
        let left = leftAnchorWidth / 2
        let right = max(left, bodyWidth - left)
        return max(left, right) * 2
    }

    nonisolated static func rightBiasOffset(
        bodyWidth: CGFloat,
        leftAnchorWidth: CGFloat
    ) -> CGFloat {
        let left = leftAnchorWidth / 2
        let right = max(left, bodyWidth - left)
        return (right - left) / 2
    }

    nonisolated static func eventOnlyContainerBodyWidth(baseWidth: CGFloat) -> CGFloat {
        rightBiasedContainerBodyWidth(
            bodyWidth: eventOnlyBodyWidth(baseWidth: baseWidth),
            leftAnchorWidth: eventOnlyLeftAnchorWidth
        )
    }

    nonisolated static func musicComboContainerBodyWidth(baseWidth: CGFloat) -> CGFloat {
        rightBiasedContainerBodyWidth(
            bodyWidth: musicComboBodyWidth(baseWidth: baseWidth),
            leftAnchorWidth: musicComboLeftAnchorWidth
        )
    }
}

struct EventCountdownChipView: View {
    let presentation: EventCountdownController.Presentation
    let event: CalendarService.Event
    /// Visual side hint for callers that share this component in mirrored layouts.
    var side: Side = .left

    enum Side {
        case left
        case right
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { ctx in
            let live = livePresentation(at: ctx.date)
            let statusAccent = accent(for: live)
            HStack(spacing: 6) {
                Text(timeText(for: live))
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.86)
                    .foregroundStyle(Color.white)
            }
            .padding(.leading, side == .right ? 0 : EventCountdownChipMetrics.horizontalPadding)
            .padding(.trailing, EventCountdownChipMetrics.horizontalPadding)
            .frame(
                minWidth: EventCountdownChipMetrics.minWidth,
                maxWidth: EventCountdownChipMetrics.maxWidth,
                alignment: .center
            )
            .frame(height: EventCountdownChipMetrics.height)
            .background {
                Capsule(style: .continuous)
                    .fill(statusAccent.opacity(0.18))
                    .overlay {
                        Capsule(style: .continuous)
                            .stroke(statusAccent.opacity(0.32), lineWidth: 0.6)
                    }
            }
        }
    }

    private func accent(for presentation: EventCountdownController.Presentation) -> Color {
        switch presentation {
        case .upcoming:
            return .red
        case .active:
            return .blue
        }
    }

    private func livePresentation(at now: Date) -> EventCountdownController.Presentation {
        if event.startDate <= now && now < event.endDate {
            return .active(eventID: event.id, secondsUntilEnd: max(0, event.endDate.timeIntervalSince(now)))
        }
        if event.startDate > now {
            return .upcoming(eventID: event.id, secondsUntilStart: event.startDate.timeIntervalSince(now))
        }
        // Event ended; fall back to the last published presentation. The
        // controller will clear it on its next tick.
        return presentation
    }

    private func timeText(for presentation: EventCountdownController.Presentation) -> String {
        switch presentation {
        case .upcoming(_, let seconds):
            return Self.format(seconds: seconds, prefix: "")
        case .active(_, let seconds):
            return Self.format(seconds: seconds, prefix: "")
        }
    }

    static func format(seconds: TimeInterval, prefix: String) -> String {
        let total = Int(ceil(max(0, seconds) / 60))
        if total >= 60 {
            let h = total / 60
            let m = total % 60
            return "\(prefix)\(h)h \(m)m"
        }
        return "\(prefix)\(max(1, total))m"
    }
}

/// Collapsed-notch wrapper that places the countdown chip on the requested side
/// and a calendar glyph on the opposite side.
struct EventCountdownCollapsedView: View {
    let presentation: EventCountdownController.Presentation
    let event: CalendarService.Event
    var side: EventCountdownChipView.Side = .left

    var body: some View {
        HStack(spacing: 0) {
            calendarIcon
                .padding(.leading, NowPlayingMetrics.collapsedSidePadding)
                .padding(.top, 5)

            Spacer(minLength: 0)

            chip
                .padding(.trailing, NowPlayingMetrics.collapsedSidePadding)
                .padding(.top, 5)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var calendarIcon: some View {
        ZStack {
            Image(systemName: "calendar")
                .font(.system(size: 18, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.red.opacity(0.9))
        }
        .frame(
            width: EventCountdownChipMetrics.calendarIconSize,
            height: EventCountdownChipMetrics.calendarIconSize
        )
    }

    private var chip: some View {
        EventCountdownChipView(presentation: presentation, event: event, side: side)
    }

    private var accent: Color {
        Color(red: event.accent.red, green: event.accent.green, blue: event.accent.blue)
    }
}

/// Collapsed-notch wrapper for the music + event combo: music artwork sits on
/// the left, the countdown chip replaces the EQ bars on the right.
struct CollapsedMusicEventView: View {
    let track: NowPlayingService.Track
    let presentation: EventCountdownController.Presentation
    let event: CalendarService.Event
    var isHovering: Bool = false
    var morphNamespace: Namespace.ID? = nil

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                artwork
                    .padding(.leading, NowPlayingMetrics.collapsedSidePadding)
                    .padding(.top, 4)
                Spacer(minLength: 0)
                EventCountdownChipView(presentation: presentation, event: event, side: .right)
                    .padding(.trailing, NowPlayingMetrics.collapsedSidePadding)
                    .padding(.top, 4)
            }
            .frame(maxWidth: .infinity)

            if isHovering {
                MarqueeText(text: marqueeText)
                    .frame(height: NowPlayingMetrics.hoverExtraHeight - 4)
                    .padding(.top, 5)
                    .padding(.horizontal, 12)
                    .padding(.bottom, 4)
                    .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var marqueeText: String {
        let trimmedTitle = track.title.trimmingCharacters(in: .whitespaces)
        let trimmedArtist = track.artist.trimmingCharacters(in: .whitespaces)
        if trimmedArtist.isEmpty { return trimmedTitle }
        return "\(trimmedTitle) - \(trimmedArtist)"
    }

    @ViewBuilder
    private var artwork: some View {
        let size = NowPlayingMetrics.collapsedArtSize
        Group {
            if let image = track.artwork {
                Image(nsImage: image)
                    .resizable()
                    .interpolation(.high)
                    .scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(Color.white.opacity(0.12))
                    .overlay {
                        Image(systemName: "music.note")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .matchedGeometry(id: "music-art", in: morphNamespace)
    }
}

#if DEBUG
#Preview("Event Countdown") {
    EventCountdownCollapsedView(
        presentation: .upcoming(
            eventID: PreviewSamples.event.id,
            secondsUntilStart: 12 * 60
        ),
        event: PreviewSamples.event
    )
    .notchPreviewSurface(
        width: EventCountdownChipMetrics.eventOnlyCollapsedWidth,
        height: 40
    )
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
