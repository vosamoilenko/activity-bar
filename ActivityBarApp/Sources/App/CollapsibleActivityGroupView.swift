import SwiftUI
import Core

/// Expandable view for a group of similar activities
///
/// Collapsed state: Shows count and summary (e.g., "6 commits to feat/facelift-2025")
/// Expanded state: Shows individual activity rows indented
struct CollapsibleActivityGroupView: View {
    let group: ActivityGroup
    var onActivityTapped: ((UnifiedActivity) -> Void)?

    @State private var isExpanded = false
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row (always visible)
            headerRow

            // Expanded content
            if isExpanded {
                expandedContent
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .animation(.easeInOut(duration: 0.2), value: isExpanded)
    }

    // MARK: - Header

    private var headerRow: some View {
        HStack(spacing: 8) {
            // Expand/collapse chevron
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                .frame(width: 12)

            // Group type icon
            groupIcon

            // Summary text
            VStack(alignment: .leading, spacing: 2) {
                Text(group.summaryText)
                    .font(.callout)
                    .fontWeight(.medium)
                    .foregroundStyle(MenuHighlightStyle.primary(isHighlighted))
                    .lineLimit(1)

                // Project name
                Text(group.projectName)
                    .font(.caption)
                    .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
                    .lineLimit(1)
            }

            Spacer()
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation {
                isExpanded.toggle()
            }
        }
    }

    // MARK: - Group Icon

    @ViewBuilder
    private var groupIcon: some View {
        Image(systemName: groupIconName)
            .font(.system(size: 12))
            .foregroundStyle(MenuHighlightStyle.secondary(isHighlighted))
            .frame(width: 16)
    }

    private var groupIconName: String {
        switch group.groupType {
        case .commits:
            return "arrow.turn.down.right"
        case .comments:
            return "text.bubble"
        }
    }

    // MARK: - Expanded Content

    @ViewBuilder
    private var expandedContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(group.activities) { activity in
                expandedRow(for: activity)
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private func expandedRow(for activity: UnifiedActivity) -> some View {
        switch group.groupType {
        case .commits:
            ExpandedCommitRowView(activity: activity)
        case .comments:
            ExpandedCommentRowView(activity: activity)
        }
    }

}

// MARK: - Previews

#Preview("Commit Group - Collapsed") {
    CollapsibleActivityGroupView(
        group: ActivityGroup(
            id: "commit-group-1",
            activities: [
                UnifiedActivity(
                    id: "c1",
                    provider: .gitlab,
                    accountId: "test",
                    sourceId: "abc123def",
                    type: .commit,
                    timestamp: Date().addingTimeInterval(-3600),
                    title: "Fix authentication bug",
                    sourceRef: "feat/facelift-2025",
                    projectName: "sclable.com"
                ),
                UnifiedActivity(
                    id: "c2",
                    provider: .gitlab,
                    accountId: "test",
                    sourceId: "def456abc",
                    type: .commit,
                    timestamp: Date().addingTimeInterval(-7200),
                    title: "Add unit tests",
                    sourceRef: "feat/facelift-2025",
                    projectName: "sclable.com"
                ),
                UnifiedActivity(
                    id: "c3",
                    provider: .gitlab,
                    accountId: "test",
                    sourceId: "789xyz012",
                    type: .commit,
                    timestamp: Date().addingTimeInterval(-10800),
                    title: "Refactor login module",
                    sourceRef: "feat/facelift-2025",
                    projectName: "sclable.com"
                )
            ],
            groupType: .commits(branch: "feat/facelift-2025", project: "sclable.com")
        )
    )
    .frame(width: 300)
    .padding()
}

#Preview("Comment Group - Collapsed") {
    CollapsibleActivityGroupView(
        group: ActivityGroup(
            id: "comment-group-1",
            activities: [
                UnifiedActivity(
                    id: "n1",
                    provider: .gitlab,
                    accountId: "test",
                    sourceId: "note-123",
                    type: .issueComment,
                    timestamp: Date().addingTimeInterval(-1800),
                    title: "Comment on MR #123",
                    summary: "I think we should reconsider this approach",
                    participants: ["alice"],
                    projectName: "sclable.com"
                ),
                UnifiedActivity(
                    id: "n2",
                    provider: .gitlab,
                    accountId: "test",
                    sourceId: "note-124",
                    type: .issueComment,
                    timestamp: Date().addingTimeInterval(-3600),
                    title: "Comment on MR #123",
                    summary: "LGTM!",
                    participants: ["bob"],
                    projectName: "sclable.com"
                ),
                UnifiedActivity(
                    id: "n3",
                    provider: .gitlab,
                    accountId: "test",
                    sourceId: "note-125",
                    type: .issueComment,
                    timestamp: Date().addingTimeInterval(-5400),
                    title: "Comment on MR #123",
                    summary: "Can you add some tests?",
                    participants: ["charlie"],
                    projectName: "sclable.com"
                ),
                UnifiedActivity(
                    id: "n4",
                    provider: .gitlab,
                    accountId: "test",
                    sourceId: "note-126",
                    type: .issueComment,
                    timestamp: Date().addingTimeInterval(-7200),
                    title: "Comment on MR #123",
                    summary: "Good work on this!",
                    participants: ["diana"],
                    projectName: "sclable.com"
                )
            ],
            groupType: .comments(targetType: "MR", targetId: "123", project: "sclable.com")
        )
    )
    .frame(width: 300)
    .padding()
}

#Preview("Group - Highlighted") {
    CollapsibleActivityGroupView(
        group: ActivityGroup(
            id: "commit-group-2",
            activities: [
                UnifiedActivity(
                    id: "c1",
                    provider: .gitlab,
                    accountId: "test",
                    sourceId: "abc123",
                    type: .commit,
                    timestamp: Date().addingTimeInterval(-3600),
                    title: "Fix bug",
                    sourceRef: "main",
                    projectName: "my-repo"
                ),
                UnifiedActivity(
                    id: "c2",
                    provider: .gitlab,
                    accountId: "test",
                    sourceId: "def456",
                    type: .commit,
                    timestamp: Date().addingTimeInterval(-7200),
                    title: "Add feature",
                    sourceRef: "main",
                    projectName: "my-repo"
                )
            ],
            groupType: .commits(branch: "main", project: "my-repo")
        )
    )
    .environment(\.menuItemHighlighted, true)
    .frame(width: 300)
    .padding()
    .background(MenuHighlightStyle.selectionBackground(true))
}
