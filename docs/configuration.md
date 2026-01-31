# Configuration Guide

This document covers all configuration options in ActivityBar.

## Table of Contents

- [User Preferences](#user-preferences)
- [Account Configuration](#account-configuration)
- [Cache Configuration](#cache-configuration)
- [OAuth Credentials (Development)](#oauth-credentials-development)
- [Environment Variables](#environment-variables)

## User Preferences

User preferences are stored in `UserDefaults` under the `com.activitybar` domain.

### Refresh Interval

Controls how often ActivityBar fetches new data from providers.

| Option | Value | Description |
|--------|-------|-------------|
| 5 minutes | `.fiveMinutes` | Most frequent updates |
| 15 minutes | `.fifteenMinutes` | **Default** |
| 30 minutes | `.thirtyMinutes` | Moderate updates |
| 1 hour | `.oneHour` | Infrequent updates |
| Manual | `.manual` | Only refresh on user action |

```swift
// Access via PreferencesManager
preferencesManager.refreshInterval = .fifteenMinutes
```

### Panel Blur Material

Sets the visual effect behind the activity panel.

| Option | Effect |
|--------|--------|
| `.none` | No blur, solid background |
| `.titlebar` | Title bar appearance |
| `.menu` | Menu appearance |
| `.popover` | Popover appearance |
| `.sidebar` | Sidebar appearance |
| `.headerView` | Header appearance |
| `.sheet` | Sheet appearance |
| `.windowBackground` | Window background |
| `.hudWindow` | HUD appearance |
| `.fullScreenUI` | Full screen UI |
| `.toolTip` | Tooltip appearance |

```swift
preferencesManager.panelBlurMaterial = .popover
```

### Panel Transparency

Controls the opacity of the panel background (0.0 to 1.0).

```swift
preferencesManager.panelTransparency = 0.9  // 90% opaque
```

### Week Start Day

Sets which day the heatmap weeks start on.

| Option | Description |
|--------|-------------|
| `.sunday` | Weeks start on Sunday (US default) |
| `.monday` | Weeks start on Monday (ISO standard) |

```swift
preferencesManager.weekStartDay = .monday
```

### Launch at Login

Whether ActivityBar starts automatically when you log in.

```swift
preferencesManager.launchAtLogin = true
```

This uses `SMAppService` for macOS 13+ to register the app as a login item.

## Account Configuration

Accounts are stored in the disk cache at `~/Library/Caches/com.activitybar/accounts.json`.

### Account Structure

```swift
public struct Account: Codable, Identifiable {
    public let id: String              // UUID
    public let provider: Provider       // gitlab, azureDevops, googleCalendar
    public var name: String            // Display name
    public var isEnabled: Bool         // Whether to fetch activities
    public var authMethod: AuthMethod  // oauth or pat

    // Provider-specific configuration
    public var gitLabConfig: GitLabAccountConfig?
    public var azureConfig: AzureDevOpsAccountConfig?
    public var calendarConfig: GoogleCalendarAccountConfig?

    // Filtering
    public var enabledEventTypes: Set<ActivityType>?  // nil = all types
}
```

### GitLab Account Configuration

```swift
public struct GitLabAccountConfig: Codable {
    public var host: String?  // nil for gitlab.com, or custom URL
}
```

**Example:**

```json
{
  "host": "https://gitlab.mycompany.com"
}
```

### Azure DevOps Account Configuration

```swift
public struct AzureDevOpsAccountConfig: Codable {
    public var organizationUrl: String  // Required
    public var projects: [String]?      // nil = all projects
}
```

**Example:**

```json
{
  "organizationUrl": "https://dev.azure.com/myorg",
  "projects": ["ProjectA", "ProjectB"]
}
```

### Google Calendar Account Configuration

```swift
public struct GoogleCalendarAccountConfig: Codable {
    public var calendarIds: [String]?   // nil = all calendars
    public var showOnlyMyEvents: Bool   // Filter to user's events
}
```

**Example:**

```json
{
  "calendarIds": ["primary", "work@group.calendar.google.com"],
  "showOnlyMyEvents": true
}
```

### Activity Type Filtering

Filter which activity types to show per account:

```swift
account.enabledEventTypes = [.commit, .pullRequest, .issue]
// Only shows commits, PRs, and issues for this account
```

Set to `nil` to show all activity types.

## Cache Configuration

### Cache Location

```
~/Library/Caches/com.activitybar/
├── activities/
│   └── {accountId}/
│       └── {yyyy-MM-dd}.json
├── heatmap_{accountId}.json
├── accounts.json
└── day_index.json
```

### Cache TTLs

| Data Type | TTL | Notes |
|-----------|-----|-------|
| Today's activities | 15 minutes | Still changing |
| Past day's activities | No expiry | History doesn't change |
| Heatmap | 6 hours | Regenerated periodically |
| Accounts | No expiry | Manual changes only |

### Day Index Structure

The `day_index.json` tracks which days have been fetched:

```json
{
  "accounts": {
    "account-uuid-1": {
      "2024-01-15": {
        "fetchedAt": "2024-01-15T10:30:00Z",
        "count": 12
      },
      "2024-01-14": {
        "fetchedAt": "2024-01-14T23:00:00Z",
        "count": 8
      }
    }
  }
}
```

### Clearing Cache

To clear all cached data:

```bash
rm -rf ~/Library/Caches/com.activitybar/*
```

To clear cache for a specific account:

```bash
rm -rf ~/Library/Caches/com.activitybar/activities/{accountId}
rm ~/Library/Caches/com.activitybar/heatmap_{accountId}.json
```

## OAuth Credentials (Development)

OAuth client credentials are required for each provider. These are typically bundled with the app but can be overridden for development.

### ActivityBarAuthDefaults

Default credentials are defined in `AuthDefaults.swift`:

```swift
public enum ActivityBarAuthDefaults {
    public static let gitLabClientId: String? = nil
    public static let gitLabClientSecret: String? = nil
    public static let azureDevOpsClientId: String? = nil
    public static let azureDevOpsClientSecret: String? = nil
    public static let googleCalendarClientId: String? = nil
    public static let googleCalendarClientSecret: String? = nil
}
```

### Runtime Credential Loading

The `OAuthClientCredentials` actor manages credentials at runtime:

```swift
actor OAuthClientCredentials {
    func setGitLabCredentials(clientId: String, clientSecret: String)
    func setAzureCredentials(clientId: String, clientSecret: String)
    func setGoogleCredentials(clientId: String, clientSecret: String)

    func gitLabCredentials() -> (clientId: String, clientSecret: String)?
    // ... etc
}
```

### Credential Prefill (Development)

In debug builds, `OAuthCredentialsLoader` loads credentials from the environment:

```swift
#if DEBUG
enum OAuthCredentialsLoader {
    static func loadFromEnvironment() {
        if let clientId = ProcessInfo.processInfo.environment["GITLAB_CLIENT_ID"],
           let clientSecret = ProcessInfo.processInfo.environment["GITLAB_CLIENT_SECRET"] {
            Task {
                await oauthCredentials.setGitLabCredentials(
                    clientId: clientId,
                    clientSecret: clientSecret
                )
            }
        }
        // ... similar for other providers
    }
}
#endif
```

## Environment Variables

For development and testing, credentials can be set via environment variables.

### Required Variables

| Variable | Provider | Description |
|----------|----------|-------------|
| `GITLAB_CLIENT_ID` | GitLab | OAuth application ID |
| `GITLAB_CLIENT_SECRET` | GitLab | OAuth application secret |
| `AZURE_CLIENT_ID` | Azure DevOps | App registration client ID |
| `AZURE_CLIENT_SECRET` | Azure DevOps | App registration secret |
| `GOOGLE_CLIENT_ID` | Google Calendar | OAuth 2.0 client ID |
| `GOOGLE_CLIENT_SECRET` | Google Calendar | OAuth 2.0 client secret |

### .env File Example

Create a `.env` file in the repository root:

```bash
# GitLab OAuth Application
# Create at: https://gitlab.com/-/profile/applications
GITLAB_CLIENT_ID=your_gitlab_client_id
GITLAB_CLIENT_SECRET=your_gitlab_client_secret

# Azure DevOps App Registration
# Create at: Azure Portal > App registrations
AZURE_CLIENT_ID=your_azure_client_id
AZURE_CLIENT_SECRET=your_azure_client_secret

# Google Cloud OAuth 2.0 Credentials
# Create at: Google Cloud Console > APIs & Services > Credentials
GOOGLE_CLIENT_ID=your_google_client_id.apps.googleusercontent.com
GOOGLE_CLIENT_SECRET=your_google_client_secret
```

### Loading Environment Variables

When running from Xcode or command line:

```bash
# Load from .env file
export $(cat .env | xargs)

# Then run the app
swift run ActivityBarApp
```

Or configure in Xcode scheme:
1. Edit Scheme → Run → Arguments → Environment Variables
2. Add each variable and its value

### Creating OAuth Applications

#### GitLab

1. Go to GitLab → Preferences → Applications
2. Create new application:
   - Name: ActivityBar
   - Redirect URI: `http://localhost:8765/oauth/callback`
   - Scopes: `read_user`, `read_api`
3. Copy Client ID and Secret

#### Azure DevOps

1. Go to Azure Portal → Azure Active Directory → App registrations
2. Create new registration:
   - Name: ActivityBar
   - Redirect URI: `http://localhost:8766/oauth/callback` (Web)
3. Add API permissions:
   - Azure DevOps → `vso.code`, `vso.work`
4. Create client secret under Certificates & secrets
5. Copy Application (client) ID and secret value

#### Google Calendar

1. Go to Google Cloud Console → APIs & Services → Credentials
2. Create OAuth 2.0 Client ID:
   - Application type: Desktop app
   - Name: ActivityBar
3. Enable Calendar API in APIs & Services → Library
4. Copy Client ID and Secret

### Production Credentials

For production builds, credentials should be:
1. Compiled into the app binary (set in `AuthDefaults.swift`)
2. Or retrieved from a secure configuration service
3. Never committed to version control

## Configuration Files Summary

| File | Location | Purpose |
|------|----------|---------|
| `accounts.json` | `~/Library/Caches/com.activitybar/` | Account configurations |
| `day_index.json` | `~/Library/Caches/com.activitybar/` | Cache index |
| `*.json` (activities) | `~/Library/Caches/com.activitybar/activities/` | Cached activities |
| UserDefaults | `com.activitybar` domain | User preferences |
| Keychain | System Keychain | OAuth tokens |
| `.env` | Repository root | Development credentials |
