import XCTest
@testable import Core

@MainActor
final class ActivityListViewTests: XCTestCase {

    // MARK: - UnifiedActivity Tests

    func testUnifiedActivityUsesActivityDiscoverySchema() {
        // UnifiedActivity should have exactly the fields from activity-discovery
        let activity = UnifiedActivity(
            id: "test-1",
            provider: .gitlab,
            accountId: "gl-account",
            sourceId: "commit-123",
            type: .commit,
            timestamp: Date(),
            title: "Fix bug",
            summary: "Fixed the login bug",
            participants: ["alice"],
            url: URL(string: "https://gitlab.com/org/repo/commit/123")
        )

        // Verify required fields
        XCTAssertEqual(activity.id, "test-1")
        XCTAssertEqual(activity.provider, .gitlab)
        XCTAssertEqual(activity.accountId, "gh-account")
        XCTAssertEqual(activity.sourceId, "commit-123")
        XCTAssertEqual(activity.type, .commit)

        // Verify optional fields
        XCTAssertEqual(activity.title, "Fix bug")
        XCTAssertEqual(activity.summary, "Fixed the login bug")
        XCTAssertEqual(activity.participants, ["alice"])
        XCTAssertNotNil(activity.url)
    }

    func testUnifiedActivityOptionalFieldsAreOptional() {
        let activity = UnifiedActivity(
            id: "test-1",
            provider: .gitlab,
            accountId: "gl-account",
            sourceId: "commit-123",
            type: .commit,
            timestamp: Date()
        )

        XCTAssertNil(activity.title)
        XCTAssertNil(activity.summary)
        XCTAssertNil(activity.participants)
        XCTAssertNil(activity.url)
    }

    func testUnifiedActivityFieldCount() {
        // UnifiedActivity should have exactly 10 fields
        let activity = UnifiedActivity(
            id: "test",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: Date()
        )

        let mirror = Mirror(reflecting: activity)
        let propertyCount = mirror.children.count

        // Fields: id, provider, accountId, sourceId, type, timestamp, title, summary, participants, url
        // Extended in ACTIVITY-056: authorAvatarURL, labels, commentCount, isDraft, sourceRef, targetRef
        XCTAssertEqual(propertyCount, 16, "UnifiedActivity should have exactly 16 fields (10 core + 6 UI extensions)")
    }

    // MARK: - ActivityType Tests

    func testActivityTypeCoversAllProviderTypes() {
        let allTypes: [ActivityType] = [
            .commit, .pullRequest, .issue, .issueComment, .codeReview,
            .meeting, .workItem, .deployment, .release, .wiki, .other
        ]

        // Ensure all types exist
        XCTAssertEqual(allTypes.count, 11)

        // Verify raw values match activity-discovery
        XCTAssertEqual(ActivityType.pullRequest.rawValue, "pull_request")
        XCTAssertEqual(ActivityType.issueComment.rawValue, "issue_comment")
        XCTAssertEqual(ActivityType.codeReview.rawValue, "code_review")
        XCTAssertEqual(ActivityType.workItem.rawValue, "work_item")
    }

    // MARK: - Sorting Tests

    func testActivitiesSortedByTimestampDescending() {
        let session = Session()
        let account = Account(id: "test", provider: .gitlab, displayName: "Test")
        session.accounts = [account]

        let now = Date()
        let activities = [
            createActivity(id: "1", timestamp: now.addingTimeInterval(-3600)), // 1 hour ago
            createActivity(id: "2", timestamp: now), // now
            createActivity(id: "3", timestamp: now.addingTimeInterval(-7200)) // 2 hours ago
        ]
        session.activitiesByAccount["test"] = activities

        let sorted = session.allActivities.sorted { $0.timestamp > $1.timestamp }

        XCTAssertEqual(sorted[0].id, "2") // Most recent first
        XCTAssertEqual(sorted[1].id, "1")
        XCTAssertEqual(sorted[2].id, "3") // Oldest last
    }

    // MARK: - Grouping Tests

    func testActivitiesCanBeGroupedByProvider() {
        let activities = [
            createActivity(id: "1", provider: .gitlab),
            createActivity(id: "2", provider: .gitlab),
            createActivity(id: "3", provider: .gitlab),
            createActivity(id: "4", provider: .azureDevops)
        ]

        let grouped = Dictionary(grouping: activities) { $0.provider }

        XCTAssertEqual(grouped[.gitlab]?.count, 2)
        XCTAssertEqual(grouped[.gitlab]?.count, 1)
        XCTAssertEqual(grouped[.azureDevops]?.count, 1)
        XCTAssertNil(grouped[.googleCalendar])
    }

    func testActivitiesCanBeGroupedByDay() {
        // Use UTC calendar to ensure consistent date strings
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        // Create dates at noon UTC to avoid timezone boundary issues
        let todayComponents = DateComponents(year: 2026, month: 1, day: 19, hour: 12)
        let yesterdayComponents = DateComponents(year: 2026, month: 1, day: 18, hour: 12)

        let today = calendar.date(from: todayComponents)!
        let yesterday = calendar.date(from: yesterdayComponents)!

        let activities = [
            createActivity(id: "1", timestamp: today.addingTimeInterval(3600)),
            createActivity(id: "2", timestamp: today.addingTimeInterval(7200)),
            createActivity(id: "3", timestamp: yesterday.addingTimeInterval(3600)),
            createActivity(id: "4", timestamp: yesterday.addingTimeInterval(7200))
        ]

        let grouped = Dictionary(grouping: activities) { activity -> String in
            Session.dateString(from: activity.timestamp)
        }

        XCTAssertEqual(grouped.count, 2) // Two days
        XCTAssertEqual(grouped["2026-01-19"]?.count, 2)
        XCTAssertEqual(grouped["2026-01-18"]?.count, 2)
    }

    // MARK: - Range Selection Tests

    func testRangeSelectionFiltersActivities() {
        let session = Session()
        let account = Account(id: "test", provider: .gitlab, displayName: "Test")
        session.accounts = [account]

        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!
        let twoDaysAgo = calendar.date(byAdding: .day, value: -2, to: today)!

        let activities = [
            createActivity(id: "1", timestamp: today.addingTimeInterval(3600)),
            createActivity(id: "2", timestamp: yesterday.addingTimeInterval(3600)),
            createActivity(id: "3", timestamp: twoDaysAgo.addingTimeInterval(3600))
        ]
        session.activitiesByAccount["test"] = activities

        // Select range: yesterday to today (exclusive of end)
        let range = DateRange(start: yesterday, end: today.addingTimeInterval(86400))
        let filtered = session.activitiesInRange(range)

        XCTAssertEqual(filtered.count, 2)
        XCTAssertTrue(filtered.contains { $0.id == "1" })
        XCTAssertTrue(filtered.contains { $0.id == "2" })
        XCTAssertFalse(filtered.contains { $0.id == "3" })
    }

    func testSelectedActivitiesReflectsCurrentSelection() {
        let session = Session()
        let account = Account(id: "test", provider: .gitlab, displayName: "Test")
        session.accounts = [account]

        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())
        let yesterday = calendar.date(byAdding: .day, value: -1, to: today)!

        let activities = [
            createActivity(id: "1", timestamp: today.addingTimeInterval(3600)),
            createActivity(id: "2", timestamp: yesterday.addingTimeInterval(3600))
        ]
        session.activitiesByAccount["test"] = activities
        session.selectedDate = today

        // Default: single day selection (today)
        XCTAssertNil(session.selectedRange)
        XCTAssertEqual(session.selectedActivities.count, 1)
        XCTAssertEqual(session.selectedActivities.first?.id, "1")
    }

    // MARK: - Provider Badge Tests

    func testAllProvidersHaveDistinctIdentifiers() {
        let providers = Provider.allCases

        XCTAssertEqual(providers.count, 4)
        XCTAssertTrue(providers.contains(.gitlab))
        XCTAssertTrue(providers.contains(.gitlab))
        XCTAssertTrue(providers.contains(.azureDevops))
        XCTAssertTrue(providers.contains(.googleCalendar))

        // Raw values should be distinct
        let rawValues = Set(providers.map { $0.rawValue })
        XCTAssertEqual(rawValues.count, 4)
    }

    func testProviderRawValuesMatchActivityDiscovery() {
        XCTAssertEqual(Provider.gitlab.rawValue, "gitlab")
        XCTAssertEqual(Provider.gitlab.rawValue, "gitlab")
        XCTAssertEqual(Provider.azureDevops.rawValue, "azure-devops")
        XCTAssertEqual(Provider.googleCalendar.rawValue, "google-calendar")
    }

    // MARK: - Disabled Accounts Filtering

    func testDisabledAccountsExcludedFromActivities() {
        let session = Session()

        let enabledAccount = Account(id: "enabled", provider: .gitlab, displayName: "Enabled", isEnabled: true)
        let disabledAccount = Account(id: "disabled", provider: .gitlab, displayName: "Disabled", isEnabled: false)

        session.accounts = [enabledAccount, disabledAccount]
        session.activitiesByAccount["enabled"] = [createActivity(id: "1")]
        session.activitiesByAccount["disabled"] = [createActivity(id: "2")]

        // All activities should only include enabled accounts
        XCTAssertEqual(session.allActivities.count, 1)
        XCTAssertEqual(session.allActivities.first?.id, "1")
    }

    // MARK: - Multiple Activities Per Day

    func testMultipleActivitiesSameDaySortedByTime() {
        let session = Session()
        let account = Account(id: "test", provider: .gitlab, displayName: "Test")
        session.accounts = [account]

        let calendar = Calendar(identifier: .gregorian)
        let today = calendar.startOfDay(for: Date())

        let activities = [
            createActivity(id: "1", timestamp: today.addingTimeInterval(10000)),
            createActivity(id: "2", timestamp: today.addingTimeInterval(20000)),
            createActivity(id: "3", timestamp: today.addingTimeInterval(5000))
        ]
        session.activitiesByAccount["test"] = activities
        session.selectedDate = today

        let selected = session.selectedActivities

        // Should be sorted by timestamp descending
        XCTAssertEqual(selected[0].id, "2") // 20000s - most recent
        XCTAssertEqual(selected[1].id, "1") // 10000s
        XCTAssertEqual(selected[2].id, "3") // 5000s - oldest
    }

    // MARK: - Codable Tests

    func testUnifiedActivityCodable() throws {
        let activity = UnifiedActivity(
            id: "test-1",
            provider: .gitlab,
            accountId: "gl-account",
            sourceId: "commit-123",
            type: .commit,
            timestamp: Date(timeIntervalSince1970: 1737331200), // Fixed timestamp
            title: "Fix bug",
            summary: "Fixed the login bug",
            participants: ["alice", "bob"],
            url: URL(string: "https://gitlab.com/org/repo/commit/123")
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(activity)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(UnifiedActivity.self, from: data)

        XCTAssertEqual(decoded.id, activity.id)
        XCTAssertEqual(decoded.provider, activity.provider)
        XCTAssertEqual(decoded.accountId, activity.accountId)
        XCTAssertEqual(decoded.sourceId, activity.sourceId)
        XCTAssertEqual(decoded.type, activity.type)
        XCTAssertEqual(decoded.title, activity.title)
        XCTAssertEqual(decoded.summary, activity.summary)
        XCTAssertEqual(decoded.participants, activity.participants)
        XCTAssertEqual(decoded.url, activity.url)
    }

    func testUnifiedActivityFromActivityDiscoveryJSON() throws {
        // JSON matching activity-discovery output format
        let json = """
        {
            "id": "github:acc1:commit-abc123",
            "provider": "github",
            "accountId": "acc1",
            "sourceId": "abc123",
            "type": "commit",
            "timestamp": 1737331200.0,
            "title": "Initial commit",
            "summary": "Set up project structure"
        }
        """

        let decoder = JSONDecoder()
        let activity = try decoder.decode(UnifiedActivity.self, from: json.data(using: .utf8)!)

        XCTAssertEqual(activity.id, "github:acc1:commit-abc123")
        XCTAssertEqual(activity.provider, .gitlab)
        XCTAssertEqual(activity.accountId, "acc1")
        XCTAssertEqual(activity.sourceId, "abc123")
        XCTAssertEqual(activity.type, .commit)
        XCTAssertEqual(activity.title, "Initial commit")
        XCTAssertEqual(activity.summary, "Set up project structure")
    }

    // MARK: - Deep Linking Tests (ACTIVITY-026)

    func testActivityWithURLIsInteractive() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "test",
            sourceId: "commit-1",
            type: .commit,
            timestamp: Date(),
            url: URL(string: "https://gitlab.com/org/repo/commit/123")
        )

        // Activity with URL should be interactive
        XCTAssertNotNil(activity.url)
    }

    func testActivityWithoutURLIsNotInteractive() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "test",
            sourceId: "commit-1",
            type: .commit,
            timestamp: Date()
        )

        // Activity without URL should not be interactive
        XCTAssertNil(activity.url)
    }

    func testMeetingActivityHasCalendarURL() {
        let meeting = UnifiedActivity(
            id: "1",
            provider: .googleCalendar,
            accountId: "test",
            sourceId: "event-1",
            type: .meeting,
            timestamp: Date(),
            title: "Sprint Planning",
            url: URL(string: "https://calendar.google.com/event?eid=abc123")
        )

        // Meeting should open calendar URL
        XCTAssertEqual(meeting.type, .meeting)
        XCTAssertNotNil(meeting.url)
        XCTAssertEqual(meeting.url?.host, "calendar.google.com")
    }

    func testMeetingActivityWithMeetingURL() {
        let meeting = UnifiedActivity(
            id: "1",
            provider: .googleCalendar,
            accountId: "test",
            sourceId: "event-1",
            type: .meeting,
            timestamp: Date(),
            title: "Team Standup",
            url: URL(string: "https://meet.google.com/abc-def-ghi")
        )

        // Meeting can also have a meeting link
        XCTAssertEqual(meeting.type, .meeting)
        XCTAssertNotNil(meeting.url)
        XCTAssertEqual(meeting.url?.host, "meet.google.com")
    }

    // MARK: - Helper Functions

    private func createActivity(
        id: String,
        provider: Provider = .gitlab,
        timestamp: Date = Date()
    ) -> UnifiedActivity {
        UnifiedActivity(
            id: id,
            provider: provider,
            accountId: "test-account",
            sourceId: "source-\(id)",
            type: .commit,
            timestamp: timestamp,
            title: "Activity \(id)"
        )
    }
}
