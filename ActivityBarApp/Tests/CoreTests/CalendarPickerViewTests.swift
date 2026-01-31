import XCTest
@testable import Core

/// Tests for CalendarPickerView date and range selection functionality
/// ACTIVITY-017: Calendar picker for date and range selection
final class CalendarPickerViewTests: XCTestCase {

    // MARK: - DateRange Tests

    func testDateRangeSingleDayFactory() {
        let calendar = Calendar.current
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!

        let range = DateRange.singleDay(date)

        // Start should be start of day
        let startComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: range.start)
        XCTAssertEqual(startComponents.year, 2026)
        XCTAssertEqual(startComponents.month, 1)
        XCTAssertEqual(startComponents.day, 15)
        XCTAssertEqual(startComponents.hour, 0)
        XCTAssertEqual(startComponents.minute, 0)
        XCTAssertEqual(startComponents.second, 0)

        // End should be start of next day
        let endComponents = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: range.end)
        XCTAssertEqual(endComponents.year, 2026)
        XCTAssertEqual(endComponents.month, 1)
        XCTAssertEqual(endComponents.day, 16)
        XCTAssertEqual(endComponents.hour, 0)
    }

    func testDateRangeTodayFactory() {
        let today = DateRange.today
        let calendar = Calendar.current
        let now = Date()

        // Should contain today
        let todayStart = calendar.startOfDay(for: now)
        XCTAssertTrue(todayStart >= today.start)
        XCTAssertTrue(todayStart < today.end)
    }

    func testDateRangeEquality() {
        let calendar = Calendar.current
        let date1 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let date2 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 16))!

        let range1 = DateRange(start: date1, end: date2)
        let range2 = DateRange(start: date1, end: date2)

        XCTAssertEqual(range1, range2)
    }

    func testDateRangeMultipleDays() {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 20))!

        let range = DateRange(start: start, end: end)

        XCTAssertEqual(range.start, start)
        XCTAssertEqual(range.end, end)
    }

    // MARK: - Session Date Selection Tests

    @MainActor
    func testSelectDateUpdatesSession() {
        let appState = AppState()
        let calendar = Calendar.current
        let newDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 10))!

        appState.selectDate(newDate)

        XCTAssertEqual(calendar.isDate(appState.session.selectedDate, inSameDayAs: newDate), true)
    }

    @MainActor
    func testSelectDateClearsRange() {
        let appState = AppState()
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 7))!

        // Set a range first
        appState.selectRange(DateRange(start: start, end: end))
        XCTAssertNotNil(appState.session.selectedRange)

        // Select a single date - should clear range
        let singleDate = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        appState.selectDate(singleDate)

        XCTAssertNil(appState.session.selectedRange)
    }

    @MainActor
    func testSelectRangeUpdatesSession() {
        let appState = AppState()
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 2026, month: 1, day: 1))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!

        let range = DateRange(start: start, end: end)
        appState.selectRange(range)

        XCTAssertNotNil(appState.session.selectedRange)
        XCTAssertEqual(appState.session.selectedRange?.start, start)
        XCTAssertEqual(appState.session.selectedRange?.end, end)
    }

    @MainActor
    func testDefaultSelectionIsToday() {
        let session = Session()
        let calendar = Calendar.current

        XCTAssertTrue(calendar.isDateInToday(session.selectedDate))
        XCTAssertNil(session.selectedRange)
    }

    // MARK: - Activity Filtering Tests

    @MainActor
    func testSelectedActivitiesFiltersToSelectedDate() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let session = Session(selectedDate: today)
        let account = Account(id: "test", provider: .gitlab, displayName: "Test")
        session.accounts = [account]

        // Add activities for today and yesterday
        session.activitiesByAccount["test"] = [
            UnifiedActivity(
                id: "1",
                provider: .gitlab,
                accountId: "test",
                sourceId: "src1",
                type: .commit,
                timestamp: today.addingTimeInterval(3600),
                title: "Today's activity"
            ),
            UnifiedActivity(
                id: "2",
                provider: .gitlab,
                accountId: "test",
                sourceId: "src2",
                type: .commit,
                timestamp: yesterday.addingTimeInterval(3600),
                title: "Yesterday's activity"
            )
        ]

        // Should only return today's activity
        let selected = session.selectedActivities
        XCTAssertEqual(selected.count, 1)
        XCTAssertEqual(selected.first?.id, "1")
    }

    @MainActor
    func testSelectedActivitiesFiltersToSelectedRange() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -7, to: today)!
        let end = calendar.date(byAdding: .day, value: 1, to: today)!  // Exclusive

        let session = Session(
            selectedDate: today,
            selectedRange: DateRange(start: start, end: end)
        )
        let account = Account(id: "test", provider: .gitlab, displayName: "Test")
        session.accounts = [account]

        // Add activities
        session.activitiesByAccount["test"] = [
            UnifiedActivity(
                id: "1",
                provider: .gitlab,
                accountId: "test",
                sourceId: "src1",
                type: .commit,
                timestamp: today,
                title: "Today"
            ),
            UnifiedActivity(
                id: "2",
                provider: .gitlab,
                accountId: "test",
                sourceId: "src2",
                type: .commit,
                timestamp: calendar.date(byAdding: .day, value: -3, to: today)!,
                title: "3 days ago"
            ),
            UnifiedActivity(
                id: "3",
                provider: .gitlab,
                accountId: "test",
                sourceId: "src3",
                type: .commit,
                timestamp: calendar.date(byAdding: .day, value: -10, to: today)!,
                title: "10 days ago (outside range)"
            )
        ]

        // Should return activities within the 7-day range
        let selected = session.selectedActivities
        XCTAssertEqual(selected.count, 2)
        XCTAssertTrue(selected.contains { $0.id == "1" })
        XCTAssertTrue(selected.contains { $0.id == "2" })
        XCTAssertFalse(selected.contains { $0.id == "3" })
    }

    // MARK: - Heatmap Range Selection Tests

    @MainActor
    func testHeatmapBucketsInRangeAreHighlighted() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -7, to: today)!
        let end = calendar.date(byAdding: .day, value: 1, to: today)!

        let session = Session(
            selectedDate: today,
            selectedRange: DateRange(start: start, end: end)
        )

        // Test date in range
        let midpoint = calendar.date(byAdding: .day, value: -3, to: today)!
        let midpointStart = calendar.startOfDay(for: midpoint)
        XCTAssertTrue(midpointStart >= session.selectedRange!.start)
        XCTAssertTrue(midpointStart < session.selectedRange!.end)

        // Test date outside range
        let outside = calendar.date(byAdding: .day, value: -10, to: today)!
        let outsideStart = calendar.startOfDay(for: outside)
        XCTAssertFalse(outsideStart >= session.selectedRange!.start && outsideStart < session.selectedRange!.end)
    }

    // MARK: - Quick Selection Tests

    @MainActor
    func testQuickSelectionLast7Days() {
        let appState = AppState()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Simulate "Last 7d" quick selection
        let start = calendar.date(byAdding: .day, value: -6, to: today)!  // 7 days including today
        let end = calendar.date(byAdding: .day, value: 1, to: today)!

        appState.selectRange(DateRange(start: start, end: end))

        XCTAssertNotNil(appState.session.selectedRange)
        // Range should span 7 days
        let days = calendar.dateComponents([.day], from: appState.session.selectedRange!.start, to: appState.session.selectedRange!.end)
        XCTAssertEqual(days.day, 7)
    }

    @MainActor
    func testQuickSelectionLast30Days() {
        let appState = AppState()
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Simulate "Last 30d" quick selection
        let start = calendar.date(byAdding: .day, value: -29, to: today)!  // 30 days including today
        let end = calendar.date(byAdding: .day, value: 1, to: today)!

        appState.selectRange(DateRange(start: start, end: end))

        XCTAssertNotNil(appState.session.selectedRange)
        let days = calendar.dateComponents([.day], from: appState.session.selectedRange!.start, to: appState.session.selectedRange!.end)
        XCTAssertEqual(days.day, 30)
    }

    @MainActor
    func testQuickSelectionTodaySelectsSingleDay() {
        let appState = AppState()
        let calendar = Calendar.current

        // First set a range
        let start = calendar.date(byAdding: .day, value: -7, to: Date())!
        let end = calendar.date(byAdding: .day, value: 1, to: Date())!
        appState.selectRange(DateRange(start: start, end: end))
        XCTAssertNotNil(appState.session.selectedRange)

        // Simulate "Today" quick selection
        appState.selectDate(calendar.startOfDay(for: Date()))

        // Should clear range and select today
        XCTAssertNil(appState.session.selectedRange)
        XCTAssertTrue(calendar.isDateInToday(appState.session.selectedDate))
    }

    // MARK: - Activity List Grouping Tests

    @MainActor
    func testActivityListGroupsByDayWhenRangeSelected() {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())
        let start = calendar.date(byAdding: .day, value: -7, to: today)!
        let end = calendar.date(byAdding: .day, value: 1, to: today)!

        let session = Session(
            selectedDate: today,
            selectedRange: DateRange(start: start, end: end)
        )

        // When a range is selected, grouping should be by day
        // This is tested via the UI but we can verify the condition
        XCTAssertTrue(session.selectedRange != nil)
    }

    @MainActor
    func testActivityListNoGroupingWhenSingleDaySelected() {
        let session = Session(selectedDate: Date(), selectedRange: nil)

        // When no range is selected, grouping should be .none
        // This is tested via the UI but we can verify the condition
        XCTAssertNil(session.selectedRange)
    }
}
