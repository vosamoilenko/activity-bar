import SwiftUI
import Core

/// Enhanced issue activity view matching RepoBar's IssueMenuItemView design
///
/// Reference: RepoBar/Sources/RepoBar/Views/IssueMenuItemView.swift
struct IssueActivityView: View {
    let activity: UnifiedActivity
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.showEventAuthor) private var showEventAuthor

    var body: some View {
        RecentItemRowView(alignment: .top, onOpen: self.onOpen) {
            // Leading: avatar or issue-specific placeholder
            self.avatar
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                // Title: issue title
                if let title = activity.title {
                    Text(title)
                        .font(.callout.weight(.medium))
                        .foregroundStyle(MenuHighlightStyle.primary(isHighlighted))
                        .lineLimit(2)
                }

                // Author line (when showEventAuthor is enabled)
                if showEventAuthor, let participants = activity.participants, let author = participants.first {
                    Text("by \(author)")
                        .font(.caption)
                        .fontWeight(.medium)
                        .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                        .lineLimit(1)
                }

                // Metadata row: issue number, time, comment badge
                HStack(spacing: 6) {
                    // Issue number (#456, monospaced)
                    Text(issueNumber)
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                        .lineLimit(1)

                    // Relative time
                    Text(RelativeTimeFormatter.string(from: activity.timestamp))
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    // Comment count badge (if > 0)
                    if let commentCount = activity.commentCount, commentCount > 0 {
                        MenuStatBadge(label: nil, value: commentCount, systemImage: "text.bubble")
                    }
                }

                // Labels (if any)
                if let labels = activity.labels, !labels.isEmpty {
                    MenuLabelChipsView(labels: labels)
                }

                // Linked tickets (if any)
                if let tickets = activity.linkedTickets, !tickets.isEmpty {
                    TicketChipsView(tickets: tickets)
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var issueNumber: String {
        // sourceId should be the issue number for issues
        // Format: "#456"
        if activity.sourceId.allSatisfy(\.isNumber) {
            return "#\(activity.sourceId)"
        }

        // Fallback: try to extract number from URL
        if let urlString = activity.url?.absoluteString,
           let range = urlString.range(of: #"/issues/(\d+)"#, options: .regularExpression) {
            let match = urlString[range]
            if let numberRange = match.range(of: #"\d+"#, options: .regularExpression) {
                return "#\(match[numberRange])"
            }
        }

        // Last resort: use sourceId as-is
        return "#\(activity.sourceId)"
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = activity.authorAvatarURL {
            AvatarView(url: avatarURL, size: 20)
        } else {
            // Issue-specific placeholder: exclamationmark.circle icon
            Circle()
                .fill(Color(nsColor: .separatorColor))
                .overlay(
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                )
                .frame(width: 20, height: 20)
        }
    }

    private func onOpen() {
        guard let url = activity.url else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Previews

#Preview("Issue with Comments") {
    IssueActivityView(
        activity: UnifiedActivity(
            id: "gitlab:account1:issue-123",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "123",
            type: .issue,
            timestamp: Date().addingTimeInterval(-3600 * 2), // 2 hours ago
            title: "App crashes on startup when offline",
            summary: "Issue opened by user123",
            participants: ["user123"],
            url: URL(string: "https://gitlab.com/owner/repo/-/issues/123"),
            authorAvatarURL: URL(string: "https://secure.gravatar.com/avatar/123456"),
            labels: [
                ActivityLabel(id: "1", name: "bug", color: "D73A4A"),
                ActivityLabel(id: "2", name: "priority-high", color: "B60205")
            ],
            commentCount: 8
        )
    )
    .frame(width: 350)
    .padding()
}

#Preview("Issue without Comments") {
    IssueActivityView(
        activity: UnifiedActivity(
            id: "gitlab:account1:issue-456",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "456",
            type: .issue,
            timestamp: Date().addingTimeInterval(-3600 * 24), // 1 day ago
            title: "Add dark mode support for settings panel",
            summary: "Issue opened by contributor",
            participants: ["contributor"],
            url: URL(string: "https://gitlab.com/owner/repo/-/issues/456"),
            authorAvatarURL: URL(string: "https://secure.gravatar.com/avatar/987654"),
            labels: [
                ActivityLabel(id: "3", name: "enhancement", color: "84B6EB")
            ]
        )
    )
    .frame(width: 350)
    .padding()
}

#Preview("Issue without Avatar") {
    IssueActivityView(
        activity: UnifiedActivity(
            id: "gitlab:account1:issue-789",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "789",
            type: .issue,
            timestamp: Date().addingTimeInterval(-3600 * 48), // 2 days ago
            title: "Documentation outdated for authentication flow",
            summary: "Issue opened by newuser",
            participants: ["newuser"],
            url: URL(string: "https://gitlab.com/org/big-repo/-/issues/789"),
            commentCount: 3
        )
    )
    .frame(width: 350)
    .padding()
}

#Preview("Issue Highlighted") {
    IssueActivityView(
        activity: UnifiedActivity(
            id: "gitlab:account1:issue-999",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "999",
            type: .issue,
            timestamp: Date().addingTimeInterval(-3600 * 72), // 3 days ago
            title: "Memory usage grows unbounded during long sessions",
            summary: "Issue opened by power-user",
            participants: ["power-user"],
            url: URL(string: "https://gitlab.com/org/repo/-/issues/999"),
            authorAvatarURL: URL(string: "https://secure.gravatar.com/avatar/555555"),
            labels: [
                ActivityLabel(id: "4", name: "bug", color: "D73A4A"),
                ActivityLabel(id: "5", name: "performance", color: "FBCA04")
            ],
            commentCount: 15
        )
    )
    .environment(\.menuItemHighlighted, true)
    .frame(width: 350)
    .padding()
    .background(MenuHighlightStyle.selectionBackground(true))
}
