import XCTest
@testable import Core

@MainActor
final class HeatmapViewTests: XCTestCase {

    // MARK: - HeatMapBucket Tests

    func testHeatMapBucketUsesDateAsId() {
        let bucket = HeatMapBucket(date: "2026-01-19", count: 10)
        XCTAssertEqual(bucket.id, "2026-01-19")
    }

    func testHeatMapBucketWithBreakdown() {
        let bucket = HeatMapBucket(
            date: "2026-01-19",
            count: 15,
            breakdown: [.gitlab: 10, .gitlab: 5]
        )

        XCTAssertEqual(bucket.count, 15)
        XCTAssertEqual(bucket.breakdown?[.gitlab], 10)
        XCTAssertEqual(bucket.breakdown?[.gitlab], 5)
    }

    func testHeatMapBucketCodable() throws {
        let bucket = HeatMapBucket(
            date: "2026-01-19",
            count: 10,
            breakdown: [.gitlab: 7, .azureDevops: 3]
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(bucket)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HeatMapBucket.self, from: data)

        XCTAssertEqual(decoded.date, bucket.date)
        XCTAssertEqual(decoded.count, bucket.count)
        XCTAssertEqual(decoded.breakdown?[.gitlab], 7)
        XCTAssertEqual(decoded.breakdown?[.azureDevops], 3)
    }

    // MARK: - Session Heatmap Data Tests

    func testSessionHeatmapCountLookup() {
        let session = Session(heatmapBuckets: [
            HeatMapBucket(date: "2026-01-19", count: 10),
            HeatMapBucket(date: "2026-01-18", count: 5),
            HeatMapBucket(date: "2026-01-17", count: 0)
        ])

        // Create dates in UTC
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let jan19 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 19))!
        let jan18 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 18))!
        let jan17 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 17))!
        let jan16 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 16))!

        XCTAssertEqual(session.heatmapCount(for: jan19), 10)
        XCTAssertEqual(session.heatmapCount(for: jan18), 5)
        XCTAssertEqual(session.heatmapCount(for: jan17), 0)
        XCTAssertEqual(session.heatmapCount(for: jan16), 0) // Not in buckets
    }

    func testHeatMapBucketOnlyUsesActivityDiscoveryFields() {
        // HeatMapBucket should only have: date, count, breakdown
        // This test ensures we're using the activity-discovery schema
        let bucket = HeatMapBucket(date: "2026-01-19", count: 5)

        // Verify only the expected fields exist
        let mirror = Mirror(reflecting: bucket)
        let propertyNames = mirror.children.compactMap { $0.label }

        XCTAssertEqual(propertyNames.sorted(), ["breakdown", "count", "date"])
    }

    func testHeatMapBucketBreakdownIsOptional() {
        let bucketWithBreakdown = HeatMapBucket(
            date: "2026-01-19",
            count: 10,
            breakdown: [.gitlab: 10]
        )
        let bucketWithoutBreakdown = HeatMapBucket(date: "2026-01-18", count: 5)

        XCTAssertNotNil(bucketWithBreakdown.breakdown)
        XCTAssertNil(bucketWithoutBreakdown.breakdown)
    }

    // MARK: - Aggregated Count Tests

    func testHeatmapAggregatesAcrossProviders() {
        let appState = AppState()

        let gitlabBuckets1 = [
            HeatMapBucket(date: "2026-01-19", count: 5, breakdown: [.gitlab: 5]),
            HeatMapBucket(date: "2026-01-18", count: 3, breakdown: [.gitlab: 3])
        ]
        let gitlabBuckets2 = [
            HeatMapBucket(date: "2026-01-19", count: 3, breakdown: [.gitlab: 3])
        ]
        let azureBuckets = [
            HeatMapBucket(date: "2026-01-19", count: 2, breakdown: [.azureDevops: 2]),
            HeatMapBucket(date: "2026-01-17", count: 1, breakdown: [.azureDevops: 1])
        ]

        appState.mergeHeatmap(from: [gitlabBuckets1, gitlabBuckets2, azureBuckets])

        // Should have 3 unique dates
        XCTAssertEqual(appState.session.heatmapBuckets.count, 3)

        // Jan 19 should aggregate: 5 + 3 + 2 = 10, GitLab: 5+3=8, Azure: 2
        let jan19 = appState.session.heatmapBuckets.first { $0.date == "2026-01-19" }
        XCTAssertEqual(jan19?.count, 10)
        XCTAssertEqual(jan19?.breakdown?[.gitlab], 8)
        XCTAssertEqual(jan19?.breakdown?[.azureDevops], 2)

        // Jan 18 should only have GitLab: 3
        let jan18 = appState.session.heatmapBuckets.first { $0.date == "2026-01-18" }
        XCTAssertEqual(jan18?.count, 3)

        // Jan 17 should only have Azure: 1
        let jan17 = appState.session.heatmapBuckets.first { $0.date == "2026-01-17" }
        XCTAssertEqual(jan17?.count, 1)
    }

    func testHeatmapAggregatesAcrossAccounts() {
        let appState = AppState()

        // Two GitHub accounts
        let account1Buckets = [
            HeatMapBucket(date: "2026-01-19", count: 5, breakdown: [.gitlab: 5])
        ]
        let account2Buckets = [
            HeatMapBucket(date: "2026-01-19", count: 7, breakdown: [.gitlab: 7])
        ]

        appState.mergeHeatmap(from: [account1Buckets, account2Buckets])

        let jan19 = appState.session.heatmapBuckets.first { $0.date == "2026-01-19" }
        XCTAssertEqual(jan19?.count, 12)
        XCTAssertEqual(jan19?.breakdown?[.gitlab], 12)
    }

    // MARK: - Date Selection Tests

    func testSelectDateUpdatesSession() {
        let appState = AppState()

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!

        appState.selectDate(date)

        XCTAssertEqual(Session.dateString(from: appState.session.selectedDate), "2026-01-15")
        XCTAssertNil(appState.session.selectedRange) // Range cleared on single date select
    }

    func testSelectDateClearsRange() {
        let appState = AppState()

        // First select a range
        let range = DateRange(start: Date().addingTimeInterval(-172800), end: Date())
        appState.selectRange(range)
        XCTAssertNotNil(appState.session.selectedRange)

        // Then select a single date
        appState.selectDate(Date())

        XCTAssertNil(appState.session.selectedRange)
    }

    // MARK: - DateString Format Tests

    func testDateStringUsesUTC() {
        // This is important: heatmap dates must use UTC to match activity-discovery
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let date = calendar.date(from: DateComponents(year: 2026, month: 6, day: 15, hour: 23, minute: 59))!
        let dateString = Session.dateString(from: date)

        // Should be 2026-06-15, not 2026-06-16 (which could happen with local timezone)
        XCTAssertEqual(dateString, "2026-06-15")
    }

    func testDateStringFormatYYYYMMDD() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let testCases: [(DateComponents, String)] = [
            (DateComponents(year: 2026, month: 1, day: 1), "2026-01-01"),
            (DateComponents(year: 2026, month: 12, day: 31), "2026-12-31"),
            (DateComponents(year: 2026, month: 3, day: 5), "2026-03-05")
        ]

        for (components, expected) in testCases {
            let date = calendar.date(from: components)!
            XCTAssertEqual(Session.dateString(from: date), expected)
        }
    }

    // MARK: - Heatmap Data Integrity Tests

    func testHeatmapBucketsAreSortedByDate() {
        let appState = AppState()

        let buckets = [
            HeatMapBucket(date: "2026-01-15", count: 1),
            HeatMapBucket(date: "2026-01-20", count: 2),
            HeatMapBucket(date: "2026-01-10", count: 3),
            HeatMapBucket(date: "2026-01-25", count: 4)
        ]

        appState.mergeHeatmap(from: [buckets])

        let dates = appState.session.heatmapBuckets.map { $0.date }
        XCTAssertEqual(dates, ["2026-01-10", "2026-01-15", "2026-01-20", "2026-01-25"])
    }

    func testEmptyHeatmap() {
        let appState = AppState()
        appState.mergeHeatmap(from: [])

        XCTAssertTrue(appState.session.heatmapBuckets.isEmpty)
    }

    func testMergeWithEmptyArray() {
        let appState = AppState()

        let buckets = [
            HeatMapBucket(date: "2026-01-19", count: 5)
        ]

        appState.mergeHeatmap(from: [buckets, []])

        XCTAssertEqual(appState.session.heatmapBuckets.count, 1)
        XCTAssertEqual(appState.session.heatmapBuckets.first?.count, 5)
    }
}
