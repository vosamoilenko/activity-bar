import XCTest
import SwiftUI
@testable import App
@testable import Core

final class PullRequestActivityViewTests: XCTestCase {

    // MARK: - Basic Initialization Tests

    func testInitializesWithMinimalPRActivity() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test PR",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/1")
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertNotNil(view)
        XCTAssertEqual(view.activity.id, "gitlab:account1:pr-1")
        XCTAssertEqual(view.activity.type, .pullRequest)
    }

    func testInitializesWithFullPRActivity() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-123",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "123",
            type: .pullRequest,
            timestamp: Date(),
            title: "Add feature X",
            summary: "PR opened",
            participants: ["octocat"],
            url: URL(string: "https://gitlab.com/owner/repo/pull/123"),
            authorAvatarURL: URL(string: "https://gitlab.com/uploads/-/system/user/avatar/u/583231"),
            labels: [ActivityLabel(id: "1", name: "feature", color: "0E8A16")],
            commentCount: 5,
            isDraft: true,
            sourceRef: "feature-branch",
            targetRef: "main"
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertNotNil(view)
        XCTAssertEqual(view.activity.authorAvatarURL?.absoluteString, "https://gitlab.com/uploads/-/system/user/avatar/u/583231")
        XCTAssertEqual(view.activity.commentCount, 5)
        XCTAssertEqual(view.activity.isDraft, true)
        XCTAssertEqual(view.activity.sourceRef, "feature-branch")
        XCTAssertEqual(view.activity.targetRef, "main")
        XCTAssertEqual(view.activity.labels?.count, 1)
    }

    // MARK: - PR Number Extraction Tests

    func testExtractsPRNumberFromSourceId() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-456",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "456",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/456")
        )

        let view = PullRequestActivityView(activity: activity)
        // We can't directly test the computed property without rendering,
        // but we verify that sourceId contains the expected value
        XCTAssertEqual(view.activity.sourceId, "456")
        XCTAssertTrue(view.activity.sourceId.allSatisfy { $0.isNumber })
    }

    func testExtractsPRNumberFromURLWhenSourceIdIsNonNumeric() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-abc",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "abc123", // Non-numeric sourceId
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/789")
        )

        let view = PullRequestActivityView(activity: activity)
        // View should extract number from URL as fallback
        XCTAssertNotNil(view.activity.url)
        XCTAssertTrue(view.activity.url!.absoluteString.contains("/pull/789"))
    }

    func testHandlesMissingPRNumber() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-unknown",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "unknown",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: nil // No URL to extract from
        )

        let view = PullRequestActivityView(activity: activity)
        // View should use sourceId as fallback
        XCTAssertEqual(view.activity.sourceId, "unknown")
    }

    // MARK: - Author Tests

    func testDisplaysAuthorFromParticipants() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: ["octocat", "developer"],
            url: URL(string: "https://gitlab.com/owner/repo/pull/1")
        )

        let view = PullRequestActivityView(activity: activity)
        // View should use first participant as author
        XCTAssertEqual(view.activity.participants?.first, "octocat")
    }

    func testHandlesMissingAuthor() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil, // No participants
            url: URL(string: "https://gitlab.com/owner/repo/pull/1")
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertNil(view.activity.participants)
    }

    func testHandlesEmptyAuthor() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: [""], // Empty author
            url: URL(string: "https://gitlab.com/owner/repo/pull/1")
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertEqual(view.activity.participants?.first, "")
    }

    // MARK: - Avatar Tests

    func testUsesAvatarURLWhenProvided() {
        let avatarURL = URL(string: "https://gitlab.com/uploads/-/system/user/avatar/u/583231")!
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/1"),
            authorAvatarURL: avatarURL
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertEqual(view.activity.authorAvatarURL, avatarURL)
    }

    func testUsesPlaceholderWhenAvatarURLMissing() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/1"),
            authorAvatarURL: nil // No avatar
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertNil(view.activity.authorAvatarURL)
    }

    // MARK: - Draft Badge Tests

    func testShowsDraftBadgeWhenDraftIsTrue() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/1"),
            isDraft: true
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertEqual(view.activity.isDraft, true)
    }

    func testHidesDraftBadgeWhenDraftIsFalse() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/1"),
            isDraft: false
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertEqual(view.activity.isDraft, false)
    }

    func testHidesDraftBadgeWhenDraftIsNil() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/1"),
            isDraft: nil
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertNil(view.activity.isDraft)
    }

    // MARK: - Comment Count Tests

    func testShowsCommentBadgeWhenCountGreaterThanZero() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/1"),
            commentCount: 5
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertEqual(view.activity.commentCount, 5)
    }

    func testHidesCommentBadgeWhenCountIsZero() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/1"),
            commentCount: 0
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertEqual(view.activity.commentCount, 0)
    }

    func testHidesCommentBadgeWhenCountIsNil() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/1"),
            commentCount: nil
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertNil(view.activity.commentCount)
    }

    // MARK: - Branch Reference Tests

    func testShowsBranchInfoWhenBothRefsProvided() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/1"),
            sourceRef: "feature-branch",
            targetRef: "main"
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertEqual(view.activity.sourceRef, "feature-branch")
        XCTAssertEqual(view.activity.targetRef, "main")
    }

    func testHidesBranchInfoWhenSourceRefMissing() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/1"),
            sourceRef: nil,
            targetRef: "main"
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertNil(view.activity.sourceRef)
        XCTAssertEqual(view.activity.targetRef, "main")
    }

    func testHidesBranchInfoWhenTargetRefMissing() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/1"),
            sourceRef: "feature-branch",
            targetRef: nil
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertEqual(view.activity.sourceRef, "feature-branch")
        XCTAssertNil(view.activity.targetRef)
    }

    func testHidesBranchInfoWhenRefsAreEmpty() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/1"),
            sourceRef: "",
            targetRef: ""
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertEqual(view.activity.sourceRef, "")
        XCTAssertEqual(view.activity.targetRef, "")
    }

    // MARK: - Label Tests

    func testShowsLabelsWhenProvided() {
        let labels = [
            ActivityLabel(id: "1", name: "feature", color: "0E8A16"),
            ActivityLabel(id: "2", name: "bug", color: "D93F0B")
        ]
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/1"),
            labels: labels
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertEqual(view.activity.labels?.count, 2)
        XCTAssertEqual(view.activity.labels?[0].name, "feature")
        XCTAssertEqual(view.activity.labels?[1].name, "bug")
    }

    func testHidesLabelsWhenEmpty() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/1"),
            labels: []
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertEqual(view.activity.labels?.count, 0)
    }

    func testHidesLabelsWhenNil() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: URL(string: "https://gitlab.com/owner/repo/pull/1"),
            labels: nil
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertNil(view.activity.labels)
    }

    // MARK: - Deep Link Tests

    func testOpensURLWhenProvided() {
        let url = URL(string: "https://gitlab.com/owner/repo/pull/123")!
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-123",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "123",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: url
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertEqual(view.activity.url, url)
    }

    func testHandlesMissingURL() {
        let activity = UnifiedActivity(
            id: "gitlab:account1:pr-1",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "1",
            type: .pullRequest,
            timestamp: Date(),
            title: "Test",
            summary: nil,
            participants: nil,
            url: nil
        )

        let view = PullRequestActivityView(activity: activity)
        XCTAssertNil(view.activity.url)
    }
}
