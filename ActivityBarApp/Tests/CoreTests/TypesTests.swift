import XCTest
@testable import Core

final class TypesTests: XCTestCase {
    func testProviderCases() {
        XCTAssertEqual(Provider.gitlab.rawValue, "github")
        XCTAssertEqual(Provider.gitlab.rawValue, "gitlab")
        XCTAssertEqual(Provider.azureDevops.rawValue, "azure-devops")
        XCTAssertEqual(Provider.googleCalendar.rawValue, "google-calendar")
        XCTAssertEqual(Provider.allCases.count, 4)
    }

    func testActivityTypes() {
        XCTAssertEqual(ActivityType.commit.rawValue, "commit")
        XCTAssertEqual(ActivityType.pullRequest.rawValue, "pull_request")
        XCTAssertEqual(ActivityType.issue.rawValue, "issue")
        XCTAssertEqual(ActivityType.issueComment.rawValue, "issue_comment")
        XCTAssertEqual(ActivityType.codeReview.rawValue, "code_review")
        XCTAssertEqual(ActivityType.meeting.rawValue, "meeting")
        XCTAssertEqual(ActivityType.workItem.rawValue, "work_item")
    }

    func testUnifiedActivityCreation() {
        let activity = UnifiedActivity(
            id: "test-1",
            provider: .gitlab,
            accountId: "gitlab-personal",
            sourceId: "abc123",
            type: .commit,
            timestamp: Date(),
            title: "Test commit",
            summary: "A test commit message",
            participants: ["user1", "user2"],
            url: URL(string: "https://gitlab.com/test/repo/commit/abc123")
        )

        XCTAssertEqual(activity.id, "test-1")
        XCTAssertEqual(activity.provider, .gitlab)
        XCTAssertEqual(activity.accountId, "github-personal")
        XCTAssertEqual(activity.sourceId, "abc123")
        XCTAssertEqual(activity.type, .commit)
        XCTAssertEqual(activity.title, "Test commit")
        XCTAssertEqual(activity.participants?.count, 2)
        XCTAssertNotNil(activity.url)
    }

    func testHeatMapBucketCreation() {
        let bucket = HeatMapBucket(
            date: "2024-01-15",
            count: 10,
            breakdown: [.gitlab: 5, .gitlab: 3, .googleCalendar: 2]
        )

        XCTAssertEqual(bucket.id, "2024-01-15")
        XCTAssertEqual(bucket.date, "2024-01-15")
        XCTAssertEqual(bucket.count, 10)
        XCTAssertEqual(bucket.breakdown?[.gitlab], 5)
        XCTAssertEqual(bucket.breakdown?[.gitlab], 3)
        XCTAssertEqual(bucket.breakdown?[.googleCalendar], 2)
    }

    func testAccountCreation() {
        let account = Account(
            id: "github-work",
            provider: .gitlab,
            displayName: "Work GitHub",
            host: "gitlab.company.com",
            isEnabled: true
        )

        XCTAssertEqual(account.id, "github-work")
        XCTAssertEqual(account.provider, .gitlab)
        XCTAssertEqual(account.displayName, "Work GitHub")
        XCTAssertEqual(account.host, "gitlab.company.com")
        XCTAssertTrue(account.isEnabled)
    }

    func testAccountDefaultHost() {
        let account = Account(
            id: "github-personal",
            provider: .gitlab,
            displayName: "Personal"
        )

        XCTAssertNil(account.host)
        XCTAssertTrue(account.isEnabled)
    }

    func testUnifiedActivityCodable() throws {
        let activity = UnifiedActivity(
            id: "test-1",
            provider: .gitlab,
            accountId: "acc1",
            sourceId: "src1",
            type: .pullRequest,
            timestamp: Date(timeIntervalSince1970: 1700000000)
        )

        let encoder = JSONEncoder()
        let data = try encoder.encode(activity)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(UnifiedActivity.self, from: data)

        XCTAssertEqual(decoded.id, activity.id)
        XCTAssertEqual(decoded.provider, activity.provider)
        XCTAssertEqual(decoded.type, activity.type)
    }

    func testHeatMapBucketCodable() throws {
        let bucket = HeatMapBucket(date: "2024-01-15", count: 5)

        let encoder = JSONEncoder()
        let data = try encoder.encode(bucket)
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(HeatMapBucket.self, from: data)

        XCTAssertEqual(decoded.date, bucket.date)
        XCTAssertEqual(decoded.count, bucket.count)
    }
}
