//
//  TicketExtractor.swift
//  ActivityBar
//
//  Extracts ticket/work item references from text using regex patterns.
//

import Foundation

/// Extracts ticket/work item references from text (branch names, titles, descriptions)
public enum TicketExtractor {

    // MARK: - Pattern Definitions

    /// Compiled regex pattern with associated ticket system
    private struct PatternDef {
        let regex: NSRegularExpression
        let system: TicketSystem
        let keyTransform: (String) -> String  // Transform matched text to key format

        init(pattern: String, system: TicketSystem, keyTransform: @escaping (String) -> String = { $0 }) {
            // Force try since patterns are compile-time constants
            self.regex = try! NSRegularExpression(pattern: pattern, options: [])
            self.system = system
            self.keyTransform = keyTransform
        }
    }

    /// Pre-compiled regex patterns for each ticket system
    /// Order matters: more specific patterns should come first
    private static let patterns: [PatternDef] = [
        // Jira/YouTrack: PROJECT-123 (uppercase letters + dash + numbers)
        PatternDef(
            pattern: #"\b([A-Z][A-Z0-9]+-\d+)\b"#,
            system: .jira
        ),
        // Azure Boards: AB#123
        PatternDef(
            pattern: #"\bAB#(\d+)\b"#,
            system: .azureBoards,
            keyTransform: { "AB#\($0)" }
        ),
        // Azure Boards: Standalone 6-digit numbers in branch names (e.g., feat/717018-description)
        // Matches numbers with 5+ digits that follow a slash and are followed by dash or end
        PatternDef(
            pattern: #"(?<=/|_)(\d{5,})(?=-|_|$)"#,
            system: .azureBoards,
            keyTransform: { "AB#\($0)" }
        ),
        // Shortcut: sc-123 or shortcut-123
        PatternDef(
            pattern: #"\b(?:sc-|shortcut-)(\d+)\b"#,
            system: .shortcut,
            keyTransform: { "sc-\($0)" }
        ),
        // Linear: TEAM-123 pattern (similar to Jira but commonly 2-3 uppercase letters)
        // Note: Linear tickets follow same pattern as Jira, distinguishing requires context
    ]

    /// Pattern for generic issue references (#123)
    /// This is handled separately because it's context-dependent
    private static let genericIssuePattern = try! NSRegularExpression(
        pattern: #"(?<![A-Za-z])#(\d+)\b"#,
        options: []
    )

    // MARK: - Public API

    /// Extract tickets from a single text source
    /// - Parameters:
    ///   - text: The text to search for ticket references
    ///   - source: Where the text came from (branch, title, description, etc.)
    ///   - defaultSystem: The ticket system to use for generic #123 references
    /// - Returns: Array of extracted tickets (may contain duplicates if same key found multiple times)
    public static func extract(
        from text: String,
        source: TicketSource,
        defaultSystem: TicketSystem = .unknown
    ) -> [LinkedTicket] {
        guard !text.isEmpty else { return [] }

        var tickets: [LinkedTicket] = []
        let range = NSRange(text.startIndex..., in: text)

        // Try each pattern
        for patternDef in patterns {
            let matches = patternDef.regex.matches(in: text, options: [], range: range)
            for match in matches {
                // Get the captured group (or full match if no group)
                let captureRange = match.numberOfRanges > 1 ? match.range(at: 1) : match.range
                if let swiftRange = Range(captureRange, in: text) {
                    let captured = String(text[swiftRange])
                    let key = patternDef.keyTransform(captured)
                    tickets.append(LinkedTicket(
                        system: patternDef.system,
                        key: key,
                        title: nil,
                        url: nil,
                        source: source
                    ))
                }
            }
        }

        // Handle generic issue references (#123)
        let genericMatches = genericIssuePattern.matches(in: text, options: [], range: range)
        for match in genericMatches {
            if match.numberOfRanges > 1,
               let captureRange = Range(match.range(at: 1), in: text) {
                let number = String(text[captureRange])
                tickets.append(LinkedTicket(
                    system: defaultSystem,
                    key: "#\(number)",
                    title: nil,
                    url: nil,
                    source: source
                ))
            }
        }

        return tickets
    }

    /// Extract tickets from multiple sources with deduplication
    /// - Parameters:
    ///   - branchName: Branch name (e.g., "feature/PROJ-123-description")
    ///   - title: PR/MR/Issue title
    ///   - description: PR/MR/Issue description/body
    ///   - defaultSystem: The ticket system to use for generic #123 references
    /// - Returns: Deduplicated array of tickets, preserving first occurrence's source
    public static func extractFromActivity(
        branchName: String? = nil,
        title: String? = nil,
        description: String? = nil,
        defaultSystem: TicketSystem = .unknown
    ) -> [LinkedTicket] {
        var allTickets: [LinkedTicket] = []

        // Extract from each source (order matters for deduplication - first source wins)
        if let branch = branchName {
            allTickets.append(contentsOf: extract(from: branch, source: .branchName, defaultSystem: defaultSystem))
        }
        if let title = title {
            allTickets.append(contentsOf: extract(from: title, source: .title, defaultSystem: defaultSystem))
        }
        if let desc = description {
            allTickets.append(contentsOf: extract(from: desc, source: .description, defaultSystem: defaultSystem))
        }

        // Deduplicate by key (case-insensitive), keeping first occurrence
        return deduplicate(allTickets)
    }

    /// Merge extracted tickets with API-linked tickets, deduplicating
    /// - Parameters:
    ///   - extracted: Tickets extracted from text
    ///   - apiLinked: Tickets from API (e.g., Azure DevOps work item links)
    /// - Returns: Merged and deduplicated array
    public static func merge(
        extracted: [LinkedTicket],
        apiLinked: [LinkedTicket]
    ) -> [LinkedTicket] {
        // API-linked tickets take precedence (they have more metadata)
        var result = apiLinked
        let existingKeys = Set(apiLinked.map { $0.key.uppercased() })

        for ticket in extracted {
            if !existingKeys.contains(ticket.key.uppercased()) {
                result.append(ticket)
            }
        }

        return result
    }

    // MARK: - Private Helpers

    /// Deduplicate tickets by key, keeping first occurrence
    private static func deduplicate(_ tickets: [LinkedTicket]) -> [LinkedTicket] {
        var seen = Set<String>()
        var result: [LinkedTicket] = []

        for ticket in tickets {
            let normalizedKey = ticket.key.uppercased()
            if !seen.contains(normalizedKey) {
                seen.insert(normalizedKey)
                result.append(ticket)
            }
        }

        return result
    }
}
