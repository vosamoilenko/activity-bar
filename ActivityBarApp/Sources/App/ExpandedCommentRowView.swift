import SwiftUI
import Core

/// Compact comment row for expanded state within a collapsed group
///
/// Displays:
/// - Comment preview (truncated, clickable)
/// - Author
/// - Relative time
struct ExpandedCommentRowView: View {
    let activity: UnifiedActivity
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 8) {
            // Comment preview (truncated)
            Button {
                openCommentURL()
            } label: {
                Text(commentPreview)
                    .font(.caption)
                    .foregroundStyle(isHighlighted ? MenuHighlightStyle.selectionText : .accentColor)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            .buttonStyle(.plain)
            .help("Open comment in browser")

            Spacer(minLength: 4)

            // Author
            if let author = activity.participants?.first {
                Text(author)
                    .font(.caption2)
                    .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                    .lineLimit(1)
            }

            // Exact time (HH:MM)
            Text(formatTime(activity.timestamp))
                .font(.caption2)
                .foregroundStyle(MenuHighlightStyle.tertiary(isHighlighted))
        }
        .padding(.leading, 24)  // Indent from parent group
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            openCommentURL()
        }
    }

    // MARK: - Computed Properties

    private var commentPreview: String {
        // Try summary first (usually contains comment body)
        if let summary = activity.summary, !summary.isEmpty {
            return truncate(summary, to: 50)
        }

        // Fallback to title if it's not a context string
        if let title = activity.title,
           !title.isEmpty,
           !title.hasPrefix("Comment on") {
            return truncate(title, to: 50)
        }

        return "View comment"
    }

    private func truncate(_ text: String, to length: Int) -> String {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Replace newlines with spaces
        let singleLine = trimmed.replacingOccurrences(of: "\n", with: " ")
        if singleLine.count > length {
            return String(singleLine.prefix(length)) + "..."
        }
        return singleLine
    }

    // MARK: - Helpers

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Actions

    private func openCommentURL() {
        guard let url = activity.url else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Previews

#Preview("Expanded Comment Row") {
    VStack(alignment: .leading, spacing: 4) {
        ExpandedCommentRowView(
            activity: UnifiedActivity(
                id: "1",
                provider: .gitlab,
                accountId: "test",
                sourceId: "note-123",
                type: .issueComment,
                timestamp: Date().addingTimeInterval(-3600),
                title: "Comment on MR #123",
                summary: "I think we should consider using a different approach here",
                participants: ["reviewer1"],
                url: URL(string: "https://gitlab.com/org/repo/-/merge_requests/123#note_456")
            )
        )
        ExpandedCommentRowView(
            activity: UnifiedActivity(
                id: "2",
                provider: .gitlab,
                accountId: "test",
                sourceId: "note-124",
                type: .issueComment,
                timestamp: Date().addingTimeInterval(-7200),
                title: "Comment on MR #123",
                summary: "LGTM! Just one small nitpick",
                participants: ["reviewer2"],
                url: URL(string: "https://gitlab.com/org/repo/-/merge_requests/123#note_457")
            )
        )
        ExpandedCommentRowView(
            activity: UnifiedActivity(
                id: "3",
                provider: .gitlab,
                accountId: "test",
                sourceId: "note-125",
                type: .issueComment,
                timestamp: Date().addingTimeInterval(-10800),
                title: "Comment on MR #123",
                summary: "This is a very long comment that should be truncated at some reasonable point to fit in the UI",
                participants: ["reviewer3"],
                url: URL(string: "https://gitlab.com/org/repo/-/merge_requests/123#note_458")
            )
        )
    }
    .frame(width: 300)
    .padding()
}

#Preview("Expanded Comment Row - Highlighted") {
    ExpandedCommentRowView(
        activity: UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "test",
            sourceId: "note-123",
            type: .issueComment,
            timestamp: Date().addingTimeInterval(-3600),
            title: "Comment on MR #123",
            summary: "I think we should consider using a different approach",
            participants: ["reviewer1"],
            url: URL(string: "https://gitlab.com/org/repo/-/merge_requests/123#note_456")
        )
    )
    .environment(\.menuItemHighlighted, true)
    .frame(width: 300)
    .padding()
    .background(MenuHighlightStyle.selectionBackground(true))
}
