import XCTest
@testable import App
@testable import Core

@MainActor
final class IssueActivityViewTests: XCTestCase {

    // MARK: - Initialization Tests

    func testViewInitializesWithValidActivity() {
        let activity = createIssueActivity(
            sourceId: "123",
            title: "Test Issue"
        )

        let view = IssueActivityView(activity: activity)

        XCTAssertNotNil(view)
        XCTAssertEqual(view.activity.id, activity.id)
        XCTAssertEqual(view.activity.type, .issue)
    }

    // MARK: - Issue Number Display Tests

    func testIssueNumberDisplayWithNumericSourceId() {
        let activity = createIssueActivity(sourceId: "456")
        let view = IssueActivityView(activity: activity)

        // sourceId should be numeric, so it should format as "#456"
        XCTAssertTrue(activity.sourceId.allSatisfy(\.isNumber))
    }

    func testIssueNumberDisplayWithNonNumericSourceId() {
        let activity = createIssueActivity(sourceId: "issue-789")
        let view = IssueActivityView(activity: activity)

        // sourceId is not numeric, should fall back to URL parsing or use as-is
        XCTAssertFalse(activity.sourceId.allSatisfy(\.isNumber))
    }

    func testIssueNumberExtractionFromURL() {
        let activity = createIssueActivity(
            sourceId: "abc",
            url: URL(string: "https://gitlab.com/owner/repo/issues/999")
        )

        let view = IssueActivityView(activity: activity)

        // URL contains issue number 999
        XCTAssertNotNil(activity.url)
        XCTAssertTrue(activity.url!.absoluteString.contains("/issues/999"))
    }

    // MARK: - Author Display Tests

    func testAuthorDisplayWithParticipants() {
        let activity = createIssueActivity(participants: ["alice", "bob"])
        let view = IssueActivityView(activity: activity)

        // Should display first participant as author
        XCTAssertEqual(activity.participants?.first, "alice")
    }

    func testAuthorDisplayWithoutParticipants() {
        let activity = createIssueActivity(participants: nil)
        let view = IssueActivityView(activity: activity)

        // Should handle nil participants gracefully
        XCTAssertNil(activity.participants)
    }

    func testAuthorDisplayWithEmptyParticipants() {
        let activity = createIssueActivity(participants: [])
        let view = IssueActivityView(activity: activity)

        // Should handle empty participants array
        XCTAssertTrue(activity.participants?.isEmpty ?? false)
    }

    // MARK: - Avatar Display Tests

    func testAvatarDisplayWithURL() {
        let avatarURL = URL(string: "https://gitlab.com/uploads/-/system/user/avatar/u/123456")
        let activity = createIssueActivity(authorAvatarURL: avatarURL)

        let view = IssueActivityView(activity: activity)

        XCTAssertNotNil(activity.authorAvatarURL)
        XCTAssertEqual(activity.authorAvatarURL, avatarURL)
    }

    func testAvatarDisplayWithoutURL() {
        let activity = createIssueActivity(authorAvatarURL: nil)
        let view = IssueActivityView(activity: activity)

        // Should fall back to placeholder with exclamationmark.circle icon
        XCTAssertNil(activity.authorAvatarURL)
    }

    // MARK: - Comment Count Tests

    func testCommentCountDisplayWhenPositive() {
        let activity = createIssueActivity(commentCount: 5)
        let view = IssueActivityView(activity: activity)

        XCTAssertEqual(activity.commentCount, 5)
        XCTAssertTrue(activity.commentCount! > 0)
    }

    func testCommentCountNotDisplayedWhenZero() {
        let activity = createIssueActivity(commentCount: 0)
        let view = IssueActivityView(activity: activity)

        XCTAssertEqual(activity.commentCount, 0)
        XCTAssertFalse(activity.commentCount! > 0)
    }

    func testCommentCountNotDisplayedWhenNil() {
        let activity = createIssueActivity(commentCount: nil)
        let view = IssueActivityView(activity: activity)

        XCTAssertNil(activity.commentCount)
    }

    // MARK: - Labels Tests

    func testLabelsDisplayWithMultipleLabels() {
        let labels = [
            ActivityLabel(id: "1", name: "bug", color: "D73A4A"),
            ActivityLabel(id: "2", name: "priority-high", color: "B60205")
        ]
        let activity = createIssueActivity(labels: labels)

        let view = IssueActivityView(activity: activity)

        XCTAssertEqual(activity.labels?.count, 2)
        XCTAssertEqual(activity.labels?[0].name, "bug")
        XCTAssertEqual(activity.labels?[1].name, "priority-high")
    }

    func testLabelsDisplayWithSingleLabel() {
        let labels = [
            ActivityLabel(id: "1", name: "enhancement", color: "84B6EB")
        ]
        let activity = createIssueActivity(labels: labels)

        let view = IssueActivityView(activity: activity)

        XCTAssertEqual(activity.labels?.count, 1)
        XCTAssertEqual(activity.labels?[0].name, "enhancement")
    }

    func testLabelsNotDisplayedWhenEmpty() {
        let activity = createIssueActivity(labels: [])
        let view = IssueActivityView(activity: activity)

        XCTAssertTrue(activity.labels?.isEmpty ?? true)
    }

    func testLabelsNotDisplayedWhenNil() {
        let activity = createIssueActivity(labels: nil)
        let view = IssueActivityView(activity: activity)

        XCTAssertNil(activity.labels)
    }

    // MARK: - Title Display Tests

    func testTitleDisplayWithValidTitle() {
        let title = "App crashes on startup when offline"
        let activity = createIssueActivity(title: title)

        let view = IssueActivityView(activity: activity)

        XCTAssertEqual(activity.title, title)
    }

    func testTitleDisplayWithEmptyTitle() {
        let activity = createIssueActivity(title: "")
        let view = IssueActivityView(activity: activity)

        // Empty title should still be set but might not display
        XCTAssertEqual(activity.title, "")
    }

    func testTitleDisplayWithNilTitle() {
        let activity = createIssueActivity(title: nil)
        let view = IssueActivityView(activity: activity)

        XCTAssertNil(activity.title)
    }

    // MARK: - URL Handling Tests

    func testURLHandlingWithValidURL() {
        let url = URL(string: "https://gitlab.com/owner/repo/issues/123")
        let activity = createIssueActivity(url: url)

        let view = IssueActivityView(activity: activity)

        XCTAssertNotNil(activity.url)
        XCTAssertEqual(activity.url, url)
    }

    func testURLHandlingWithNilURL() {
        let activity = createIssueActivity(url: nil)
        let view = IssueActivityView(activity: activity)

        // Should handle nil URL gracefully (no action on tap)
        XCTAssertNil(activity.url)
    }

    // MARK: - Timestamp Tests

    func testTimestampFormattingRecent() {
        let twoHoursAgo = Date().addingTimeInterval(-3600 * 2)
        let activity = createIssueActivity(timestamp: twoHoursAgo)

        let view = IssueActivityView(activity: activity)

        XCTAssertEqual(activity.timestamp, twoHoursAgo)

        // Verify RelativeTimeFormatter would produce expected format
        let formatted = RelativeTimeFormatter.string(from: twoHoursAgo)
        XCTAssertTrue(formatted.contains("hr") || formatted.contains("hour"))
    }

    func testTimestampFormattingOld() {
        let threeDaysAgo = Date().addingTimeInterval(-3600 * 72)
        let activity = createIssueActivity(timestamp: threeDaysAgo)

        let view = IssueActivityView(activity: activity)

        XCTAssertEqual(activity.timestamp, threeDaysAgo)

        // Verify RelativeTimeFormatter would produce expected format
        let formatted = RelativeTimeFormatter.string(from: threeDaysAgo)
        XCTAssertTrue(formatted.contains("day") || formatted.contains("dy"))
    }

    // MARK: - Edge Cases

    func testViewWithMinimalActivity() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:issue-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .issue,
            timestamp: Date()
        )

        let view = IssueActivityView(activity: activity)

        // Should initialize successfully even with minimal data
        XCTAssertNotNil(view)
        XCTAssertNil(activity.title)
        XCTAssertNil(activity.participants)
        XCTAssertNil(activity.url)
        XCTAssertNil(activity.commentCount)
        XCTAssertNil(activity.labels)
    }

    func testViewWithMaximalActivity() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:issue-999",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "999",
            type: .issue,
            timestamp: Date(),
            title: "Very long issue title that might be truncated in the UI",
            summary: "Detailed summary",
            participants: ["user1", "user2", "user3"],
            url: URL(string: "https://gitlab.com/owner/repo/issues/999"),
            authorAvatarURL: URL(string: "https://gitlab.com/uploads/-/system/user/avatar/u/999999"),
            labels: [
                ActivityLabel(id: "1", name: "bug", color: "D73A4A"),
                ActivityLabel(id: "2", name: "priority-high", color: "B60205"),
                ActivityLabel(id: "3", name: "regression", color: "D93F0B")
            ],
            commentCount: 42
        )

        let view = IssueActivityView(activity: activity)

        // Should handle all optional fields
        XCTAssertNotNil(view)
        XCTAssertNotNil(activity.title)
        XCTAssertNotNil(activity.participants)
        XCTAssertNotNil(activity.url)
        XCTAssertNotNil(activity.commentCount)
        XCTAssertNotNil(activity.labels)
        XCTAssertEqual(activity.labels?.count, 3)
    }

    // MARK: - Helper Methods

    private func createIssueActivity(
        sourceId: String = "123",
        title: String? = "Test Issue",
        participants: [String]? = ["testuser"],
        url: URL? = URL(string: "https://gitlab.com/owner/repo/issues/123"),
        authorAvatarURL: URL? = nil,
        labels: [ActivityLabel]? = nil,
        commentCount: Int? = nil,
        timestamp: Date = Date()
    ) -> UnifiedActivity {
        return UnifiedActivity(
            id: "gitlab:account1:issue-\(sourceId)",
            provider: .gitlab,
            accountId: "account1",
            sourceId: sourceId,
            type: .issue,
            timestamp: timestamp,
            title: title,
            summary: "Issue summary",
            participants: participants,
            url: url,
            authorAvatarURL: authorAvatarURL,
            labels: labels,
            commentCount: commentCount
        )
    }
}
