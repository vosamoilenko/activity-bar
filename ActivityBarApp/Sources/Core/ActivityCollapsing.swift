import Foundation

/// Type of grouped activities for collapsing
public enum ActivityGroupType: Hashable, Sendable {
    case commits(branch: String, project: String)
    case comments(targetType: String, targetId: String, project: String)
}

/// Group of similar activities that can be collapsed
public struct ActivityGroup: Identifiable, Sendable {
    public let id: String
    public let activities: [UnifiedActivity]
    public let groupType: ActivityGroupType

    public init(id: String, activities: [UnifiedActivity], groupType: ActivityGroupType) {
        self.id = id
        self.activities = activities
        self.groupType = groupType
    }

    /// Summary text for collapsed state (e.g., "6 commits to feat/facelift-2025")
    public var summaryText: String {
        let count = activities.count
        switch groupType {
        case .commits(let branch, _):
            return "\(count) commits to \(branch)"
        case .comments(let targetType, let targetId, _):
            return "\(count) comments on \(targetType) #\(targetId)"
        }
    }

    /// Project name for display
    public var projectName: String {
        switch groupType {
        case .commits(_, let project):
            return project
        case .comments(_, _, let project):
            return project
        }
    }
}

/// Wrapper enum for displaying either single activities or collapsed groups
public enum DisplayableActivity: Identifiable, Sendable {
    case single(UnifiedActivity)
    case group(ActivityGroup)

    public var id: String {
        switch self {
        case .single(let activity):
            return activity.id
        case .group(let group):
            return group.id
        }
    }

    /// Timestamp for sorting (uses first activity's timestamp for groups)
    public var timestamp: Date {
        switch self {
        case .single(let activity):
            return activity.timestamp
        case .group(let group):
            return group.activities.first?.timestamp ?? Date.distantPast
        }
    }
}

/// Logic for collapsing similar activities into groups
public enum ActivityCollapser {
    /// Maximum time gap (in seconds) between activities to be grouped together
    /// Activities more than 2 hours apart won't be grouped even if they share the same branch/target
    private static let maxTimeGapSeconds: TimeInterval = 2 * 60 * 60  // 2 hours

    /// Collapse activities into displayable items (singles and groups)
    /// Only groups activities that are close in time (within 2 hours of each other)
    /// - Parameter activities: Activities to collapse
    /// - Returns: Array of DisplayableActivity items sorted by time ascending (oldest first)
    public static func collapse(_ activities: [UnifiedActivity]) -> [DisplayableActivity] {
        // Sort activities by time ascending first
        let sortedActivities = activities.sorted { $0.timestamp < $1.timestamp }

        var result: [DisplayableActivity] = []
        var i = 0

        while i < sortedActivities.count {
            let activity = sortedActivities[i]

            // Try to form a group starting from this activity
            if let groupKey = commitGroupKey(for: activity) {
                // Collect consecutive activities with same key that are close in time
                var groupActivities = [activity]
                var j = i + 1

                while j < sortedActivities.count {
                    let nextActivity = sortedActivities[j]
                    guard let nextKey = commitGroupKey(for: nextActivity), nextKey == groupKey else { break }

                    // Check time proximity with the previous activity in the group
                    let timeDiff = nextActivity.timestamp.timeIntervalSince(groupActivities.last!.timestamp)
                    guard timeDiff <= maxTimeGapSeconds else { break }

                    groupActivities.append(nextActivity)
                    j += 1
                }

                if groupActivities.count > 1 {
                    // Create a group
                    let parts = groupKey.split(separator: ":", maxSplits: 1)
                    let branch = parts.count > 0 ? String(parts[0]) : "unknown"
                    let project = parts.count > 1 ? String(parts[1]) : "unknown"
                    let group = ActivityGroup(
                        id: "commit-group:\(groupKey):\(groupActivities.first!.id)",
                        activities: groupActivities,  // Already sorted ascending
                        groupType: .commits(branch: branch, project: project)
                    )
                    result.append(.group(group))
                    i = j
                } else {
                    result.append(.single(activity))
                    i += 1
                }
            } else if let groupKey = commentGroupKey(for: activity) {
                // Collect consecutive activities with same key that are close in time
                var groupActivities = [activity]
                var j = i + 1

                while j < sortedActivities.count {
                    let nextActivity = sortedActivities[j]
                    guard let nextKey = commentGroupKey(for: nextActivity), nextKey == groupKey else { break }

                    // Check time proximity with the previous activity in the group
                    let timeDiff = nextActivity.timestamp.timeIntervalSince(groupActivities.last!.timestamp)
                    guard timeDiff <= maxTimeGapSeconds else { break }

                    groupActivities.append(nextActivity)
                    j += 1
                }

                if groupActivities.count > 1 {
                    // Create a group
                    let parts = groupKey.split(separator: ":", maxSplits: 2)
                    let targetType = parts.count > 0 ? String(parts[0]) : "item"
                    let targetId = parts.count > 1 ? String(parts[1]) : "?"
                    let project = parts.count > 2 ? String(parts[2]) : "unknown"
                    let group = ActivityGroup(
                        id: "comment-group:\(groupKey):\(groupActivities.first!.id)",
                        activities: groupActivities,  // Already sorted ascending
                        groupType: .comments(targetType: targetType, targetId: targetId, project: project)
                    )
                    result.append(.group(group))
                    i = j
                } else {
                    result.append(.single(activity))
                    i += 1
                }
            } else {
                result.append(.single(activity))
                i += 1
            }
        }

        // Result is already sorted ascending by construction
        return result
    }

    /// Generate grouping key for commits: branch:project
    private static func commitGroupKey(for activity: UnifiedActivity) -> String? {
        guard activity.type == .commit else { return nil }

        // Use sourceRef (branch name) and projectName
        let branch = activity.sourceRef ?? extractBranchFromSummary(activity.summary)
        let project = activity.projectName ?? "unknown"

        guard let branch = branch, !branch.isEmpty else { return nil }

        return "\(branch):\(project)"
    }

    /// Extract branch name from summary (fallback when sourceRef is nil)
    private static func extractBranchFromSummary(_ summary: String?) -> String? {
        guard let summary = summary else { return nil }

        // Try to match patterns like "Pushed N commits to branch-name"
        // or "Branch: branch-name"
        if let range = summary.range(of: #"to ([^\s,]+)"#, options: .regularExpression) {
            let match = String(summary[range])
            return match.replacingOccurrences(of: "to ", with: "")
        }

        if let range = summary.range(of: #"Branch: ([^\s,]+)"#, options: .regularExpression) {
            let match = String(summary[range])
            return match.replacingOccurrences(of: "Branch: ", with: "")
        }

        return nil
    }

    /// Generate grouping key for comments: targetType:targetId:project
    private static func commentGroupKey(for activity: UnifiedActivity) -> String? {
        guard activity.type == .issueComment || activity.type == .codeReview else { return nil }

        let project = activity.projectName ?? "unknown"

        // Parse from title: "Comment on MR #123" or "Comment on Issue #456"
        if let title = activity.title {
            if let match = extractCommentTarget(from: title) {
                return "\(match.type):\(match.id):\(project)"
            }
        }

        // Parse from URL
        if let url = activity.url?.absoluteString {
            if let match = extractCommentTargetFromURL(url) {
                return "\(match.type):\(match.id):\(project)"
            }
        }

        return nil
    }

    /// Extract comment target (MR/Issue + ID) from title
    private static func extractCommentTarget(from title: String) -> (type: String, id: String)? {
        // Match patterns like "Comment on MR #123" or "Comment on Issue #456"
        let patterns: [(regex: String, type: String)] = [
            (#"MR #?(\d+)"#, "MR"),
            (#"PR #?(\d+)"#, "PR"),
            (#"[Mm]erge [Rr]equest #?(\d+)"#, "MR"),
            (#"[Pp]ull [Rr]equest #?(\d+)"#, "PR"),
            (#"[Ii]ssue #?(\d+)"#, "Issue"),
            (#"#(\d+)"#, "Issue")  // Default fallback for "#123" pattern
        ]

        for (pattern, type) in patterns {
            if let range = title.range(of: pattern, options: .regularExpression) {
                let match = String(title[range])
                // Extract just the number
                if let numRange = match.range(of: #"\d+"#, options: .regularExpression) {
                    return (type, String(match[numRange]))
                }
            }
        }

        return nil
    }

    /// Extract comment target from URL
    private static func extractCommentTargetFromURL(_ url: String) -> (type: String, id: String)? {
        // GitLab: /-/merge_requests/123 or /-/issues/123
        // GitHub: /pull/123 or /issues/123
        // Azure: /_workitems/edit/123 or /pullrequest/123

        let patterns: [(regex: String, type: String)] = [
            (#"/merge_requests?/(\d+)"#, "MR"),
            (#"/pull/(\d+)"#, "PR"),
            (#"/pullrequest/(\d+)"#, "PR"),
            (#"/issues/(\d+)"#, "Issue"),
            (#"/_workitems/edit/(\d+)"#, "WorkItem")
        ]

        for (pattern, type) in patterns {
            if let range = url.range(of: pattern, options: .regularExpression) {
                let match = String(url[range])
                if let numRange = match.range(of: #"\d+"#, options: .regularExpression) {
                    return (type, String(match[numRange]))
                }
            }
        }

        return nil
    }
}
