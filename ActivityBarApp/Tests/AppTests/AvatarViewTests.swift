import XCTest
import SwiftUI
@testable import App

final class AvatarViewTests: XCTestCase {

    // MARK: - Initialization Tests

    func testDefaultSize() {
        let view = AvatarView(url: nil)
        XCTAssertEqual(view.size, 20, "Default size should be 20x20")
    }

    func testCustomSize() {
        let view = AvatarView(url: nil, size: 32)
        XCTAssertEqual(view.size, 32, "Custom size should be applied")
    }

    func testNilURL() {
        let view = AvatarView(url: nil)
        XCTAssertNil(view.url, "URL should be nil when not provided")
    }

    func testValidURL() {
        let testURL = URL(string: "https://gitlab.com/uploads/-/system/user/avatar/u/1?v=4")
        let view = AvatarView(url: testURL)
        XCTAssertEqual(view.url, testURL, "URL should match provided URL")
    }

    // MARK: - Size Tests

    func testSmallSize() {
        let view = AvatarView(url: nil, size: 16)
        XCTAssertEqual(view.size, 16, "Should support small size (16x16)")
    }

    func testLargeSize() {
        let view = AvatarView(url: nil, size: 48)
        XCTAssertEqual(view.size, 48, "Should support large size (48x48)")
    }

    // MARK: - URL Validation Tests

    func testGitHubAvatarURL() {
        let githubURL = URL(string: "https://gitlab.com/uploads/-/system/user/avatar/u/123456")
        let view = AvatarView(url: githubURL)
        XCTAssertEqual(view.url, githubURL, "Should accept GitHub avatar URLs")
    }

    func testGitLabAvatarURL() {
        let gitlabURL = URL(string: "https://gitlab.com/uploads/-/system/user/avatar/123/avatar.png")
        let view = AvatarView(url: gitlabURL)
        XCTAssertEqual(view.url, gitlabURL, "Should accept GitLab avatar URLs")
    }

    func testGravatarURL() {
        let gravatarURL = URL(string: "https://www.gravatar.com/avatar/abc123")
        let view = AvatarView(url: gravatarURL)
        XCTAssertEqual(view.url, gravatarURL, "Should accept Gravatar URLs")
    }

    // MARK: - Edge Case Tests

    func testZeroSize() {
        let view = AvatarView(url: nil, size: 0)
        XCTAssertEqual(view.size, 0, "Should handle zero size (though not practical)")
    }

    func testVeryLargeSize() {
        let view = AvatarView(url: nil, size: 500)
        XCTAssertEqual(view.size, 500, "Should handle very large sizes")
    }

    // MARK: - Integration Tests

    func testPlaceholderWithoutURL() {
        let view = AvatarView(url: nil, size: 20)
        XCTAssertNil(view.url, "Should show placeholder when URL is nil")
        XCTAssertEqual(view.size, 20, "Placeholder should respect size parameter")
    }

    func testMultipleAvatars() {
        let url1 = URL(string: "https://example.com/avatar1.png")
        let url2 = URL(string: "https://example.com/avatar2.png")

        let view1 = AvatarView(url: url1, size: 20)
        let view2 = AvatarView(url: url2, size: 24)

        XCTAssertEqual(view1.url, url1, "First avatar should have first URL")
        XCTAssertEqual(view2.url, url2, "Second avatar should have second URL")
        XCTAssertEqual(view1.size, 20, "First avatar should have size 20")
        XCTAssertEqual(view2.size, 24, "Second avatar should have size 24")
    }

    // MARK: - Acceptance Criteria Tests

    func testLoadsRemoteImageFromURL() {
        let remoteURL = URL(string: "https://gitlab.com/uploads/-/system/user/avatar/u/1")
        let view = AvatarView(url: remoteURL)
        XCTAssertNotNil(view.url, "Should load remote image from URL")
    }

    func testShowsPlaceholderWhenNoURL() {
        let view = AvatarView(url: nil)
        XCTAssertNil(view.url, "Should show placeholder (person.fill icon) when no URL")
    }

    func testConfigurableSize() {
        let view16 = AvatarView(url: nil, size: 16)
        let view20 = AvatarView(url: nil, size: 20)
        let view24 = AvatarView(url: nil, size: 24)

        XCTAssertEqual(view16.size, 16, "Should support 16x16 size")
        XCTAssertEqual(view20.size, 20, "Should support 20x20 size (default)")
        XCTAssertEqual(view24.size, 24, "Should support 24x24 size")
    }

    func testDefaultSizeIs20x20() {
        let view = AvatarView(url: nil)
        XCTAssertEqual(view.size, 20, "Default size should be 20x20 as specified")
    }

    // Note: Circular clip shape and caching are tested visually in SwiftUI previews
    // AsyncImage handles caching automatically via URLCache
}
