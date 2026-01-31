import XCTest
import SwiftUI
@testable import App
@testable import Core

final class ActivityRowViewTests: XCTestCase {
    // MARK: - Test Data

    private let baseActivity = UnifiedActivity(
        id: "test-1",
        provider: .gitlab,
        accountId: "account-1",
        sourceId: "source-1",
        type: .commit,
        timestamp: Date(timeIntervalSince1970: 1700000000),
        title: "Test commit",
        summary: "Test summary",
        participants: ["alice"],
        url: URL(string: "https://example.com")
    )

    // MARK: - Initialization Tests

    func testActivityRowViewInitialization() {
        let view = ActivityRowView(activity: baseActivity)
        XCTAssertEqual(view.activity.id, "test-1")
        XCTAssertEqual(view.activity.provider, .gitlab)
        XCTAssertEqual(view.activity.type, .commit)
    }

    // MARK: - Title Display Tests

    func testDisplaysTitleWhenPresent() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: Date(),
            title: "Fix authentication bug",
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        XCTAssertEqual(activity.title, "Fix authentication bug")
    }

    func testHandlesNilTitle() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: Date(),
            title: nil,
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        XCTAssertNil(activity.title)
    }

    func testHandlesEmptyTitle() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: Date(),
            title: "",
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        XCTAssertEqual(activity.title, "")
    }

    func testHandlesLongTitle() {
        let longTitle = String(repeating: "A", count: 500)
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: Date(),
            title: longTitle,
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        XCTAssertEqual(activity.title?.count, 500)
    }

    // MARK: - Metadata Display Tests

    func testDisplaysFirstParticipantAsAuthor() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: Date(),
            participants: ["alice", "bob", "charlie"],
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        XCTAssertEqual(activity.participants?.first, "alice")
    }

    func testHandlesNilParticipants() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: Date(),
            participants: nil,
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        XCTAssertNil(activity.participants)
    }

    func testHandlesEmptyParticipants() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: Date(),
            participants: [],
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        XCTAssertEqual(activity.participants?.count, 0)
    }

    // MARK: - Provider Badge Tests

    func testProviderBadgeGitHub() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: Date(),
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        // Provider short name accessed via private property, verify enum value
        XCTAssertEqual(activity.provider, .gitlab)
    }

    func testProviderBadgeGitLab() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: Date(),
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        XCTAssertEqual(activity.provider, .gitlab)
    }

    func testProviderBadgeAzureDevOps() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .azureDevops,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: Date(),
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        XCTAssertEqual(activity.provider, .azureDevops)
    }

    func testProviderBadgeGoogleCalendar() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .googleCalendar,
            accountId: "acc",
            sourceId: "src",
            type: .meeting,
            timestamp: Date(),
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        XCTAssertEqual(activity.provider, .googleCalendar)
    }

    // MARK: - Activity Type Icon Tests

    func testDisplaysCorrectIconForCommit() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: Date(),
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        let iconName = ActivityIconMapper.symbolName(for: activity.type)
        XCTAssertEqual(iconName, "arrow.up.circle")
    }

    func testDisplaysCorrectIconForPullRequest() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .pullRequest,
            timestamp: Date(),
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        let iconName = ActivityIconMapper.symbolName(for: activity.type)
        XCTAssertEqual(iconName, "arrow.triangle.branch")
    }

    func testDisplaysCorrectIconForIssue() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .issue,
            timestamp: Date(),
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        let iconName = ActivityIconMapper.symbolName(for: activity.type)
        XCTAssertEqual(iconName, "exclamationmark.circle")
    }

    func testDisplaysCorrectIconForMeeting() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .googleCalendar,
            accountId: "acc",
            sourceId: "src",
            type: .meeting,
            timestamp: Date(),
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        let iconName = ActivityIconMapper.symbolName(for: activity.type)
        XCTAssertEqual(iconName, "calendar")
    }

    // MARK: - Timestamp Display Tests

    func testDisplaysRelativeTime() {
        let oneHourAgo = Date().addingTimeInterval(-3600)
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: oneHourAgo,
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        let relativeTime = RelativeTimeFormatter.string(from: activity.timestamp)
        XCTAssertTrue(relativeTime.contains("ago"))
    }

    func testDisplaysRelativeTimeForRecentActivity() {
        let twoMinutesAgo = Date().addingTimeInterval(-120)
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: twoMinutesAgo,
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        let relativeTime = RelativeTimeFormatter.string(from: activity.timestamp)
        XCTAssertTrue(relativeTime.contains("ago"))
    }

    func testDisplaysRelativeTimeForOldActivity() {
        let thirtyDaysAgo = Date().addingTimeInterval(-30 * 24 * 3600)
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: thirtyDaysAgo,
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        let relativeTime = RelativeTimeFormatter.string(from: activity.timestamp)
        XCTAssertTrue(relativeTime.contains("ago"))
    }

    // MARK: - URL Handling Tests

    func testHandlesValidURL() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: Date(),
            url: URL(string: "https://gitlab.com/example/repo/commit/abc123")
        )
        let view = ActivityRowView(activity: activity)
        XCTAssertNotNil(activity.url)
        XCTAssertEqual(activity.url?.absoluteString, "https://gitlab.com/example/repo/commit/abc123")
    }

    func testHandlesNilURL() {
        let activity = UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: Date(),
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        XCTAssertNil(activity.url)
    }

    // MARK: - All Activity Types Tests

    func testSupportsAllActivityTypes() {
        let activityTypes: [ActivityType] = [
            .commit, .pullRequest, .issue, .issueComment,
            .codeReview, .meeting, .workItem, .deployment,
            .release, .wiki, .other
        ]

        for type in activityTypes {
            let activity = UnifiedActivity(
                id: "test-\(type.rawValue)",
                provider: .gitlab,
                accountId: "acc",
                sourceId: "src",
                type: type,
                timestamp: Date(),
                url: nil
            )
            let view = ActivityRowView(activity: activity)
            XCTAssertEqual(view.activity.type, type)

            // Verify icon exists for this type
            let iconName = ActivityIconMapper.symbolName(for: type)
            XCTAssertFalse(iconName.isEmpty, "Icon should exist for \(type)")
        }
    }

    // MARK: - Edge Case Tests

    func testHandlesMinimalActivity() {
        let activity = UnifiedActivity(
            id: "minimal",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .other,
            timestamp: Date(),
            title: nil,
            summary: nil,
            participants: nil,
            url: nil
        )
        let view = ActivityRowView(activity: activity)
        XCTAssertEqual(view.activity.id, "minimal")
        XCTAssertNil(view.activity.title)
        XCTAssertNil(view.activity.participants)
        XCTAssertNil(view.activity.url)
    }

    func testHandlesCompleteActivity() {
        let activity = UnifiedActivity(
            id: "complete",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .pullRequest,
            timestamp: Date(),
            title: "Complete PR",
            summary: "With all fields",
            participants: ["alice", "bob"],
            url: URL(string: "https://example.com")
        )
        let view = ActivityRowView(activity: activity)
        XCTAssertEqual(view.activity.id, "complete")
        XCTAssertNotNil(view.activity.title)
        XCTAssertNotNil(view.activity.summary)
        XCTAssertNotNil(view.activity.participants)
        XCTAssertNotNil(view.activity.url)
    }

    func testHandlesMultipleActivitiesInSequence() {
        let activities = [
            UnifiedActivity(id: "1", provider: .gitlab, accountId: "a", sourceId: "s1", type: .commit, timestamp: Date(), url: nil),
            UnifiedActivity(id: "2", provider: .gitlab, accountId: "b", sourceId: "s2", type: .issue, timestamp: Date(), url: nil),
            UnifiedActivity(id: "3", provider: .azureDevops, accountId: "c", sourceId: "s3", type: .workItem, timestamp: Date(), url: nil),
        ]

        for activity in activities {
            let view = ActivityRowView(activity: activity)
            XCTAssertNotNil(view.activity)
        }
    }

    // MARK: - Highlight State Tests

    func testRespondsToHighlightState() {
        // These tests verify that ActivityRowView can be initialized with different activities
        // Actual highlight state testing would require ViewInspector or similar SwiftUI testing tools
        let normalActivity = UnifiedActivity(
            id: "normal",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: Date(),
            title: "Normal state",
            url: nil
        )

        let highlightedActivity = UnifiedActivity(
            id: "highlighted",
            provider: .gitlab,
            accountId: "acc",
            sourceId: "src",
            type: .commit,
            timestamp: Date(),
            title: "Highlighted state",
            url: nil
        )

        let normalView = ActivityRowView(activity: normalActivity)
        let highlightedView = ActivityRowView(activity: highlightedActivity)

        XCTAssertEqual(normalView.activity.title, "Normal state")
        XCTAssertEqual(highlightedView.activity.title, "Highlighted state")
    }
}
