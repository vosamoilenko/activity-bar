import SwiftUI
import Core

/// Visual indicator showing current time position in the activity list
private struct NowIndicatorView: View {
    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(Color.red)
                .frame(width: 8, height: 8)

            Rectangle()
                .fill(Color.red)
                .frame(height: 1)

            Text(currentTimeString)
                .font(.caption2)
                .foregroundStyle(.red)
                .fontWeight(.medium)
        }
        .padding(.vertical, 4)
    }

    private var currentTimeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: Date())
    }
}

/// Activity list view consuming UnifiedActivity records
/// Shows activities sorted by time ascending (oldest first)
/// Automatically groups similar activities that are close in time
/// ACTIVITY-057: Supports keyboard navigation with arrow keys, Enter, and Escape
struct ActivityListView: View {
    let activities: [UnifiedActivity]
    let showNowIndicator: Bool
    var onActivityTapped: ((UnifiedActivity) -> Void)?
    var onEscapePressed: (() -> Void)?

    // ACTIVITY-057: Keyboard navigation state
    @FocusState private var focusedActivityId: String?
    @State private var keyboardFocusEnabled = false

    /// Activities sorted by time ascending and collapsed into groups
    private var displayableItems: [DisplayableActivity] {
        ActivityCollapser.collapse(activities)
    }

    // ACTIVITY-057: Flat list of all activities for keyboard navigation
    private var flatActivities: [UnifiedActivity] {
        activities.sorted { $0.timestamp < $1.timestamp }
    }

    var body: some View {
        if activities.isEmpty {
            emptyStateView
        } else {
            VStack(alignment: .leading, spacing: 8) {
                renderDisplayableActivities(displayableItems)
            }
            // ACTIVITY-057: Keyboard navigation handlers
            .onMoveCommand { direction in
                handleMoveCommand(direction)
            }
            .onKeyPress(.return) {
                handleEnterKey()
                return .handled
            }
            .onKeyPress(.escape) {
                handleEscapeKey()
                return .handled
            }
            .focusable()
            .onAppear {
                // Enable keyboard focus when view appears
                keyboardFocusEnabled = true
            }
        }
    }

    // MARK: - Subviews

    /// Render displayable activities (singles and collapsed groups)
    @ViewBuilder
    private func renderDisplayableActivities(_ items: [DisplayableActivity]) -> some View {
        let now = Date()
        let shouldShowIndicator = showNowIndicator && containsTodayActivities

        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
            // Insert now indicator at the correct position (between past and future activities)
            if shouldShowIndicator && shouldInsertNowIndicatorBefore(item: item, previousItem: index > 0 ? items[index - 1] : nil, now: now) {
                NowIndicatorView()
            }

            switch item {
            case .single(let activity):
                activityView(for: activity)
                    .contentShape(Rectangle())
                    .focusable()
                    .focused($focusedActivityId, equals: activity.id)
                    .environment(\.menuItemHighlighted, focusedActivityId == activity.id && keyboardFocusEnabled)
                    .onTapGesture {
                        if activity.url != nil {
                            onActivityTapped?(activity)
                        }
                    }
            case .group(let group):
                CollapsibleActivityGroupView(
                    group: group,
                    onActivityTapped: onActivityTapped
                )
            }
        }

        // Insert now indicator at the end if all activities are in the past
        if shouldShowIndicator && allActivitiesInPast(items: items, now: now) {
            NowIndicatorView()
        }
    }

    /// Check if activities contain any from today
    private var containsTodayActivities: Bool {
        let calendar = Calendar.current
        return activities.contains { calendar.isDateInToday($0.timestamp) }
    }

    /// Determine if now indicator should be inserted before this item
    /// Activities are sorted ascending, so we insert when previous is past and current is future
    private func shouldInsertNowIndicatorBefore(item: DisplayableActivity, previousItem: DisplayableActivity?, now: Date) -> Bool {
        let itemTime = item.timestamp
        let previousTime = previousItem?.timestamp

        // Insert if this item is in the future and either:
        // - It's the first item, or
        // - The previous item was in the past
        if itemTime > now {
            if let prevTime = previousTime {
                return prevTime <= now
            }
            return true  // First item and it's in the future
        }
        return false
    }

    /// Check if all activities are in the past
    private func allActivitiesInPast(items: [DisplayableActivity], now: Date) -> Bool {
        guard let lastItem = items.last else { return false }
        return lastItem.timestamp <= now
    }

    private var emptyStateView: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray")
                .font(.title2)
                .foregroundStyle(.tertiary)
            Text("No activities")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Keyboard Navigation (ACTIVITY-057)

    /// Handle arrow key navigation
    private func handleMoveCommand(_ direction: MoveCommandDirection) {
        let allActivities = flatActivities
        guard !allActivities.isEmpty else { return }

        // Find current index
        if let currentId = focusedActivityId,
           let currentIndex = allActivities.firstIndex(where: { $0.id == currentId }) {
            // Navigate from current position
            switch direction {
            case .up:
                let newIndex = max(0, currentIndex - 1)
                focusedActivityId = allActivities[newIndex].id
            case .down:
                let newIndex = min(allActivities.count - 1, currentIndex + 1)
                focusedActivityId = allActivities[newIndex].id
            case .left, .right:
                // Left/right navigation not used in vertical list
                break
            @unknown default:
                break
            }
        } else {
            // No current focus, select first item
            focusedActivityId = allActivities.first?.id
        }

        // Enable keyboard focus mode
        keyboardFocusEnabled = true
    }

    /// Handle Enter key to open focused activity URL
    private func handleEnterKey() {
        guard let focusedId = focusedActivityId,
              let activity = flatActivities.first(where: { $0.id == focusedId }),
              activity.url != nil else {
            return
        }

        onActivityTapped?(activity)
    }

    /// Handle Escape key to close menu
    private func handleEscapeKey() {
        onEscapePressed?()
    }

    // MARK: - Helpers

    /// Return type-specific view for activity based on its type
    @ViewBuilder
    private func activityView(for activity: UnifiedActivity) -> some View {
        switch activity.type {
        case .commit:
            CommitActivityView(activity: activity)
        case .pullRequest:
            PullRequestActivityView(activity: activity)
        case .issue:
            IssueActivityView(activity: activity)
        case .issueComment:
            CommentActivityView(activity: activity)
        case .codeReview:
            CodeReviewActivityView(activity: activity)
        case .meeting, .workItem, .deployment, .release, .wiki, .other:
            // Generic view for other activity types
            ActivityRowView(activity: activity)
        }
    }
}

// MARK: - Previews

#Preview("Empty") {
    ActivityListView(
        activities: [],
        showNowIndicator: false
    )
    .frame(width: 300, height: 200)
}

#Preview("Activities") {
    ActivityListView(
        activities: sampleActivities,
        showNowIndicator: false
    )
    .frame(width: 300, height: 300)
}

#Preview("With Now Indicator") {
    ActivityListView(
        activities: sampleActivitiesWithFuture,
        showNowIndicator: true
    )
    .frame(width: 300, height: 350)
}

#Preview("With Collapsing") {
    ActivityListView(
        activities: sampleActivitiesForCollapsing,
        showNowIndicator: false
    )
    .frame(width: 300, height: 400)
}

// Sample data for previews
private let sampleActivities: [UnifiedActivity] = [
    UnifiedActivity(
        id: "1",
        provider: .gitlab,
        accountId: "gl-1",
        sourceId: "commit-1",
        type: .commit,
        timestamp: Date(),
        title: "Fix authentication bug",
        summary: "Resolved token refresh issue"
    ),
    UnifiedActivity(
        id: "2",
        provider: .gitlab,
        accountId: "gl-1",
        sourceId: "pr-1",
        type: .pullRequest,
        timestamp: Date().addingTimeInterval(-3600),
        title: "Add user profile feature",
        participants: ["alice", "bob"]
    ),
    UnifiedActivity(
        id: "3",
        provider: .gitlab,
        accountId: "gl-1",
        sourceId: "issue-1",
        type: .issue,
        timestamp: Date().addingTimeInterval(-7200),
        title: "Performance regression in dashboard"
    ),
    UnifiedActivity(
        id: "4",
        provider: .googleCalendar,
        accountId: "cal-1",
        sourceId: "event-1",
        type: .meeting,
        timestamp: Date().addingTimeInterval(-86400),
        title: "Sprint Planning",
        participants: ["team@example.com"]
    ),
    UnifiedActivity(
        id: "5",
        provider: .azureDevops,
        accountId: "ado-1",
        sourceId: "wi-1",
        type: .workItem,
        timestamp: Date().addingTimeInterval(-86400 - 3600),
        title: "Implement caching layer"
    )
]

// Sample data for collapsing preview
private let sampleActivitiesForCollapsing: [UnifiedActivity] = [
    // Multiple commits to same branch
    UnifiedActivity(
        id: "c1",
        provider: .gitlab,
        accountId: "gl-1",
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
        accountId: "gl-1",
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
        accountId: "gl-1",
        sourceId: "789xyz012",
        type: .commit,
        timestamp: Date().addingTimeInterval(-10800),
        title: "Refactor login module",
        sourceRef: "feat/facelift-2025",
        projectName: "sclable.com"
    ),
    // Multiple comments on same MR
    UnifiedActivity(
        id: "n1",
        provider: .gitlab,
        accountId: "gl-1",
        sourceId: "note-123",
        type: .issueComment,
        timestamp: Date().addingTimeInterval(-1800),
        title: "Comment on MR #123",
        summary: "I think we should reconsider this approach",
        participants: ["alice"],
        url: URL(string: "https://gitlab.com/org/repo/-/merge_requests/123#note_456"),
        projectName: "sclable.com"
    ),
    UnifiedActivity(
        id: "n2",
        provider: .gitlab,
        accountId: "gl-1",
        sourceId: "note-124",
        type: .issueComment,
        timestamp: Date().addingTimeInterval(-5400),
        title: "Comment on MR #123",
        summary: "LGTM!",
        participants: ["bob"],
        url: URL(string: "https://gitlab.com/org/repo/-/merge_requests/123#note_457"),
        projectName: "sclable.com"
    ),
    // Single PR (should not collapse)
    UnifiedActivity(
        id: "pr1",
        provider: .gitlab,
        accountId: "gl-1",
        sourceId: "pr-456",
        type: .pullRequest,
        timestamp: Date().addingTimeInterval(-14400),
        title: "Add new feature",
        participants: ["charlie"]
    )
]

// Sample data with future events to demonstrate now indicator
private let sampleActivitiesWithFuture: [UnifiedActivity] = [
    UnifiedActivity(
        id: "f1",
        provider: .googleCalendar,
        accountId: "cal-1",
        sourceId: "event-future-1",
        type: .meeting,
        timestamp: Date().addingTimeInterval(3600), // 1 hour from now
        title: "Team standup",
        participants: ["team@example.com"]
    ),
    UnifiedActivity(
        id: "f2",
        provider: .googleCalendar,
        accountId: "cal-1",
        sourceId: "event-future-2",
        type: .meeting,
        timestamp: Date().addingTimeInterval(7200), // 2 hours from now
        title: "Design review",
        participants: ["design@example.com"]
    ),
    UnifiedActivity(
        id: "p1",
        provider: .gitlab,
        accountId: "gl-1",
        sourceId: "commit-past-1",
        type: .commit,
        timestamp: Date().addingTimeInterval(-1800), // 30 mins ago
        title: "Fix authentication bug",
        summary: "Resolved token refresh issue"
    ),
    UnifiedActivity(
        id: "p2",
        provider: .gitlab,
        accountId: "gl-1",
        sourceId: "pr-past-1",
        type: .pullRequest,
        timestamp: Date().addingTimeInterval(-3600), // 1 hour ago
        title: "Add user profile feature",
        participants: ["alice", "bob"]
    ),
    UnifiedActivity(
        id: "p3",
        provider: .gitlab,
        accountId: "gl-1",
        sourceId: "issue-past-1",
        type: .issue,
        timestamp: Date().addingTimeInterval(-7200), // 2 hours ago
        title: "Performance regression in dashboard"
    )
]
