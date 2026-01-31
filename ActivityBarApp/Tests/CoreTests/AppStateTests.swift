import XCTest
@testable import Core

@MainActor
final class AppStateTests: XCTestCase {

    // MARK: - Session Tests

    func testSessionInitialState() {
        let session = Session()

        XCTAssertTrue(session.accounts.isEmpty)
        XCTAssertTrue(session.activitiesByAccount.isEmpty)
        XCTAssertTrue(session.heatmapBuckets.isEmpty)
        XCTAssertNil(session.selectedRange)
        XCTAssertNil(session.lastRefreshed)
        XCTAssertFalse(session.isRefreshing)
        XCTAssertFalse(session.isOffline)  // ACTIVITY-023: Initial state is online
    }

    func testSessionEnabledAccounts() {
        let session = Session(accounts: [
            Account(id: "1", provider: .gitlab, displayName: "GitLab", isEnabled: true),
            Account(id: "2", provider: .gitlab, displayName: "GitLab", isEnabled: false),
            Account(id: "3", provider: .azureDevops, displayName: "Azure", isEnabled: true)
        ])

        XCTAssertEqual(session.accounts.count, 3)
        XCTAssertEqual(session.enabledAccounts.count, 2)
        XCTAssertTrue(session.enabledAccounts.allSatisfy { $0.isEnabled })
    }

    func testSessionAllActivities() {
        let activity1 = UnifiedActivity(
            id: "a1", provider: .gitlab, accountId: "gl1",
            sourceId: "s1", type: .commit, timestamp: Date()
        )
        let activity2 = UnifiedActivity(
            id: "a2", provider: .gitlab, accountId: "gl1",
            sourceId: "s2", type: .pullRequest, timestamp: Date()
        )

        let session = Session(
            accounts: [
                Account(id: "gl1", provider: .gitlab, displayName: "GitLab", isEnabled: true),
                Account(id: "gl1", provider: .gitlab, displayName: "GitLab", isEnabled: true)
            ],
            activitiesByAccount: [
                "gh1": [activity1],
                "gl1": [activity2]
            ]
        )

        XCTAssertEqual(session.allActivities.count, 2)
    }

    func testSessionAllActivitiesExcludesDisabledAccounts() {
        let activity1 = UnifiedActivity(
            id: "a1", provider: .gitlab, accountId: "gl1",
            sourceId: "s1", type: .commit, timestamp: Date()
        )
        let activity2 = UnifiedActivity(
            id: "a2", provider: .gitlab, accountId: "gl1",
            sourceId: "s2", type: .pullRequest, timestamp: Date()
        )

        let session = Session(
            accounts: [
                Account(id: "gl1", provider: .gitlab, displayName: "GitLab", isEnabled: true),
                Account(id: "gl1", provider: .gitlab, displayName: "GitLab", isEnabled: false)
            ],
            activitiesByAccount: [
                "gh1": [activity1],
                "gl1": [activity2]
            ]
        )

        XCTAssertEqual(session.allActivities.count, 1)
        XCTAssertEqual(session.allActivities.first?.id, "a1")
    }

    func testSessionActivitiesInRange() {
        let now = Date()
        let yesterday = now.addingTimeInterval(-86400)
        let twoDaysAgo = now.addingTimeInterval(-172800)

        let activityToday = UnifiedActivity(
            id: "a1", provider: .gitlab, accountId: "gl1",
            sourceId: "s1", type: .commit, timestamp: now
        )
        let activityYesterday = UnifiedActivity(
            id: "a2", provider: .gitlab, accountId: "gl1",
            sourceId: "s2", type: .commit, timestamp: yesterday
        )
        let activityOld = UnifiedActivity(
            id: "a3", provider: .gitlab, accountId: "gl1",
            sourceId: "s3", type: .commit, timestamp: twoDaysAgo
        )

        let session = Session(
            accounts: [Account(id: "gl1", provider: .gitlab, displayName: "GitLab")],
            activitiesByAccount: ["gh1": [activityToday, activityYesterday, activityOld]]
        )

        let range = DateRange(start: yesterday, end: now.addingTimeInterval(1))
        let filtered = session.activitiesInRange(range)

        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.id == "a1" })
        XCTAssertTrue(filtered.contains { $0.id == "a2" })
    }

    func testSessionActivitiesSortedDescending() {
        let now = Date()
        let earlier = now.addingTimeInterval(-3600)
        let earliest = now.addingTimeInterval(-7200)

        let activity1 = UnifiedActivity(
            id: "a1", provider: .gitlab, accountId: "gl1",
            sourceId: "s1", type: .commit, timestamp: earliest
        )
        let activity2 = UnifiedActivity(
            id: "a2", provider: .gitlab, accountId: "gl1",
            sourceId: "s2", type: .commit, timestamp: now
        )
        let activity3 = UnifiedActivity(
            id: "a3", provider: .gitlab, accountId: "gl1",
            sourceId: "s3", type: .commit, timestamp: earlier
        )

        let session = Session(
            accounts: [Account(id: "gl1", provider: .gitlab, displayName: "GitLab")],
            activitiesByAccount: ["gh1": [activity1, activity2, activity3]]
        )

        let range = DateRange(start: earliest.addingTimeInterval(-1), end: now.addingTimeInterval(1))
        let sorted = session.activitiesInRange(range)

        XCTAssertEqual(sorted.map { $0.id }, ["a2", "a3", "a1"])
    }

    func testSessionHeatmapCount() {
        let session = Session(heatmapBuckets: [
            HeatMapBucket(date: "2026-01-19", count: 10),
            HeatMapBucket(date: "2026-01-18", count: 5)
        ])

        // Create dates in UTC
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let jan19 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 19))!
        let jan18 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 18))!
        let jan17 = calendar.date(from: DateComponents(year: 2026, month: 1, day: 17))!

        XCTAssertEqual(session.heatmapCount(for: jan19), 10)
        XCTAssertEqual(session.heatmapCount(for: jan18), 5)
        XCTAssertEqual(session.heatmapCount(for: jan17), 0)
    }

    func testDateRangeSingleDay() {
        let date = Date()
        let range = DateRange.singleDay(date)

        let calendar = Calendar.current
        XCTAssertEqual(calendar.startOfDay(for: range.start), calendar.startOfDay(for: date))
        XCTAssertTrue(range.end > range.start)

        // End should be start of next day
        let dayDiff = calendar.dateComponents([.day], from: range.start, to: range.end).day
        XCTAssertEqual(dayDiff, 1)
    }

    func testDateRangeToday() {
        let today = DateRange.today
        let calendar = Calendar.current

        XCTAssertEqual(calendar.startOfDay(for: today.start), calendar.startOfDay(for: Date()))
    }

    func testDateStringFormat() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 15))!
        let dateString = Session.dateString(from: date)

        XCTAssertEqual(dateString, "2026-01-15")
    }

    // MARK: - AppState Tests

    func testAppStateInitialState() {
        let appState = AppState()

        XCTAssertNil(appState.lastError)
        XCTAssertFalse(appState.hasLoadedFromCache)
        XCTAssertNotNil(appState.session)
    }

    func testAppStateAddAccount() {
        let appState = AppState()
        let account = Account(id: "gl1", provider: .gitlab, displayName: "GitLab")

        appState.addAccount(account)

        XCTAssertEqual(appState.session.accounts.count, 1)
        XCTAssertEqual(appState.session.accounts.first?.id, "gh1")
    }

    func testAppStateRemoveAccount() {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab"),
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        appState.removeAccount(id: "gl1")

        XCTAssertEqual(appState.session.accounts.count, 1)
        XCTAssertEqual(appState.session.accounts.first?.id, "gl1")
    }

    func testAppStateRemoveAccountClearsActivities() {
        let appState = AppState(session: Session(
            accounts: [Account(id: "gl1", provider: .gitlab, displayName: "GitLab")],
            activitiesByAccount: ["gh1": [
                UnifiedActivity(id: "a1", provider: .gitlab, accountId: "gl1",
                              sourceId: "s1", type: .commit, timestamp: Date())
            ]]
        ))

        appState.removeAccount(id: "gl1")

        XCTAssertNil(appState.session.activitiesByAccount["gh1"])
    }

    func testAppStateToggleAccount() {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab", isEnabled: true)
        ]))

        XCTAssertTrue(appState.session.accounts.first!.isEnabled)

        appState.toggleAccount(id: "gl1")

        XCTAssertFalse(appState.session.accounts.first!.isEnabled)

        appState.toggleAccount(id: "gl1")

        XCTAssertTrue(appState.session.accounts.first!.isEnabled)
    }

    func testAppStateUpdateActivities() {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        let activities = [
            UnifiedActivity(id: "a1", provider: .gitlab, accountId: "gl1",
                          sourceId: "s1", type: .commit, timestamp: Date()),
            UnifiedActivity(id: "a2", provider: .gitlab, accountId: "gl1",
                          sourceId: "s2", type: .pullRequest, timestamp: Date())
        ]

        appState.updateActivities(activities, for: "gh1")

        XCTAssertEqual(appState.session.activitiesByAccount["gh1"]?.count, 2)
    }

    func testAppStateUpdateHeatmap() {
        let appState = AppState()
        let buckets = [
            HeatMapBucket(date: "2026-01-19", count: 10),
            HeatMapBucket(date: "2026-01-18", count: 5)
        ]

        appState.updateHeatmap(buckets)

        XCTAssertEqual(appState.session.heatmapBuckets.count, 2)
    }

    func testAppStateMergeHeatmap() {
        let appState = AppState()

        let buckets1 = [
            HeatMapBucket(date: "2026-01-19", count: 5, breakdown: [.gitlab: 5]),
            HeatMapBucket(date: "2026-01-18", count: 3, breakdown: [.gitlab: 3])
        ]
        let buckets2 = [
            HeatMapBucket(date: "2026-01-19", count: 3, breakdown: [.gitlab: 3]),
            HeatMapBucket(date: "2026-01-17", count: 2, breakdown: [.gitlab: 2])
        ]

        appState.mergeHeatmap(from: [buckets1, buckets2])

        XCTAssertEqual(appState.session.heatmapBuckets.count, 3)

        let jan19 = appState.session.heatmapBuckets.first { $0.date == "2026-01-19" }
        XCTAssertEqual(jan19?.count, 8)
        XCTAssertEqual(jan19?.breakdown?[.gitlab], 5)
        XCTAssertEqual(jan19?.breakdown?[.gitlab], 3)
    }

    func testAppStateSelectDate() {
        let appState = AppState()
        let date = Date().addingTimeInterval(-86400) // Yesterday

        appState.selectDate(date)

        XCTAssertEqual(appState.session.selectedDate, date)
        XCTAssertNil(appState.session.selectedRange)
    }

    func testAppStateSelectRange() {
        let appState = AppState()
        let range = DateRange(start: Date().addingTimeInterval(-172800), end: Date())

        appState.selectRange(range)

        XCTAssertEqual(appState.session.selectedRange, range)
    }

    func testAppStateRefreshCycle() {
        let appState = AppState()

        XCTAssertFalse(appState.session.isRefreshing)
        XCTAssertNil(appState.session.lastRefreshed)

        appState.startRefresh()

        XCTAssertTrue(appState.session.isRefreshing)
        XCTAssertNil(appState.lastError)

        appState.finishRefresh()

        XCTAssertFalse(appState.session.isRefreshing)
        XCTAssertNotNil(appState.session.lastRefreshed)
        XCTAssertNil(appState.lastError)
    }

    func testAppStateRefreshWithError() {
        let appState = AppState()

        appState.startRefresh()
        appState.finishRefresh(error: "Network unavailable")

        XCTAssertFalse(appState.session.isRefreshing)
        XCTAssertNil(appState.session.lastRefreshed) // Not set on error
        XCTAssertEqual(appState.lastError, "Network unavailable")
        XCTAssertTrue(appState.session.isOffline)  // ACTIVITY-023: Offline on error
    }

    // MARK: - ACTIVITY-023: Offline Mode Tests

    func testAppStateOfflineModeOnRefreshError() {
        let appState = AppState()

        XCTAssertFalse(appState.session.isOffline)

        appState.startRefresh()
        appState.finishRefresh(error: "Network error")

        XCTAssertTrue(appState.session.isOffline)
    }

    func testAppStateOnlineAfterSuccessfulRefresh() {
        let appState = AppState()

        // Simulate being offline
        appState.startRefresh()
        appState.finishRefresh(error: "Network error")
        XCTAssertTrue(appState.session.isOffline)

        // Successful refresh brings us back online
        appState.startRefresh()
        appState.finishRefresh()

        XCTAssertFalse(appState.session.isOffline)
        XCTAssertNotNil(appState.session.lastRefreshed)
    }

    func testAppStateSetOffline() {
        let appState = AppState()

        XCTAssertFalse(appState.session.isOffline)

        appState.setOffline(true)
        XCTAssertTrue(appState.session.isOffline)

        appState.setOffline(false)
        XCTAssertFalse(appState.session.isOffline)
    }

    func testSessionInitWithOfflineState() {
        let session = Session(isOffline: true)

        XCTAssertTrue(session.isOffline)
    }

    func testAppStateMarkCacheLoaded() {
        let appState = AppState()

        XCTAssertFalse(appState.hasLoadedFromCache)

        appState.markCacheLoaded()

        XCTAssertTrue(appState.hasLoadedFromCache)
    }

    func testAppStateClearError() {
        let appState = AppState()
        appState.startRefresh()
        appState.finishRefresh(error: "Some error")

        XCTAssertNotNil(appState.lastError)

        appState.clearError()

        XCTAssertNil(appState.lastError)
    }

    func testAppStateUpdateAccounts() {
        let appState = AppState()
        let accounts = [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab"),
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]

        appState.updateAccounts(accounts)

        XCTAssertEqual(appState.session.accounts.count, 2)
    }

    // MARK: - Per-Day State Tests

    func testSessionLoadedDaysInitiallyEmpty() {
        let session = Session()
        XCTAssertTrue(session.loadedDays.isEmpty)
    }

    func testSessionDayActivityCountsInitiallyEmpty() {
        let session = Session()
        XCTAssertTrue(session.dayActivityCounts.isEmpty)
    }

    func testSessionLoadingDaysInitiallyEmpty() {
        let session = Session()
        XCTAssertTrue(session.loadingDays.isEmpty)
    }

    func testSessionInitWithPerDayState() {
        let session = Session(
            loadedDays: ["2026-01-30", "2026-01-31"],
            dayActivityCounts: ["2026-01-30": 5, "2026-01-31": 10],
            loadingDays: ["2026-01-29"]
        )

        XCTAssertEqual(session.loadedDays.count, 2)
        XCTAssertEqual(session.dayActivityCounts.count, 2)
        XCTAssertEqual(session.loadingDays.count, 1)
    }

    func testSessionIsDayLoaded() {
        let session = Session(loadedDays: ["2026-01-31"])

        XCTAssertTrue(session.isDayLoaded("2026-01-31"))
        XCTAssertFalse(session.isDayLoaded("2026-01-30"))
    }

    func testSessionIsDayLoading() {
        let session = Session(loadingDays: ["2026-01-31"])

        XCTAssertTrue(session.isDayLoading("2026-01-31"))
        XCTAssertFalse(session.isDayLoading("2026-01-30"))
    }

    func testAppStateMarkDayLoading() {
        let appState = AppState()

        XCTAssertFalse(appState.session.isDayLoading("2026-01-31"))

        appState.markDayLoading("2026-01-31")

        XCTAssertTrue(appState.session.isDayLoading("2026-01-31"))
    }

    func testAppStateMarkDayLoaded() {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        // Mark as loading first
        appState.markDayLoading("2026-01-31")
        XCTAssertTrue(appState.session.isDayLoading("2026-01-31"))
        XCTAssertFalse(appState.session.isDayLoaded("2026-01-31"))

        // Create activities for the day
        let activities = [
            UnifiedActivity(
                id: "a1", provider: .gitlab, accountId: "gl1",
                sourceId: "s1", type: .commit, timestamp: Date()
            ),
            UnifiedActivity(
                id: "a2", provider: .gitlab, accountId: "gl1",
                sourceId: "s2", type: .pullRequest, timestamp: Date()
            )
        ]

        // Mark as loaded
        appState.markDayLoaded("2026-01-31", activities: activities)

        // Should be loaded, not loading
        XCTAssertTrue(appState.session.isDayLoaded("2026-01-31"))
        XCTAssertFalse(appState.session.isDayLoading("2026-01-31"))

        // Activities should be added to session
        XCTAssertEqual(appState.session.activitiesByAccount["gl1"]?.count, 2)
    }

    func testAppStateMarkDayLoadedMergesActivities() {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        // Load first day
        let day1Activities = [
            UnifiedActivity(
                id: "a1", provider: .gitlab, accountId: "gl1",
                sourceId: "s1", type: .commit, timestamp: Date().addingTimeInterval(-86400)
            )
        ]
        appState.markDayLoaded("2026-01-30", activities: day1Activities)

        // Load second day
        let day2Activities = [
            UnifiedActivity(
                id: "a2", provider: .gitlab, accountId: "gl1",
                sourceId: "s2", type: .pullRequest, timestamp: Date()
            )
        ]
        appState.markDayLoaded("2026-01-31", activities: day2Activities)

        // Both days should be loaded
        XCTAssertTrue(appState.session.isDayLoaded("2026-01-30"))
        XCTAssertTrue(appState.session.isDayLoaded("2026-01-31"))

        // All activities should be merged
        XCTAssertEqual(appState.session.activitiesByAccount["gl1"]?.count, 2)
    }

    func testAppStateMarkDayLoadedReplacesOldActivities() {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        // Load day with old activities
        let oldActivities = [
            UnifiedActivity(
                id: "old1", provider: .gitlab, accountId: "gl1",
                sourceId: "s1", type: .commit, timestamp: Date()
            )
        ]
        appState.markDayLoaded("2026-01-31", activities: oldActivities)
        XCTAssertEqual(appState.session.activitiesByAccount["gl1"]?.first?.id, "old1")

        // Reload same day with new activities
        let newActivities = [
            UnifiedActivity(
                id: "new1", provider: .gitlab, accountId: "gl1",
                sourceId: "s2", type: .pullRequest, timestamp: Date()
            ),
            UnifiedActivity(
                id: "new2", provider: .gitlab, accountId: "gl1",
                sourceId: "s3", type: .issue, timestamp: Date()
            )
        ]
        appState.markDayLoaded("2026-01-31", activities: newActivities)

        // Should have new activities, not old
        XCTAssertEqual(appState.session.activitiesByAccount["gl1"]?.count, 2)
        XCTAssertFalse(appState.session.activitiesByAccount["gl1"]?.contains { $0.id == "old1" } ?? true)
        XCTAssertTrue(appState.session.activitiesByAccount["gl1"]?.contains { $0.id == "new1" } ?? false)
    }

    func testAppStateUpdateDayActivityCounts() {
        let appState = AppState()

        let counts: [String: Int] = [
            "2026-01-29": 5,
            "2026-01-30": 10,
            "2026-01-31": 3
        ]

        appState.updateDayActivityCounts(counts)

        XCTAssertEqual(appState.session.dayActivityCounts.count, 3)
        XCTAssertEqual(appState.session.dayActivityCounts["2026-01-30"], 10)

        // Should also update heatmap buckets
        XCTAssertEqual(appState.session.heatmapBuckets.count, 3)
        let jan30Bucket = appState.session.heatmapBuckets.first { $0.date == "2026-01-30" }
        XCTAssertEqual(jan30Bucket?.count, 10)
    }

    func testAppStateClearLoadedDays() {
        let appState = AppState(session: Session(
            accounts: [Account(id: "gl1", provider: .gitlab, displayName: "GitLab")],
            activitiesByAccount: ["gl1": [
                UnifiedActivity(id: "a1", provider: .gitlab, accountId: "gl1",
                              sourceId: "s1", type: .commit, timestamp: Date())
            ]],
            loadedDays: ["2026-01-30", "2026-01-31"],
            loadingDays: ["2026-01-29"]
        ))

        XCTAssertFalse(appState.session.loadedDays.isEmpty)
        XCTAssertFalse(appState.session.loadingDays.isEmpty)
        XCTAssertFalse(appState.session.activitiesByAccount.isEmpty)

        appState.clearLoadedDays()

        XCTAssertTrue(appState.session.loadedDays.isEmpty)
        XCTAssertTrue(appState.session.loadingDays.isEmpty)
        XCTAssertTrue(appState.session.activitiesByAccount.isEmpty)
    }
}

// MARK: - Account Filtering Tests

@MainActor
final class AccountFilteringTests: XCTestCase {

    // MARK: - Event Type Filtering Tests

    func testAccountEventTypeFilteringAllEnabled() {
        let account = Account(
            id: "gl1", provider: .gitlab, displayName: "GitLab",
            enabledEventTypes: nil  // nil means all enabled
        )

        XCTAssertTrue(account.isEventTypeEnabled(.commit))
        XCTAssertTrue(account.isEventTypeEnabled(.pullRequest))
        XCTAssertTrue(account.isEventTypeEnabled(.issue))
        XCTAssertTrue(account.isEventTypeEnabled(.meeting))
    }

    func testAccountEventTypeFilteringSpecificTypes() {
        let account = Account(
            id: "gl1", provider: .gitlab, displayName: "GitLab",
            enabledEventTypes: [.commit, .pullRequest]
        )

        XCTAssertTrue(account.isEventTypeEnabled(.commit))
        XCTAssertTrue(account.isEventTypeEnabled(.pullRequest))
        XCTAssertFalse(account.isEventTypeEnabled(.issue))
        XCTAssertFalse(account.isEventTypeEnabled(.meeting))
    }

    func testAccountEventTypeFilteringEmptySet() {
        let account = Account(
            id: "gl1", provider: .gitlab, displayName: "GitLab",
            enabledEventTypes: []  // Empty set means none enabled
        )

        XCTAssertFalse(account.isEventTypeEnabled(.commit))
        XCTAssertFalse(account.isEventTypeEnabled(.pullRequest))
    }

    func testAppStateUpdateEnabledEventTypes() {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        ]))

        XCTAssertNil(appState.session.accounts.first?.enabledEventTypes)

        appState.updateEnabledEventTypes(for: "gl1", types: [.commit, .issue])

        XCTAssertEqual(appState.session.accounts.first?.enabledEventTypes, [.commit, .issue])
    }

    func testAppStateUpdateEnabledEventTypesToNil() {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab",
                   enabledEventTypes: [.commit])
        ]))

        XCTAssertNotNil(appState.session.accounts.first?.enabledEventTypes)

        appState.updateEnabledEventTypes(for: "gl1", types: nil)

        XCTAssertNil(appState.session.accounts.first?.enabledEventTypes)
    }

    // MARK: - Calendar Filtering Tests (Google Calendar only)

    func testAccountCalendarFilteringAllEnabled() {
        let account = Account(
            id: "gc1", provider: .googleCalendar, displayName: "Google Calendar",
            calendarIds: nil  // nil means all calendars
        )

        XCTAssertTrue(account.isCalendarEnabled("calendar1"))
        XCTAssertTrue(account.isCalendarEnabled("calendar2"))
        XCTAssertTrue(account.isCalendarEnabled(nil))
    }

    func testAccountCalendarFilteringSpecificCalendars() {
        let account = Account(
            id: "gc1", provider: .googleCalendar, displayName: "Google Calendar",
            calendarIds: ["work", "personal"]
        )

        XCTAssertTrue(account.isCalendarEnabled("work"))
        XCTAssertTrue(account.isCalendarEnabled("personal"))
        XCTAssertFalse(account.isCalendarEnabled("other"))
    }

    func testAccountCalendarFilteringEmptyArray() {
        let account = Account(
            id: "gc1", provider: .googleCalendar, displayName: "Google Calendar",
            calendarIds: []  // Empty array means all enabled
        )

        XCTAssertTrue(account.isCalendarEnabled("any"))
    }

    func testAccountSupportsCalendarFiltering() {
        let googleAccount = Account(id: "gc1", provider: .googleCalendar, displayName: "Google")
        let gitlabAccount = Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        let azureAccount = Account(id: "az1", provider: .azureDevops, displayName: "Azure")

        XCTAssertTrue(googleAccount.supportsCalendarFiltering)
        XCTAssertFalse(gitlabAccount.supportsCalendarFiltering)
        XCTAssertFalse(azureAccount.supportsCalendarFiltering)
    }

    func testAppStateUpdateCalendarIds() {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gc1", provider: .googleCalendar, displayName: "Google Calendar")
        ]))

        XCTAssertNil(appState.session.accounts.first?.calendarIds)

        appState.updateCalendarIds(for: "gc1", calendarIds: ["work", "personal"])

        XCTAssertEqual(appState.session.accounts.first?.calendarIds, ["work", "personal"])
    }

    // MARK: - Show Only My Events Tests

    func testAccountShowOnlyMyEventsDefaultFalse() {
        let account = Account(id: "gl1", provider: .gitlab, displayName: "GitLab")

        XCTAssertFalse(account.showOnlyMyEvents)
    }

    func testAccountIsMyEventWhenFilterDisabled() {
        let account = Account(
            id: "gl1", provider: .gitlab, displayName: "GitLab",
            username: "myuser",
            showOnlyMyEvents: false
        )

        // When filter disabled, all events pass
        XCTAssertTrue(account.isMyEvent(author: "otheruser"))
        XCTAssertTrue(account.isMyEvent(author: "myuser"))
        XCTAssertTrue(account.isMyEvent(author: nil))
    }

    func testAccountIsMyEventWhenFilterEnabled() {
        let account = Account(
            id: "gl1", provider: .gitlab, displayName: "GitLab",
            username: "myuser",
            showOnlyMyEvents: true
        )

        // Only events by me should pass
        XCTAssertTrue(account.isMyEvent(author: "myuser"))
        XCTAssertTrue(account.isMyEvent(author: "MYUSER"))  // Case insensitive
        XCTAssertTrue(account.isMyEvent(author: "MyUser"))  // Case insensitive
        XCTAssertFalse(account.isMyEvent(author: "otheruser"))
    }

    func testAccountIsMyEventWithNoUsername() {
        let account = Account(
            id: "gl1", provider: .gitlab, displayName: "GitLab",
            username: nil,  // No username set
            showOnlyMyEvents: true
        )

        // When no username set, all events pass (can't filter)
        XCTAssertTrue(account.isMyEvent(author: "anyuser"))
    }

    func testAccountIsMyEventWithNilAuthor() {
        let account = Account(
            id: "gl1", provider: .gitlab, displayName: "GitLab",
            username: "myuser",
            showOnlyMyEvents: true
        )

        // When author is nil, event passes (don't filter unknown authors)
        XCTAssertTrue(account.isMyEvent(author: nil))
        XCTAssertTrue(account.isMyEvent(author: ""))
    }

    func testAppStateToggleShowOnlyMyEvents() {
        let appState = AppState(session: Session(accounts: [
            Account(id: "gl1", provider: .gitlab, displayName: "GitLab", username: "user")
        ]))

        XCTAssertFalse(appState.session.accounts.first!.showOnlyMyEvents)

        appState.toggleShowOnlyMyEvents(for: "gl1")

        XCTAssertTrue(appState.session.accounts.first!.showOnlyMyEvents)

        appState.toggleShowOnlyMyEvents(for: "gl1")

        XCTAssertFalse(appState.session.accounts.first!.showOnlyMyEvents)
    }

    // MARK: - Relevant Event Types Tests

    func testGitLabRelevantEventTypes() {
        let account = Account(id: "gl1", provider: .gitlab, displayName: "GitLab")
        let relevant = account.relevantEventTypes

        XCTAssertTrue(relevant.contains(.commit))
        XCTAssertTrue(relevant.contains(.pullRequest))
        XCTAssertTrue(relevant.contains(.issue))
        XCTAssertTrue(relevant.contains(.issueComment))
        XCTAssertTrue(relevant.contains(.codeReview))
        XCTAssertTrue(relevant.contains(.release))
        XCTAssertTrue(relevant.contains(.wiki))
        XCTAssertFalse(relevant.contains(.meeting))
        XCTAssertFalse(relevant.contains(.workItem))
    }

    func testAzureDevOpsRelevantEventTypes() {
        let account = Account(id: "az1", provider: .azureDevops, displayName: "Azure")
        let relevant = account.relevantEventTypes

        XCTAssertTrue(relevant.contains(.commit))
        XCTAssertTrue(relevant.contains(.pullRequest))
        XCTAssertTrue(relevant.contains(.workItem))
        XCTAssertFalse(relevant.contains(.issue))
        XCTAssertFalse(relevant.contains(.meeting))
    }

    func testGoogleCalendarRelevantEventTypes() {
        let account = Account(id: "gc1", provider: .googleCalendar, displayName: "Google")
        let relevant = account.relevantEventTypes

        XCTAssertTrue(relevant.contains(.meeting))
        XCTAssertEqual(relevant.count, 1)
    }
}
