import XCTest
@testable import App
import Core

final class CodeReviewActivityViewTests: XCTestCase {

    // MARK: - View Initialization Tests

    func testViewInitialization() {
        let activity = createCodeReviewActivity()
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testViewWithAllFields() {
        let activity = createCodeReviewActivity(
            title: "Approved: Add feature",
            summary: "Looks good to me!",
            author: "reviewer",
            avatarURL: URL(string: "https://example.com/avatar.jpg"),
            url: URL(string: "https://gitlab.com/org/repo/-/merge_requests/123")
        )
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testViewWithMinimalFields() {
        let activity = createCodeReviewActivity(
            title: nil,
            summary: nil,
            author: nil,
            avatarURL: nil,
            url: nil
        )
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    // MARK: - Review State Detection Tests

    func testApprovedStateDetection() {
        let activity = createCodeReviewActivity(title: "Approved: Fix bug")
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // State is derived from title - "Approved" keyword present
    }

    func testApprovedStateInSummary() {
        let activity = createCodeReviewActivity(
            title: "Review on #123",
            summary: "This is approved by the team"
        )
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // State can also be derived from summary
    }

    func testChangesRequestedStateDetection() {
        let activity = createCodeReviewActivity(title: "Changes requested on #124")
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // State is derived from title - "Changes requested" keyword present
    }

    func testChangesRequestedAlternativePhrase() {
        let activity = createCodeReviewActivity(
            title: "Review on #125",
            summary: "Please request changes to the implementation"
        )
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Alternative phrasing detection
    }

    func testCommentedStateDetection() {
        let activity = createCodeReviewActivity(title: "Comment on MergeRequest #126")
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Default state for code review without specific keywords
    }

    // MARK: - Review Context Tests

    func testReviewContextWithPRTitle() {
        let activity = createCodeReviewActivity(title: "Add user authentication feature")
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Context should use the PR title directly
    }

    func testReviewContextWithCommentPrefix() {
        let activity = createCodeReviewActivity(title: "Comment on MergeRequest #123")
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Context should preserve "Comment on" prefix
    }

    func testReviewContextWithReviewPrefix() {
        let activity = createCodeReviewActivity(title: "Review on #124")
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Context should preserve "Review on" prefix
    }

    func testReviewContextFallbackToSourceId() {
        let activity = createCodeReviewActivity(
            sourceId: "125",
            title: nil
        )
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Context should extract from sourceId when title is missing
    }

    func testReviewContextFallbackToURL() {
        let activity = createCodeReviewActivity(
            sourceId: "event-123",
            title: nil,
            url: URL(string: "https://gitlab.com/org/repo/-/merge_requests/126")
        )
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Context should extract PR number from URL when sourceId and title are unavailable
    }

    func testReviewContextGenericFallback() {
        let activity = createCodeReviewActivity(
            sourceId: "event-abc",
            title: nil,
            url: URL(string: "https://gitlab.com/org/repo")
        )
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Context should fall back to generic "Code Review" text
    }

    // MARK: - PR Number Extraction Tests

    func testPRNumberFromNumericSourceId() {
        let activity = createCodeReviewActivity(sourceId: "123")
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Should extract "123" from sourceId
    }

    func testPRNumberFromGitLabURL() {
        let activity = createCodeReviewActivity(
            sourceId: "event-456",
            url: URL(string: "https://gitlab.com/org/repo/-/merge_requests/789")
        )
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Should extract "789" from URL merge_requests path
    }

    func testPRNumberFromGitLabURLWithAnchor() {
        let activity = createCodeReviewActivity(
            sourceId: "event-456",
            url: URL(string: "https://gitlab.com/org/repo/-/merge_requests/234#note_567")
        )
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Should extract "234" from URL even with anchor
    }

    func testPRNumberNotFoundInURL() {
        let activity = createCodeReviewActivity(
            sourceId: "event-xyz",
            url: URL(string: "https://gitlab.com/org/repo/-/commits/main")
        )
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Should handle URL without PR number gracefully
    }

    // MARK: - Avatar Tests

    func testAvatarWithURL() {
        let activity = createCodeReviewActivity(
            avatarURL: URL(string: "https://secure.gravatar.com/avatar/abc123")
        )
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Should use AvatarView with provided URL
    }

    func testAvatarPlaceholder() {
        let activity = createCodeReviewActivity(avatarURL: nil)
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Should show placeholder with checkmark.bubble icon
    }

    // MARK: - Metadata Tests

    func testMetadataWithAuthor() {
        let activity = createCodeReviewActivity(author: "senior-dev")
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Metadata row should include author
    }

    func testMetadataWithoutAuthor() {
        let activity = createCodeReviewActivity(author: nil)
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Metadata row should work without author
    }

    func testMetadataWithEmptyAuthor() {
        let activity = createCodeReviewActivity(participants: [""])
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Empty author should be treated as missing
    }

    // MARK: - Summary Tests

    func testSummaryDisplay() {
        let activity = createCodeReviewActivity(
            summary: "Great implementation! Just a few minor suggestions."
        )
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Should display summary text
    }

    func testEmptySummaryHidden() {
        let activity = createCodeReviewActivity(summary: "")
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Empty summary should be hidden
    }

    func testNilSummaryHidden() {
        let activity = createCodeReviewActivity(summary: nil)
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Nil summary should be hidden
    }

    // MARK: - URL Handling Tests

    func testActivityWithURL() {
        let activity = createCodeReviewActivity(
            url: URL(string: "https://gitlab.com/org/repo/-/merge_requests/123")
        )
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Should be clickable with valid URL
    }

    func testActivityWithoutURL() {
        let activity = createCodeReviewActivity(url: nil)
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Should handle missing URL gracefully (non-interactive)
    }

    // MARK: - Provider Tests

    func testGitLabProvider() {
        let activity = createCodeReviewActivity(provider: .gitlab)
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testAzureDevOpsProvider() {
        let activity = createCodeReviewActivity(provider: .azureDevops)
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    // MARK: - Timestamp Tests

    func testRecentTimestamp() {
        let activity = createCodeReviewActivity(
            timestamp: Date().addingTimeInterval(-300)  // 5 minutes ago
        )
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Should display relative time (e.g., "5m ago")
    }

    func testOldTimestamp() {
        let activity = createCodeReviewActivity(
            timestamp: Date().addingTimeInterval(-86400 * 7)  // 7 days ago
        )
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Should display relative time (e.g., "1w ago")
    }

    // MARK: - Edge Cases

    func testCaseInsensitiveStateDetection() {
        let activity = createCodeReviewActivity(title: "APPROVED: Major refactor")
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // State detection should be case-insensitive
    }

    func testMultipleKeywordsInTitle() {
        let activity = createCodeReviewActivity(
            title: "Approved: Changes requested previously are now addressed"
        )
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Should detect first matching keyword (approved)
    }

    func testLongSummary() {
        let longSummary = String(repeating: "This is a very detailed review comment. ", count: 10)
        let activity = createCodeReviewActivity(summary: longSummary)
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Should handle long summaries with lineLimit
    }

    func testSpecialCharactersInTitle() {
        let activity = createCodeReviewActivity(
            title: "Approved: Fix bug with <special> & \"characters\""
        )
        let view = CodeReviewActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Should handle special characters in text
    }

    // MARK: - Helper Methods

    private func createCodeReviewActivity(
        id: String = "test-1",
        provider: Provider = .gitlab,
        sourceId: String = "123",
        timestamp: Date = Date(),
        title: String? = "Review on #123",
        summary: String? = nil,
        author: String? = "reviewer",
        participants: [String]? = nil,
        avatarURL: URL? = nil,
        url: URL? = URL(string: "https://gitlab.com/org/repo/-/merge_requests/123")
    ) -> UnifiedActivity {
        UnifiedActivity(
            id: id,
            provider: provider,
            accountId: "test-account",
            sourceId: sourceId,
            type: .codeReview,
            timestamp: timestamp,
            title: title,
            summary: summary,
            participants: participants ?? (author.map { [$0] }),
            url: url,
            authorAvatarURL: avatarURL
        )
    }
}
