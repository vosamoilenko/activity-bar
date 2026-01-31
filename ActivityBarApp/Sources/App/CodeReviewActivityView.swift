import SwiftUI
import Core

/// View for displaying code review activities
///
/// Displays review information including:
/// - Review context (PR title or "Review on #123")
/// - Metadata: author, time, review state badge
/// - State-specific badge colors (green for approved, gray for commented)
/// - Avatar or placeholder with checkmark.bubble icon
///
/// Based on RepoBar's comment/review view patterns adapted for code review activities.
/// GitLab review data is limited to "approved" and "commented" actions from events API.
struct CodeReviewActivityView: View {
    let activity: UnifiedActivity
    @Environment(\.menuItemHighlighted) private var isHighlighted
    @Environment(\.showEventAuthor) private var showEventAuthor

    var body: some View {
        RecentItemRowView(alignment: .top, onOpen: openActivity) {
            avatar
        } content: {
            VStack(alignment: .leading, spacing: 4) {
                // Title: review context
                Text(reviewContext)
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

                // Metadata row: time, state badge
                HStack(spacing: 6) {
                    Text(RelativeTimeFormatter.string(from: activity.timestamp))
                        .font(.caption2)
                        .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                        .lineLimit(1)

                    Spacer(minLength: 2)

                    // Review state badge (only show for non-comment states - icon already indicates comment)
                    if let state = reviewState, state != .commented {
                        ReviewStateBadge(state: state, isHighlighted: isHighlighted)
                    }
                }

                // Summary/comment snippet if available
                if let summary = activity.summary, !summary.isEmpty {
                    Text(summary)
                        .font(.caption)
                        .foregroundStyle(MenuHighlightStyle.tertiary(isHighlighted))
                        .lineLimit(2)
                }
            }
        }
    }

    // MARK: - Computed Properties

    /// Review context text - prefer PR title from activity title, fallback to generic text
    private var reviewContext: String {
        if let title = activity.title, !title.isEmpty {
            // If title starts with "Comment on" or "Review on", use as-is
            if title.hasPrefix("Comment on") || title.hasPrefix("Review on") {
                return title
            }
            // Otherwise assume it's the PR title
            return title
        }

        // Fallback: extract PR number from sourceId or URL
        if let prNumber = extractPRNumber() {
            return "Review on #\(prNumber)"
        }

        return "Code Review"
    }

    /// Extract PR number from sourceId or URL
    private func extractPRNumber() -> String? {
        // Try sourceId first (might be PR number)
        let sourceId = activity.sourceId
        if !sourceId.isEmpty {
            // If sourceId is just a number, use it
            if sourceId.allSatisfy({ $0.isNumber }) {
                return sourceId
            }
        }

        // Try to parse from URL (e.g., ".../-/merge_requests/123" or ".../pull/123")
        if let url = activity.url?.absoluteString {
            if let range = url.range(of: #"/(merge_requests?|pull)/(\d+)"#, options: .regularExpression) {
                let match = String(url[range])
                if let numberRange = match.range(of: #"\d+"#, options: .regularExpression) {
                    return String(match[numberRange])
                }
            }
        }

        return nil
    }

    /// Determine review state from activity title or summary
    /// GitLab events API provides "approved" action or "commented" action
    private var reviewState: ReviewState? {
        // Check if title contains review state keywords
        let titleLower = (activity.title ?? "").lowercased()
        let summaryLower = (activity.summary ?? "").lowercased()

        if titleLower.contains("approved") || summaryLower.contains("approved") {
            return .approved
        }

        if titleLower.contains("changes requested") || titleLower.contains("request changes") {
            return .changesRequested
        }

        // Default to commented for code review activities
        return .commented
    }

    // MARK: - Avatar

    @ViewBuilder
    private var avatar: some View {
        if let url = activity.authorAvatarURL {
            AvatarView(url: url, size: 20)
        } else {
            // Code review specific placeholder
            Circle()
                .fill(Color(nsColor: .separatorColor))
                .frame(width: 20, height: 20)
                .overlay(
                    Image(systemName: "checkmark.bubble")
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

// MARK: - Review State

/// Review state for code reviews
private enum ReviewState {
    case approved
    case changesRequested
    case commented

    var displayText: String {
        switch self {
        case .approved: return "Approved"
        case .changesRequested: return "Changes"
        case .commented: return "Comment"
        }
    }

    var iconName: String {
        switch self {
        case .approved: return "checkmark.circle.fill"
        case .changesRequested: return "xmark.circle.fill"
        case .commented: return "bubble.left.fill"
        }
    }
}

/// Badge showing review state with appropriate colors
private struct ReviewStateBadge: View {
    let state: ReviewState
    let isHighlighted: Bool

    var body: some View {
        HStack(spacing: 2) {
            Image(systemName: state.iconName)
                .font(.system(size: 8))
            Text(state.displayText)
                .font(.system(size: 9).weight(.medium))
        }
        .foregroundStyle(badgeColor)
        .padding(.horizontal, 4)
        .padding(.vertical, 1.5)
        .background(
            Capsule(style: .continuous)
                .fill(backgroundColor)
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(borderColor, lineWidth: 0.5)
        )
    }

    // MARK: - Colors

    private var badgeColor: Color {
        if isHighlighted {
            return .white.opacity(0.95)
        }

        switch state {
        case .approved:
            return Color(nsColor: .systemGreen)
        case .changesRequested:
            return Color(nsColor: .systemRed)
        case .commented:
            return Color(nsColor: .secondaryLabelColor)
        }
    }

    private var backgroundColor: Color {
        if isHighlighted {
            return .white.opacity(0.16)
        }

        switch state {
        case .approved:
            return Color(nsColor: .systemGreen).opacity(0.14)
        case .changesRequested:
            return Color(nsColor: .systemRed).opacity(0.14)
        case .commented:
            return Color(nsColor: .separatorColor).opacity(0.5)
        }
    }

    private var borderColor: Color {
        if isHighlighted {
            return .white.opacity(0.30)
        }

        switch state {
        case .approved:
            return Color(nsColor: .systemGreen).opacity(0.55)
        case .changesRequested:
            return Color(nsColor: .systemRed).opacity(0.55)
        case .commented:
            return Color(nsColor: .separatorColor)
        }
    }
}

// MARK: - Previews

#Preview("Approved Review") {
    CodeReviewActivityView(
        activity: UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "test",
            sourceId: "123",
            type: .codeReview,
            timestamp: Date().addingTimeInterval(-3600),
            title: "Approved: Add user authentication",
            summary: "LGTM! Great implementation of the auth flow.",
            participants: ["reviewer"],
            url: URL(string: "https://gitlab.com/org/repo/-/merge_requests/123"),
            authorAvatarURL: nil
        )
    )
    .frame(width: 300)
    .padding()
}

#Preview("Changes Requested") {
    CodeReviewActivityView(
        activity: UnifiedActivity(
            id: "2",
            provider: .gitlab,
            accountId: "test",
            sourceId: "124",
            type: .codeReview,
            timestamp: Date().addingTimeInterval(-7200),
            title: "Changes requested on #124",
            summary: "Please add error handling for the edge cases.",
            participants: ["reviewer"],
            url: URL(string: "https://gitlab.com/org/repo/-/merge_requests/124"),
            authorAvatarURL: nil
        )
    )
    .frame(width: 300)
    .padding()
}

#Preview("Comment on MR") {
    CodeReviewActivityView(
        activity: UnifiedActivity(
            id: "3",
            provider: .gitlab,
            accountId: "test",
            sourceId: "125",
            type: .codeReview,
            timestamp: Date().addingTimeInterval(-1800),
            title: "Comment on MergeRequest #125",
            summary: "Have you considered using a different approach here?",
            participants: ["reviewer"],
            url: URL(string: "https://gitlab.com/org/repo/-/merge_requests/125#note_456"),
            authorAvatarURL: nil
        )
    )
    .frame(width: 300)
    .padding()
}

#Preview("With Avatar") {
    CodeReviewActivityView(
        activity: UnifiedActivity(
            id: "4",
            provider: .gitlab,
            accountId: "test",
            sourceId: "126",
            type: .codeReview,
            timestamp: Date().addingTimeInterval(-900),
            title: "Approved: Fix bug in payment processing",
            summary: nil,
            participants: ["senior-dev"],
            url: URL(string: "https://gitlab.com/org/repo/-/merge_requests/126"),
            authorAvatarURL: URL(string: "https://secure.gravatar.com/avatar/abc123?s=80&d=identicon")
        )
    )
    .frame(width: 300)
    .padding()
}
