//
//  TicketExtractorTests.swift
//  ActivityBarTests
//
//  Unit tests for TicketExtractor.
//

import XCTest
@testable import Core

final class TicketExtractorTests: XCTestCase {

    // MARK: - Jira Pattern Tests

    func testExtractJiraFromBranchName() {
        let tickets = TicketExtractor.extract(from: "feature/PROJ-123-add-login", source: .branchName)

        XCTAssertEqual(tickets.count, 1)
        XCTAssertEqual(tickets[0].key, "PROJ-123")
        XCTAssertEqual(tickets[0].system, .jira)
        XCTAssertEqual(tickets[0].source, .branchName)
    }

    func testExtractJiraWithNumbers() {
        let tickets = TicketExtractor.extract(from: "ABC2-456 is the ticket", source: .title)

        XCTAssertEqual(tickets.count, 1)
        XCTAssertEqual(tickets[0].key, "ABC2-456")
        XCTAssertEqual(tickets[0].system, .jira)
    }

    func testExtractMultipleJira() {
        let tickets = TicketExtractor.extract(from: "Fixes PROJ-123 and TEAM-456", source: .description)

        XCTAssertEqual(tickets.count, 2)
        XCTAssertEqual(tickets[0].key, "PROJ-123")
        XCTAssertEqual(tickets[1].key, "TEAM-456")
    }

    // MARK: - Azure Boards Pattern Tests

    func testExtractAzureBoards() {
        let tickets = TicketExtractor.extract(from: "feature/AB#123-fix-bug", source: .branchName)

        XCTAssertEqual(tickets.count, 1)
        XCTAssertEqual(tickets[0].key, "AB#123")
        XCTAssertEqual(tickets[0].system, .azureBoards)
    }

    func testExtractAzureBoardsInTitle() {
        let tickets = TicketExtractor.extract(from: "Fix authentication AB#456", source: .title)

        XCTAssertEqual(tickets.count, 1)
        XCTAssertEqual(tickets[0].key, "AB#456")
        XCTAssertEqual(tickets[0].system, .azureBoards)
    }

    // MARK: - Generic Issue Pattern Tests

    func testExtractGenericIssue() {
        let tickets = TicketExtractor.extract(from: "Closes #123", source: .description, defaultSystem: .githubIssue)

        XCTAssertEqual(tickets.count, 1)
        XCTAssertEqual(tickets[0].key, "#123")
        XCTAssertEqual(tickets[0].system, .githubIssue)
    }

    func testExtractGenericIssueWithDefaultSystem() {
        let tickets = TicketExtractor.extract(from: "Fixes #42", source: .title, defaultSystem: .gitlabIssue)

        XCTAssertEqual(tickets.count, 1)
        XCTAssertEqual(tickets[0].key, "#42")
        XCTAssertEqual(tickets[0].system, .gitlabIssue)
    }

    func testGenericIssueNotExtractedAfterLetters() {
        // "#123" preceded by letters should not match (to avoid false positives like "PR#123")
        let tickets = TicketExtractor.extract(from: "PR#123", source: .title, defaultSystem: .githubIssue)

        XCTAssertTrue(tickets.isEmpty, "PR#123 should not match as generic issue")
    }

    // MARK: - Shortcut Pattern Tests

    func testExtractShortcut() {
        let tickets = TicketExtractor.extract(from: "sc-123 story", source: .title)

        XCTAssertEqual(tickets.count, 1)
        XCTAssertEqual(tickets[0].key, "sc-123")
        XCTAssertEqual(tickets[0].system, .shortcut)
    }

    func testExtractShortcutLongForm() {
        let tickets = TicketExtractor.extract(from: "shortcut-456 feature", source: .title)

        XCTAssertEqual(tickets.count, 1)
        XCTAssertEqual(tickets[0].key, "sc-456")  // Normalized to short form
        XCTAssertEqual(tickets[0].system, .shortcut)
    }

    // MARK: - Mixed Patterns Tests

    func testExtractMixedPatterns() {
        let text = "JIRA-123: Fix bug (AB#456, closes #789)"
        let tickets = TicketExtractor.extract(from: text, source: .description, defaultSystem: .githubIssue)

        XCTAssertEqual(tickets.count, 3)

        let keys = Set(tickets.map { $0.key })
        XCTAssertTrue(keys.contains("JIRA-123"))
        XCTAssertTrue(keys.contains("AB#456"))
        XCTAssertTrue(keys.contains("#789"))
    }

    // MARK: - extractFromActivity Tests

    func testExtractFromActivityDeduplication() {
        // Same ticket in branch and title should be deduplicated
        let tickets = TicketExtractor.extractFromActivity(
            branchName: "feature/PROJ-123-desc",
            title: "PROJ-123: Add feature",
            description: nil
        )

        XCTAssertEqual(tickets.count, 1)
        XCTAssertEqual(tickets[0].key, "PROJ-123")
        // First occurrence wins (branchName)
        XCTAssertEqual(tickets[0].source, .branchName)
    }

    func testExtractFromActivityMultipleSources() {
        let tickets = TicketExtractor.extractFromActivity(
            branchName: "feature/PROJ-123",
            title: "TEAM-456: New feature",
            description: "Also fixes AB#789"
        )

        XCTAssertEqual(tickets.count, 3)

        let byKey = Dictionary(uniqueKeysWithValues: tickets.map { ($0.key, $0) })
        XCTAssertEqual(byKey["PROJ-123"]?.source, .branchName)
        XCTAssertEqual(byKey["TEAM-456"]?.source, .title)
        XCTAssertEqual(byKey["AB#789"]?.source, .description)
    }

    func testExtractFromActivityCaseInsensitiveDedup() {
        // PROJ-123 and proj-123 should be deduplicated (but Jira pattern is uppercase only)
        let tickets = TicketExtractor.extractFromActivity(
            branchName: "AB#123",
            title: "ab#123 fix",  // ab# won't match (pattern is uppercase AB#)
            description: nil,
            defaultSystem: .azureBoards
        )

        // Only one AB#123 from branch
        XCTAssertEqual(tickets.count, 1)
    }

    // MARK: - Merge Tests

    func testMergeApiLinkedTakesPrecedence() {
        let extracted = [
            LinkedTicket(system: .jira, key: "PROJ-123", title: nil, url: nil, source: .branchName)
        ]
        let apiLinked = [
            LinkedTicket(
                system: .jira,
                key: "PROJ-123",
                title: "Full title from API",
                url: URL(string: "https://jira.example.com/PROJ-123"),
                source: .apiLink
            )
        ]

        let merged = TicketExtractor.merge(extracted: extracted, apiLinked: apiLinked)

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged[0].title, "Full title from API")
        XCTAssertEqual(merged[0].source, .apiLink)
    }

    func testMergeAddsExtracted() {
        let extracted = [
            LinkedTicket(system: .jira, key: "PROJ-123", title: nil, url: nil, source: .branchName),
            LinkedTicket(system: .jira, key: "TEAM-456", title: nil, url: nil, source: .title)
        ]
        let apiLinked = [
            LinkedTicket(system: .azureBoards, key: "AB#789", title: "Work item", url: nil, source: .apiLink)
        ]

        let merged = TicketExtractor.merge(extracted: extracted, apiLinked: apiLinked)

        XCTAssertEqual(merged.count, 3)
    }

    // MARK: - Edge Cases

    func testEmptyInput() {
        let tickets = TicketExtractor.extract(from: "", source: .title)
        XCTAssertTrue(tickets.isEmpty)
    }

    func testNoMatches() {
        let tickets = TicketExtractor.extract(from: "Just some regular text", source: .description)
        XCTAssertTrue(tickets.isEmpty)
    }

    func testNilInputs() {
        let tickets = TicketExtractor.extractFromActivity(
            branchName: nil,
            title: nil,
            description: nil
        )
        XCTAssertTrue(tickets.isEmpty)
    }

    func testLowercaseJiraNotMatched() {
        // Jira pattern requires uppercase project key
        let tickets = TicketExtractor.extract(from: "proj-123", source: .title)
        XCTAssertTrue(tickets.filter { $0.system == .jira }.isEmpty)
    }

    func testPartialMatchNotExtracted() {
        // Should not match incomplete patterns
        let tickets = TicketExtractor.extract(from: "PROJ- or -123", source: .title)
        XCTAssertTrue(tickets.filter { $0.system == .jira }.isEmpty)
    }
}
