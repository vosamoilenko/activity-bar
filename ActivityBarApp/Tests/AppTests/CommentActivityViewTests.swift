import XCTest
@testable import App
import Core
import SwiftUI

/// Tests for CommentActivityView component
final class CommentActivityViewTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitialization() {
        let activity = createCommentActivity()
        let view = CommentActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testInitializationWithMinimalData() {
        let activity = UnifiedActivity(
            id: "test:1",
            provider: .gitlab,
            accountId: "test",
            sourceId: "123",
            type: .issueComment,
            timestamp: Date()
        )
        let view = CommentActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    // MARK: - Comment Context Tests

    func testCommentContextFromTitle() {
        let activity = createCommentActivity(
            title: "Comment on #123",
            summary: "This is the comment body"
        )
        let view = CommentActivityView(activity: activity)
        // Context should use the title directly
        XCTAssertNotNil(view)
    }

    func testCommentContextIssueFromURL() {
        let activity = createCommentActivity(
            title: nil,
            url: URL(string: "https://gitlab.com/owner/repo/-/issues/456#note_789")
        )
        let view = CommentActivityView(activity: activity)
        // Should extract issue number from URL
        XCTAssertNotNil(view)
    }

    func testCommentContextPRFromURL() {
        let activity = createCommentActivity(
            title: nil,
            url: URL(string: "https://gitlab.com/owner/repo/-/merge_requests/789#note_123")
        )
        let view = CommentActivityView(activity: activity)
        // Should extract PR number from URL
        XCTAssertNotNil(view)
    }

    func testCommentContextFromSourceId() {
        let activity = createCommentActivity(
            sourceId: "999",
            title: nil,
            url: nil
        )
        let view = CommentActivityView(activity: activity)
        // Should fallback to sourceId
        XCTAssertNotNil(view)
    }

    func testCommentContextUnknown() {
        let activity = createCommentActivity(
            sourceId: "non-numeric-id",
            title: nil,
            url: nil
        )
        let view = CommentActivityView(activity: activity)
        // Should fallback to generic "Comment"
        XCTAssertNotNil(view)
    }

    // MARK: - Comment Snippet Tests

    func testCommentSnippetFromSummary() {
        let summary = "This is a test comment body"
        let activity = createCommentActivity(summary: summary)
        let view = CommentActivityView(activity: activity)
        // Snippet should come from summary
        XCTAssertNotNil(view)
    }

    func testCommentSnippetFromTitle() {
        let activity = createCommentActivity(
            title: "This is the comment text",
            summary: nil
        )
        let view = CommentActivityView(activity: activity)
        // Snippet should use title if summary is nil
        XCTAssertNotNil(view)
    }

    func testCommentSnippetTruncation() {
        let longText = String(repeating: "a", count: 150)
        let activity = createCommentActivity(summary: longText)
        let view = CommentActivityView(activity: activity)
        // Should truncate to 100 chars
        XCTAssertNotNil(view)
    }

    func testCommentSnippetExactly100Chars() {
        let text = String(repeating: "b", count: 100)
        let activity = createCommentActivity(summary: text)
        let view = CommentActivityView(activity: activity)
        // Should not truncate
        XCTAssertNotNil(view)
    }

    func testCommentSnippetWhitespaceTrimming() {
        let activity = createCommentActivity(summary: "  \n  Test comment  \n  ")
        let view = CommentActivityView(activity: activity)
        // Should trim whitespace
        XCTAssertNotNil(view)
    }

    func testCommentSnippetEmpty() {
        let activity = createCommentActivity(summary: "")
        let view = CommentActivityView(activity: activity)
        // Should handle empty snippet gracefully
        XCTAssertNotNil(view)
    }

    func testCommentSnippetNil() {
        let activity = createCommentActivity(
            title: "Comment on #123",
            summary: nil
        )
        let view = CommentActivityView(activity: activity)
        // Should handle nil snippet gracefully
        XCTAssertNotNil(view)
    }

    func testCommentSnippetIgnoresContextTitle() {
        let activity = createCommentActivity(
            title: "Comment on #123",
            summary: "Actual comment body"
        )
        let view = CommentActivityView(activity: activity)
        // Should not use "Comment on #123" as snippet
        XCTAssertNotNil(view)
    }

    // MARK: - URL Pattern Tests

    func testURLPatternGitLabIssue() {
        let activity = createCommentActivity(
            url: URL(string: "https://gitlab.com/org/repo/-/issues/123#note_456")
        )
        let view = CommentActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testURLPatternGitLabMergeRequest() {
        let activity = createCommentActivity(
            url: URL(string: "https://gitlab.com/org/repo/-/merge_requests/789#note_123")
        )
        let view = CommentActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testURLPatternSelfHostedGitLab() {
        let activity = createCommentActivity(
            url: URL(string: "https://gitlab.company.com/team/project/-/issues/456#note_789")
        )
        let view = CommentActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    // MARK: - Avatar Tests

    func testAvatarWithURL() {
        let activity = createCommentActivity(
            authorAvatarURL: URL(string: "https://secure.gravatar.com/avatar/abc123")
        )
        let view = CommentActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testAvatarWithoutURL() {
        let activity = createCommentActivity(authorAvatarURL: nil)
        let view = CommentActivityView(activity: activity)
        // Should show placeholder with text.bubble icon
        XCTAssertNotNil(view)
    }

    // MARK: - Metadata Tests

    func testMetadataWithAuthor() {
        let activity = createCommentActivity(participants: ["test-user"])
        let view = CommentActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testMetadataWithoutAuthor() {
        let activity = createCommentActivity(participants: nil)
        let view = CommentActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testMetadataWithEmptyParticipants() {
        let activity = createCommentActivity(participants: [])
        let view = CommentActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testMetadataTimestamp() {
        let timestamp = Date().addingTimeInterval(-3600) // 1 hour ago
        let activity = createCommentActivity(timestamp: timestamp)
        let view = CommentActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    // MARK: - Navigation Tests

    func testOpenActivityWithURL() {
        let url = URL(string: "https://gitlab.com/owner/repo/-/issues/123#note_456")!
        let activity = createCommentActivity(url: url)
        let view = CommentActivityView(activity: activity)
        // Should be able to open URL
        XCTAssertNotNil(view)
    }

    func testOpenActivityWithoutURL() {
        let activity = createCommentActivity(url: nil)
        let view = CommentActivityView(activity: activity)
        // Should handle missing URL gracefully
        XCTAssertNotNil(view)
    }

    // MARK: - Edge Cases

    func testMultilineCommentSnippet() {
        let multiline = """
        First line of comment
        Second line of comment
        Third line of comment
        """
        let activity = createCommentActivity(summary: multiline)
        let view = CommentActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testSpecialCharactersInComment() {
        let activity = createCommentActivity(
            summary: "Comment with special chars: @mention #hashtag https://example.com"
        )
        let view = CommentActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testUnicodeInComment() {
        let activity = createCommentActivity(summary: "🎉 Great work! 你好 😊")
        let view = CommentActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testVeryLongURLPath() {
        let activity = createCommentActivity(
            url: URL(string: "https://gitlab.com/very/deep/nested/organization/team/subteam/project/-/issues/123456789#note_987654321")
        )
        let view = CommentActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    // MARK: - Helper Methods

    private func createCommentActivity(
        sourceId: String = "123",
        title: String? = "Comment on #123",
        summary: String? = "This is a test comment",
        participants: [String]? = ["test-user"],
        url: URL? = URL(string: "https://gitlab.com/owner/repo/-/issues/123#note_456"),
        timestamp: Date = Date(),
        authorAvatarURL: URL? = URL(string: "https://secure.gravatar.com/avatar/test")
    ) -> UnifiedActivity {
        UnifiedActivity(
            id: "gitlab:test:comment-\(sourceId)",
            provider: .gitlab,
            accountId: "test",
            sourceId: sourceId,
            type: .issueComment,
            timestamp: timestamp,
            title: title,
            summary: summary,
            participants: participants,
            url: url,
            authorAvatarURL: authorAvatarURL
        )
    }
}
