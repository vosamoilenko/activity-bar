import XCTest
@testable import Core

@MainActor
final class DataCoordinatorTests: XCTestCase {

    // MARK: - Cache Loading Tests

    func testLoadFromCacheWithNilProvider() async {
        let appState = AppState()
        let coordinator = DataCoordinator(appState: appState, cacheProvider: nil)

        await coordinator.loadFromCache()

        XCTAssertTrue(coordinator.hasLoadedCache)
        XCTAssertTrue(appState.hasLoadedFromCache)
    }

    func testLoadFromCacheWithProvider() async {
        let appState = AppState()

        let accounts = [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab"),
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]
        let activities: [String: [UnifiedActivity]] = [
            "gh1": [
                UnifiedActivity(id: "a1", provider: .gitlab, accountId: "gl1",
                              sourceId: "s1", type: .commit, timestamp: Date())
            ],
            "gl1": [
                UnifiedActivity(id: "a2", provider: .gitlab, accountId: "gl1",
                              sourceId: "s2", type: .pullRequest, timestamp: Date())
            ]
        ]
        let heatmap = [
            HeatMapBucket(date: "2026-01-19", count: 5),
            HeatMapBucket(date: "2026-01-18", count: 3)
        ]

        let cache = InMemoryCacheProvider(
            accounts: accounts,
            activities: activities,
            heatmap: heatmap
        )

        let coordinator = DataCoordinator(appState: appState, cacheProvider: cache)

        await coordinator.loadFromCache()

        XCTAssertTrue(coordinator.hasLoadedCache)
        XCTAssertTrue(appState.hasLoadedFromCache)
        XCTAssertEqual(appState.session.accounts.count, 2)
        XCTAssertEqual(appState.session.activitiesByAccount["gh1"]?.count, 1)
        XCTAssertEqual(appState.session.activitiesByAccount["gl1"]?.count, 1)
        XCTAssertEqual(appState.session.heatmapBuckets.count, 2)
    }

    func testLoadFromCachePopulatesAccounts() async {
        let appState = AppState()
        let accounts = [
            Account(id: "test1", provider: .gitlab, displayName: "Test 1"),
            Account(id: "test2", provider: .gitlab, displayName: "Test 2", isEnabled: false)
        ]

        let cache = InMemoryCacheProvider(accounts: accounts)
        let coordinator = DataCoordinator(appState: appState, cacheProvider: cache)

        await coordinator.loadFromCache()

        XCTAssertEqual(appState.session.accounts.count, 2)
        XCTAssertEqual(appState.session.enabledAccounts.count, 1)
    }

    // MARK: - Background Refresh Tests

    func testRefreshWithNilProviderDoesNothing() async {
        let appState = AppState()
        let coordinator = DataCoordinator(appState: appState, refreshProvider: nil)

        await coordinator.refreshInBackground()

        XCTAssertFalse(appState.session.isRefreshing)
        XCTAssertNil(appState.session.lastRefreshed)
    }

    func testRefreshWithStubProvider() async {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        let refresher = StubRefreshProvider()
        let coordinator = DataCoordinator(appState: appState, refreshProvider: refresher)

        await coordinator.refreshInBackground()

        XCTAssertFalse(coordinator.isRefreshing)
        XCTAssertFalse(appState.session.isRefreshing)
        XCTAssertNotNil(appState.session.lastRefreshed)
        XCTAssertNil(appState.lastError)
    }

    func testRefreshUpdatesActivities() async {
        let appState = AppState(session: Session(accounts: [
            Account(id: "test1", provider: .gitlab, displayName: "Test")
        ]))

        let refresher = MockRefreshProvider(
            activities: [
                UnifiedActivity(id: "new1", provider: .gitlab, accountId: "test1",
                              sourceId: "s1", type: .commit, timestamp: Date())
            ],
            heatmap: [HeatMapBucket(date: "2026-01-19", count: 10)]
        )

        let coordinator = DataCoordinator(appState: appState, refreshProvider: refresher)

        await coordinator.refreshInBackground()

        XCTAssertEqual(appState.session.activitiesByAccount["test1"]?.count, 1)
        XCTAssertEqual(appState.session.activitiesByAccount["test1"]?.first?.id, "new1")
    }

    func testRefreshMergesHeatmapFromMultipleAccounts() async {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab"),
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        let refresher = MockRefreshProvider(
            activities: [],
            heatmap: [HeatMapBucket(date: "2026-01-19", count: 5)]
        )

        let coordinator = DataCoordinator(appState: appState, refreshProvider: refresher)

        await coordinator.refreshInBackground()

        // 2 accounts, each returning count 5 = merged count 10
        let bucket = appState.session.heatmapBuckets.first { $0.date == "2026-01-19" }
        XCTAssertEqual(bucket?.count, 10)
    }

    func testRefreshDebouncesConcurrentCalls() async {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        let refresher = SlowRefreshProvider()
        let coordinator = DataCoordinator(appState: appState, refreshProvider: refresher)

        // Start first refresh
        let task1 = Task {
            await coordinator.refreshInBackground()
        }

        // Try second refresh immediately (should be debounced)
        let task2 = Task {
            await coordinator.refreshInBackground()
        }

        await task1.value
        await task2.value

        // Slow provider increments call count - should only be 1 if debounced
        XCTAssertEqual(refresher.callCount, 1)
    }

    func testRefreshHandlesAccountErrors() async {
        let appState = AppState(session: Session(accounts: [
            Account(id: "fail1", provider: .gitlab, displayName: "Failing Account")
        ]))

        let refresher = FailingRefreshProvider()
        let coordinator = DataCoordinator(appState: appState, refreshProvider: refresher)

        await coordinator.refreshInBackground()

        XCTAssertFalse(coordinator.isRefreshing)
        XCTAssertNotNil(appState.lastError)
        XCTAssertTrue(appState.lastError?.contains("Failing Account") ?? false)
    }

    func testRefreshOnlyFetchesEnabledAccounts() async {
        let appState = AppState(session: Session(accounts: [
            Account(id: "enabled", provider: .gitlab, displayName: "Enabled", isEnabled: true),
            Account(id: "disabled", provider: .gitlab, displayName: "Disabled", isEnabled: false)
        ]))

        let refresher = TrackingRefreshProvider()
        let coordinator = DataCoordinator(appState: appState, refreshProvider: refresher)

        await coordinator.refreshInBackground()

        XCTAssertEqual(refresher.fetchedAccountIds, ["enabled"])
    }

    // MARK: - Integration Tests

    func testCacheLoadThenRefreshFlow() async {
        let appState = AppState()

        // Initial cache with old data
        let oldActivity = UnifiedActivity(
            id: "old1", provider: .gitlab, accountId: "gl1",
            sourceId: "s1", type: .commit, timestamp: Date().addingTimeInterval(-86400)
        )
        let cache = InMemoryCacheProvider(
            accounts: [Account(id: "gl1", provider: .gitlab, displayName: "GitLab")],
            activities: ["gl1": [oldActivity]],
            heatmap: [HeatMapBucket(date: "2026-01-18", count: 1)]
        )

        // Refresher returns new data
        let newActivity = UnifiedActivity(
            id: "new1", provider: .gitlab, accountId: "gl1",
            sourceId: "s2", type: .pullRequest, timestamp: Date()
        )
        let refresher = MockRefreshProvider(
            activities: [newActivity],
            heatmap: [HeatMapBucket(date: "2026-01-19", count: 5)]
        )

        let coordinator = DataCoordinator(
            appState: appState,
            cacheProvider: cache,
            refreshProvider: refresher
        )

        // 1. Load from cache first
        await coordinator.loadFromCache()

        XCTAssertTrue(appState.hasLoadedFromCache)
        XCTAssertEqual(appState.session.activitiesByAccount["gl1"]?.first?.id, "old1")
        XCTAssertEqual(appState.session.heatmapBuckets.first?.date, "2026-01-18")

        // 2. Refresh in background
        await coordinator.refreshInBackground()

        XCTAssertEqual(appState.session.activitiesByAccount["gl1"]?.first?.id, "new1")
        XCTAssertEqual(appState.session.heatmapBuckets.first?.date, "2026-01-19")
        XCTAssertNotNil(appState.session.lastRefreshed)
    }

    func testOverlayRendersImmediatelyFromCache() async {
        let appState = AppState()

        // Simulate cached data
        let cachedActivities = [
            UnifiedActivity(
                id: "cached1", provider: .gitlab, accountId: "gl1",
                sourceId: "s1", type: .commit, timestamp: Date(),
                title: "Fix bug"
            )
        ]
        let cache = InMemoryCacheProvider(
            accounts: [Account(id: "gl1", provider: .gitlab, displayName: "GitLab")],
            activities: ["gl1": cachedActivities],
            heatmap: [HeatMapBucket(date: "2026-01-19", count: 3)]
        )

        let coordinator = DataCoordinator(appState: appState, cacheProvider: cache)

        // Load from cache - this should be immediate (no network)
        await coordinator.loadFromCache()

        // Verify data is available for overlay rendering
        XCTAssertTrue(appState.hasLoadedFromCache)
        XCTAssertEqual(appState.session.allActivities.count, 1)
        XCTAssertEqual(appState.session.allActivities.first?.title, "Fix bug")
        XCTAssertEqual(appState.session.heatmapBuckets.count, 1)
    }
}

// MARK: - Test Helpers

/// Mock refresh provider that returns configured data
final class MockRefreshProvider: RefreshProvider, @unchecked Sendable {
    private let activities: [UnifiedActivity]
    private let heatmap: [HeatMapBucket]

    init(activities: [UnifiedActivity], heatmap: [HeatMapBucket]) {
        self.activities = activities
        self.heatmap = heatmap
    }

    func fetchActivities(for account: Account) async throws -> [UnifiedActivity] {
        activities
    }

    func fetchHeatmap(for account: Account) async throws -> [HeatMapBucket] {
        heatmap
    }
}

/// Slow refresh provider for testing debounce
final class SlowRefreshProvider: RefreshProvider, @unchecked Sendable {
    private(set) var callCount = 0

    func fetchActivities(for account: Account) async throws -> [UnifiedActivity] {
        callCount += 1
        try? await Task.sleep(for: .milliseconds(50))
        return []
    }

    func fetchHeatmap(for account: Account) async throws -> [HeatMapBucket] {
        []
    }
}

/// Refresh provider that always fails
final class FailingRefreshProvider: RefreshProvider, @unchecked Sendable {
    struct MockError: Error, LocalizedError {
        var errorDescription: String? { "Network error" }
    }

    func fetchActivities(for account: Account) async throws -> [UnifiedActivity] {
        throw MockError()
    }

    func fetchHeatmap(for account: Account) async throws -> [HeatMapBucket] {
        throw MockError()
    }
}

/// Refresh provider that tracks which accounts were fetched
final class TrackingRefreshProvider: RefreshProvider, @unchecked Sendable {
    private(set) var fetchedAccountIds: [String] = []

    func fetchActivities(for account: Account) async throws -> [UnifiedActivity] {
        fetchedAccountIds.append(account.id)
        return []
    }

    func fetchHeatmap(for account: Account) async throws -> [HeatMapBucket] {
        []
    }
}

// MARK: - Per-Day Cache Provider Tests

/// Mock per-day cache provider for testing
final class MockPerDayCacheProvider: PerDayCacheProvider, @unchecked Sendable {
    private var dayIndex: [String: [String: DayIndexEntry]] = [:]
    private var activitiesByAccountAndDay: [String: [String: [UnifiedActivity]]] = [:]
    private var accounts: [Account]
    private var staleDays: Set<String> = []

    init(accounts: [Account] = []) {
        self.accounts = accounts
    }

    func setDayActivities(_ activities: [UnifiedActivity], accountId: String, date: String) {
        if activitiesByAccountAndDay[accountId] == nil {
            activitiesByAccountAndDay[accountId] = [:]
        }
        activitiesByAccountAndDay[accountId]![date] = activities

        if dayIndex[accountId] == nil {
            dayIndex[accountId] = [:]
        }
        dayIndex[accountId]![date] = DayIndexEntry(fetchedAt: Date(), count: activities.count)
    }

    func markDayStale(_ date: String) {
        staleDays.insert(date)
    }

    // MARK: - CacheProvider

    func loadCachedActivities() async -> [String: [UnifiedActivity]] {
        var result: [String: [UnifiedActivity]] = [:]
        for (accountId, days) in activitiesByAccountAndDay {
            result[accountId] = days.values.flatMap { $0 }
        }
        return result
    }

    func loadCachedHeatmap() async -> [HeatMapBucket] {
        var countsByDate: [String: Int] = [:]
        for (_, days) in dayIndex {
            for (date, entry) in days {
                countsByDate[date, default: 0] += entry.count
            }
        }
        return countsByDate.map { HeatMapBucket(date: $0.key, count: $0.value) }
    }

    func loadCachedAccounts() async -> [Account] {
        accounts
    }

    // MARK: - PerDayCacheProvider

    func loadDayIndex() async -> [String: [String: DayIndexEntry]] {
        dayIndex
    }

    func loadActivitiesForDay(accountId: String, date: String) async -> [UnifiedActivity]? {
        activitiesByAccountAndDay[accountId]?[date]
    }

    func saveActivitiesForDay(_ activities: [UnifiedActivity], accountId: String, date: String) async {
        setDayActivities(activities, accountId: accountId, date: date)
    }

    func isTodayCacheStale(accountId: String) async -> Bool {
        let today = Self.dateString(from: Date())
        return staleDays.contains(today) || activitiesByAccountAndDay[accountId]?[today] == nil
    }

    // Helper to format date string (non-MainActor)
    private static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

/// Mock per-day refresh provider for testing
final class MockPerDayRefreshProvider: PerDayRefreshProvider, @unchecked Sendable {
    private var activitiesByDate: [String: [UnifiedActivity]] = [:]
    private(set) var fetchedDates: [String] = []
    private(set) var fetchedAccountIds: [String] = []

    func setActivitiesForDate(_ activities: [UnifiedActivity], date: String) {
        activitiesByDate[date] = activities
    }

    func fetchActivities(for account: Account) async throws -> [UnifiedActivity] {
        fetchedAccountIds.append(account.id)
        return activitiesByDate.values.flatMap { $0 }
    }

    func fetchHeatmap(for account: Account) async throws -> [HeatMapBucket] {
        return activitiesByDate.map { HeatMapBucket(date: $0.key, count: $0.value.count) }
    }

    func fetchActivitiesForDay(for account: Account, date: Date) async throws -> [UnifiedActivity] {
        let dateStr = Self.dateString(from: date)
        fetchedDates.append(dateStr)
        fetchedAccountIds.append(account.id)
        return activitiesByDate[dateStr] ?? []
    }

    func fetchActivitiesForDateRange(for account: Account, from: Date, to: Date) async throws -> [String: [UnifiedActivity]] {
        fetchedAccountIds.append(account.id)
        // Return all activities grouped by date that fall within the range
        var result: [String: [UnifiedActivity]] = [:]
        let fromStr = Self.dateString(from: from)
        let toStr = Self.dateString(from: to)
        for (dateStr, activities) in activitiesByDate {
            if dateStr >= fromStr && dateStr <= toStr {
                result[dateStr] = activities
                fetchedDates.append(dateStr)
            }
        }
        return result
    }

    // Helper to format date string (non-MainActor)
    private static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

@MainActor
final class PerDayDataCoordinatorTests: XCTestCase {

    // MARK: - calculateVisibleHeatmapDates Tests (tested via needsInitialFetch)

    func testNeedsInitialFetchReturnsTrueWhenNoCacheProvider() async {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        let coordinator = DataCoordinator(appState: appState, cacheProvider: nil)

        let needsFetch = await coordinator.needsInitialFetch()
        XCTAssertTrue(needsFetch)
    }

    func testNeedsInitialFetchReturnsTrueWhenTodayIsStale() async {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        let cache = MockPerDayCacheProvider(accounts: appState.session.accounts)
        let today = DataCoordinator.dateString(from: Date())
        cache.setDayActivities([], accountId: "gl1", date: today)
        cache.markDayStale(today)

        let coordinator = DataCoordinator(appState: appState, cacheProvider: cache)

        let needsFetch = await coordinator.needsInitialFetch()
        XCTAssertTrue(needsFetch)
    }

    func testNeedsInitialFetchReturnsTrueWhenDaysMissing() async {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        let cache = MockPerDayCacheProvider(accounts: appState.session.accounts)
        // Only cache today, but many other days are missing
        let today = DataCoordinator.dateString(from: Date())
        cache.setDayActivities([], accountId: "gl1", date: today)

        let coordinator = DataCoordinator(appState: appState, cacheProvider: cache)

        let needsFetch = await coordinator.needsInitialFetch()
        XCTAssertTrue(needsFetch) // Missing days in heatmap range
    }

    // MARK: - getMissingDays Tests

    func testGetMissingDaysReturnsAllDaysWhenNoCacheProvider() async {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        let coordinator = DataCoordinator(appState: appState, cacheProvider: nil)

        let missingDays = await coordinator.getMissingDays()
        // Should return all visible heatmap days (13 weeks = 91 days)
        XCTAssertGreaterThan(missingDays.count, 80)
    }

    func testGetMissingDaysReturnsOnlyMissingDays() async {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        let cache = MockPerDayCacheProvider(accounts: appState.session.accounts)

        // Cache some days
        let today = DataCoordinator.dateString(from: Date())
        let yesterday = DataCoordinator.dateString(from: Date().addingTimeInterval(-86400))
        cache.setDayActivities([], accountId: "gl1", date: today)
        cache.setDayActivities([], accountId: "gl1", date: yesterday)

        let coordinator = DataCoordinator(appState: appState, cacheProvider: cache)

        let missingDays = await coordinator.getMissingDays()

        // Should not include today and yesterday
        XCTAssertFalse(missingDays.contains(today))
        XCTAssertFalse(missingDays.contains(yesterday))
    }

    func testGetMissingDaysReturnsSorted() async {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        let coordinator = DataCoordinator(appState: appState, cacheProvider: nil)

        let missingDays = await coordinator.getMissingDays()

        // Should be sorted from oldest to newest
        let sorted = missingDays.sorted()
        XCTAssertEqual(missingDays, sorted)
    }

    // MARK: - loadDay Tests

    func testLoadDayFromCache() async {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        let cache = MockPerDayCacheProvider(accounts: appState.session.accounts)
        let activity = UnifiedActivity(
            id: "a1", provider: .gitlab, accountId: "gl1",
            sourceId: "s1", type: .commit, timestamp: Date()
        )
        cache.setDayActivities([activity], accountId: "gl1", date: "2026-01-31")

        let coordinator = DataCoordinator(appState: appState, cacheProvider: cache)
        await coordinator.loadFromCache()

        // Manually load the day
        await coordinator.loadDayByString("2026-01-31")

        XCTAssertTrue(appState.session.isDayLoaded("2026-01-31"))
    }

    func testLoadDaySkipsIfAlreadyLoaded() async {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        let cache = MockPerDayCacheProvider(accounts: appState.session.accounts)
        let activity = UnifiedActivity(
            id: "a1", provider: .gitlab, accountId: "gl1",
            sourceId: "s1", type: .commit, timestamp: Date()
        )
        cache.setDayActivities([activity], accountId: "gl1", date: "2026-01-31")

        let coordinator = DataCoordinator(appState: appState, cacheProvider: cache)
        await coordinator.loadFromCache()

        // After loadFromCache, the day should already be loaded because
        // it's within the visible heatmap range and has cached data
        let isLoadedInitially = appState.session.isDayLoaded("2026-01-31")

        // Second call should be idempotent
        await coordinator.loadDayByString("2026-01-31")

        // Should still be marked as loaded
        XCTAssertTrue(appState.session.isDayLoaded("2026-01-31"))

        // The key point: calling again doesn't break anything
        await coordinator.loadDayByString("2026-01-31")
        XCTAssertTrue(appState.session.isDayLoaded("2026-01-31"))
    }

    func testLoadDayFetchesFromNetworkWhenNotCached() async {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        let cache = MockPerDayCacheProvider(accounts: appState.session.accounts)
        let refresher = MockPerDayRefreshProvider()
        let activity = UnifiedActivity(
            id: "net1", provider: .gitlab, accountId: "gl1",
            sourceId: "s1", type: .commit, timestamp: Date()
        )
        refresher.setActivitiesForDate([activity], date: "2026-01-31")

        let coordinator = DataCoordinator(
            appState: appState,
            cacheProvider: cache,
            refreshProvider: refresher
        )

        await coordinator.loadDayByString("2026-01-31")

        XCTAssertTrue(appState.session.isDayLoaded("2026-01-31"))
        XCTAssertTrue(refresher.fetchedDates.contains("2026-01-31"))
    }

    // MARK: - loadFromCache Tests

    func testLoadFromCacheUsesPerDayCache() async {
        let appState = AppState()

        let accounts = [Account(id: "gl1", provider: .gitlab, displayName: "GitLab")]
        let cache = MockPerDayCacheProvider(accounts: accounts)

        // Set up some cached data
        let today = DataCoordinator.dateString(from: Date())
        let activity = UnifiedActivity(
            id: "a1", provider: .gitlab, accountId: "gl1",
            sourceId: "s1", type: .commit, timestamp: Date()
        )
        cache.setDayActivities([activity], accountId: "gl1", date: today)

        let coordinator = DataCoordinator(appState: appState, cacheProvider: cache)

        await coordinator.loadFromCache()

        XCTAssertTrue(appState.hasLoadedFromCache)
        XCTAssertEqual(appState.session.accounts.count, 1)
        // Day activity counts should be populated from day index
        XCTAssertEqual(appState.session.dayActivityCounts[today], 1)
    }

    // MARK: - refreshInBackground Tests

    func testRefreshUsesPerDayProvider() async {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        let cache = MockPerDayCacheProvider(accounts: appState.session.accounts)
        let refresher = MockPerDayRefreshProvider()

        let today = DataCoordinator.dateString(from: Date())
        let activity = UnifiedActivity(
            id: "a1", provider: .gitlab, accountId: "gl1",
            sourceId: "s1", type: .commit, timestamp: Date()
        )
        refresher.setActivitiesForDate([activity], date: today)

        let coordinator = DataCoordinator(
            appState: appState,
            cacheProvider: cache,
            refreshProvider: refresher
        )

        await coordinator.refreshInBackground()

        // Should have fetched today at minimum
        XCTAssertTrue(refresher.fetchedDates.contains(today))
        XCTAssertFalse(coordinator.isRefreshing)
        XCTAssertNotNil(appState.session.lastRefreshed)
    }

    func testRefreshAlwaysIncludesToday() async {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        // Set up cache with all days including today
        let cache = MockPerDayCacheProvider(accounts: appState.session.accounts)
        let today = DataCoordinator.dateString(from: Date())
        cache.setDayActivities([], accountId: "gl1", date: today)

        // Set up refresher
        let refresher = MockPerDayRefreshProvider()
        refresher.setActivitiesForDate([
            UnifiedActivity(id: "new1", provider: .gitlab, accountId: "gl1",
                          sourceId: "s1", type: .commit, timestamp: Date())
        ], date: today)

        let coordinator = DataCoordinator(
            appState: appState,
            cacheProvider: cache,
            refreshProvider: refresher
        )

        await coordinator.refreshInBackground()

        // Today should always be refetched
        XCTAssertTrue(refresher.fetchedDates.contains(today))
    }

    // MARK: - Date Helper Tests

    func testDateStringFromDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!

        let dateString = DataCoordinator.dateString(from: date)
        XCTAssertEqual(dateString, "2026-01-31")
    }

    func testDateFromString() {
        let date = DataCoordinator.date(from: "2026-01-31")
        XCTAssertNotNil(date)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day], from: date!)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 31)
    }

    func testDateFromStringInvalid() {
        XCTAssertNil(DataCoordinator.date(from: "invalid"))
        XCTAssertNil(DataCoordinator.date(from: ""))
    }
}
