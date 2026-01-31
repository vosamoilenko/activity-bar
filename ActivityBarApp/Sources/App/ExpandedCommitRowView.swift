import SwiftUI
import Core

/// Compact commit row for expanded state within a collapsed group
///
/// Displays:
/// - Short SHA (7 chars, monospaced, clickable)
/// - Commit message preview (truncated)
/// - Relative time
struct ExpandedCommitRowView: View {
    let activity: UnifiedActivity
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        HStack(spacing: 8) {
            // Short SHA (7 chars, monospaced)
            Button {
                openCommitURL()
            } label: {
                Text(shortSHA)
                    .font(.caption)
                    .monospaced()
                    .foregroundStyle(isHighlighted ? MenuHighlightStyle.selectionText : .accentColor)
            }
            .buttonStyle(.plain)
            .help("Open commit in browser")

            // Commit message preview (truncated)
            if let title = activity.title {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(MenuHighlightStyle.primary(isHighlighted))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Spacer(minLength: 4)

            // Exact time (HH:MM)
            Text(formatTime(activity.timestamp))
                .font(.caption2)
                .foregroundStyle(MenuHighlightStyle.tertiary(isHighlighted))
        }
        .padding(.leading, 24)  // Indent from parent group
        .padding(.vertical, 2)
        .contentShape(Rectangle())
        .onTapGesture {
            openCommitURL()
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

    // MARK: - Helpers

    private func formatTime(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    // MARK: - Actions

    private func openCommitURL() {
        guard let url = activity.url else { return }
        NSWorkspace.shared.open(url)
    }
}

// MARK: - Previews

#Preview("Expanded Commit Row") {
    VStack(alignment: .leading, spacing: 4) {
        ExpandedCommitRowView(
            activity: UnifiedActivity(
                id: "1",
                provider: .gitlab,
                accountId: "test",
                sourceId: "abc123def456789",
                type: .commit,
                timestamp: Date().addingTimeInterval(-3600),
                title: "Fix authentication bug in login flow",
                url: URL(string: "https://gitlab.com/org/repo/-/commit/abc123def456789")
            )
        )
        ExpandedCommitRowView(
            activity: UnifiedActivity(
                id: "2",
                provider: .gitlab,
                accountId: "test",
                sourceId: "def456abc789012",
                type: .commit,
                timestamp: Date().addingTimeInterval(-7200),
                title: "Add unit tests for authentication module",
                url: URL(string: "https://gitlab.com/org/repo/-/commit/def456abc789012")
            )
        )
        ExpandedCommitRowView(
            activity: UnifiedActivity(
                id: "3",
                provider: .gitlab,
                accountId: "test",
                sourceId: "789012ghi345678",
                type: .commit,
                timestamp: Date().addingTimeInterval(-10800),
                title: "Refactor login controller for better error handling and improved user feedback",
                url: URL(string: "https://gitlab.com/org/repo/-/commit/789012ghi345678")
            )
        )
    }
    .frame(width: 300)
    .padding()
}

#Preview("Expanded Commit Row - Highlighted") {
    ExpandedCommitRowView(
        activity: UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "test",
            sourceId: "abc123def456789",
            type: .commit,
            timestamp: Date().addingTimeInterval(-3600),
            title: "Fix authentication bug in login flow",
            url: URL(string: "https://gitlab.com/org/repo/-/commit/abc123def456789")
        )
    )
    .environment(\.menuItemHighlighted, true)
    .frame(width: 300)
    .padding()
    .background(MenuHighlightStyle.selectionBackground(true))
}
