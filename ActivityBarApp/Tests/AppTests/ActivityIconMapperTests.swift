import XCTest
import Core
@testable import App

final class ActivityIconMapperTests: XCTestCase {
    // MARK: - Individual ActivityType Mappings

    func testCommitIcon() {
        let symbol = ActivityIconMapper.symbolName(for: .commit)
        XCTAssertEqual(symbol, "arrow.up.circle", "Commit should map to arrow.up.circle")
    }

    func testPullRequestIcon() {
        let symbol = ActivityIconMapper.symbolName(for: .pullRequest)
        XCTAssertEqual(symbol, "arrow.triangle.branch", "Pull request should map to arrow.triangle.branch")
    }

    func testIssueIcon() {
        let symbol = ActivityIconMapper.symbolName(for: .issue)
        XCTAssertEqual(symbol, "exclamationmark.circle", "Issue should map to exclamationmark.circle")
    }

    func testIssueCommentIcon() {
        let symbol = ActivityIconMapper.symbolName(for: .issueComment)
        XCTAssertEqual(symbol, "text.bubble", "Issue comment should map to text.bubble")
    }

    func testCodeReviewIcon() {
        let symbol = ActivityIconMapper.symbolName(for: .codeReview)
        XCTAssertEqual(symbol, "checkmark.bubble", "Code review should map to checkmark.bubble")
    }

    func testMeetingIcon() {
        let symbol = ActivityIconMapper.symbolName(for: .meeting)
        XCTAssertEqual(symbol, "calendar", "Meeting should map to calendar")
    }

    func testWorkItemIcon() {
        let symbol = ActivityIconMapper.symbolName(for: .workItem)
        XCTAssertEqual(symbol, "checklist", "Work item should map to checklist")
    }

    func testDeploymentIcon() {
        let symbol = ActivityIconMapper.symbolName(for: .deployment)
        XCTAssertEqual(symbol, "shippingbox", "Deployment should map to shippingbox")
    }

    func testReleaseIcon() {
        let symbol = ActivityIconMapper.symbolName(for: .release)
        XCTAssertEqual(symbol, "tag", "Release should map to tag")
    }

    func testWikiIcon() {
        let symbol = ActivityIconMapper.symbolName(for: .wiki)
        XCTAssertEqual(symbol, "book", "Wiki should map to book")
    }

    func testOtherIcon() {
        let symbol = ActivityIconMapper.symbolName(for: .other)
        XCTAssertEqual(symbol, "clock", "Other should map to clock")
    }

    // MARK: - Mapping Completeness

    func testAllActivityTypesHaveMappings() {
        // Verify all known ActivityType cases have mappings
        let activityTypes: [ActivityType] = [
            .commit, .pullRequest, .issue, .issueComment,
            .codeReview, .meeting, .workItem, .deployment,
            .release, .wiki, .other
        ]

        for activityType in activityTypes {
            let symbol = ActivityIconMapper.symbolName(for: activityType)
            XCTAssertFalse(symbol.isEmpty, "ActivityType \(activityType) should have a non-empty symbol")
        }
    }

    func testAllSymbolNamesAreValidSFSymbols() {
        // Verify all returned symbol names are valid SF Symbol format
        let activityTypes: [ActivityType] = [
            .commit, .pullRequest, .issue, .issueComment,
            .codeReview, .meeting, .workItem, .deployment,
            .release, .wiki, .other
        ]

        for activityType in activityTypes {
            let symbol = ActivityIconMapper.symbolName(for: activityType)
            // SF Symbol names use lowercase with dots/underscores
            XCTAssertTrue(
                symbol.allSatisfy { $0.isLowercase || $0 == "." || $0.isNumber },
                "Symbol \(symbol) for \(activityType) should be lowercase with dots"
            )
        }
    }

    // MARK: - Semantic Verification

    func testCommitSymbolIsSemanticallyClear() {
        // Commit icon should indicate "upload" or "push" action
        let symbol = ActivityIconMapper.symbolName(for: .commit)
        XCTAssertTrue(symbol.contains("arrow"), "Commit symbol should contain 'arrow' for direction")
        XCTAssertTrue(symbol.contains("up"), "Commit symbol should contain 'up' for push action")
    }

    func testPullRequestSymbolIsSemanticallyClear() {
        // PR icon should indicate branching/merging
        let symbol = ActivityIconMapper.symbolName(for: .pullRequest)
        XCTAssertTrue(symbol.contains("branch"), "PR symbol should contain 'branch' for git branching")
    }

    func testIssueSymbolIsSemanticallyClear() {
        // Issue icon should indicate attention/problem
        let symbol = ActivityIconMapper.symbolName(for: .issue)
        XCTAssertTrue(symbol.contains("exclamation"), "Issue symbol should contain 'exclamation' for attention")
    }

    func testCommentSymbolsUseBubbleMotif() {
        // Both issue comments and review comments use bubble icons
        let issueCommentSymbol = ActivityIconMapper.symbolName(for: .issueComment)
        let codeReviewSymbol = ActivityIconMapper.symbolName(for: .codeReview)

        XCTAssertTrue(issueCommentSymbol.contains("bubble"), "Issue comment should use bubble icon")
        XCTAssertTrue(codeReviewSymbol.contains("bubble"), "Code review should use bubble icon")
    }

    // MARK: - Uniqueness

    func testAllSymbolsAreDistinct() {
        let activityTypes: [ActivityType] = [
            .commit, .pullRequest, .issue, .issueComment,
            .codeReview, .meeting, .workItem, .deployment,
            .release, .wiki, .other
        ]

        let symbols = activityTypes.map { ActivityIconMapper.symbolName(for: $0) }
        let uniqueSymbols = Set(symbols)

        // Note: issueComment and codeReview both use "text.bubble" and "checkmark.bubble" respectively
        // This is intentional as they're both comment-related, but they should be different
        XCTAssertEqual(uniqueSymbols.count, symbols.count, "All activity types should have unique symbols")
    }

    // MARK: - Integration with UnifiedActivity

    func testMappingWorksWithUnifiedActivity() {
        let activity = UnifiedActivity(
            id: "test-1",
            provider: .gitlab,
            accountId: "acc-1",
            sourceId: "src-1",
            type: .pullRequest,
            timestamp: Date()
        )

        let symbol = ActivityIconMapper.symbolName(for: activity.type)
        XCTAssertEqual(symbol, "arrow.triangle.branch", "Should work with UnifiedActivity.type")
    }

    func testMappingWorksWithAllProviders() {
        // Verify mapping is provider-agnostic
        let providers: [Provider] = [.gitlab, .gitlab, .azureDevops, .googleCalendar]

        for provider in providers {
            let activity = UnifiedActivity(
                id: "test-\(provider.rawValue)",
                provider: provider,
                accountId: "acc-1",
                sourceId: "src-1",
                type: .commit,
                timestamp: Date()
            )

            let symbol = ActivityIconMapper.symbolName(for: activity.type)
            XCTAssertEqual(symbol, "arrow.up.circle", "Mapping should be consistent across providers")
        }
    }
}
