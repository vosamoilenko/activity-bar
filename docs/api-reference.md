# Internal API Reference

This document provides a reference for the internal APIs used throughout ActivityBar.

## Table of Contents

- [Core APIs](#core-apis)
- [Provider APIs](#provider-apis)
- [Storage APIs](#storage-apis)
- [OAuth APIs](#oauth-apis)

## Core APIs

### AppState

Root application state manager.

```swift
@Observable
@MainActor
public final class AppState {
    public let session: Session
    public var refreshError: Error?
    public var cacheLoadComplete: Bool
}
```

#### Account Management

```swift
/// Adds a new account
public func addAccount(_ account: Account)

/// Updates an existing account
public func updateAccount(_ account: Account)

/// Removes an account by ID
public func removeAccount(id: String)

/// Returns all enabled accounts
public var enabledAccounts: [Account]
```

#### Activity Management

```swift
/// Updates activities for a specific account
public func updateActivities(_ activities: [UnifiedActivity], for accountId: String)

/// Returns all activities from all enabled accounts, sorted by timestamp
public var allActivities: [UnifiedActivity]

/// Returns activities for a specific date
public func activities(for date: Date) -> [UnifiedActivity]
```

#### Heatmap Management

```swift
/// Merges new heatmap buckets with existing data
public func mergeHeatmapBuckets(_ buckets: [HeatMapBucket])

/// Returns heatmap buckets for the visible range
public var visibleHeatmapBuckets: [HeatMapBucket]
```

#### Selection

```swift
/// Selects a specific date for filtering
public func selectDate(_ date: Date)

/// Selects a date range
public func selectRange(_ range: DateRange)

/// Clears the current selection
public func clearSelection()
```

---

### DataCoordinator

Coordinates data loading from cache and network.

```swift
@MainActor
public final class DataCoordinator {
    public init(
        appState: AppState,
        cache: CacheProvider,
        provider: PerDayRefreshProvider
    )
}
```

#### Cache Operations

```swift
/// Loads all cached data (accounts, activities, heatmap)
/// Call on app startup
public func loadFromCache() async

/// Loads activities for a specific day
public func loadDay(_ date: Date) async throws

/// Returns true if initial network fetch is needed
public func needsInitialFetch() -> Bool
```

#### Refresh Operations

```swift
/// Performs a full background refresh
/// Phase 1: Today + yesterday (priority)
/// Phase 2: Older days (background)
public func refreshInBackground() async

/// Clears all cached data for an account
public func clearCache(for accountId: String)
```

---

### RefreshScheduler

Manages periodic refresh timing.

```swift
@MainActor
public final class RefreshScheduler {
    public init(
        interval: RefreshInterval,
        refreshAction: @escaping () async -> Void
    )
}
```

#### Properties

```swift
/// Current refresh interval setting
public var interval: RefreshInterval { get set }

/// Whether a refresh is currently in progress
public var isRefreshing: Bool { get }

/// When the last successful refresh completed
public var lastRefreshed: Date? { get }

/// Last error from refresh attempt
public var lastError: Error? { get }
```

#### Control Methods

```swift
/// Starts the automatic refresh timer
public func start()

/// Stops the automatic refresh timer
public func stop()

/// Triggers a refresh (debounced, 30s minimum between)
public func triggerRefresh()

/// Forces an immediate refresh (bypasses debounce)
public func forceRefresh()
```

---

### ActivityCollapser

Groups similar activities for display.

```swift
public enum ActivityCollapser {
    /// Collapses activities into groups where appropriate
    /// - Parameter activities: Raw activities sorted by timestamp
    /// - Returns: Array of displayable items (single or grouped)
    public static func collapse(_ activities: [UnifiedActivity]) -> [DisplayableActivity]
}
```

**Collapsing Rules:**

| Condition | Result |
|-----------|--------|
| Multiple commits to same branch within 2h | Grouped as "N commits to {branch}" |
| Multiple comments on same issue/PR within 2h | Grouped as "N comments on {target}" |
| Other activities | Remain as single items |

---

### HeatmapGenerator

Generates heatmap data from activities.

```swift
public enum HeatmapGenerator {
    /// Generates heatmap buckets from activities
    public static func generateBuckets(
        from activities: [UnifiedActivity],
        includeBreakdown: Bool = false
    ) -> [HeatMapBucket]

    /// Merges multiple bucket arrays, summing counts for same dates
    public static func mergeBuckets(_ bucketArrays: [[HeatMapBucket]]) -> [HeatMapBucket]
}
```

---

### PreferencesManager

Manages user preferences.

```swift
public final class PreferencesManager: ObservableObject {
    public static let shared: PreferencesManager
}
```

#### Properties

```swift
/// Auto-refresh interval
@AppStorage("refreshInterval")
public var refreshInterval: RefreshInterval

/// Start app on login
@AppStorage("launchAtLogin")
public var launchAtLogin: Bool

/// Panel blur effect
@AppStorage("panelBlurMaterial")
public var panelBlurMaterial: PanelBlurMaterial

/// Panel transparency (0.0-1.0)
@AppStorage("panelTransparency")
public var panelTransparency: Double

/// First day of week for heatmap
@AppStorage("weekStartDay")
public var weekStartDay: WeekStartDay
```

---

## Provider APIs

### ProviderAdapter Protocol

Interface for provider-specific implementations.

```swift
public protocol ProviderAdapter {
    var provider: Provider { get }

    /// Fetches activities for the given account and date range
    func fetchActivities(
        for account: Account,
        token: String,
        from: Date,
        to: Date
    ) async throws -> [UnifiedActivity]

    /// Fetches heatmap data for the given account and date range
    func fetchHeatmap(
        for account: Account,
        token: String,
        from: Date,
        to: Date
    ) async throws -> [HeatMapBucket]
}
```

### RefreshProvider Protocol

High-level interface for fetching activities.

```swift
public protocol RefreshProvider {
    /// Fetches all activities for an account within the specified days
    func fetchActivities(
        for account: Account,
        daysBack: Int
    ) async throws -> [UnifiedActivity]

    /// Fetches activities for multiple accounts
    func fetchActivities(
        for accounts: [Account],
        daysBack: Int
    ) async throws -> [String: [UnifiedActivity]]
}
```

### PerDayRefreshProvider Protocol

Interface for per-day fetching (more efficient for incremental updates).

```swift
public protocol PerDayRefreshProvider {
    /// Fetches activities for a single day
    func fetchActivitiesForDay(
        account: Account,
        date: Date
    ) async throws -> [UnifiedActivity]

    /// Fetches activities for a date range
    func fetchActivitiesForDateRange(
        account: Account,
        from: Date,
        to: Date
    ) async throws -> [UnifiedActivity]
}
```

### ActivityRefreshProvider

Concrete implementation of refresh providers.

```swift
public final class ActivityRefreshProvider: RefreshProvider, PerDayRefreshProvider {
    public init(
        tokenStore: TokenStore,
        cache: CacheProvider? = nil,
        gitLabAdapter: ProviderAdapter? = nil,
        azureAdapter: ProviderAdapter? = nil,
        calendarAdapter: ProviderAdapter? = nil
    )
}
```

**Features:**
- Routes to appropriate adapter based on account provider
- Retrieves tokens from token store
- Auto-refreshes OAuth tokens on 401 errors
- Optionally persists results to cache

---

### HTTPClient

Actor-based HTTP client for API requests.

```swift
public actor HTTPClient {
    public init(session: URLSession = .shared)
}
```

#### Request Methods

```swift
/// Performs a GET request
public func get(
    _ url: URL,
    headers: [String: String] = [:]
) async throws -> Data

/// Performs a POST request with JSON body
public func post(
    _ url: URL,
    json: [String: Any],
    headers: [String: String] = [:]
) async throws -> Data

/// Performs a GraphQL query
public func graphql(
    _ url: URL,
    query: String,
    variables: [String: Any]? = nil,
    headers: [String: String] = [:]
) async throws -> [String: Any]
```

#### Error Handling

All methods throw `ProviderError`:
- `.unauthorized` - 401 response
- `.rateLimited(retryAfter:)` - 429 response
- `.notFound` - 404 response
- `.serverError(statusCode:)` - 5xx response
- `.networkError(Error)` - Connection failures

---

## Storage APIs

### CacheProvider Protocol

Interface for activity caching.

```swift
public protocol CacheProvider {
    // MARK: - Per-Day Operations

    /// Loads activities for a specific day
    func loadActivitiesForDay(
        accountId: String,
        date: Date
    ) -> [UnifiedActivity]?

    /// Saves activities for a specific day
    func saveActivitiesForDay(
        _ activities: [UnifiedActivity],
        accountId: String,
        date: Date
    )

    /// Checks if a day has been fetched
    func isDayFetched(accountId: String, date: Date) -> Bool

    /// Gets the day index
    func getDayIndex() -> DayIndex

    /// Updates the day index
    func updateDayIndex(accountId: String, date: Date, count: Int)

    // MARK: - Heatmap Operations

    /// Loads cached heatmap for an account
    func loadHeatmap(for accountId: String) -> [HeatMapBucket]?

    /// Saves heatmap for an account
    func saveHeatmap(_ buckets: [HeatMapBucket], for accountId: String)

    // MARK: - Account Operations

    /// Loads all saved accounts
    func loadAccounts() -> [Account]?

    /// Saves accounts
    func saveAccounts(_ accounts: [Account])

    // MARK: - Maintenance

    /// Clears all cache for an account
    func clearCache(for accountId: String)
}
```

### DiskActivityCache

File-based implementation of CacheProvider.

```swift
public final class DiskActivityCache: CacheProvider {
    /// Creates a cache at the specified directory
    public init(directory: URL? = nil)
}
```

**Default Location:** `~/Library/Caches/com.activitybar/`

**File Structure:**

| Path | Contents |
|------|----------|
| `activities/{accountId}/{date}.json` | Day's activities |
| `heatmap_{accountId}.json` | Account heatmap |
| `accounts.json` | Account list |
| `day_index.json` | Day fetch status |

---

### TokenStore Protocol

Interface for secure token storage.

```swift
public protocol TokenStore {
    /// Gets the access token for an account
    func getToken(for accountId: String) -> String?

    /// Saves an access token
    func saveToken(_ token: String, for accountId: String) throws

    /// Deletes an access token
    func deleteToken(for accountId: String) throws

    /// Gets the refresh token for an account
    func getRefreshToken(for accountId: String) -> String?

    /// Saves a refresh token
    func saveRefreshToken(_ token: String, for accountId: String) throws

    /// Deletes a refresh token
    func deleteRefreshToken(for accountId: String) throws
}
```

### KeychainTokenStore

Keychain-based implementation of TokenStore.

```swift
public final class KeychainTokenStore: TokenStore {
    public init(service: String = "com.activitybar")
}
```

**Keychain Item Attributes:**

| Attribute | Value |
|-----------|-------|
| Service | `com.activitybar` |
| Account | `{accountId}` or `{accountId}_refresh` |
| Class | Generic Password |

---

### ProjectStore Protocol

Interface for project graph persistence.

```swift
public protocol ProjectStore {
    /// Lists all stored project IDs
    func listProjects() -> [String]

    /// Loads a project graph
    func loadGraph(for projectId: String) -> ProjectGraph?

    /// Saves a project graph
    func saveGraph(_ graph: ProjectGraph, for projectId: String) throws

    /// Deletes a project graph
    func deleteProject(_ projectId: String) throws
}
```

---

## OAuth APIs

### OAuthCoordinator Protocol

Interface for provider-specific OAuth flows.

```swift
public protocol OAuthCoordinator {
    var provider: Provider { get }

    /// The authorization URL to open in browser
    var authorizationURL: URL { get }

    /// The callback URL scheme to listen for
    var callbackURLScheme: String { get }

    /// Performs the full OAuth flow
    func authenticate() async throws -> OAuthTokenResponse

    /// Refreshes an expired token
    func refreshToken(_ refreshToken: String) async throws -> OAuthTokenResponse
}
```

### OAuthCoordinatorFactory

Creates provider-specific OAuth coordinators.

```swift
public enum OAuthCoordinatorFactory {
    /// Creates an OAuth coordinator for the given provider
    public static func coordinator(for provider: Provider) -> OAuthCoordinator
}
```

### TokenRefreshService

Handles automatic token refresh.

```swift
public final class TokenRefreshService {
    public init(tokenStore: TokenStore)

    /// Refreshes the token for an account
    /// - Returns: New access token
    public func refresh(
        account: Account
    ) async throws -> String
}
```

### OAuthClientCredentials

Actor managing OAuth client credentials.

```swift
public actor OAuthClientCredentials {
    public static let shared: OAuthClientCredentials

    // Setters
    public func setGitLabCredentials(clientId: String, clientSecret: String)
    public func setAzureCredentials(clientId: String, clientSecret: String)
    public func setGoogleCredentials(clientId: String, clientSecret: String)

    // Getters
    public func gitLabCredentials() -> (clientId: String, clientSecret: String)?
    public func azureCredentials() -> (clientId: String, clientSecret: String)?
    public func googleCredentials() -> (clientId: String, clientSecret: String)?
}
```

### LocalOAuthServer

Low-level server for OAuth callbacks.

```swift
public final class LocalOAuthServer {
    public init()

    /// Starts the server on the specified port
    /// - Returns: Actual port (may differ if requested port unavailable)
    public func start(port: Int) async throws -> Int

    /// Waits for the OAuth callback
    /// - Returns: Query parameters from callback URL
    public func waitForCallback() async throws -> [String: String]

    /// Stops the server
    public func stop()
}
```

---

## Error Types

### ProviderError

```swift
public enum ProviderError: Error, LocalizedError {
    case unauthorized
    case rateLimited(retryAfter: Int?)
    case networkError(Error)
    case invalidResponse
    case notFound
    case serverError(statusCode: Int)
    case authenticationRequired
}
```

### OAuthError

```swift
public enum OAuthError: Error, LocalizedError {
    case missingCredentials
    case invalidResponse
    case tokenExchangeFailed(String)
    case refreshFailed(String)
    case userCancelled
}
```

### CacheError

```swift
public enum CacheError: Error, LocalizedError {
    case directoryCreationFailed(Error)
    case encodingFailed(Error)
    case decodingFailed(Error)
    case writeFailed(Error)
    case readFailed(Error)
}
```
