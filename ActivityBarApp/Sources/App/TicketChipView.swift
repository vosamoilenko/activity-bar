//
//  TicketChipView.swift
//  ActivityBar
//
//  Displays linked tickets as clickable chips in a flow layout.
//

import SwiftUI
import AppKit
import Core

/// Displays linked tickets as a flow layout of clickable chips
struct TicketChipsView: View {
    let tickets: [LinkedTicket]
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        FlowLayout(itemSpacing: 6, lineSpacing: 4) {
            ForEach(tickets, id: \.id) { ticket in
                TicketChipView(ticket: ticket, isHighlighted: isHighlighted)
            }
        }
    }
}

/// Individual ticket chip with icon, key, and click handler
struct TicketChipView: View {
    let ticket: LinkedTicket
    let isHighlighted: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let baseColor = ticketColor
        let fillOpacity: CGFloat = 0.16
        let strokeOpacity: CGFloat = colorScheme == .dark ? 0.45 : 0.85

        // Adaptive colors based on highlight state
        let fill = isHighlighted ? .white.opacity(0.16) : baseColor.opacity(fillOpacity)
        let stroke = isHighlighted ? .white.opacity(0.30) : baseColor.opacity(strokeOpacity)
        let iconColor = isHighlighted ? .white.opacity(0.85) : baseColor
        let textColor = isHighlighted ? Color.white.opacity(0.95) : Color(nsColor: .labelColor)

        Button(action: openTicket) {
            HStack(spacing: 4) {
                Image(systemName: ticket.system.iconName)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(iconColor)

                Text(ticket.key)
                    .font(.caption2.weight(.semibold).monospaced())
                    .foregroundStyle(textColor)
                    .lineLimit(1)
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(fill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(stroke, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .help(tooltipText)
    }

    // MARK: - Computed Properties

    private var ticketColor: Color {
        Color(nsColor: LabelColorParser.nsColor(from: ticket.system.color) ?? .systemBlue)
    }

    private var tooltipText: String {
        var parts: [String] = [ticket.system.displayName]
        if let title = ticket.title, !title.isEmpty {
            parts.append(title)
        }
        parts.append("Found in: \(ticket.source.displayName)")
        return parts.joined(separator: "\n")
    }

    // MARK: - Actions

    private func openTicket() {
        guard let url = ticket.url else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Previews

#Preview("Ticket Chips - Various Systems") {
    let tickets = [
        LinkedTicket(system: .jira, key: "PROJ-123", title: "Fix authentication bug", url: URL(string: "https://jira.example.com/browse/PROJ-123"), source: .branchName),
        LinkedTicket(system: .azureBoards, key: "AB#456", title: "Add user profile page", url: URL(string: "https://dev.azure.com/org/project/_workitems/edit/456"), source: .apiLink),
        LinkedTicket(system: .gitlabIssue, key: "#789", title: "Memory leak in parser", url: URL(string: "https://gitlab.com/org/repo/-/issues/789"), source: .title),
        LinkedTicket(system: .linear, key: "ENG-42", title: nil, url: nil, source: .description),
    ]

    return VStack(spacing: 16) {
        TicketChipsView(tickets: tickets)
            .environment(\.menuItemHighlighted, false)
            .padding()

        TicketChipsView(tickets: tickets)
            .environment(\.menuItemHighlighted, true)
            .padding()
            .background(Color.accentColor)
    }
    .frame(width: 350)
}

#Preview("Ticket Chips - Dark Mode") {
    let tickets = [
        LinkedTicket(system: .jira, key: "PROJ-123", title: "Fix bug", url: nil, source: .branchName),
        LinkedTicket(system: .githubIssue, key: "#42", title: nil, url: nil, source: .title),
        LinkedTicket(system: .shortcut, key: "sc-999", title: "Feature request", url: nil, source: .description),
    ]

    return VStack(spacing: 16) {
        TicketChipsView(tickets: tickets)
            .environment(\.menuItemHighlighted, false)
            .padding()

        TicketChipsView(tickets: tickets)
            .environment(\.menuItemHighlighted, true)
            .padding()
            .background(Color.accentColor)
    }
    .frame(width: 300)
    .preferredColorScheme(.dark)
}

#Preview("Single Ticket") {
    TicketChipView(
        ticket: LinkedTicket(
            system: .jira,
            key: "TICKET-42",
            title: "Important fix for critical issue",
            url: URL(string: "https://jira.example.com/browse/TICKET-42"),
            source: .branchName
        ),
        isHighlighted: false
    )
    .padding()
}
