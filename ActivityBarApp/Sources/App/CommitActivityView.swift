import SwiftUI
import Core

/// Enhanced commit activity view matching RepoBar's CommitMenuItemView design
///
/// Reference: RepoBar/Sources/RepoBar/Views/CommitMenuItemView.swift
struct CommitActivityView: View {
    let activity: UnifiedActivity
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.showEventAuthor) private var showEventAuthor
    @Environment(\.showEventType) private var showEventType
    @Environment(\.showEventBranch) private var showEventBranch

    var body: some View {
        RecentItemRowView(alignment: .top, onOpen: self.onOpen) {
            // Leading: avatar or commit-specific placeholder
            self.avatar
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                // Title: commit message (first line)
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

                // Event type line (when showEventType is enabled)
                if showEventType, let eventType = activity.rawEventType {
                    Text("[\(eventType)]")
                        .font(.caption2)
                        .fontWeight(.medium)
                        .foregroundStyle(MenuHighlightStyle.tertiary(isHighlighted))
                        .lineLimit(1)
                }

                // Metadata row: SHA, branch, repo, time
                HStack(spacing: 6) {
                    // Short SHA (7 chars, monospaced)
                    Text(shortSHA)
                        .font(.caption)
                        .monospaced()
                        .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                        .lineLimit(1)

                    // Branch name (from sourceRef)
                    if showEventBranch, let branch = activity.sourceRef, !branch.isEmpty {
                        Text(branch)
                            .font(.caption2)
                            .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                            .lineLimit(1)
                    }

                    // Repo name (from summary or title)
                    if let repo = repoName, !repo.isEmpty {
                        Text(repo)
                            .font(.caption2)
                            .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                            .lineLimit(1)
                    }

                    // Relative time
                    Text(RelativeTimeFormatter.string(from: activity.timestamp))
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                        .lineLimit(1)
                }

                // Linked tickets (if any)
                if let tickets = activity.linkedTickets, !tickets.isEmpty {
                    TicketChipsView(tickets: tickets)
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var shortSHA: String {
        // sourceId should be the full SHA for commits
        if activity.sourceId.count >= 7 {
            return String(activity.sourceId.prefix(7))
        }

        // Fallback: try to extract SHA from summary
        if let summary = activity.summary,
           let shaRange = summary.range(of: #"SHA: ([a-f0-9]{7,40})"#, options: .regularExpression) {
            let match = summary[shaRange]
            if let valueRange = match.range(of: #"[a-f0-9]{7,40}"#, options: .regularExpression) {
                return String(match[valueRange].prefix(7))
            }
        }

        // Last resort: use sourceId as-is
        return String(activity.sourceId.prefix(7))
    }

    private var repoName: String? {
        // Extract repo name from summary: "Repo: owner/repo, SHA: ..."
        if let summary = activity.summary,
           let repoRange = summary.range(of: #"Repo: ([^,]+)"#, options: .regularExpression) {
            let match = summary[repoRange]
            // Remove "Repo: " prefix
            let repoValue = match.replacingOccurrences(of: "Repo: ", with: "")
            return repoValue.isEmpty ? nil : repoValue
        }

        // Fallback: try to extract from URL
        if let urlString = activity.url?.absoluteString,
           let range = urlString.range(of: #"github\.com/([^/]+/[^/]+)"#, options: .regularExpression) {
            let match = urlString[range]
            if let repoRange = match.range(of: #"[^/]+/[^/]+"#, options: .regularExpression) {
                return String(match[repoRange])
            }
        }

        return nil
    }

    @ViewBuilder
    private var avatar: some View {
        if let avatarURL = activity.authorAvatarURL {
            AvatarView(url: avatarURL, size: 20)
        } else {
            // Commit-specific placeholder: arrow.turn.down.right icon
            Circle()
                .fill(Color(nsColor: .separatorColor))
                .overlay(
                    Image(systemName: "arrow.turn.down.right")
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

#Preview("Commit with Avatar") {
    CommitActivityView(
        activity: UnifiedActivity(
            id: "gitlab:account1:push-123",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "abc123def456",
            type: .commit,
            timestamp: Date().addingTimeInterval(-3600 * 2), // 2 hours ago
            title: "my-repo",
            summary: "Pushed 3 commits to main\nFix authentication bug",
            participants: ["octocat"],
            url: URL(string: "https://gitlab.com/owner/my-repo/-/commits/main"),
            authorAvatarURL: URL(string: "https://secure.gravatar.com/avatar/583231")
        )
    )
    .frame(width: 300)
    .padding()
}

#Preview("Commit without Avatar") {
    CommitActivityView(
        activity: UnifiedActivity(
            id: "gitlab:account1:push-456",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "def456abc",
            type: .commit,
            timestamp: Date().addingTimeInterval(-3600 * 24), // 1 day ago
            title: "another-repo",
            summary: "Pushed 1 commit to feature-branch",
            participants: ["developer"],
            url: URL(string: "https://gitlab.com/owner/another-repo/-/commits/feature-branch")
        )
    )
    .frame(width: 300)
    .padding()
}

#Preview("Commit Highlighted") {
    CommitActivityView(
        activity: UnifiedActivity(
            id: "gitlab:account1:push-789",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "789xyz",
            type: .commit,
            timestamp: Date().addingTimeInterval(-3600 * 48), // 2 days ago
            title: "big-repo",
            summary: "Pushed 5 commits to develop",
            participants: ["contributor"],
            url: URL(string: "https://gitlab.com/org/big-repo/-/commits/develop")
        )
    )
    .environment(\.menuItemHighlighted, true)
    .frame(width: 300)
    .padding()
    .background(MenuHighlightStyle.selectionBackground(true))
}
