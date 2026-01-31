import SwiftUI
import Core

/// Calendar picker for date and range selection
/// ACTIVITY-017: User can pick single day or range, selection updates heatmap and activity list
struct CalendarPickerView: View {
    let selectedDate: Date
    let selectedRange: DateRange?
    let onDateSelected: (Date) -> Void
    let onRangeSelected: (DateRange) -> Void

    /// Calendar for date calculations
    private let calendar = Calendar.current

    /// Currently displayed month
    @State private var displayedMonth: Date = Date()

    /// Range selection start (when selecting a range)
    @State private var rangeStart: Date?

    /// Whether range selection mode is active
    @State private var isRangeMode: Bool = false

    var body: some View {
        VStack(spacing: 8) {
            // Mode toggle and month navigation
            headerView

            // Day of week labels
            weekdayHeader

            // Calendar grid
            calendarGrid

            // Quick selection buttons
            quickSelectionButtons
        }
        .onAppear {
            // Initialize displayed month to show selected date
            displayedMonth = selectedDate
            // Initialize range mode based on whether a range is selected
            isRangeMode = selectedRange != nil
            rangeStart = selectedRange?.start
        }
    }

    // MARK: - Header View

    private var headerView: some View {
        HStack {
            // Range mode toggle
            Toggle(isOn: $isRangeMode) {
                Text("Range")
                    .font(.caption)
            }
            .toggleStyle(.checkbox)
            .onChange(of: isRangeMode) { _, newValue in
                if !newValue {
                    // Exiting range mode - clear range and select current date
                    rangeStart = nil
                    onDateSelected(selectedDate)
                } else {
                    // Entering range mode - start with current date
                    rangeStart = selectedDate
                }
            }

            Spacer()

            // Month navigation
            Button {
                displayedMonth = calendar.date(byAdding: .month, value: -1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.left")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            Text(monthYearString)
                .font(.subheadline.weight(.medium))
                .frame(minWidth: 100)

            Button {
                displayedMonth = calendar.date(byAdding: .month, value: 1, to: displayedMonth) ?? displayedMonth
            } label: {
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            // Today button
            Button("Today") {
                displayedMonth = Date()
                if isRangeMode {
                    rangeStart = nil
                    isRangeMode = false
                }
                onDateSelected(Date())
            }
            .buttonStyle(.plain)
            .font(.caption)
            .foregroundStyle(Color.accentColor)
        }
    }

    // MARK: - Weekday Header

    private var weekdayHeader: some View {
        HStack(spacing: 2) {
            ForEach(weekdaySymbols, id: \.self) { symbol in
                Text(symbol)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }

    // MARK: - Calendar Grid

    private var calendarGrid: some View {
        let days = daysInMonth()
        let weeks = days.chunked(into: 7)

        return VStack(spacing: 2) {
            ForEach(weeks.indices, id: \.self) { weekIndex in
                HStack(spacing: 2) {
                    ForEach(weeks[weekIndex].indices, id: \.self) { dayIndex in
                        let dayInfo = weeks[weekIndex][dayIndex]
                        dayCell(dayInfo)
                    }
                }
            }
        }
    }

    // MARK: - Day Cell

    private func dayCell(_ dayInfo: DayInfo) -> some View {
        let isSelected = isDaySelected(dayInfo)
        let isInRange = isDayInRange(dayInfo)
        let isRangeStart = isRangeStartDay(dayInfo)
        let isRangeEnd = isRangeEndDay(dayInfo)
        let isToday = dayInfo.date != nil && calendar.isDateInToday(dayInfo.date!)
        let isFutureDate = dayInfo.date != nil && dayInfo.date! > Date()

        return Button {
            if let date = dayInfo.date, !isFutureDate {
                handleDayTap(date)
            }
        } label: {
            ZStack {
                // Range background (for dates in the selected range)
                if isInRange && !isRangeStart && !isRangeEnd {
                    Rectangle()
                        .fill(Color.accentColor.opacity(0.15))
                }

                // Range start/end backgrounds (rounded on edges)
                if isRangeStart || isRangeEnd {
                    HStack(spacing: 0) {
                        if isRangeStart && !isRangeEnd {
                            Color.clear
                                .frame(width: 10)
                            Color.accentColor.opacity(0.15)
                        } else if isRangeEnd && !isRangeStart {
                            Color.accentColor.opacity(0.15)
                            Color.clear
                                .frame(width: 10)
                        } else {
                            // Single day range - no extended background
                            Color.clear
                        }
                    }
                }

                // Day circle for selected/range start/end days
                if isSelected || isRangeStart || isRangeEnd {
                    Circle()
                        .fill(Color.accentColor)
                        .frame(width: 22, height: 22)
                }

                // Today circle outline (when not selected)
                if isToday && !isSelected && !isRangeStart && !isRangeEnd {
                    Circle()
                        .strokeBorder(Color.accentColor, lineWidth: 1)
                        .frame(width: 22, height: 22)
                }

                // Day number
                if let day = dayInfo.day {
                    Text("\(day)")
                        .font(.caption)
                        .foregroundColor(dayTextColor(
                            isSelected: isSelected,
                            isRangeStart: isRangeStart,
                            isRangeEnd: isRangeEnd,
                            isCurrentMonth: dayInfo.isCurrentMonth,
                            isFutureDate: isFutureDate
                        ))
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: 26)
        }
        .buttonStyle(.plain)
        .disabled(isFutureDate || dayInfo.date == nil)
    }

    // MARK: - Day Text Color Helper

    private func dayTextColor(isSelected: Bool, isRangeStart: Bool, isRangeEnd: Bool, isCurrentMonth: Bool, isFutureDate: Bool) -> Color {
        if isSelected || isRangeStart || isRangeEnd {
            return .white
        }
        if !isCurrentMonth {
            return .secondary.opacity(0.5)
        }
        if isFutureDate {
            return .secondary.opacity(0.5)
        }
        return .primary
    }

    // MARK: - Quick Selection Buttons

    private var quickSelectionButtons: some View {
        HStack(spacing: 8) {
            quickButton("Today", days: 0)
            quickButton("Last 7d", days: 7)
            quickButton("Last 30d", days: 30)
            quickButton("Last 90d", days: 90)
        }
        .padding(.top, 4)
    }

    private func quickButton(_ title: String, days: Int) -> some View {
        Button(title) {
            let today = calendar.startOfDay(for: Date())
            if days == 0 {
                // Today - single day selection
                isRangeMode = false
                rangeStart = nil
                onDateSelected(today)
            } else {
                // Range selection
                isRangeMode = true
                guard let startDate = calendar.date(byAdding: .day, value: -(days - 1), to: today) else { return }
                let range = DateRange(start: startDate, end: calendar.date(byAdding: .day, value: 1, to: today)!)
                rangeStart = startDate
                onRangeSelected(range)
            }
            displayedMonth = Date()
        }
        .buttonStyle(.plain)
        .font(.caption2)
        .padding(.horizontal, 6)
        .padding(.vertical, 3)
        .background(
            RoundedRectangle(cornerRadius: 4)
                .fill(Color.secondary.opacity(0.1))
        )
    }

    // MARK: - Date Handling

    private func handleDayTap(_ date: Date) {
        if isRangeMode {
            if let start = rangeStart {
                // Complete range selection
                let (rangeStartDate, rangeEndDate) = date < start ? (date, start) : (start, date)
                let endOfRangeDate = calendar.date(byAdding: .day, value: 1, to: rangeEndDate)!
                let range = DateRange(start: rangeStartDate, end: endOfRangeDate)
                onRangeSelected(range)
                rangeStart = nil
            } else {
                // Start range selection
                rangeStart = date
            }
        } else {
            // Single day selection
            onDateSelected(date)
        }
    }

    // MARK: - Selection State Helpers

    private func isDaySelected(_ dayInfo: DayInfo) -> Bool {
        guard let date = dayInfo.date else { return false }
        if isRangeMode { return false }
        return calendar.isDate(date, inSameDayAs: selectedDate)
    }

    private func isDayInRange(_ dayInfo: DayInfo) -> Bool {
        guard let date = dayInfo.date else { return false }

        // Check active range selection in progress
        if let start = rangeStart, isRangeMode {
            return date >= start && date <= (selectedRange?.start ?? start)
        }

        // Check confirmed selected range
        guard let range = selectedRange else { return false }
        let dayStart = calendar.startOfDay(for: date)
        return dayStart >= range.start && dayStart < range.end
    }

    private func isRangeStartDay(_ dayInfo: DayInfo) -> Bool {
        guard let date = dayInfo.date else { return false }
        if let range = selectedRange {
            return calendar.isDate(date, inSameDayAs: range.start)
        }
        if let start = rangeStart, isRangeMode {
            return calendar.isDate(date, inSameDayAs: start)
        }
        return false
    }

    private func isRangeEndDay(_ dayInfo: DayInfo) -> Bool {
        guard let date = dayInfo.date, let range = selectedRange else { return false }
        // End is exclusive, so we need the day before end
        guard let endDay = calendar.date(byAdding: .day, value: -1, to: range.end) else { return false }
        return calendar.isDate(date, inSameDayAs: endDay)
    }

    // MARK: - Calendar Helpers

    private var monthYearString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMMM yyyy"
        return formatter.string(from: displayedMonth)
    }

    private var weekdaySymbols: [String] {
        // Short weekday symbols starting from Sunday
        let symbols = calendar.veryShortWeekdaySymbols
        return symbols
    }

    /// Day information for rendering
    private struct DayInfo {
        let day: Int?
        let date: Date?
        let isCurrentMonth: Bool
    }

    /// Generate all days to display for the current month (including padding from adjacent months)
    private func daysInMonth() -> [DayInfo] {
        var days: [DayInfo] = []

        // Get the first day of the displayed month
        let components = calendar.dateComponents([.year, .month], from: displayedMonth)
        guard let firstOfMonth = calendar.date(from: components) else { return days }

        // Get the weekday of the first day (1 = Sunday)
        let firstWeekday = calendar.component(.weekday, from: firstOfMonth)

        // Calculate days to show from previous month
        let daysFromPreviousMonth = firstWeekday - 1

        // Get the number of days in the current month
        guard let range = calendar.range(of: .day, in: .month, for: firstOfMonth) else { return days }
        let daysInCurrentMonth = range.count

        // Get the last day of previous month
        guard let previousMonth = calendar.date(byAdding: .month, value: -1, to: firstOfMonth),
              let previousMonthRange = calendar.range(of: .day, in: .month, for: previousMonth) else { return days }
        let daysInPreviousMonth = previousMonthRange.count

        // Add days from previous month (padding)
        for i in stride(from: daysFromPreviousMonth, through: 1, by: -1) {
            let day = daysInPreviousMonth - i + 1
            let date = calendar.date(byAdding: .day, value: -i, to: firstOfMonth)
            days.append(DayInfo(day: day, date: date, isCurrentMonth: false))
        }

        // Add days from current month
        for day in 1...daysInCurrentMonth {
            let date = calendar.date(byAdding: .day, value: day - 1, to: firstOfMonth)
            days.append(DayInfo(day: day, date: date, isCurrentMonth: true))
        }

        // Add days from next month to complete the grid (fill to 6 weeks = 42 days)
        let remainingDays = 42 - days.count
        guard let nextMonth = calendar.date(byAdding: .month, value: 1, to: firstOfMonth) else { return days }
        for day in 1...remainingDays {
            let date = calendar.date(byAdding: .day, value: day - 1, to: nextMonth)
            days.append(DayInfo(day: day, date: date, isCurrentMonth: false))
        }

        return days
    }
}

// MARK: - Array Extension for Chunking

private extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

// MARK: - Previews

#Preview("Single Selection") {
    CalendarPickerView(
        selectedDate: Date(),
        selectedRange: nil,
        onDateSelected: { _ in },
        onRangeSelected: { _ in }
    )
    .padding()
    .frame(width: 280)
}

#Preview("Range Selection") {
    let calendar = Calendar.current
    let today = Date()
    let start = calendar.date(byAdding: .day, value: -7, to: today)!
    let end = calendar.date(byAdding: .day, value: 1, to: today)!

    return CalendarPickerView(
        selectedDate: today,
        selectedRange: DateRange(start: start, end: end),
        onDateSelected: { _ in },
        onRangeSelected: { _ in }
    )
    .padding()
    .frame(width: 280)
}
