import SwiftUI
import Core

/// Enhanced pull request activity view matching RepoBar's PullRequestMenuItemView design
///
/// Reference: RepoBar/Sources/RepoBar/Views/PullRequestMenuItemView.swift
struct PullRequestActivityView: View {
    let activity: UnifiedActivity
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.showEventAuthor) private var showEventAuthor

    var body: some View {
        RecentItemRowView(alignment: .top, onOpen: self.onOpen) {
            // Leading: avatar or PR-specific placeholder
            self.avatar
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                // Title: PR title
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

                // Metadata row: PR number, time, draft badge, comment badges
                HStack(spacing: 6) {
                    // PR number (#123, monospaced)
                    Text(prNumber)
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

                    // Draft badge (if applicable)
                    if activity.isDraft == true {
                        DraftBadgeView(isHighlighted: isHighlighted)
                    }

                    // Comment count badge (if > 0)
                    if let commentCount = activity.commentCount, commentCount > 0 {
                        MenuStatBadge(label: nil, value: commentCount, systemImage: "text.bubble")
                    }

                    // Reviewer/assignee avatars
                    if let reviewers = activity.reviewers, !reviewers.isEmpty {
                        AvatarStackView(participants: reviewers, size: 14, maxVisible: 3)
                    }
                }

                // Branch info: head → base
                if let sourceRef = activity.sourceRef, let targetRef = activity.targetRef,
                   !sourceRef.isEmpty, !targetRef.isEmpty {
                    Text("\(sourceRef) → \(targetRef)")
                        .font(.caption2)
                        .monospaced()
                        .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                        .lineLimit(1)
                }

                // Labels (if any)
                if let labels = activity.labels, !labels.isEmpty {
                    MenuLabelChipsView(labels: labels)
                }
            }
        }
    }

    // MARK: - Computed Properties

    private var prNumber: String {
        // sourceId should be the PR number for pull requests
        // Format: "#123"
        if activity.sourceId.allSatisfy(\.isNumber) {
            return "#\(activity.sourceId)"
        }

        // Fallback: try to extract number from URL
        if let urlString = activity.url?.absoluteString,
           let range = urlString.range(of: #"/pull/(\d+)"#, options: .regularExpression) {
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
            // PR-specific placeholder: arrow.triangle.branch icon
            Circle()
                .fill(Color(nsColor: .separatorColor))
                .overlay(
                    Image(systemName: "arrow.triangle.branch")
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

// MARK: - Draft Badge

private struct DraftBadgeView: View {
    let isHighlighted: Bool

    var body: some View {
        Text("Draft")
            .font(.caption2.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(isHighlighted ? .white.opacity(0.95) : Color(nsColor: .systemOrange))
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(
                Capsule(style: .continuous)
                    .fill(isHighlighted ? .white.opacity(0.16) : Color(nsColor: .systemOrange).opacity(0.14))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isHighlighted ? .white.opacity(0.30) : Color(nsColor: .systemOrange).opacity(0.55), lineWidth: 1)
            )
    }
}

// MARK: - Previews

#Preview("Pull Request with Draft") {
    PullRequestActivityView(
        activity: UnifiedActivity(
            id: "gitlab:account1:pr-123",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "123",
            type: .pullRequest,
            timestamp: Date().addingTimeInterval(-3600 * 2), // 2 hours ago
            title: "Add authentication middleware for API routes",
            summary: "Pull request opened by octocat",
            participants: ["octocat"],
            url: URL(string: "https://gitlab.com/owner/repo/-/merge_requests/123"),
            authorAvatarURL: URL(string: "https://secure.gravatar.com/avatar/583231"),
            labels: [
                ActivityLabel(id: "1", name: "feature", color: "0E8A16"),
                ActivityLabel(id: "2", name: "breaking-change", color: "D93F0B")
            ],
            commentCount: 5,
            isDraft: true,
            sourceRef: "feature/auth-middleware",
            targetRef: "main"
        )
    )
    .frame(width: 350)
    .padding()
}

#Preview("Pull Request without Draft") {
    PullRequestActivityView(
        activity: UnifiedActivity(
            id: "gitlab:account1:pr-456",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "456",
            type: .pullRequest,
            timestamp: Date().addingTimeInterval(-3600 * 24), // 1 day ago
            title: "Fix memory leak in network client",
            summary: "Pull request opened by developer",
            participants: ["developer"],
            url: URL(string: "https://gitlab.com/owner/repo/-/merge_requests/456"),
            authorAvatarURL: URL(string: "https://secure.gravatar.com/avatar/123456"),
            commentCount: 12,
            isDraft: false,
            sourceRef: "bugfix/memory-leak",
            targetRef: "develop"
        )
    )
    .frame(width: 350)
    .padding()
}

#Preview("Pull Request without Avatar") {
    PullRequestActivityView(
        activity: UnifiedActivity(
            id: "gitlab:account1:pr-789",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "789",
            type: .pullRequest,
            timestamp: Date().addingTimeInterval(-3600 * 48), // 2 days ago
            title: "Update dependencies to latest versions",
            summary: "Pull request opened by contributor",
            participants: ["contributor"],
            url: URL(string: "https://gitlab.com/org/big-repo/-/merge_requests/789"),
            sourceRef: "chore/deps-update",
            targetRef: "main"
        )
    )
    .frame(width: 350)
    .padding()
}

#Preview("Pull Request Highlighted") {
    PullRequestActivityView(
        activity: UnifiedActivity(
            id: "gitlab:account1:pr-999",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "999",
            type: .pullRequest,
            timestamp: Date().addingTimeInterval(-3600 * 72), // 3 days ago
            title: "Implement real-time notifications with WebSocket",
            summary: "Pull request opened by maintainer",
            participants: ["maintainer"],
            url: URL(string: "https://gitlab.com/org/repo/-/merge_requests/999"),
            authorAvatarURL: URL(string: "https://secure.gravatar.com/avatar/999999"),
            labels: [
                ActivityLabel(id: "3", name: "enhancement", color: "84B6EB")
            ],
            commentCount: 3,
            isDraft: false,
            sourceRef: "feature/websocket-notifications",
            targetRef: "main"
        )
    )
    .environment(\.menuItemHighlighted, true)
    .frame(width: 350)
    .padding()
    .background(MenuHighlightStyle.selectionBackground(true))
}
