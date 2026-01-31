import SwiftUI
import Core

/// Heatmap view displaying aggregated activity counts from HeatMapBucket data
/// Uses only HeatMapBucket output defined in activity-discovery
/// ACTIVITY-017: Supports date range highlighting for calendar picker integration
struct HeatmapView: View {
    let buckets: [HeatMapBucket]
    let selectedDate: Date
    let selectedRange: DateRange?
    let weekStartDay: WeekStartDay
    let onDateSelected: (Date) -> Void

    /// Number of weeks to display
    private let weeksToShow: Int = 13 // ~3 months

    /// Number of days per week
    private let daysPerWeek: Int = 7

    /// Day label width
    private let dayLabelWidth: CGFloat = 12

    /// Currently hovered cell (date string for tooltip)
    @State private var hoveredDate: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            // Heatmap grid - use GeometryReader to fill available space
            GeometryReader { geometry in
                heatmapGrid(availableWidth: geometry.size.width)
            }
            .frame(height: calculateGridHeight())

            // Tooltip showing date and count on hover - fixed height to prevent UI jumps
            HStack(spacing: 4) {
                if let date = hoveredDate {
                    Text(formatDateForDisplay(date))
                        .font(.caption2)
                    Text("•")
                        .foregroundStyle(.tertiary)
                    Text("\(bucketsByDate[date]?.count ?? 0) activities")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(height: 14, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 2)
        }
    }

    /// Calculate optimal cell size and spacing based on available width
    private func calculateCellMetrics(availableWidth: CGFloat) -> (cellSize: CGFloat, spacing: CGFloat) {
        // Available width after day labels
        let gridWidth = availableWidth - dayLabelWidth

        // Calculate cell size to fill the width with proportional spacing
        // Formula: gridWidth = (weeksToShow * cellSize) + ((weeksToShow - 1) * spacing)
        // We want spacing to be ~20% of cell size for good proportions
        let totalUnits = CGFloat(weeksToShow) * 1.2 - 0.2 // 1.2 accounts for cell + spacing
        let cellSize = floor(gridWidth / totalUnits)
        let spacing = floor(cellSize * 0.2)

        return (cellSize, spacing)
    }

    /// Calculate grid height based on cell metrics
    private func calculateGridHeight() -> CGFloat {
        // Use a default width to calculate proportional height
        // The actual width will be determined by GeometryReader
        let metrics = calculateCellMetrics(availableWidth: 300)
        return (metrics.cellSize * CGFloat(daysPerWeek)) + (metrics.spacing * CGFloat(daysPerWeek - 1))
    }

    // MARK: - Heatmap Grid

    private func heatmapGrid(availableWidth: CGFloat) -> some View {
        let metrics = calculateCellMetrics(availableWidth: availableWidth)
        let cellSize = metrics.cellSize
        let spacing = metrics.spacing

        return HStack(alignment: .top, spacing: spacing) {
            // Day labels (S, M, T, W, T, F, S)
            VStack(spacing: spacing) {
                ForEach(0..<daysPerWeek, id: \.self) { dayIndex in
                    Text(dayLabel(for: dayIndex))
                        .font(.system(size: 8))
                        .foregroundStyle(.tertiary)
                        .frame(width: dayLabelWidth, height: cellSize)
                }
            }

            // Week columns (most recent on the right)
            ForEach(0..<weeksToShow, id: \.self) { weekIndex in
                VStack(spacing: spacing) {
                    ForEach(0..<daysPerWeek, id: \.self) { dayIndex in
                        let date = dateForCell(weekIndex: weekIndex, dayIndex: dayIndex)
                        if let dateStr = date {
                            HeatmapCell(
                                dateString: dateStr,
                                count: bucketsByDate[dateStr]?.count ?? 0,
                                maxCount: maxCount,
                                isSelected: isDateSelected(dateStr),
                                isInRange: isDateInRange(dateStr),
                                isHovered: hoveredDate == dateStr,
                                cellSize: cellSize
                            )
                            .onHover { hovering in
                                hoveredDate = hovering ? dateStr : nil
                            }
                            .onTapGesture {
                                if let parsedDate = parseDate(dateStr) {
                                    onDateSelected(parsedDate)
                                }
                            }
                        } else {
                            // Empty cell for dates outside our range
                            Rectangle()
                                .fill(Color.clear)
                                .frame(width: cellSize, height: cellSize)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Data Helpers

    /// Buckets indexed by date string for O(1) lookup
    private var bucketsByDate: [String: HeatMapBucket] {
        Dictionary(uniqueKeysWithValues: buckets.map { ($0.date, $0) })
    }

    /// Maximum count across all buckets for color scaling
    private var maxCount: Int {
        buckets.map(\.count).max() ?? 1
    }

    /// UTC date formatter for consistent date strings (must match Session.dateString)
    private static let localDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Calculate the date string for a cell position
    /// weekIndex 0 is the oldest week, weeksToShow-1 is the current week
    private func dateForCell(weekIndex: Int, dayIndex: Int) -> String? {
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: "UTC")!

        // Calculate end date (today at start of day in UTC to match bucket dates)
        let today = calendar.startOfDay(for: Date())

        // Find the first day of the current week based on weekStartDay setting
        let currentWeekday = calendar.component(.weekday, from: today)
        let startDayValue = weekStartDay.weekdayValue

        // Calculate days back to the week start
        // weekday values: 1=Sunday, 2=Monday, ..., 7=Saturday
        var daysFromWeekStart = currentWeekday - startDayValue
        if daysFromWeekStart < 0 {
            daysFromWeekStart += 7
        }

        guard let currentWeekStart = calendar.date(byAdding: .day, value: -daysFromWeekStart, to: today) else {
            return nil
        }

        // Calculate weeks back from current week
        let weeksBack = weeksToShow - 1 - weekIndex
        guard let targetWeekStart = calendar.date(byAdding: .weekOfYear, value: -weeksBack, to: currentWeekStart) else {
            return nil
        }

        // Add day offset
        guard let targetDate = calendar.date(byAdding: .day, value: dayIndex, to: targetWeekStart) else {
            return nil
        }

        // Don't show future dates (use day granularity to avoid timezone issues)
        if calendar.compare(targetDate, to: today, toGranularity: .day) == .orderedDescending {
            return nil
        }

        // Use local timezone for date string (must match bucket date format)
        return Self.localDateFormatter.string(from: targetDate)
    }

    /// Check if a date string matches the selected date (single day selection only)
    private func isDateSelected(_ dateString: String) -> Bool {
        // Don't highlight single date if range is selected
        if selectedRange != nil { return false }
        return Session.dateString(from: selectedDate) == dateString
    }

    /// Check if a date string falls within the selected range
    /// ACTIVITY-017: Range selection highlights multiple cells in heatmap
    private func isDateInRange(_ dateString: String) -> Bool {
        guard let range = selectedRange,
              let date = parseDate(dateString) else { return false }
        let calendar = Calendar.current
        let dayStart = calendar.startOfDay(for: date)
        return dayStart >= range.start && dayStart < range.end
    }

    /// Day label for row index based on weekStartDay setting
    private func dayLabel(for index: Int) -> String {
        // Full week labels starting from Sunday (weekday value 1)
        let allLabels = ["S", "M", "T", "W", "T", "F", "S"]

        // Calculate which weekday this index represents
        // index 0 = weekStartDay, index 1 = weekStartDay+1, etc.
        let weekdayIndex = (weekStartDay.weekdayValue - 1 + index) % 7
        return allLabels[weekdayIndex]
    }

    /// Format date string for display in tooltip
    private func formatDateForDisplay(_ dateString: String) -> String {
        guard let date = parseDate(dateString) else { return dateString }
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter.string(from: date)
    }

    /// Parse date string back to Date (using local timezone)
    private func parseDate(_ dateString: String) -> Date? {
        Self.localDateFormatter.date(from: dateString)
    }
}

/// Individual heatmap cell representing a single day
/// ACTIVITY-017: Supports range highlighting in addition to single selection
struct HeatmapCell: View {
    let dateString: String
    let count: Int
    let maxCount: Int
    let isSelected: Bool
    let isInRange: Bool
    let isHovered: Bool
    let cellSize: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 2)
            .fill(cellColor)
            .frame(width: cellSize, height: cellSize)
            .overlay {
                if isSelected || isInRange {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.accentColor, lineWidth: isSelected ? 1.5 : 1)
                }
            }
            .overlay {
                if isHovered && !isSelected && !isInRange {
                    RoundedRectangle(cornerRadius: 2)
                        .strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1)
                }
            }
    }

    /// Color based on activity count (GitHub-style gradient)
    private var cellColor: Color {
        if count == 0 {
            return Color.gray.opacity(0.15)
        }

        // Calculate intensity (0.0 to 1.0) based on count relative to max
        let intensity = min(1.0, Double(count) / Double(max(maxCount, 1)))

        // GitHub-style green gradient
        // Level 0: gray (no activity)
        // Level 1-4: progressively darker green
        if intensity < 0.25 {
            return Color.green.opacity(0.3)
        } else if intensity < 0.5 {
            return Color.green.opacity(0.5)
        } else if intensity < 0.75 {
            return Color.green.opacity(0.7)
        } else {
            return Color.green.opacity(0.9)
        }
    }
}

#Preview("Empty Heatmap") {
    HeatmapView(
        buckets: [],
        selectedDate: Date(),
        selectedRange: nil,
        weekStartDay: .sunday,
        onDateSelected: { _ in }
    )
    .padding()
}

#Preview("With Data - Sunday Start") {
    let calendar = Calendar.current
    let today = Date()

    // Generate sample data for the last 30 days
    var buckets: [HeatMapBucket] = []
    for i in 0..<30 {
        if let date = calendar.date(byAdding: .day, value: -i, to: today) {
            let dateStr = Session.dateString(from: date)
            let count = Int.random(in: 0...15)
            if count > 0 {
                buckets.append(HeatMapBucket(date: dateStr, count: count))
            }
        }
    }

    return HeatmapView(
        buckets: buckets,
        selectedDate: today,
        selectedRange: nil,
        weekStartDay: .sunday,
        onDateSelected: { _ in }
    )
    .padding()
}

#Preview("With Data - Monday Start") {
    let calendar = Calendar.current
    let today = Date()

    var buckets: [HeatMapBucket] = []
    for i in 0..<30 {
        if let date = calendar.date(byAdding: .day, value: -i, to: today) {
            let dateStr = Session.dateString(from: date)
            let count = Int.random(in: 0...15)
            if count > 0 {
                buckets.append(HeatMapBucket(date: dateStr, count: count))
            }
        }
    }

    return HeatmapView(
        buckets: buckets,
        selectedDate: today,
        selectedRange: nil,
        weekStartDay: .monday,
        onDateSelected: { _ in }
    )
    .padding()
}

#Preview("With Range Selection") {
    let calendar = Calendar.current
    let today = Date()
    let start = calendar.date(byAdding: .day, value: -7, to: today)!
    let end = calendar.date(byAdding: .day, value: 1, to: today)!

    // Generate sample data for the last 30 days
    var buckets: [HeatMapBucket] = []
    for i in 0..<30 {
        if let date = calendar.date(byAdding: .day, value: -i, to: today) {
            let dateStr = Session.dateString(from: date)
            let count = Int.random(in: 0...15)
            if count > 0 {
                buckets.append(HeatMapBucket(date: dateStr, count: count))
            }
        }
    }

    return HeatmapView(
        buckets: buckets,
        selectedDate: today,
        selectedRange: DateRange(start: start, end: end),
        weekStartDay: .monday,
        onDateSelected: { _ in }
    )
    .padding()
}
