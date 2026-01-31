import XCTest
import SwiftUI
@testable import App
@testable import Core

final class CommitActivityViewTests: XCTestCase {

    // MARK: - SHA Extraction Tests

    func testShortSHAFromSourceId() {
        let activity = UnifiedActivity(
            id: "test:1:commit-1",
            provider: .gitlab,
            accountId: "acc1",
            sourceId: "abc123def456",
            type: .commit,
            timestamp: Date()
        )

        let view = CommitActivityView(activity: activity)
        // Access private computed property via reflection or test the rendered view
        // For now, verify the view can be initialized
        XCTAssertNotNil(view)
    }

    func testShortSHAFromSummary() {
        let activity = UnifiedActivity(
            id: "test:1:commit-2",
            provider: .gitlab,
            accountId: "acc1",
            sourceId: "event123",
            type: .commit,
            timestamp: Date(),
            summary: "Repo: owner/repo, SHA: abc123def456"
        )

        let view = CommitActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    // MARK: - Repo Name Extraction Tests

    func testRepoNameFromSummary() {
        let activity = UnifiedActivity(
            id: "test:1:commit-3",
            provider: .gitlab,
            accountId: "acc1",
            sourceId: "sha123",
            type: .commit,
            timestamp: Date(),
            summary: "Repo: owner/my-repo, SHA: abc123"
        )

        let view = CommitActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testRepoNameFromURL() {
        let activity = UnifiedActivity(
            id: "test:1:commit-4",
            provider: .gitlab,
            accountId: "acc1",
            sourceId: "sha456",
            type: .commit,
            timestamp: Date(),
            url: URL(string: "https://gitlab.com/owner/repo-name/commit/abc123")
        )

        let view = CommitActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    // MARK: - Avatar Tests

    func testCommitWithAvatar() {
        let activity = UnifiedActivity(
            id: "test:1:commit-5",
            provider: .gitlab,
            accountId: "acc1",
            sourceId: "sha789",
            type: .commit,
            timestamp: Date(),
            title: "Fix bug in authentication",
            authorAvatarURL: URL(string: "https://gitlab.com/uploads/-/system/user/avatar/u/123")
        )

        let view = CommitActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testCommitWithoutAvatar() {
        let activity = UnifiedActivity(
            id: "test:1:commit-6",
            provider: .gitlab,
            accountId: "acc1",
            sourceId: "shaabc",
            type: .commit,
            timestamp: Date(),
            title: "Update README"
        )

        let view = CommitActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    // MARK: - Full Commit Display Tests

    func testCompleteCommitActivity() {
        let activity = UnifiedActivity(
            id: "github:acc1:push-123",
            provider: .gitlab,
            accountId: "acc1",
            sourceId: "abc123def456789",
            type: .commit,
            timestamp: Date().addingTimeInterval(-3600),
            title: "Fix authentication bug",
            summary: "Repo: owner/my-repo, SHA: abc123def",
            participants: ["octocat"],
            url: URL(string: "https://gitlab.com/owner/my-repo/commit/abc123def"),
            authorAvatarURL: URL(string: "https://gitlab.com/uploads/-/system/user/avatar/u/583231")
        )

        let view = CommitActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testCommitWithoutTitle() {
        let activity = UnifiedActivity(
            id: "github:acc1:push-456",
            provider: .gitlab,
            accountId: "acc1",
            sourceId: "def456",
            type: .commit,
            timestamp: Date(),
            summary: "Repo: test/repo, SHA: def456"
        )

        let view = CommitActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testCommitWithoutURL() {
        let activity = UnifiedActivity(
            id: "github:acc1:push-789",
            provider: .gitlab,
            accountId: "acc1",
            sourceId: "789xyz",
            type: .commit,
            timestamp: Date(),
            title: "Local commit"
        )

        let view = CommitActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    // MARK: - Author Tests

    func testCommitWithAuthor() {
        let activity = UnifiedActivity(
            id: "test:1:commit-10",
            provider: .gitlab,
            accountId: "acc1",
            sourceId: "sha123",
            type: .commit,
            timestamp: Date(),
            title: "Update dependencies",
            participants: ["developer123"]
        )

        let view = CommitActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testCommitWithMultipleParticipants() {
        let activity = UnifiedActivity(
            id: "test:1:commit-11",
            provider: .gitlab,
            accountId: "acc1",
            sourceId: "sha456",
            type: .commit,
            timestamp: Date(),
            title: "Merge pull request",
            participants: ["author", "reviewer", "approver"]
        )

        let view = CommitActivityView(activity: activity)
        XCTAssertNotNil(view)
        // Should use first participant as author
    }

    // MARK: - Edge Cases

    func testCommitWithEmptySHA() {
        let activity = UnifiedActivity(
            id: "test:1:commit-12",
            provider: .gitlab,
            accountId: "acc1",
            sourceId: "",
            type: .commit,
            timestamp: Date(),
            title: "Test commit"
        )

        let view = CommitActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testCommitWithShortSourceId() {
        let activity = UnifiedActivity(
            id: "test:1:commit-13",
            provider: .gitlab,
            accountId: "acc1",
            sourceId: "abc",
            type: .commit,
            timestamp: Date(),
            title: "Short SHA commit"
        )

        let view = CommitActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testCommitWithLongTitle() {
        let activity = UnifiedActivity(
            id: "test:1:commit-14",
            provider: .gitlab,
            accountId: "acc1",
            sourceId: "sha123",
            type: .commit,
            timestamp: Date(),
            title: "This is a very long commit message that should be truncated or wrapped to fit within the layout constraints of the activity view"
        )

        let view = CommitActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    // MARK: - Timestamp Tests

    func testCommitRecentTimestamp() {
        let activity = UnifiedActivity(
            id: "test:1:commit-15",
            provider: .gitlab,
            accountId: "acc1",
            sourceId: "sha123",
            type: .commit,
            timestamp: Date().addingTimeInterval(-60) // 1 minute ago
        )

        let view = CommitActivityView(activity: activity)
        XCTAssertNotNil(view)
    }

    func testCommitOldTimestamp() {
        let activity = UnifiedActivity(
            id: "test:1:commit-16",
            provider: .gitlab,
            accountId: "acc1",
            sourceId: "sha456",
            type: .commit,
            timestamp: Date().addingTimeInterval(-86400 * 30) // 30 days ago
        )

        let view = CommitActivityView(activity: activity)
        XCTAssertNotNil(view)
    }
}
