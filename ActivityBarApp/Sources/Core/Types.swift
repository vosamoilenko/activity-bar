import Foundation

/// Provider types matching activity-discovery
public enum Provider: String, Codable, Sendable, CaseIterable {
    case gitlab = "gitlab"
    case azureDevops = "azure-devops"
    case googleCalendar = "google-calendar"
}

/// Activity types matching activity-discovery UnifiedActivity.type
public enum ActivityType: String, Codable, Sendable, CaseIterable, Hashable {
    case commit
    case pullRequest = "pull_request"
    case issue
    case issueComment = "issue_comment"
    case codeReview = "code_review"
    case meeting
    case workItem = "work_item"
    case deployment
    case release
    case wiki
    case other

    /// Human-readable display name for UI
    public var displayName: String {
        switch self {
        case .commit: return "Commits"
        case .pullRequest: return "Pull Requests"
        case .issue: return "Issues"
        case .issueComment: return "Comments"
        case .codeReview: return "Code Reviews"
        case .meeting: return "Meetings"
        case .workItem: return "Work Items"
        case .deployment: return "Deployments"
        case .release: return "Releases"
        case .wiki: return "Wiki"
        case .other: return "Other"
        }
    }

    /// SF Symbol icon for the activity type
    public var iconName: String {
        switch self {
        case .commit: return "point.topleft.down.to.point.bottomright.curvepath"
        case .pullRequest: return "arrow.triangle.pull"
        case .issue: return "exclamationmark.circle"
        case .issueComment: return "text.bubble"
        case .codeReview: return "eye"
        case .meeting: return "video"
        case .workItem: return "checklist"
        case .deployment: return "shippingbox"
        case .release: return "tag"
        case .wiki: return "book"
        case .other: return "ellipsis.circle"
        }
    }

    /// Event types relevant for each provider
    public static func relevantTypes(for provider: Provider) -> [ActivityType] {
        switch provider {
        case .gitlab:
            return [.commit, .pullRequest, .issue, .issueComment, .codeReview, .release, .wiki]
        case .azureDevops:
            return [.commit, .pullRequest, .workItem]
        case .googleCalendar:
            return [.meeting]
        }
    }
}

/// Unified activity record matching activity-discovery schema
public struct UnifiedActivity: Codable, Sendable, Identifiable {
    public let id: String
    public let provider: Provider
    public let accountId: String
    public let sourceId: String
    public let type: ActivityType
    public let timestamp: Date
    public let title: String?
    public let summary: String?
    public let participants: [String]?
    public let url: URL?

    // UI-specific fields (ACTIVITY-056)
    public let authorAvatarURL: URL?
    public let labels: [ActivityLabel]?
    public let commentCount: Int?
    public let isDraft: Bool?
    public let sourceRef: String?  // For PRs: head branch
    public let targetRef: String?  // For PRs: base branch
    public let projectName: String?  // Project/repository name for grouping
    public let reviewers: [Participant]?  // Reviewers/assignees with avatars

    // Calendar event-specific fields
    public let endTimestamp: Date?  // End time for meetings (to calculate duration)
    public let isAllDay: Bool?  // Whether this is an all-day event
    public let attendees: [Participant]?  // Meeting attendees with avatars
    public let calendarId: String?  // Source calendar identifier for calendar events

    // Linked ticket/work item references
    public let linkedTickets: [LinkedTicket]?

    public init(
        id: String,
        provider: Provider,
        accountId: String,
        sourceId: String,
        type: ActivityType,
        timestamp: Date,
        title: String? = nil,
        summary: String? = nil,
        participants: [String]? = nil,
        url: URL? = nil,
        authorAvatarURL: URL? = nil,
        labels: [ActivityLabel]? = nil,
        commentCount: Int? = nil,
        isDraft: Bool? = nil,
        sourceRef: String? = nil,
        targetRef: String? = nil,
        projectName: String? = nil,
        reviewers: [Participant]? = nil,
        endTimestamp: Date? = nil,
        isAllDay: Bool? = nil,
        attendees: [Participant]? = nil,
        calendarId: String? = nil,
        linkedTickets: [LinkedTicket]? = nil
    ) {
        self.id = id
        self.provider = provider
        self.accountId = accountId
        self.sourceId = sourceId
        self.type = type
        self.timestamp = timestamp
        self.title = title
        self.summary = summary
        self.participants = participants
        self.url = url
        self.authorAvatarURL = authorAvatarURL
        self.labels = labels
        self.commentCount = commentCount
        self.isDraft = isDraft
        self.sourceRef = sourceRef
        self.targetRef = targetRef
        self.projectName = projectName
        self.reviewers = reviewers
        self.endTimestamp = endTimestamp
        self.isAllDay = isAllDay
        self.attendees = attendees
        self.calendarId = calendarId
        self.linkedTickets = linkedTickets
    }

    // Backward-compatible initializer (pre-ACTIVITY-056)
    public init(
        id: String,
        provider: Provider,
        accountId: String,
        sourceId: String,
        type: ActivityType,
        timestamp: Date,
        title: String? = nil,
        summary: String? = nil,
        participants: [String]? = nil,
        url: URL? = nil
    ) {
        self.init(
            id: id,
            provider: provider,
            accountId: accountId,
            sourceId: sourceId,
            type: type,
            timestamp: timestamp,
            title: title,
            summary: summary,
            participants: participants,
            url: url,
            authorAvatarURL: nil,
            labels: nil,
            commentCount: nil,
            isDraft: nil,
            sourceRef: nil,
            targetRef: nil,
            projectName: nil,
            reviewers: nil,
            endTimestamp: nil,
            isAllDay: nil,
            attendees: nil,
            calendarId: nil,
            linkedTickets: nil
        )
    }
}

/// Label for issues and pull requests
public struct ActivityLabel: Codable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public let color: String  // Hex color string (e.g., "FF0000" or "#FF0000")

    public init(id: String, name: String, color: String) {
        self.id = id
        self.name = name
        self.color = color
    }
}

// MARK: - Ticket/Work Item Types

/// Represents a ticket system type
public enum TicketSystem: String, Codable, Sendable, CaseIterable {
    case jira = "jira"
    case azureBoards = "azure_boards"
    case gitlabIssue = "gitlab_issue"
    case githubIssue = "github_issue"
    case linear = "linear"
    case youtrack = "youtrack"
    case shortcut = "shortcut"
    case unknown = "unknown"

    /// SF Symbol icon name for the ticket system
    public var iconName: String {
        switch self {
        case .jira: return "square.grid.2x2"
        case .azureBoards: return "checklist"
        case .gitlabIssue: return "exclamationmark.circle"
        case .githubIssue: return "exclamationmark.circle"
        case .linear: return "line.3.horizontal"
        case .youtrack: return "ticket"
        case .shortcut: return "bolt"
        case .unknown: return "tag"
        }
    }

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .jira: return "Jira"
        case .azureBoards: return "Azure Boards"
        case .gitlabIssue: return "GitLab Issue"
        case .githubIssue: return "GitHub Issue"
        case .linear: return "Linear"
        case .youtrack: return "YouTrack"
        case .shortcut: return "Shortcut"
        case .unknown: return "Ticket"
        }
    }

    /// Color associated with the ticket system (hex string)
    public var color: String {
        switch self {
        case .jira: return "0052CC"  // Jira blue
        case .azureBoards: return "0078D4"  // Azure blue
        case .gitlabIssue: return "FC6D26"  // GitLab orange
        case .githubIssue: return "238636"  // GitHub green
        case .linear: return "5E6AD2"  // Linear purple
        case .youtrack: return "FF318C"  // YouTrack pink
        case .shortcut: return "58B4DB"  // Shortcut teal
        case .unknown: return "6B7280"  // Gray
        }
    }
}

/// Where the ticket reference was found
public enum TicketSource: String, Codable, Sendable {
    case branchName = "branch"
    case title = "title"
    case description = "description"
    case apiLink = "api_link"

    /// Human-readable description of the source
    public var displayName: String {
        switch self {
        case .branchName: return "Branch"
        case .title: return "Title"
        case .description: return "Description"
        case .apiLink: return "Linked"
        }
    }
}

/// A linked ticket/work item reference
public struct LinkedTicket: Codable, Sendable, Identifiable, Equatable, Hashable {
    public var id: String { "\(system.rawValue):\(key)" }
    public let system: TicketSystem
    public let key: String           // e.g., "JIRA-123", "AB#456", "#789"
    public let title: String?        // Ticket title (if from API)
    public let url: URL?             // Deep link (if available)
    public let source: TicketSource  // Where it was found

    public init(system: TicketSystem, key: String, title: String? = nil, url: URL? = nil, source: TicketSource) {
        self.system = system
        self.key = key
        self.title = title
        self.url = url
        self.source = source
    }
}

/// Participant in an activity (reviewer, assignee, etc.)
public struct Participant: Codable, Sendable, Identifiable, Equatable {
    public var id: String { username }
    public let username: String
    public let avatarURL: URL?

    public init(username: String, avatarURL: URL? = nil) {
        self.username = username
        self.avatarURL = avatarURL
    }
}

/// Heatmap bucket matching activity-discovery schema
public struct HeatMapBucket: Codable, Sendable, Identifiable {
    public var id: String { date }
    public let date: String // YYYY-MM-DD
    public let count: Int
    public let breakdown: [Provider: Int]?

    public init(date: String, count: Int, breakdown: [Provider: Int]? = nil) {
        self.date = date
        self.count = count
        self.breakdown = breakdown
    }
}

/// Authentication method for provider accounts
public enum AuthMethod: String, Codable, Sendable {
    case oauth = "oauth"
    case pat = "pat"  // Personal Access Token
}

/// Account configuration
public struct Account: Codable, Sendable, Identifiable {
    public let id: String
    public let provider: Provider
    public let displayName: String
    public let host: String?
    // Azure DevOps-specific configuration
    public let organization: String?
    public let projects: [String]?
    // Google Calendar-specific configuration
    public let calendarIds: [String]?
    // Authentication method (OAuth vs PAT)
    public let authMethod: AuthMethod
    public var isEnabled: Bool
    // Event type filtering (nil = all types enabled)
    public var enabledEventTypes: Set<ActivityType>?
    // Authenticated user's username (for "show only my events" filtering)
    public let username: String?
    // Show only events where the authenticated user is the author (simple filter)
    public var showOnlyMyEvents: Bool
    // Google Calendar: Show only events where the user has accepted
    public var showOnlyAcceptedEvents: Bool
    // Google Calendar: Hide all-day events
    public var hideAllDayEvents: Bool

    public init(
        id: String,
        provider: Provider,
        displayName: String,
        host: String? = nil,
        organization: String? = nil,
        projects: [String]? = nil,
        calendarIds: [String]? = nil,
        authMethod: AuthMethod = .pat,
        isEnabled: Bool = true,
        enabledEventTypes: Set<ActivityType>? = nil,
        username: String? = nil,
        showOnlyMyEvents: Bool = false,
        showOnlyAcceptedEvents: Bool = false,
        hideAllDayEvents: Bool = false
    ) {
        self.id = id
        self.provider = provider
        self.displayName = displayName
        self.host = host
        self.organization = organization
        self.projects = projects
        self.calendarIds = calendarIds
        self.authMethod = authMethod
        self.isEnabled = isEnabled
        self.enabledEventTypes = enabledEventTypes
        self.username = username
        self.showOnlyMyEvents = showOnlyMyEvents
        self.showOnlyAcceptedEvents = showOnlyAcceptedEvents
        self.hideAllDayEvents = hideAllDayEvents
    }

    // Backward-compatible initializer (pre-ACTIVITY-037)
    public init(
        id: String,
        provider: Provider,
        displayName: String,
        host: String? = nil,
        isEnabled: Bool = true
    ) {
        self.init(
            id: id,
            provider: provider,
            displayName: displayName,
            host: host,
            organization: nil,
            projects: nil,
            calendarIds: nil,
            authMethod: .pat,
            isEnabled: isEnabled,
            enabledEventTypes: nil,
            username: nil,
            showOnlyMyEvents: false,
            showOnlyAcceptedEvents: false,
            hideAllDayEvents: false
        )
    }

    /// Check if a specific activity type is enabled for this account
    /// Returns true if enabledEventTypes is nil (all enabled) or if the type is in the set
    public func isEventTypeEnabled(_ type: ActivityType) -> Bool {
        guard let enabled = enabledEventTypes else { return true }
        return enabled.contains(type)
    }

    /// Check if a calendar event is enabled based on calendarId
    public func isCalendarEnabled(_ calendarId: String?) -> Bool {
        // If no specific calendarIds configured, show all
        guard let configuredIds = calendarIds, !configuredIds.isEmpty else { return true }
        guard let calendarId = calendarId else { return true }
        return configuredIds.contains(calendarId)
    }

    /// Get the relevant event types for this account based on its provider
    public var relevantEventTypes: [ActivityType] {
        ActivityType.relevantTypes(for: provider)
    }

    /// Whether this account supports calendar filtering
    public var supportsCalendarFiltering: Bool {
        provider == .googleCalendar
    }

    /// Check if an activity should be shown based on "show only my events" filter
    /// Returns true if showOnlyMyEvents is false, or if the activity's author matches the account username
    public func isMyEvent(author: String?) -> Bool {
        guard showOnlyMyEvents else { return true }
        guard let myUsername = username, !myUsername.isEmpty else { return true }
        guard let author = author, !author.isEmpty else { return true }
        // Case-insensitive comparison for usernames
        return author.lowercased() == myUsername.lowercased()
    }
}
