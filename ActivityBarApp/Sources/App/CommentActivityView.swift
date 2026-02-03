import SwiftUI
import Core

/// Enhanced comment activity view for issue and PR comments
///
/// Displays:
/// - Comment snippet (first 100 chars of body or summary)
/// - Context: "Comment on #123" or "Comment on PR #456"
/// - Metadata: author, time
/// - Avatar or placeholder with text.bubble icon
///
/// Reference: RepoBar's comment view patterns adapted for unified comment activities.
struct CommentActivityView: View {
    let activity: UnifiedActivity
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.showEventAuthor) private var showEventAuthor
    @Environment(\.showEventType) private var showEventType

    var body: some View {
        RecentItemRowView(alignment: .top, onOpen: openActivity) {
            avatar
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                // Context: "Comment on #123" or "Comment on PR #456"
                Text(commentContext)
                    .font(.callout.weight(.medium))
                    .foregroundStyle(MenuHighlightStyle.primary(isHighlighted))
                    .lineLimit(2)

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

                // Metadata row: time
                HStack(spacing: 6) {
                    Text(RelativeTimeFormatter.string(from: activity.timestamp))
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                        .lineLimit(1)

                    Spacer(minLength: 2)
                }

                // Comment snippet (first 100 chars)
                if let snippet = commentSnippet, !snippet.isEmpty {
                    Text(snippet)
                        .font(.caption)
                        .foregroundStyle(MenuHighlightStyle.tertiary(isHighlighted))
                        .lineLimit(2)
                }

                // Linked tickets (if any)
                if let tickets = activity.linkedTickets, !tickets.isEmpty {
                    TicketChipsView(tickets: tickets)
                }
            }
        }
    }

    // MARK: - Computed Properties

    /// Comment context - determines what the comment is on (issue or PR)
    private var commentContext: String {
        // If title already contains "Comment on", use it as-is
        if let title = activity.title, !title.isEmpty {
            if title.hasPrefix("Comment on") {
                return title
            }
            // If title is the comment body, use it for snippet instead
        }

        // Try to extract context from sourceId or URL
        let contextType = extractCommentContext()

        switch contextType {
        case .issue(let number):
            return "Comment on #\(number)"
        case .pullRequest(let number):
            return "Comment on PR #\(number)"
        case .unknown:
            return "Comment"
        }
    }

    /// Comment snippet - first 100 chars of body
    private var commentSnippet: String? {
        // Priority: summary field, then title if it's not a context string
        var body: String?

        if let summary = activity.summary, !summary.isEmpty {
            body = summary
        } else if let title = activity.title,
                  !title.isEmpty,
                  !title.hasPrefix("Comment on") {
            body = title
        }

        guard let text = body else { return nil }

        // Truncate to 100 chars, trim whitespace
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.count > 100 {
            return String(trimmed.prefix(100)) + "…"
        }
        return trimmed
    }

    /// Extract comment context from sourceId or URL
    private func extractCommentContext() -> CommentContext {
        // Try to parse from URL
        // GitLab: /-/issues/123#note_456 or /-/merge_requests/123#note_456
        if let url = activity.url?.absoluteString {
            // Check for issue comment
            if let issueRange = url.range(of: #"/issues/(\d+)"#, options: .regularExpression) {
                let match = String(url[issueRange])
                if let numberRange = match.range(of: #"\d+"#, options: .regularExpression) {
                    return .issue(String(match[numberRange]))
                }
            }

            // Check for MR/PR comment
            if let prRange = url.range(of: #"/(merge_requests?|pull)/(\d+)"#, options: .regularExpression) {
                let match = String(url[prRange])
                if let numberRange = match.range(of: #"\d+"#, options: .regularExpression) {
                    return .pullRequest(String(match[numberRange]))
                }
            }
        }

        // Try sourceId if it's a number
        if !activity.sourceId.isEmpty, activity.sourceId.allSatisfy(\.isNumber) {
            // Default to issue comment if we can't determine type
            return .issue(activity.sourceId)
        }

        return .unknown
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatar: some View {
        if let url = activity.authorAvatarURL {
            AvatarView(url: url, size: 20)
        } else {
            // Comment specific placeholder: text.bubble icon
            Circle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "text.bubble")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                )
        }
    }

    // MARK: - Actions

    private func openActivity() {
        guard let url = activity.url else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Comment Context

/// Context type for a comment (issue or pull request)
private enum CommentContext {
    case issue(String)
    case pullRequest(String)
    case unknown
}

// MARK: - Previews

#Preview("Issue Comment with Snippet") {
    CommentActivityView(
        activity: UnifiedActivity(
            id: "gitlab:account1:comment-123",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "123",
            type: .issueComment,
            timestamp: Date().addingTimeInterval(-3600), // 1 hour ago
            title: "Comment on #123",
            summary: "I think we should consider using a different approach here. The current implementation has some performance issues that need to be addressed.",
            participants: ["reviewer123"],
            url: URL(string: "https://gitlab.com/owner/repo/-/issues/123#note_456"),
            authorAvatarURL: URL(string: "https://secure.gravatar.com/avatar/abc123")
        )
    )
    .frame(width: 350)
    .padding()
}

#Preview("PR Comment") {
    CommentActivityView(
        activity: UnifiedActivity(
            id: "gitlab:account1:comment-456",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "456",
            type: .issueComment,
            timestamp: Date().addingTimeInterval(-7200), // 2 hours ago
            title: "Comment on PR #456",
            summary: "LGTM! Just one small suggestion about the error handling in line 42.",
            participants: ["senior-dev"],
            url: URL(string: "https://gitlab.com/owner/repo/-/merge_requests/456#note_789"),
            authorAvatarURL: URL(string: "https://secure.gravatar.com/avatar/def456")
        )
    )
    .frame(width: 350)
    .padding()
}

#Preview("Comment without Avatar") {
    CommentActivityView(
        activity: UnifiedActivity(
            id: "gitlab:account1:comment-789",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "789",
            type: .issueComment,
            timestamp: Date().addingTimeInterval(-3600 * 4), // 4 hours ago
            title: "Comment on #789",
            summary: "Thanks for reporting this! I'll investigate and get back to you soon.",
            participants: ["maintainer"],
            url: URL(string: "https://gitlab.com/org/project/-/issues/789#note_1234")
        )
    )
    .frame(width: 350)
    .padding()
}

#Preview("Long Comment Truncated") {
    CommentActivityView(
        activity: UnifiedActivity(
            id: "gitlab:account1:comment-999",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "999",
            type: .issueComment,
            timestamp: Date().addingTimeInterval(-86400), // 1 day ago
            title: "Comment on PR #999",
            summary: "This is a very long comment that discusses multiple aspects of the implementation including performance considerations, security implications, code style preferences, testing strategies, and documentation requirements. It should be truncated to 100 characters.",
            participants: ["tech-lead"],
            url: URL(string: "https://gitlab.com/owner/repo/-/merge_requests/999#note_5678"),
            authorAvatarURL: URL(string: "https://secure.gravatar.com/avatar/xyz789")
        )
    )
    .frame(width: 350)
    .padding()
}

#Preview("Comment Highlighted") {
    CommentActivityView(
        activity: UnifiedActivity(
            id: "gitlab:account1:comment-111",
            provider: .gitlab,
            accountId: "account1",
            sourceId: "111",
            type: .issueComment,
            timestamp: Date().addingTimeInterval(-1800), // 30 min ago
            title: "Comment on #111",
            summary: "Could you add some tests for this edge case?",
            participants: ["qa-engineer"],
            url: URL(string: "https://gitlab.com/owner/repo/-/issues/111#note_9999"),
            authorAvatarURL: URL(string: "https://secure.gravatar.com/avatar/qwe123")
        )
    )
    .environment(\.menuItemHighlighted, true)
    .frame(width: 350)
    .padding()
    .background(MenuHighlightStyle.selectionBackground(true))
}
