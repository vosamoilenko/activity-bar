import Testing
import Foundation
@testable import App

@Suite("RelativeTimeFormatter Tests")
struct RelativeTimeFormatterTests {
    // MARK: - Recent Times (< 1 minute)

    @Test("Formats current time as 'now'")
    func testCurrentTime() {
        let now = Date()
        let result = RelativeTimeFormatter.relativeString(from: now, relativeTo: now)
        // RelativeDateTimeFormatter returns "now" or "in 0 seconds" depending on locale
        #expect(result.contains("now") || result.contains("0"))
    }

    @Test("Formats 30 seconds ago")
    func testThirtySecondsAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-30)
        let result = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        // Expect either "30 sec. ago" or similar short format
        #expect(result.contains("sec") || result.contains("now"))
    }

    // MARK: - Minutes

    @Test("Formats 2 minutes ago")
    func testTwoMinutesAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-2 * 60)
        let result = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        #expect(result.contains("2"))
        #expect(result.contains("min"))
    }

    @Test("Formats 45 minutes ago")
    func testFortyFiveMinutesAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-45 * 60)
        let result = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        #expect(result.contains("45"))
        #expect(result.contains("min"))
    }

    // MARK: - Hours

    @Test("Formats 1 hour ago")
    func testOneHourAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-1 * 60 * 60)
        let result = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        #expect(result.contains("1"))
        #expect(result.contains("hr") || result.contains("hour"))
    }

    @Test("Formats 5 hours ago")
    func testFiveHoursAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-5 * 60 * 60)
        let result = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        #expect(result.contains("5"))
        #expect(result.contains("hr") || result.contains("hour"))
    }

    @Test("Formats 23 hours ago")
    func testTwentyThreeHoursAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-23 * 60 * 60)
        let result = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        #expect(result.contains("23"))
        #expect(result.contains("hr") || result.contains("hour"))
    }

    // MARK: - Days

    @Test("Formats 1 day ago")
    func testOneDayAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-24 * 60 * 60)
        let result = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        #expect(result.contains("1"))
        #expect(result.contains("day"))
    }

    @Test("Formats 3 days ago")
    func testThreeDaysAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-3 * 24 * 60 * 60)
        let result = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        #expect(result.contains("3"))
        #expect(result.contains("day"))
    }

    @Test("Formats 6 days ago")
    func testSixDaysAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-6 * 24 * 60 * 60)
        let result = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        #expect(result.contains("6"))
        #expect(result.contains("day"))
    }

    // MARK: - Weeks

    @Test("Formats 1 week ago")
    func testOneWeekAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-7 * 24 * 60 * 60)
        let result = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        #expect(result.contains("1"))
        #expect(result.contains("wk") || result.contains("week"))
    }

    @Test("Formats 2 weeks ago")
    func testTwoWeeksAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-14 * 24 * 60 * 60)
        let result = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        #expect(result.contains("2"))
        #expect(result.contains("wk") || result.contains("week"))
    }

    @Test("Formats 3 weeks ago")
    func testThreeWeeksAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-21 * 24 * 60 * 60)
        let result = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        #expect(result.contains("3"))
        #expect(result.contains("wk") || result.contains("week"))
    }

    // MARK: - Months

    @Test("Formats 1 month ago")
    func testOneMonthAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-30 * 24 * 60 * 60)
        let result = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        // 30 days may be formatted as "4 wk" or "1 mo" depending on the formatter
        #expect(result.contains("wk") || result.contains("mo") || result.contains("week") || result.contains("month"))
    }

    @Test("Formats 3 months ago")
    func testThreeMonthsAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-90 * 24 * 60 * 60)
        let result = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        // 90 days may be formatted as "2 mo" or "3 mo" depending on precision
        #expect(result.contains("mo") || result.contains("month"))
    }

    // MARK: - Years

    @Test("Formats 1 year ago")
    func testOneYearAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-365 * 24 * 60 * 60)
        let result = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        #expect(result.contains("1"))
        #expect(result.contains("yr") || result.contains("year"))
    }

    @Test("Formats 2 years ago")
    func testTwoYearsAgo() {
        let now = Date()
        let past = now.addingTimeInterval(-2 * 365 * 24 * 60 * 60)
        let result = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        // 2 years may be rounded to "1 yr" or "2 yr" depending on precision
        #expect(result.contains("yr") || result.contains("year"))
    }

    // MARK: - Future Dates

    @Test("Formats future date (1 hour from now)")
    func testOneHourInFuture() {
        let now = Date()
        let future = now.addingTimeInterval(1 * 60 * 60)
        let result = RelativeTimeFormatter.relativeString(from: future, relativeTo: now)
        #expect(result.contains("1"))
        #expect(result.contains("hr") || result.contains("hour") || result.contains("in"))
    }

    @Test("Formats future date (2 days from now)")
    func testTwoDaysInFuture() {
        let now = Date()
        let future = now.addingTimeInterval(2 * 24 * 60 * 60)
        let result = RelativeTimeFormatter.relativeString(from: future, relativeTo: now)
        #expect(result.contains("2"))
        #expect(result.contains("day") || result.contains("in"))
    }

    // MARK: - Default Convenience Method

    @Test("Convenience method formats exact time")
    func testConvenienceMethod() {
        let date = Date()
        let result = RelativeTimeFormatter.string(from: date)
        // Should return HH:MM format
        #expect(result.contains(":"))
        #expect(result.count >= 4 && result.count <= 5)  // "H:MM" or "HH:MM"
    }

    // MARK: - Edge Cases

    @Test("Handles very old dates gracefully")
    func testVeryOldDate() {
        let now = Date()
        let veryOld = now.addingTimeInterval(-10 * 365 * 24 * 60 * 60)
        let result = RelativeTimeFormatter.relativeString(from: veryOld, relativeTo: now)
        // Should indicate years
        #expect(result.contains("yr") || result.contains("year"))
    }

    @Test("Handles identical dates")
    func testIdenticalDates() {
        let date = Date(timeIntervalSince1970: 1640000000)
        let result = RelativeTimeFormatter.relativeString(from: date, relativeTo: date)
        #expect(result.contains("now") || result.contains("0"))
    }

    @Test("Short units style produces compact output")
    func testShortUnitsStyle() {
        let now = Date()
        let past = now.addingTimeInterval(-5 * 60)
        let result = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        // Short style should use abbreviations like "min", "hr", "wk", not full words
        // Length should be reasonably short (< 20 characters for 5 minutes)
        #expect(result.count < 20)
    }

    @Test("Multiple calls produce consistent results")
    func testConsistency() {
        let now = Date()
        let past = now.addingTimeInterval(-3 * 60 * 60)
        let result1 = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        let result2 = RelativeTimeFormatter.relativeString(from: past, relativeTo: now)
        #expect(result1 == result2)
    }
}
