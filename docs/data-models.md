# Data Models Reference

This document provides a complete reference for all data models used in ActivityBar.

## Table of Contents

- [Core Types](#core-types)
- [Activity Models](#activity-models)
- [Account Models](#account-models)
- [Heatmap Models](#heatmap-models)
- [State Models](#state-models)
- [Cache Models](#cache-models)
- [OAuth Models](#oauth-models)

## Core Types

### Provider

Represents a supported activity provider.

```swift
public enum Provider: String, Codable, CaseIterable, Sendable {
    case gitlab
    case azureDevops
    case googleCalendar
}
```

**Display Names:**

| Case | Display Name |
|------|--------------|
| `.gitlab` | "GitLab" |
| `.azureDevops` | "Azure DevOps" |
| `.googleCalendar` | "Google Calendar" |

### ActivityType

Types of activities that can be displayed.

```swift
public enum ActivityType: String, Codable, CaseIterable, Sendable {
    case commit
    case pullRequest
    case issue
    case issueComment
    case codeReview
    case meeting
    case workItem
    case deployment
    case release
    case wiki
    case other
}
```

**Properties:**

| Case | Display Name | Icon (SF Symbol) |
|------|--------------|------------------|
| `.commit` | "Commits" | `arrow.triangle.branch` |
| `.pullRequest` | "Pull Requests" | `arrow.triangle.pull` |
| `.issue` | "Issues" | `exclamationmark.circle` |
| `.issueComment` | "Comments" | `bubble.left` |
| `.codeReview` | "Code Reviews" | `checkmark.circle` |
| `.meeting` | "Meetings" | `calendar` |
| `.workItem` | "Work Items" | `checklist` |
| `.deployment` | "Deployments" | `shippingbox` |
| `.release` | "Releases" | `tag` |
| `.wiki` | "Wiki" | `doc.text` |
| `.other` | "Other" | `questionmark.circle` |

**Relevant Types by Provider:**

```swift
ActivityType.relevantTypes(for provider: Provider) -> [ActivityType]
```

| Provider | Relevant Types |
|----------|----------------|
| GitLab | commit, pullRequest, issue, issueComment, codeReview |
| Azure DevOps | commit, pullRequest, workItem, deployment, release |
| Google Calendar | meeting |

### AuthMethod

Authentication method for an account.

```swift
public enum AuthMethod: String, Codable, Sendable {
    case oauth
    case pat  // Personal Access Token
}
```

## Activity Models

### UnifiedActivity

The primary activity model, normalized across all providers.

```swift
public struct UnifiedActivity: Codable, Identifiable, Hashable, Sendable {
    // MARK: - Identity
    public let id: String           // Format: "provider:accountId:sourceId"
    public let provider: Provider
    public let accountId: String
    public let sourceId: String     // Provider-specific ID

    // MARK: - Core Data
    public let type: ActivityType
    public let title: String
    public let subtitle: String?
    public let url: URL?
    public let timestamp: Date

    // MARK: - Author
    public let authorName: String?
    public let authorAvatarURL: URL?

    // MARK: - Metadata
    public let labels: [ActivityLabel]?
    public let commentCount: Int?
    public let isDraft: Bool?

    // MARK: - PR/MR Specific
    public let sourceRef: String?    // Source branch
    public let targetRef: String?    // Target branch
    public let projectName: String?
    public let reviewers: [Participant]?

    // MARK: - Calendar Specific
    public let endTimestamp: Date?
    public let isAllDay: Bool?
    public let attendees: [Participant]?
    public let calendarId: String?

    // MARK: - Commit Specific
    public let commitSha: String?
    public let filesChanged: Int?
    public let additions: Int?
    public let deletions: Int?
}
```

**ID Format:**

The `id` uniquely identifies an activity across the entire system:
```
{provider}:{accountId}:{sourceId}
```

Examples:
- `gitlab:abc123:push_12345`
- `azureDevops:def456:pr_789`
- `googleCalendar:ghi789:event_abc`

### ActivityLabel

A label/tag attached to an activity (issues, PRs).

```swift
public struct ActivityLabel: Codable, Hashable, Sendable {
    public let name: String
    public let color: String?  // Hex color (e.g., "#ff0000")

    public init(name: String, color: String? = nil)
}
```

### Participant

Represents a person involved in an activity.

```swift
public struct Participant: Codable, Hashable, Sendable {
    public let name: String
    public let email: String?
    public let avatarURL: URL?

    public init(name: String, email: String? = nil, avatarURL: URL? = nil)
}
```

### DisplayableActivity

Wrapper for rendering in activity list (either single or grouped).

```swift
public enum DisplayableActivity: Identifiable {
    case single(UnifiedActivity)
    case group(CollapsedActivityGroup)

    public var id: String {
        switch self {
        case .single(let activity): return activity.id
        case .group(let group): return group.id
        }
    }
}
```

### CollapsedActivityGroup

A group of similar activities collapsed together.

```swift
public struct CollapsedActivityGroup: Identifiable {
    public let id: String
    public let type: ActivityType
    public let activities: [UnifiedActivity]
    public let summary: String       // e.g., "5 commits to main"
    public let timestamp: Date       // Most recent activity time
    public let provider: Provider
}
```

## Account Models

### Account

Represents a connected provider account.

```swift
public struct Account: Codable, Identifiable, Hashable, Sendable {
    public let id: String           // UUID
    public let provider: Provider
    public var name: String         // Display name
    public var isEnabled: Bool      // Whether to fetch activities
    public var authMethod: AuthMethod

    // Provider-specific configuration
    public var gitLabConfig: GitLabAccountConfig?
    public var azureConfig: AzureDevOpsAccountConfig?
    public var calendarConfig: GoogleCalendarAccountConfig?

    // Activity filtering
    public var enabledEventTypes: Set<ActivityType>?  // nil = all types
}
```

### GitLabAccountConfig

Configuration specific to GitLab accounts.

```swift
public struct GitLabAccountConfig: Codable, Hashable, Sendable {
    public var host: String?  // nil for gitlab.com, URL for self-hosted

    public init(host: String? = nil)
}
```

**Examples:**
- `GitLabAccountConfig()` → gitlab.com
- `GitLabAccountConfig(host: "https://gitlab.mycompany.com")` → self-hosted

### AzureDevOpsAccountConfig

Configuration specific to Azure DevOps accounts.

```swift
public struct AzureDevOpsAccountConfig: Codable, Hashable, Sendable {
    public var organizationUrl: String  // Required
    public var projects: [String]?      // nil = all projects

    public init(organizationUrl: String, projects: [String]? = nil)
}
```

**Examples:**
- `AzureDevOpsAccountConfig(organizationUrl: "https://dev.azure.com/myorg")` → all projects
- `AzureDevOpsAccountConfig(organizationUrl: "https://dev.azure.com/myorg", projects: ["ProjectA"])` → specific project

### GoogleCalendarAccountConfig

Configuration specific to Google Calendar accounts.

```swift
public struct GoogleCalendarAccountConfig: Codable, Hashable, Sendable {
    public var calendarIds: [String]?   // nil = all calendars
    public var showOnlyMyEvents: Bool   // Only events where user is attendee

    public init(calendarIds: [String]? = nil, showOnlyMyEvents: Bool = true)
}
```

## Heatmap Models

### HeatMapBucket

Activity count for a single day.

```swift
public struct HeatMapBucket: Codable, Hashable, Sendable {
    public let date: String           // Format: "yyyy-MM-dd" (UTC)
    public let count: Int             // Total activities
    public let breakdown: [Provider: Int]?  // Per-provider counts

    public init(date: String, count: Int, breakdown: [Provider: Int]? = nil)
}
```

**Date Format:**

Dates are stored as UTC strings in `yyyy-MM-dd` format for consistency across time zones.

**Example:**

```json
{
  "date": "2024-01-15",
  "count": 12,
  "breakdown": {
    "gitlab": 8,
    "azureDevops": 4
  }
}
```

### DateRange

A date range for filtering activities.

```swift
public struct DateRange: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date)

    public func contains(_ date: Date) -> Bool
}
```

## State Models

### Session

Observable session state.

```swift
@Observable
@MainActor
public final class Session {
    // Accounts
    public var accounts: [Account]

    // Activities indexed by account ID
    public var activitiesByAccount: [String: [UnifiedActivity]]

    // Heatmap data
    public var heatmapBuckets: [HeatMapBucket]

    // Selection state
    public var selectedDate: Date?
    public var selectedRange: DateRange?

    // Loading state
    public var isRefreshing: Bool
    public var isOffline: Bool

    // Cache tracking
    public var loadedDays: Set<String>   // Days loaded from cache
    public var loadingDays: Set<String>  // Days currently being loaded
}
```

### AppState

Root application state.

```swift
@Observable
@MainActor
public final class AppState {
    public let session: Session
    public var refreshError: Error?
    public var cacheLoadComplete: Bool

    // Computed
    public var allActivities: [UnifiedActivity]  // Merged from all accounts

    // Methods
    public func addAccount(_ account: Account)
    public func updateAccount(_ account: Account)
    public func removeAccount(id: String)
    public func updateActivities(_ activities: [UnifiedActivity], for accountId: String)
    public func mergeHeatmapBuckets(_ buckets: [HeatMapBucket])
    public func selectDate(_ date: Date)
    public func clearSelection()
}
```

## Cache Models

### DayIndex

Index of cached day data.

```swift
public struct DayIndex: Codable {
    public var accounts: [String: [String: DayStatus]]
    // accountId -> dateString -> status

    public init()
    public mutating func update(accountId: String, date: String, status: DayStatus)
    public func status(for accountId: String, date: String) -> DayStatus?
}
```

### DayStatus

Status of a cached day.

```swift
public struct DayStatus: Codable {
    public let fetchedAt: Date
    public let count: Int

    public init(fetchedAt: Date, count: Int)
}
```

**Cache Validity:**

```swift
extension DayStatus {
    var isStale: Bool {
        // Today's data: stale after 15 minutes
        // Past data: never stale
        if isToday {
            return Date().timeIntervalSince(fetchedAt) > 15 * 60
        }
        return false
    }
}
```

### CachedActivities

Wrapper for cached activity data.

```swift
struct CachedActivities: Codable {
    let activities: [UnifiedActivity]
    let fetchedAt: Date
}
```

### CachedHeatmap

Wrapper for cached heatmap data.

```swift
struct CachedHeatmap: Codable {
    let buckets: [HeatMapBucket]
    let fetchedAt: Date
}
```

## OAuth Models

### OAuthTokenResponse

Response from OAuth token exchange.

```swift
public struct OAuthTokenResponse: Codable, Sendable {
    public let accessToken: String
    public let refreshToken: String?
    public let expiresIn: Int?           // Seconds until expiry
    public let tokenType: String?        // Usually "Bearer"
    public let scope: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case tokenType = "token_type"
        case scope
    }
}
```

### OAuthError

OAuth-specific errors.

```swift
public enum OAuthError: Error, LocalizedError {
    case missingCredentials
    case invalidResponse
    case tokenExchangeFailed(String)
    case refreshFailed(String)
    case userCancelled

    public var errorDescription: String? {
        switch self {
        case .missingCredentials:
            return "OAuth credentials not configured"
        case .invalidResponse:
            return "Invalid response from OAuth server"
        case .tokenExchangeFailed(let message):
            return "Token exchange failed: \(message)"
        case .refreshFailed(let message):
            return "Token refresh failed: \(message)"
        case .userCancelled:
            return "Authentication was cancelled"
        }
    }
}
```

### ProviderError

General provider errors.

```swift
public enum ProviderError: Error, LocalizedError {
    case unauthorized
    case rateLimited(retryAfter: Int?)
    case networkError(Error)
    case invalidResponse
    case notFound
    case serverError(statusCode: Int)
    case authenticationRequired

    public var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "Authentication required"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Retry after \(seconds) seconds"
            }
            return "Rate limited"
        case .networkError(let error):
            return "Network error: \(error.localizedDescription)"
        case .invalidResponse:
            return "Invalid response from server"
        case .notFound:
            return "Resource not found"
        case .serverError(let code):
            return "Server error (HTTP \(code))"
        case .authenticationRequired:
            return "Please re-authenticate your account"
        }
    }
}
```

## User Preferences Models

### RefreshInterval

How often to auto-refresh.

```swift
public enum RefreshInterval: String, Codable, CaseIterable {
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case manual

    public var timeInterval: TimeInterval? {
        switch self {
        case .fiveMinutes: return 5 * 60
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .manual: return nil
        }
    }

    public var displayName: String {
        switch self {
        case .fiveMinutes: return "Every 5 minutes"
        case .fifteenMinutes: return "Every 15 minutes"
        case .thirtyMinutes: return "Every 30 minutes"
        case .oneHour: return "Every hour"
        case .manual: return "Manual only"
        }
    }
}
```

### PanelBlurMaterial

Visual effect material options.

```swift
public enum PanelBlurMaterial: String, Codable, CaseIterable {
    case none
    case titlebar
    case menu
    case popover
    case sidebar
    case headerView
    case sheet
    case windowBackground
    case hudWindow
    case fullScreenUI
    case toolTip

    public var nsMaterial: NSVisualEffectView.Material? {
        switch self {
        case .none: return nil
        case .titlebar: return .titlebar
        case .menu: return .menu
        case .popover: return .popover
        case .sidebar: return .sidebar
        case .headerView: return .headerView
        case .sheet: return .sheet
        case .windowBackground: return .windowBackground
        case .hudWindow: return .hudWindow
        case .fullScreenUI: return .fullScreenUI
        case .toolTip: return .toolTip
        }
    }
}
```

### WeekStartDay

First day of the week for heatmap.

```swift
public enum WeekStartDay: String, Codable, CaseIterable {
    case sunday
    case monday

    public var calendarWeekday: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        }
    }
}
```

## JSON Serialization

All models use Swift's `Codable` protocol with the following conventions:

### Date Encoding

```swift
let encoder = JSONEncoder()
encoder.dateEncodingStrategy = .iso8601

let decoder = JSONDecoder()
decoder.dateDecodingStrategy = .iso8601
```

### Heatmap Date Strings

Heatmap dates use string format `yyyy-MM-dd` in UTC:

```swift
let formatter = DateFormatter()
formatter.dateFormat = "yyyy-MM-dd"
formatter.timeZone = TimeZone(identifier: "UTC")
```

### Provider Enum Encoding

Providers encode as their raw string value:

```json
{
  "provider": "gitlab"
}
```

### Optional Fields

Optional fields are omitted from JSON when nil (using default Codable behavior):

```json
{
  "id": "gitlab:abc:123",
  "title": "My Activity",
  "subtitle": null  // This would be omitted
}
```
