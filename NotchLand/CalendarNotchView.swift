//
//  CalendarNotchView.swift
//  NotchLand
//
//  Developed by Rudra Shah — Author & Creator of NotchLand.
//  Copyright © 2026 Rudra Shah. All rights reserved.
//
//  Expanded calendar surface. Uses one primary month calendar with the selected
//  day's agenda beside it.
//

import SwiftUI

enum CalendarNotchMetrics {
    nonisolated static let expandedSize = CGSize(width: 540, height: 220)
    nonisolated static let monthColumnWidth: CGFloat = 218
}

struct CalendarNotchView: View {
    @EnvironmentObject var calendar: CalendarService
    @State private var selectedDate = Date()

    private let systemCalendar = Foundation.Calendar.current

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            monthView
                .frame(width: CalendarNotchMetrics.monthColumnWidth)

            agendaView
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .padding(.horizontal, 18)
        .padding(.top, 15)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .foregroundStyle(.white)
        .onAppear {
            selectedDate = calendar.currentDate
        }
        .onChange(of: calendar.currentDate) { _, newDate in
            if systemCalendar.isDateInToday(selectedDate) {
                selectedDate = newDate
            }
        }
    }

    // MARK: - Month

    private var monthView: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .firstTextBaseline) {
                Text(monthTitle)
                    .font(.system(size: 16, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Text(yearTitle)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .monospacedDigit()
            }

            weekdayHeader

            LazyVGrid(columns: dayColumns, spacing: 3) {
                ForEach(monthDays) { day in
                    dayButton(day)
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var weekdayHeader: some View {
        HStack(spacing: 3) {
            ForEach(Array(weekdaySymbols.enumerated()), id: \.offset) { _, symbol in
                Text(symbol)
                    .font(.system(size: 8, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.36))
                    .frame(maxWidth: .infinity)
            }
        }
    }

    private var dayColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(minimum: 20, maximum: 26), spacing: 3), count: 7)
    }

    private func dayButton(_ day: CalendarMonthDay) -> some View {
        let isSelected = systemCalendar.isDate(day.date, inSameDayAs: selectedDate)
        let hasEvents = calendar.hasEvents(on: day.date)

        return Button {
            withAnimation(.spring(response: 0.22, dampingFraction: 0.82)) {
                selectedDate = day.date
            }
        } label: {
            ZStack(alignment: .bottom) {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(dayFill(isSelected: isSelected, isToday: day.isToday))

                VStack(spacing: 1) {
                    Text(dayNumber(day.date))
                        .font(.system(size: 11, weight: isSelected ? .bold : .semibold, design: .rounded))
                        .foregroundStyle(dayTextColor(day, isSelected: isSelected))
                        .monospacedDigit()

                    Circle()
                        .fill(hasEvents ? eventDotColor(isSelected: isSelected) : Color.clear)
                        .frame(width: 3.5, height: 3.5)
                }
                .padding(.top, 2)
                .padding(.bottom, 2)
            }
            .frame(height: 20)
        }
        .buttonStyle(.plain)
        .disabled(!day.isInDisplayedMonth)
    }

    private func dayFill(isSelected: Bool, isToday: Bool) -> Color {
        if isSelected { return Color.white.opacity(0.22) }
        if isToday { return Color.red.opacity(0.22) }
        return Color.white.opacity(0.045)
    }

    private func dayTextColor(_ day: CalendarMonthDay, isSelected: Bool) -> Color {
        if isSelected { return .white }
        if day.isToday { return Color.red.opacity(0.95) }
        return day.isInDisplayedMonth ? Color.white.opacity(0.74) : Color.white.opacity(0.2)
    }

    private func eventDotColor(isSelected: Bool) -> Color {
        isSelected ? Color.white.opacity(0.92) : Color.red.opacity(0.82)
    }

    // MARK: - Agenda

    @ViewBuilder
    private var agendaView: some View {
        VStack(alignment: .leading, spacing: 11) {
            agendaHeader

            if !calendar.canReadEvents {
                connectionPrompt
            } else if selectedEvents.isEmpty {
                emptyAgenda
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 0) {
                        ForEach(selectedEvents) { event in
                            agendaRow(event)
                        }
                    }
                }
                .mask {
                    LinearGradient(
                        stops: [
                            .init(color: .clear, location: 0),
                            .init(color: .black, location: 0.06),
                            .init(color: .black, location: 0.94),
                            .init(color: .clear, location: 1),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
            }
        }
        .frame(maxHeight: .infinity, alignment: .topLeading)
    }

    private var agendaHeader: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(selectedDayTitle.uppercased())
                    .font(.system(size: 9, weight: .bold, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.44))
                    .lineLimit(1)

                Text(selectedDateTitle)
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            statusPill
        }
    }

    private var statusPill: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(calendar.canReadEvents ? Color.green.opacity(0.85) : Color.white.opacity(0.4))
                .frame(width: 6, height: 6)
            Text(calendar.canReadEvents ? eventCountText : calendar.connectionTitle)
                .font(.system(size: 9, weight: .semibold, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.58))
                .lineLimit(1)
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background {
            Capsule(style: .continuous)
                .fill(Color.white.opacity(0.06))
        }
    }

    private var connectionPrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "calendar.badge.plus")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.8))
            Text("Connect Calendar")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("Allow access in the companion app.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.5))
                .lineLimit(2)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var emptyAgenda: some View {
        VStack(alignment: .leading, spacing: 8) {
            Image(systemName: "sparkles")
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(Color.white.opacity(0.74))
            Text(emptyTitle)
                .font(.system(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(.white)
            Text("No events scheduled for this day.")
                .font(.system(size: 11, weight: .medium, design: .rounded))
                .foregroundStyle(Color.white.opacity(0.5))
                .lineLimit(2)
        }
        .padding(.top, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func agendaRow(_ event: CalendarService.Event) -> some View {
        let accent = Color(red: event.accent.red, green: event.accent.green, blue: event.accent.blue)
        return HStack(alignment: .top, spacing: 0) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accent.opacity(0.95))
                .frame(width: 3)
                .padding(.vertical, 7)

            VStack(alignment: .leading, spacing: 3) {
                Text(timeText(for: event))
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(Color.white.opacity(0.55))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Text(event.title)
                    .font(.system(size: 10.5, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white.opacity(0.94))
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)

                Text(event.calendarTitle)
                    .font(.system(size: 8.5, weight: .medium, design: .rounded))
                    .foregroundStyle(Color.white.opacity(0.42))
                    .lineLimit(1)
            }
            .padding(.leading, 8)
            .padding(.trailing, 8)
            .padding(.vertical, 6)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(Color.white.opacity(0.08))
        }
        .padding(.vertical, 3)
    }

    // MARK: - Data

    private var selectedEvents: [CalendarService.Event] {
        calendar.events(on: selectedDate)
    }

    private var monthDays: [CalendarMonthDay] {
        guard let monthInterval = systemCalendar.dateInterval(of: .month, for: calendar.currentDate),
              let monthGrid = systemCalendar.dateInterval(of: .weekOfMonth, for: monthInterval.start)
        else {
            return []
        }

        var days: [CalendarMonthDay] = []
        var day = monthGrid.start

        while days.count < 42 {
            days.append(
                CalendarMonthDay(
                    date: day,
                    isInDisplayedMonth: systemCalendar.isDate(day, equalTo: monthInterval.start, toGranularity: .month),
                    isToday: systemCalendar.isDateInToday(day)
                )
            )
            guard let nextDay = systemCalendar.date(byAdding: .day, value: 1, to: day) else { break }
            day = nextDay
        }

        return days
    }

    private var weekdaySymbols: [String] {
        let symbols = systemCalendar.veryShortWeekdaySymbols
        let first = max(0, systemCalendar.firstWeekday - 1)
        return Array(symbols[first...] + symbols[..<first])
    }

    // MARK: - Formatting

    private var monthTitle: String {
        calendar.currentDate.formatted(.dateTime.month(.wide))
    }

    private var yearTitle: String {
        calendar.currentDate.formatted(.dateTime.year())
    }

    private var selectedDayTitle: String {
        systemCalendar.isDateInToday(selectedDate) ? "Today" : selectedDate.formatted(.dateTime.weekday(.wide))
    }

    private var selectedDateTitle: String {
        selectedDate.formatted(.dateTime.month(.abbreviated).day())
    }

    private var eventCountText: String {
        let count = selectedEvents.count
        if count == 1 { return "1 Event" }
        return "\(count) Events"
    }

    private var emptyTitle: String {
        systemCalendar.isDateInToday(selectedDate) ? "All clear" : "Free day"
    }

    private func dayNumber(_ date: Date) -> String {
        date.formatted(.dateTime.day())
    }

    private func timeText(for event: CalendarService.Event) -> String {
        if event.isAllDay { return "All-day" }
        let start = event.startDate.formatted(.dateTime.hour().minute())
        let end = event.endDate.formatted(.dateTime.hour().minute())
        return "\(start)-\(end)"
    }
}

private struct CalendarMonthDay: Identifiable {
    let date: Date
    let isInDisplayedMonth: Bool
    let isToday: Bool

    var id: TimeInterval {
        date.timeIntervalSinceReferenceDate
    }
}

#if DEBUG
#Preview("Calendar Notch") {
    NotchPreviewContainer {
        CalendarNotchView()
            .notchPreviewSurface(
                width: CalendarNotchMetrics.expandedSize.width,
                height: CalendarNotchMetrics.expandedSize.height
            )
    }
}
#endif

// ─────────────────────────────────────────────────────────────────────────────
// Developed by Rudra Shah — Author & Creator of NotchLand.
// ─────────────────────────────────────────────────────────────────────────────
