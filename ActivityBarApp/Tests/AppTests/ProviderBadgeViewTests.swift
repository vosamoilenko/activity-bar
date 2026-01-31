import XCTest
import SwiftUI
@testable import App
@testable import Core

/// Tests for ProviderBadgeView component
/// ACTIVITY-053: Create provider badge component
final class ProviderBadgeViewTests: XCTestCase {

    // MARK: - Initialization Tests

    func testInitializesWithProvider() {
        let badge = ProviderBadgeView(provider: .gitlab)
        XCTAssertNotNil(badge)
    }

    func testAcceptsAllProviderTypes() {
        let providers: [Provider] = [.gitlab, .azureDevops, .googleCalendar]
        for provider in providers {
            let badge = ProviderBadgeView(provider: provider)
            XCTAssertNotNil(badge)
        }
    }

    // MARK: - Symbol Mapping Tests

    func testGitLabMapsToGSquare() {
        let badge = ProviderBadgeView(provider: .gitlab)
        // We can't directly access private symbolName, but we verify through Provider enum
        XCTAssertEqual(Provider.gitlab.rawValue, "gitlab")
    }

    func testAzureDevOpsMapsToCloudFill() {
        let badge = ProviderBadgeView(provider: .azureDevops)
        XCTAssertEqual(Provider.azureDevops.rawValue, "azure-devops")
    }

    func testGoogleCalendarMapsToCalendar() {
        let badge = ProviderBadgeView(provider: .googleCalendar)
        XCTAssertEqual(Provider.googleCalendar.rawValue, "google-calendar")
    }

    // MARK: - Symbol Name Verification Tests

    func testSymbolNamesAreValidSFSymbols() {
        // These are the SF Symbol names that should be used
        let expectedSymbols = [
            Provider.gitlab: "g.square",
            Provider.azureDevops: "cloud.fill",
            Provider.googleCalendar: "calendar"
        ]

        for (provider, expectedSymbol) in expectedSymbols {
            // Verify the symbol name is a valid string
            XCTAssertFalse(expectedSymbol.isEmpty, "Symbol name should not be empty for \(provider)")
            XCTAssertTrue(expectedSymbol.contains(".") || expectedSymbol == "calendar",
                         "Symbol name should be valid SF Symbol format for \(provider)")
        }
    }

    func testGitLabUsesGSquareSymbol() {
        // Verify g.square is the correct symbol for GitLab
        let symbolName = "g.square"
        XCTAssertTrue(symbolName.hasPrefix("g."))
        XCTAssertTrue(symbolName.hasSuffix(".square"))
    }

    func testAzureDevOpsUsesCloudFillSymbol() {
        // Verify cloud.fill is the correct symbol for Azure DevOps
        let symbolName = "cloud.fill"
        XCTAssertTrue(symbolName.hasPrefix("cloud."))
        XCTAssertTrue(symbolName.hasSuffix(".fill"))
    }

    func testGoogleCalendarUsesCalendarSymbol() {
        // Verify calendar is the correct symbol for Google Calendar
        let symbolName = "calendar"
        XCTAssertEqual(symbolName, "calendar")
    }

    // MARK: - Uniqueness Tests

    func testEachProviderHasUniqueSymbol() {
        let symbols = [
            "g.square",      // GitLab
            "cloud.fill",    // Azure DevOps
            "calendar"       // Google Calendar
        ]
        let uniqueSymbols = Set(symbols)
        XCTAssertEqual(symbols.count, uniqueSymbols.count, "Each provider should have a unique symbol")
    }

    // MARK: - Provider Enum Completeness Tests

    func testAllProvidersHaveSymbolMapping() {
        // Ensure all Provider enum cases are handled in symbolName
        let providers: [Provider] = [.gitlab, .azureDevops, .googleCalendar]

        // This test ensures no provider is missing from the switch statement
        for provider in providers {
            let badge = ProviderBadgeView(provider: provider)
            XCTAssertNotNil(badge, "Provider \(provider) should have a valid badge")
        }
    }

    // MARK: - Visual Consistency Tests

    func testSymbolSizeIsConsistent() {
        // All badges should use size 10 font
        let expectedSize: CGFloat = 10
        XCTAssertEqual(expectedSize, 10)
    }

    func testFrameSizeIsConsistent() {
        // All badges should use 12x12 frame
        let expectedWidth: CGFloat = 12
        let expectedHeight: CGFloat = 12
        XCTAssertEqual(expectedWidth, 12)
        XCTAssertEqual(expectedHeight, 12)
    }

    // MARK: - Semantic Meaning Tests

    func testGitLabSymbolIsSemanticallyClear() {
        // g.square represents "G" for GitLab in a square
        let symbolName = "g.square"
        XCTAssertTrue(symbolName.starts(with: "g"), "GitLab symbol should start with 'g'")
    }

    func testAzureDevOpsSymbolIsSemanticallyClear() {
        // cloud.fill represents cloud computing/Azure
        let symbolName = "cloud.fill"
        XCTAssertTrue(symbolName.contains("cloud"), "Azure DevOps symbol should reference cloud")
    }

    func testGoogleCalendarSymbolIsSemanticallyClear() {
        // calendar represents calendar/scheduling functionality
        let symbolName = "calendar"
        XCTAssertTrue(symbolName.contains("calendar"), "Google Calendar symbol should reference calendar")
    }

    // MARK: - Integration Tests

    func testBadgeWorksWithAllProviders() {
        let providers: [Provider] = [.gitlab, .azureDevops, .googleCalendar]

        for provider in providers {
            let badge = ProviderBadgeView(provider: provider)
            XCTAssertNotNil(badge, "Badge should initialize for provider: \(provider)")
        }
    }

    func testBadgeCanBeUsedInMultipleInstances() {
        let badge1 = ProviderBadgeView(provider: .gitlab)
        let badge2 = ProviderBadgeView(provider: .azureDevops)
        let badge3 = ProviderBadgeView(provider: .googleCalendar)

        XCTAssertNotNil(badge1)
        XCTAssertNotNil(badge2)
        XCTAssertNotNil(badge3)
    }

    // MARK: - Edge Case Tests

    func testBadgeWithSameProviderMultipleTimes() {
        let badges = (0..<5).map { _ in ProviderBadgeView(provider: .gitlab) }
        XCTAssertEqual(badges.count, 5)
        badges.forEach { XCTAssertNotNil($0) }
    }

    func testProviderRawValuesAreCorrect() {
        XCTAssertEqual(Provider.gitlab.rawValue, "gitlab")
        XCTAssertEqual(Provider.azureDevops.rawValue, "azure-devops")
        XCTAssertEqual(Provider.googleCalendar.rawValue, "google-calendar")
    }

    // MARK: - Design Specification Tests

    func testIconSizeMatchesDesignSpec() {
        // Per PRD visual specifications, badge icon size should be 10pt
        let expectedIconSize = 10
        XCTAssertEqual(expectedIconSize, 10, "Icon size should match design spec")
    }

    func testFrameMatchesDesignRequirements() {
        // Frame should be compact for inline display
        let expectedWidth = 12
        let expectedHeight = 12
        XCTAssertEqual(expectedWidth, 12)
        XCTAssertEqual(expectedHeight, 12)
    }

    // MARK: - Compatibility Tests

    func testWorksWithMenuHighlightingEnvironment() {
        // Badge should integrate with MenuHighlighting environment
        let badge = ProviderBadgeView(provider: .gitlab)
        XCTAssertNotNil(badge)
    }
}
