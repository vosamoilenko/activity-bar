# Provider Integration Guide

This document details how ActivityBar integrates with each supported provider.

## Table of Contents

- [Overview](#overview)
- [Provider Adapter Architecture](#provider-adapter-architecture)
- [GitLab](#gitlab)
- [Azure DevOps](#azure-devops)
- [Google Calendar](#google-calendar)
- [OAuth Authentication](#oauth-authentication)
- [Token Management](#token-management)
- [Adding New Providers](#adding-new-providers)

## Overview

ActivityBar supports three providers:

| Provider | Activity Types | Auth Method |
|----------|---------------|-------------|
| GitLab | Commits, MRs, Issues, Comments, Reviews | OAuth 2.0 |
| Azure DevOps | Commits, PRs, Work Items, Deployments | OAuth 2.0 |
| Google Calendar | Meetings | OAuth 2.0 |

All providers are normalized to the common `UnifiedActivity` structure, enabling a consistent UI experience.

## Provider Adapter Architecture

### Protocol Definition

```swift
protocol ProviderAdapter {
    var provider: Provider { get }

    func fetchActivities(
        for account: Account,
        token: String,
        from: Date,
        to: Date
    ) async throws -> [UnifiedActivity]

    func fetchHeatmap(
        for account: Account,
        token: String,
        from: Date,
        to: Date
    ) async throws -> [HeatMapBucket]
}
```

### Adapter Routing

`ActivityRefreshProvider` routes requests to the appropriate adapter:

```swift
func fetchActivities(for account: Account, ...) async throws -> [UnifiedActivity] {
    let adapter = adapterFor(account.provider)
    let token = try tokenStore.getToken(for: account.id)
    return try await adapter.fetchActivities(for: account, token: token, ...)
}

private func adapterFor(_ provider: Provider) -> ProviderAdapter {
    switch provider {
    case .gitlab: return gitLabAdapter
    case .azureDevops: return azureAdapter
    case .googleCalendar: return calendarAdapter
    }
}
```

## GitLab

### Configuration

```swift
struct GitLabAccountConfig {
    var host: String?  // nil = gitlab.com, otherwise self-hosted URL
}
```

### API Endpoints Used

| Endpoint | Purpose |
|----------|---------|
| `GET /users/:id/events` | Fetch user's activity events |
| `GET /user` | Get authenticated user info |
| `GET /projects/:id` | Get project details |
| `GET /projects/:id/merge_requests/:iid` | Get MR details |
| `GET /projects/:id/issues/:iid` | Get issue details |

### Activity Type Mapping

| GitLab Event | ActivityType |
|--------------|--------------|
| `pushed` | `.commit` |
| `opened` (MR) | `.pullRequest` |
| `merged` (MR) | `.pullRequest` |
| `closed` (MR/Issue) | `.pullRequest` / `.issue` |
| `opened` (Issue) | `.issue` |
| `commented` | `.issueComment` |
| `approved` | `.codeReview` |

### Implementation Details

```swift
class GitLabProviderAdapter: ProviderAdapter {
    func fetchActivities(...) async throws -> [UnifiedActivity] {
        // 1. Fetch user events with pagination (100 per page)
        let events = try await fetchUserEvents(userId, token, from, to)

        // 2. For each event, fetch additional details
        for event in events {
            if let projectId = event.projectId {
                let project = try await fetchProject(projectId, token)
                // Extract repo name, MR/issue details, etc.
            }
        }

        // 3. Normalize to UnifiedActivity
        return events.compactMap { normalizeEvent($0) }
    }
}
```

### Self-Hosted GitLab

For self-hosted instances:

```swift
let baseURL = account.gitLabConfig?.host ?? "https://gitlab.com"
let apiURL = "\(baseURL)/api/v4"
```

Ensure the OAuth application is registered on the self-hosted instance.

## Azure DevOps

### Configuration

```swift
struct AzureDevOpsAccountConfig {
    var organizationUrl: String  // e.g., "https://dev.azure.com/myorg"
    var projects: [String]?      // nil = all projects, or specific project names
}
```

### API Endpoints Used

| Endpoint | Purpose |
|----------|---------|
| `GET /_apis/projects` | List all projects |
| `GET /{project}/_apis/git/repositories` | List repositories |
| `GET /{project}/_apis/git/pullrequests` | List pull requests |
| `GET /{project}/_apis/git/repositories/{repo}/commits` | List commits |
| `GET /{project}/_apis/wit/wiql` | Query work items |

### Activity Type Mapping

| Azure DevOps Item | ActivityType |
|-------------------|--------------|
| Pull Request | `.pullRequest` |
| Commit | `.commit` |
| Work Item (Bug) | `.issue` |
| Work Item (Task) | `.workItem` |
| Deployment | `.deployment` |
| Release | `.release` |

### Implementation Details

```swift
class AzureDevOpsProviderAdapter: ProviderAdapter {
    func fetchActivities(...) async throws -> [UnifiedActivity] {
        // 1. Discover projects (max 10 to avoid over-fetching)
        let projects = try await fetchProjects(orgUrl, token)
        let limitedProjects = Array(projects.prefix(10))

        // 2. For each project, fetch PRs, commits, work items
        var activities: [UnifiedActivity] = []
        for project in limitedProjects {
            // Fetch PRs created by user
            let prs = try await fetchPullRequests(project, token, createdBy: userId)
            activities.append(contentsOf: prs.map { normalizePR($0) })

            // Fetch commits authored by user (max 10 repos per project)
            let repos = try await fetchRepositories(project, token)
            for repo in repos.prefix(10) {
                let commits = try await fetchCommits(repo, token, author: userEmail)
                activities.append(contentsOf: commits.map { normalizeCommit($0) })
            }

            // Fetch work items assigned to user
            let workItems = try await fetchWorkItems(project, token, assignedTo: userId)
            activities.append(contentsOf: workItems.map { normalizeWorkItem($0) })
        }

        return activities
    }
}
```

### API Version

Uses API version `7.0-preview` with Basic authentication:

```swift
let authHeader = "Basic " + "\(username):\(token)".base64Encoded()
```

## Google Calendar

### Configuration

```swift
struct GoogleCalendarAccountConfig {
    var calendarIds: [String]?  // nil = all calendars, or specific IDs
    var showOnlyMyEvents: Bool  // Only events where user is attendee
}
```

### API Endpoints Used

| Endpoint | Purpose |
|----------|---------|
| `GET /calendar/v3/users/me/calendarList` | List user's calendars |
| `GET /calendar/v3/calendars/{calendarId}/events` | List events in calendar |

### Activity Type Mapping

All calendar events map to `.meeting`.

### Implementation Details

```swift
class GoogleCalendarProviderAdapter: ProviderAdapter {
    func fetchActivities(...) async throws -> [UnifiedActivity] {
        // 1. List accessible calendars
        let calendars = try await fetchCalendarList(token)

        // 2. Filter to selected calendars (if configured)
        let selectedCalendars = filterCalendars(calendars, account.calendarConfig?.calendarIds)

        // 3. Fetch events from each calendar with pagination
        var activities: [UnifiedActivity] = []
        for calendar in selectedCalendars {
            let events = try await fetchEvents(
                calendarId: calendar.id,
                token: token,
                timeMin: from,
                timeMax: to
            )

            // 4. Filter to events where user is attendee (if configured)
            let filtered = account.calendarConfig?.showOnlyMyEvents == true
                ? events.filter { isUserAttendee($0) }
                : events

            activities.append(contentsOf: filtered.map { normalizeEvent($0) })
        }

        return activities
    }
}
```

### Event Normalization

```swift
func normalizeEvent(_ event: CalendarEvent) -> UnifiedActivity {
    UnifiedActivity(
        id: "googleCalendar:\(accountId):\(event.id)",
        provider: .googleCalendar,
        accountId: accountId,
        sourceId: event.id,
        type: .meeting,
        title: event.summary ?? "Untitled Event",
        timestamp: event.start.dateTime ?? event.start.date,
        endTimestamp: event.end.dateTime ?? event.end.date,
        isAllDay: event.start.date != nil,  // Date-only = all-day
        attendees: event.attendees?.map { Participant(name: $0.email, avatarURL: nil) },
        calendarId: calendarId
    )
}
```

## OAuth Authentication

### Flow Overview

```
1. User clicks "Add Account" → selects provider
2. App opens ASWebAuthenticationSession with provider's auth URL
3. User authenticates in browser
4. Provider redirects to localhost callback with auth code
5. App exchanges code for access token (and refresh token)
6. Tokens stored in Keychain
```

### OAuth Coordinator Protocol

```swift
protocol OAuthCoordinator {
    var provider: Provider { get }
    var authorizationURL: URL { get }
    var callbackURLScheme: String { get }

    func authenticate() async throws -> OAuthTokenResponse
    func refreshToken(_ refreshToken: String) async throws -> OAuthTokenResponse
}
```

### Provider-Specific OAuth Details

#### GitLab OAuth

| Parameter | Value |
|-----------|-------|
| Auth URL | `https://gitlab.com/oauth/authorize` |
| Token URL | `https://gitlab.com/oauth/token` |
| Callback | `http://localhost:8765/oauth/callback` |
| Scopes | `read_user, read_api` |

#### Azure DevOps OAuth

| Parameter | Value |
|-----------|-------|
| Auth URL | `https://app.vssps.visualstudio.com/oauth2/authorize` |
| Token URL | `https://app.vssps.visualstudio.com/oauth2/token` |
| Callback | `http://localhost:8766/oauth/callback` |
| Scopes | `vso.code, vso.work` |

#### Google Calendar OAuth

| Parameter | Value |
|-----------|-------|
| Auth URL | `https://accounts.google.com/o/oauth2/v2/auth` |
| Token URL | `https://oauth2.googleapis.com/token` |
| Callback | Dynamic localhost port |
| Scopes | `https://www.googleapis.com/auth/calendar.readonly` |

### Local OAuth Server

For providers requiring a localhost callback, `LocalOAuthServer` handles the redirect:

```swift
class LocalOAuthServer {
    func start(port: Int) async throws -> Int  // Returns actual port
    func waitForCallback() async throws -> [String: String]  // Query params
    func stop()
}
```

## Token Management

### Token Storage

Tokens are stored in macOS Keychain via `KeychainTokenStore`:

```swift
protocol TokenStore {
    func getToken(for accountId: String) -> String?
    func saveToken(_ token: String, for accountId: String) throws
    func deleteToken(for accountId: String) throws
    func getRefreshToken(for accountId: String) -> String?
    func saveRefreshToken(_ token: String, for accountId: String) throws
}
```

### Automatic Token Refresh

When a request returns 401 Unauthorized:

```swift
func fetchWithAutoRefresh(...) async throws -> Response {
    do {
        return try await fetch(token: accessToken)
    } catch ProviderError.unauthorized {
        // Attempt token refresh
        guard let refreshToken = tokenStore.getRefreshToken(for: accountId) else {
            throw ProviderError.authenticationRequired
        }

        let newTokens = try await tokenRefreshService.refresh(
            provider: account.provider,
            refreshToken: refreshToken
        )

        try tokenStore.saveToken(newTokens.accessToken, for: accountId)
        if let newRefresh = newTokens.refreshToken {
            try tokenStore.saveRefreshToken(newRefresh, for: accountId)
        }

        // Retry with new token
        return try await fetch(token: newTokens.accessToken)
    }
}
```

## Adding New Providers

To add a new provider:

### 1. Add Provider Enum Case

```swift
// In Types.swift
public enum Provider: String, Codable, CaseIterable {
    case gitlab
    case azureDevops
    case googleCalendar
    case newProvider  // Add new case
}
```

### 2. Create Provider Adapter

```swift
// NewProviderAdapter.swift
class NewProviderAdapter: ProviderAdapter {
    let provider: Provider = .newProvider
    let httpClient: HTTPClient

    func fetchActivities(
        for account: Account,
        token: String,
        from: Date,
        to: Date
    ) async throws -> [UnifiedActivity] {
        // Implement API calls and normalization
    }

    func fetchHeatmap(...) async throws -> [HeatMapBucket] {
        // Either fetch dedicated endpoint or generate from activities
    }
}
```

### 3. Create OAuth Coordinator

```swift
// NewProviderOAuthCoordinator.swift
class NewProviderOAuthCoordinator: OAuthCoordinator {
    let provider: Provider = .newProvider

    var authorizationURL: URL {
        // Build OAuth auth URL
    }

    func authenticate() async throws -> OAuthTokenResponse {
        // Implement OAuth flow
    }

    func refreshToken(_ refreshToken: String) async throws -> OAuthTokenResponse {
        // Implement token refresh
    }
}
```

### 4. Register in Factory

```swift
// In Providers.swift
enum OAuthCoordinatorFactory {
    static func coordinator(for provider: Provider) -> OAuthCoordinator {
        switch provider {
        // ... existing cases
        case .newProvider: return NewProviderOAuthCoordinator()
        }
    }
}
```

### 5. Add Adapter to RefreshProvider

```swift
// In ActivityRefreshProvider.swift
private func adapterFor(_ provider: Provider) -> ProviderAdapter {
    switch provider {
    // ... existing cases
    case .newProvider: return newProviderAdapter
    }
}
```

### 6. Add Activity Types

If the provider has unique activity types:

```swift
// In Types.swift
public enum ActivityType: String, Codable, CaseIterable {
    // ... existing types
    case newType

    public var displayName: String {
        switch self {
        case .newType: return "New Type"
        // ...
        }
    }

    public var iconName: String {
        switch self {
        case .newType: return "star"  // SF Symbol
        // ...
        }
    }
}
```

### 7. Create Activity View (Optional)

If the activity type needs custom rendering:

```swift
// NewTypeActivityView.swift
struct NewTypeActivityView: View {
    let activity: UnifiedActivity

    var body: some View {
        // Custom rendering
    }
}
```

### 8. Update UI to Handle New Provider

```swift
// In activity list rendering
switch activity.type {
case .newType:
    NewTypeActivityView(activity: activity)
// ... existing cases
}
```
