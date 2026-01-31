import XCTest
@testable import Core

@MainActor
final class RefreshSchedulerTests: XCTestCase {

    // MARK: - RefreshInterval Tests

    func testRefreshIntervalSeconds() {
        XCTAssertEqual(RefreshInterval.fiveMinutes.seconds, 5 * 60)
        XCTAssertEqual(RefreshInterval.fifteenMinutes.seconds, 15 * 60)
        XCTAssertEqual(RefreshInterval.thirtyMinutes.seconds, 30 * 60)
        XCTAssertEqual(RefreshInterval.oneHour.seconds, 60 * 60)
        XCTAssertNil(RefreshInterval.manual.seconds)
    }

    func testRefreshIntervalDisplayNames() {
        XCTAssertEqual(RefreshInterval.fiveMinutes.displayName, "5 minutes")
        XCTAssertEqual(RefreshInterval.fifteenMinutes.displayName, "15 minutes")
        XCTAssertEqual(RefreshInterval.thirtyMinutes.displayName, "30 minutes")
        XCTAssertEqual(RefreshInterval.oneHour.displayName, "1 hour")
        XCTAssertEqual(RefreshInterval.manual.displayName, "Manual only")
    }

    func testRefreshIntervalRawValues() {
        XCTAssertEqual(RefreshInterval.fiveMinutes.rawValue, "5m")
        XCTAssertEqual(RefreshInterval.fifteenMinutes.rawValue, "15m")
        XCTAssertEqual(RefreshInterval.thirtyMinutes.rawValue, "30m")
        XCTAssertEqual(RefreshInterval.oneHour.rawValue, "1h")
        XCTAssertEqual(RefreshInterval.manual.rawValue, "manual")
    }

    func testRefreshIntervalCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for interval in RefreshInterval.allCases {
            let data = try encoder.encode(interval)
            let decoded = try decoder.decode(RefreshInterval.self, from: data)
            XCTAssertEqual(decoded, interval)
        }
    }

    func testRefreshIntervalAllCases() {
        XCTAssertEqual(RefreshInterval.allCases.count, 5)
    }

    // MARK: - RefreshScheduler Initialization Tests

    func testSchedulerInitialState() {
        let scheduler = RefreshScheduler(
            interval: .fifteenMinutes,
            debounceInterval: 30,
            onRefresh: {}
        )

        XCTAssertEqual(scheduler.interval, .fifteenMinutes)
        XCTAssertEqual(scheduler.debounceInterval, 30)
        XCTAssertFalse(scheduler.isRefreshing)
        XCTAssertFalse(scheduler.isActive)
        XCTAssertNil(scheduler.lastRefreshed)
        XCTAssertNil(scheduler.lastError)
    }

    func testSchedulerDefaultValues() {
        let scheduler = RefreshScheduler(onRefresh: {})

        XCTAssertEqual(scheduler.interval, .fifteenMinutes)
        XCTAssertEqual(scheduler.debounceInterval, 30)
    }

    // MARK: - Lifecycle Tests

    func testStartSetsActive() {
        let scheduler = RefreshScheduler(onRefresh: {})

        XCTAssertFalse(scheduler.isActive)
        scheduler.start()
        XCTAssertTrue(scheduler.isActive)
    }

    func testStopSetsInactive() {
        let scheduler = RefreshScheduler(onRefresh: {})

        scheduler.start()
        XCTAssertTrue(scheduler.isActive)

        scheduler.stop()
        XCTAssertFalse(scheduler.isActive)
    }

    func testStartIsIdempotent() {
        let scheduler = RefreshScheduler(onRefresh: {})

        scheduler.start()
        scheduler.start()
        XCTAssertTrue(scheduler.isActive)
    }

    // MARK: - Refresh Trigger Tests

    func testTriggerRefreshCallsCallback() async {
        var callCount = 0

        let scheduler = RefreshScheduler(
            debounceInterval: 0,  // Disable debounce for test
            onRefresh: { callCount += 1 }
        )

        scheduler.start()
        scheduler.triggerRefresh()

        // Wait for async refresh to complete
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(callCount, 1)
    }

    func testForceRefreshCallsCallback() async {
        var callCount = 0

        let scheduler = RefreshScheduler(
            debounceInterval: 60,  // Long debounce
            onRefresh: { callCount += 1 }
        )

        scheduler.start()
        scheduler.forceRefresh()

        // Wait for async refresh to complete
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(callCount, 1)
    }

    func testDebouncePreventsDuplicateTriggers() async {
        var callCount = 0

        let scheduler = RefreshScheduler(
            debounceInterval: 60,  // 60 second debounce
            onRefresh: {
                callCount += 1
                // Simulate work
            }
        )

        scheduler.start()
        scheduler.triggerRefresh()

        // Wait for first refresh
        try? await Task.sleep(for: .milliseconds(50))

        // Second trigger should be debounced
        scheduler.triggerRefresh()

        // Wait again
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertEqual(callCount, 1, "Second trigger should be debounced")
    }

    func testConcurrentRefreshesArePrevented() async {
        var concurrentCount = 0
        var maxConcurrent = 0

        let scheduler = RefreshScheduler(
            debounceInterval: 0,
            onRefresh: {
                concurrentCount += 1
                maxConcurrent = max(maxConcurrent, concurrentCount)
                try? await Task.sleep(for: .milliseconds(100))
                concurrentCount -= 1
            }
        )

        scheduler.start()
        scheduler.forceRefresh()
        scheduler.forceRefresh()
        scheduler.forceRefresh()

        // Wait for all to complete
        try? await Task.sleep(for: .milliseconds(200))

        XCTAssertEqual(maxConcurrent, 1, "Only one refresh should run at a time")
    }

    // MARK: - Interval Change Tests

    func testIntervalChange() {
        let scheduler = RefreshScheduler(
            interval: .fifteenMinutes,
            onRefresh: {}
        )

        XCTAssertEqual(scheduler.interval, .fifteenMinutes)

        scheduler.interval = .oneHour
        XCTAssertEqual(scheduler.interval, .oneHour)
    }

    func testManualIntervalDisablesTimer() {
        let scheduler = RefreshScheduler(
            interval: .manual,
            onRefresh: {}
        )

        scheduler.start()
        XCTAssertTrue(scheduler.isActive)
        XCTAssertNil(scheduler.interval.seconds)
    }

    // MARK: - Status Description Tests

    func testStatusDescriptionNotYetRefreshed() {
        let scheduler = RefreshScheduler(onRefresh: {})

        XCTAssertEqual(scheduler.statusDescription, "Not yet refreshed")
    }

    func testStatusDescriptionRefreshing() async {
        let scheduler = RefreshScheduler(
            debounceInterval: 0,
            onRefresh: {
                try? await Task.sleep(for: .milliseconds(100))
            }
        )

        scheduler.start()
        scheduler.triggerRefresh()

        // Check while refreshing
        try? await Task.sleep(for: .milliseconds(10))
        XCTAssertEqual(scheduler.statusDescription, "Refreshing...")
    }

    func testStatusDescriptionUpdated() async {
        let scheduler = RefreshScheduler(
            debounceInterval: 0,
            onRefresh: {}
        )

        scheduler.start()
        scheduler.triggerRefresh()

        // Wait for completion
        try? await Task.sleep(for: .milliseconds(50))

        XCTAssertTrue(scheduler.statusDescription.contains("Updated"))
    }

    // MARK: - Time Until Next Refresh Tests

    func testTimeUntilNextRefreshNilWhenNotActive() {
        let scheduler = RefreshScheduler(
            interval: .fifteenMinutes,
            onRefresh: {}
        )

        XCTAssertNil(scheduler.timeUntilNextRefresh)
    }

    func testTimeUntilNextRefreshNilForManual() {
        let scheduler = RefreshScheduler(
            interval: .manual,
            onRefresh: {}
        )

        scheduler.start()
        XCTAssertNil(scheduler.timeUntilNextRefresh)
    }
}
