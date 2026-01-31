# Architecture

This document provides a comprehensive technical overview of ActivityBar's architecture.

## Table of Contents

- [Overview](#overview)
- [Layer Architecture](#layer-architecture)
- [Application Lifecycle](#application-lifecycle)
- [State Management](#state-management)
- [Data Flow](#data-flow)
- [Threading Model](#threading-model)
- [Key Design Patterns](#key-design-patterns)

## Overview

ActivityBar is a macOS menu bar application built with Swift, SwiftUI, and AppKit. It follows a layered architecture that separates concerns into distinct modules:

```
┌─────────────────────────────────────────────────────────────┐
│                        App Layer                             │
│   (SwiftUI Views, Window Management, User Interaction)       │
├─────────────────────────────────────────────────────────────┤
│                       Core Layer                             │
│   (State Management, Data Coordination, Scheduling)          │
├─────────────────────────────────────────────────────────────┤
│                     Providers Layer                          │
│   (HTTP Client, OAuth, Provider Adapters)                    │
├─────────────────────────────────────────────────────────────┤
│                     Storage Layer                            │
│   (Disk Cache, Keychain, UserDefaults)                       │
└─────────────────────────────────────────────────────────────┘
```

## Layer Architecture

### App Layer (`Sources/App/`)

The App layer handles all user interface concerns:

| Component | Responsibility |
|-----------|----------------|
| `ActivityBarApp.swift` | App entry point, AppDelegate, menu bar setup |
| `ActivityWindowController.swift` | Main panel window management |
| `MenuBarContentView.swift` | Root content view with header/footer |
| `HeatmapView.swift` | Activity heatmap visualization |
| `ActivityListView.swift` | Scrollable activity list |
| `SettingsView.swift` | Settings window with tabs |
| `*ActivityView.swift` | Type-specific activity rendering |

**Key Characteristics:**
- Pure SwiftUI views with minimal business logic
- Receives data via Observable state
- Communicates actions via closures/callbacks
- Follows single-responsibility principle

### Core Layer (`Sources/Core/`)

The Core layer contains business logic and state management:

| Component | Responsibility |
|-----------|----------------|
| `AppState.swift` | Root observable state container |
| `Types.swift` | Data models (UnifiedActivity, Account, etc.) |
| `DataCoordinator.swift` | Orchestrates cache and network operations |
| `RefreshScheduler.swift` | Manages periodic refresh timing |
| `ActivityCollapsing.swift` | Groups similar activities |
| `UserPreferences.swift` | User settings management |
| `ProjectGraph.swift` | Project relationship modeling |

**Key Characteristics:**
- `@Observable` macro for reactive updates
- `@MainActor` isolation for UI safety
- Protocol-driven dependencies
- No UI imports (pure business logic)

### Providers Layer (`Sources/Providers/`)

The Providers layer handles external service communication:

| Component | Responsibility |
|-----------|----------------|
| `Providers.swift` | HTTPClient, base protocols |
| `GitLabProviderAdapter.swift` | GitLab API integration |
| `AzureDevOpsProviderAdapter.swift` | Azure DevOps API integration |
| `GoogleCalendarProviderAdapter.swift` | Google Calendar API integration |
| `ActivityRefreshProvider.swift` | Routes requests to adapters |
| `TokenRefreshService.swift` | OAuth token refresh logic |
| `AuthDefaults.swift` | OAuth client credentials |

**Key Characteristics:**
- Protocol-driven adapter pattern
- Actor-based HTTP client
- OAuth 2.0 with automatic token refresh
- Provider-agnostic `UnifiedActivity` output

### Storage Layer (`Sources/Storage/`)

The Storage layer handles persistence:

| Component | Responsibility |
|-----------|----------------|
| `Storage.swift` | Disk cache protocols and implementations |
| `ProjectStore.swift` | Project graph persistence |

**Key Characteristics:**
- Protocol-driven (enables testing with mocks)
- JSON serialization with ISO8601 dates
- Per-day file organization for activities
- Thread-safe with DispatchQueue

## Application Lifecycle

### Startup Sequence

```
1. @main ActivityBarApp initializes
   └── Creates AppDelegate via @NSApplicationDelegateAdaptor

2. AppDelegate.applicationDidFinishLaunching()
   ├── Sets activation policy to .regular
   ├── Creates ActivityWindowController
   ├── Calls setupStatusItem()
   │   └── Creates NSStatusItem with icon
   └── Calls initializeCoordinatorAndLoadCache()

3. initializeCoordinatorAndLoadCache()
   ├── Creates KeychainTokenStore
   ├── Creates DiskActivityCache
   ├── Creates ActivityRefreshProvider
   ├── Creates DataCoordinator
   ├── Creates RefreshScheduler
   └── Calls dataCoordinator.loadFromCache()

4. DataCoordinator.loadFromCache()
   ├── Loads accounts from disk
   ├── Calculates visible heatmap dates (13 weeks)
   ├── Loads per-day cache files in parallel
   └── Triggers initial fetch if needed
```

### Menu Bar Interaction

```
Left Click on Status Item:
  ├── If panel visible: hide panel
  └── If panel hidden: show panel, trigger refresh if needed

Right Click on Status Item:
  └── Show context menu (Settings, Quit)
```

## State Management

### Observable State Hierarchy

```
AppState (@Observable, @MainActor)
├── session: Session
│   ├── accounts: [Account]
│   ├── activitiesByAccount: [String: [UnifiedActivity]]
│   ├── heatmapBuckets: [HeatMapBucket]
│   ├── selectedDate: Date?
│   ├── selectedRange: DateRange?
│   ├── isRefreshing: Bool
│   └── isOffline: Bool
├── refreshError: Error?
└── cacheLoadComplete: Bool
```

### State Flow

```
User Action → AppState Method → Session Update → View Re-render
     │                │
     │                └── Cache/Network Operations (async)
     │
     └── View receives updated state automatically
```

### Key State Methods

```swift
// Account management
appState.addAccount(_ account: Account)
appState.updateAccount(_ account: Account)
appState.removeAccount(id: String)

// Activity management
appState.updateActivities(_ activities: [UnifiedActivity], for accountId: String)
appState.mergeHeatmapBuckets(_ buckets: [HeatMapBucket])

// Date selection
appState.selectDate(_ date: Date)
appState.selectRange(_ range: DateRange)
appState.clearSelection()
```

## Data Flow

### Activity Fetch Flow

```
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐
│ User clicks  │────▶│ DataCoordinator  │────▶│ RefreshProvider  │
│ heatmap date │     │ .loadDay(date)   │     │ .fetchForDay()   │
└──────────────┘     └──────────────────┘     └──────────────────┘
                                                       │
                                                       ▼
┌──────────────┐     ┌──────────────────┐     ┌──────────────────┐
│ View updates │◀────│ AppState updates │◀────│ Provider Adapter │
│ with data    │     │ activities       │     │ (GitLab/Azure)   │
└──────────────┘     └──────────────────┘     └──────────────────┘
```

### Periodic Refresh Flow

```
┌──────────────────┐     ┌──────────────────┐     ┌──────────────────┐
│ RefreshScheduler │────▶│ DataCoordinator  │────▶│ Phase 1: Priority│
│ timer fires      │     │ .refreshInBg()   │     │ (today/yesterday)│
└──────────────────┘     └──────────────────┘     └──────────────────┘
                                                           │
                                                           ▼
                         ┌──────────────────┐     ┌──────────────────┐
                         │ UI shows updated │◀────│ Phase 2: Older   │
                         │ activities       │     │ days (background)│
                         └──────────────────┘     └──────────────────┘
```

### Cache Strategy

```
Request for Day's Activities
        │
        ▼
┌───────────────────┐
│ Check DayIndex    │
│ isDayFetched?     │
└───────────────────┘
        │
   ┌────┴────┐
   │ Yes     │ No
   ▼         ▼
┌───────┐  ┌───────────────┐
│ Load  │  │ Fetch from    │
│ cache │  │ provider API  │
└───────┘  └───────────────┘
   │              │
   │              ▼
   │       ┌───────────────┐
   │       │ Save to cache │
   │       │ Update index  │
   │       └───────────────┘
   │              │
   └──────┬───────┘
          ▼
    Return activities
```

## Threading Model

### Actor Isolation

| Component | Isolation | Reason |
|-----------|-----------|--------|
| `AppState` | `@MainActor` | UI state must be on main thread |
| `Session` | `@MainActor` | Part of UI state |
| `DataCoordinator` | `@MainActor` | Updates UI state |
| `RefreshScheduler` | `@MainActor` | Timer fires on main thread |
| `HTTPClient` | `actor` | Protects HTTP session state |
| `OAuthClientCredentials` | `actor` | Protects shared credentials |

### Dispatch Queues

| Queue | QoS | Purpose |
|-------|-----|---------|
| `DiskActivityCache.queue` | `.utility` | Serialized disk I/O |
| `Main.async` | UI | View updates |

### Async Operations

```swift
// Example: Loading a day's activities
func loadDay(_ date: Date) async throws {
    // 1. Check cache (utility queue, via DiskActivityCache)
    if let cached = cache.loadActivitiesForDay(accountId, date) {
        // 2. Update state (main actor)
        await appState.updateActivities(cached, for: accountId)
        return
    }

    // 3. Fetch from network (background, via HTTPClient actor)
    let activities = try await provider.fetchActivitiesForDay(account, date)

    // 4. Save to cache (utility queue)
    cache.saveActivitiesForDay(activities, accountId, date)

    // 5. Update state (main actor)
    await appState.updateActivities(activities, for: accountId)
}
```

## Key Design Patterns

### Protocol-Driven Dependencies

All major components depend on protocols rather than concrete implementations:

```swift
protocol CacheProvider {
    func loadActivitiesForDay(...) -> [UnifiedActivity]?
    func saveActivitiesForDay(...)
}

protocol RefreshProvider {
    func fetchActivities(for account: Account, ...) async throws -> [UnifiedActivity]
}

protocol TokenStore {
    func getToken(for accountId: String) -> String?
    func saveToken(_ token: String, for accountId: String)
}
```

This enables:
- Unit testing with mocks
- Swapping implementations
- Clear interface boundaries

### Adapter Pattern (Providers)

Each provider implements `ProviderAdapter`:

```swift
protocol ProviderAdapter {
    var provider: Provider { get }
    func fetchActivities(for account: Account, ...) async throws -> [UnifiedActivity]
    func fetchHeatmap(for account: Account, ...) async throws -> [HeatMapBucket]
}

class GitLabProviderAdapter: ProviderAdapter { ... }
class AzureDevOpsProviderAdapter: ProviderAdapter { ... }
class GoogleCalendarProviderAdapter: ProviderAdapter { ... }
```

`ActivityRefreshProvider` routes to the appropriate adapter based on account type.

### Observer Pattern (SwiftUI)

Uses Swift's `@Observable` macro for automatic UI updates:

```swift
@Observable
@MainActor
public final class AppState {
    public var session: Session
    // Views automatically re-render when session changes
}
```

### Factory Pattern (OAuth)

`OAuthCoordinatorFactory` creates provider-specific coordinators:

```swift
enum OAuthCoordinatorFactory {
    static func coordinator(for provider: Provider) -> OAuthCoordinator {
        switch provider {
        case .gitlab: return GitLabOAuthCoordinator()
        case .azureDevops: return AzureDevOpsOAuthCoordinator()
        case .googleCalendar: return GoogleCalendarOAuthCoordinator()
        }
    }
}
```

### Coordinator Pattern

`DataCoordinator` orchestrates complex workflows:

```swift
final class DataCoordinator {
    // Coordinates cache loading, network fetching, state updates
    func loadFromCache() async
    func refreshInBackground() async
    func loadDay(_ date: Date) async
}
```

## File Organization

```
Sources/
├── App/                          # UI Layer
│   ├── ActivityBarApp.swift      # Entry point
│   ├── ActivityWindowController.swift
│   ├── MenuBarContentView.swift
│   ├── HeatmapView.swift
│   ├── ActivityListView.swift
│   ├── SettingsView.swift
│   ├── CommitActivityView.swift
│   ├── PullRequestActivityView.swift
│   ├── IssueActivityView.swift
│   ├── CommentActivityView.swift
│   ├── CodeReviewActivityView.swift
│   ├── ActivityRowView.swift
│   ├── RecentItemRowView.swift
│   ├── AvatarView.swift
│   ├── LabelChipView.swift
│   ├── ProviderBadgeView.swift
│   ├── MenuStatBadge.swift
│   ├── CalendarPickerView.swift
│   └── ...
├── Core/                         # Business Logic
│   ├── AppState.swift
│   ├── Types.swift
│   ├── DataCoordinator.swift
│   ├── RefreshScheduler.swift
│   ├── ActivityCollapsing.swift
│   ├── UserPreferences.swift
│   ├── ProjectGraph.swift
│   └── LaunchAtLoginManager.swift
├── Providers/                    # External Services
│   ├── Providers.swift
│   ├── GitLabProviderAdapter.swift
│   ├── AzureDevOpsProviderAdapter.swift
│   ├── GoogleCalendarProviderAdapter.swift
│   ├── ActivityRefreshProvider.swift
│   ├── TokenRefreshService.swift
│   └── AuthDefaults.swift
└── Storage/                      # Persistence
    ├── Storage.swift
    └── ProjectStore.swift
```
