import Foundation
import Core
import Storage

// Re-export for convenience
private typealias DateHelper = CacheKeyGenerator

/// Implementation of RefreshProvider that routes fetch requests to provider adapters
///
/// This bridges the provider adapters (GitLab, Azure DevOps, Google Calendar) to the DataCoordinator's
/// refresh system, handling token retrieval and per-account fetching.
///
/// Includes automatic token refresh: when a 401 authentication error occurs, the provider
/// will attempt to refresh the OAuth token and retry the request once.
public final class ActivityRefreshProvider: RefreshProvider, PerDayRefreshProvider, @unchecked Sendable {
    private let tokenStore: TokenStore
    private let adapters: [Provider: ProviderAdapter]
    private let daysBack: Int

    /// Cache for persisting fetched data
    private let cache: ActivityCache?

    /// Service for refreshing OAuth tokens on authentication failure
    private let refreshService: TokenRefreshing

    /// Creates a new ActivityRefreshProvider
    /// - Parameters:
    ///   - tokenStore: Store for retrieving account tokens
    ///   - daysBack: Number of days to fetch activities for (default: 30)
    ///   - cache: Optional cache for persisting fetched data
    ///   - adapters: Optional custom adapters (defaults to standard set)
    ///   - refreshService: Service for refreshing OAuth tokens (defaults to TokenRefreshService)
    public init(
        tokenStore: TokenStore,
        daysBack: Int = 30,
        cache: ActivityCache? = nil,
        adapters: [Provider: ProviderAdapter]? = nil,
        refreshService: TokenRefreshing? = nil
    ) {
        self.tokenStore = tokenStore
        self.daysBack = daysBack
        self.cache = cache
        self.adapters = adapters ?? Self.createDefaultAdapters()
        self.refreshService = refreshService ?? TokenRefreshService()
    }

    // MARK: - RefreshProvider Protocol

    /// Fetch fresh activities for an account
    /// If authentication fails, attempts to refresh the token and retry once
    public func fetchActivities(for account: Account) async throws -> [UnifiedActivity] {
        print("[ActivityBar][RefreshProvider] fetchActivities called for account: \(account.id)")
        print("[ActivityBar][RefreshProvider]   provider: \(account.provider)")
        print("[ActivityBar][RefreshProvider]   isEnabled: \(account.isEnabled)")

        guard account.isEnabled else {
            print("[ActivityBar][RefreshProvider] Account is disabled, returning empty")
            return []
        }

        guard let adapter = adapters[account.provider] else {
            print("[ActivityBar][RefreshProvider] ERROR: No adapter for provider \(account.provider)")
            throw ProviderError.notImplemented
        }
        print("[ActivityBar][RefreshProvider] Found adapter: \(type(of: adapter))")

        print("[ActivityBar][RefreshProvider] Getting token for account: \(account.id)")
        guard let token = try await tokenStore.getToken(for: account.id), !token.isEmpty else {
            print("[ActivityBar][RefreshProvider] ERROR: No token found for account \(account.id)")
            throw ProviderError.authenticationFailed("No token found for account \(account.id)")
        }
        print("[ActivityBar][RefreshProvider] Token found, length: \(token.count) chars")

        let (from, to) = calculateDateRange()
        print("[ActivityBar][RefreshProvider] Date range: \(from) to \(to)")

        // Try fetching activities, with automatic token refresh on auth failure
        let activities = try await fetchWithAutoRefresh(
            account: account,
            token: token,
            adapter: adapter,
            from: from,
            to: to
        )

        // Persist to cache if available
        if let cache = cache {
            print("[ActivityBar][RefreshProvider] Saving to cache...")
            await cache.saveActivities(activities, for: account, from: from, to: to)
        }

        return activities
    }

    /// Attempt to fetch activities, refreshing token on auth failure
    private func fetchWithAutoRefresh(
        account: Account,
        token: String,
        adapter: ProviderAdapter,
        from: Date,
        to: Date
    ) async throws -> [UnifiedActivity] {
        do {
            print("[ActivityBar][RefreshProvider] Calling adapter.fetchActivities...")
            let activities = try await adapter.fetchActivities(
                for: account,
                token: token,
                from: from,
                to: to
            )
            print("[ActivityBar][RefreshProvider] Adapter returned \(activities.count) activities")
            return activities
        } catch let error as ProviderError {
            // Check if this is an authentication error that can be retried
            guard case .authenticationFailed = error else {
                throw error
            }

            // Check if we can refresh the token for this account
            guard refreshService.canRefresh(account: account) else {
                print("[ActivityBar][RefreshProvider] Cannot refresh token for account \(account.id) - rethrowing auth error")
                throw error
            }

            print("[ActivityBar][RefreshProvider] Auth failed, attempting token refresh for \(account.id)...")

            // Try to refresh the token
            let newToken: String
            do {
                newToken = try await refreshService.refreshToken(for: account, using: tokenStore)
                print("[ActivityBar][RefreshProvider] Token refreshed successfully, retrying fetch...")
            } catch {
                print("[ActivityBar][RefreshProvider] Token refresh failed: \(error)")
                throw ProviderError.authenticationFailed("Token refresh failed - please re-authenticate")
            }

            // Retry with the new token (no more retries after this)
            let activities = try await adapter.fetchActivities(
                for: account,
                token: newToken,
                from: from,
                to: to
            )
            print("[ActivityBar][RefreshProvider] Retry successful, got \(activities.count) activities")
            return activities
        }
    }

    /// Fetch fresh heatmap data for an account
    /// If authentication fails, attempts to refresh the token and retry once
    public func fetchHeatmap(for account: Account) async throws -> [HeatMapBucket] {
        print("[ActivityBar][RefreshProvider] fetchHeatmap called for account: \(account.id)")

        guard account.isEnabled else {
            print("[ActivityBar][RefreshProvider] Account is disabled, returning empty heatmap")
            return []
        }

        guard let adapter = adapters[account.provider] else {
            print("[ActivityBar][RefreshProvider] ERROR: No adapter for heatmap")
            throw ProviderError.notImplemented
        }

        guard let token = try await tokenStore.getToken(for: account.id), !token.isEmpty else {
            print("[ActivityBar][RefreshProvider] ERROR: No token for heatmap")
            throw ProviderError.authenticationFailed("No token found for account \(account.id)")
        }

        let (from, to) = calculateDateRange()

        // Try fetching heatmap, with automatic token refresh on auth failure
        let buckets = try await fetchHeatmapWithAutoRefresh(
            account: account,
            token: token,
            adapter: adapter,
            from: from,
            to: to
        )

        // Persist to cache if available
        if let cache = cache {
            await cache.saveHeatmap(buckets, for: account)
        }

        return buckets
    }

    /// Attempt to fetch heatmap, refreshing token on auth failure
    private func fetchHeatmapWithAutoRefresh(
        account: Account,
        token: String,
        adapter: ProviderAdapter,
        from: Date,
        to: Date
    ) async throws -> [HeatMapBucket] {
        do {
            print("[ActivityBar][RefreshProvider] Calling adapter.fetchHeatmap...")
            let buckets = try await adapter.fetchHeatmap(
                for: account,
                token: token,
                from: from,
                to: to
            )
            print("[ActivityBar][RefreshProvider] Adapter returned \(buckets.count) heatmap buckets")
            return buckets
        } catch let error as ProviderError {
            // Check if this is an authentication error that can be retried
            guard case .authenticationFailed = error else {
                throw error
            }

            // Check if we can refresh the token for this account
            guard refreshService.canRefresh(account: account) else {
                print("[ActivityBar][RefreshProvider] Cannot refresh token for heatmap \(account.id) - rethrowing auth error")
                throw error
            }

            print("[ActivityBar][RefreshProvider] Heatmap auth failed, attempting token refresh for \(account.id)...")

            // Try to refresh the token
            let newToken: String
            do {
                newToken = try await refreshService.refreshToken(for: account, using: tokenStore)
                print("[ActivityBar][RefreshProvider] Token refreshed successfully, retrying heatmap fetch...")
            } catch {
                print("[ActivityBar][RefreshProvider] Token refresh failed for heatmap: \(error)")
                throw ProviderError.authenticationFailed("Token refresh failed - please re-authenticate")
            }

            // Retry with the new token (no more retries after this)
            let buckets = try await adapter.fetchHeatmap(
                for: account,
                token: newToken,
                from: from,
                to: to
            )
            print("[ActivityBar][RefreshProvider] Heatmap retry successful, got \(buckets.count) buckets")
            return buckets
        }
    }

    // MARK: - Single-Day Fetch

    /// Fetch activities for a specific day
    /// - Parameters:
    ///   - account: The account to fetch for
    ///   - date: The date to fetch (only day matters, time is ignored)
    /// - Returns: Activities for that day
    public func fetchActivitiesForDay(for account: Account, date: Date) async throws -> [UnifiedActivity] {
        print("[ActivityBar][RefreshProvider] fetchActivitiesForDay called for account: \(account.id), date: \(date)")

        guard account.isEnabled else {
            print("[ActivityBar][RefreshProvider] Account is disabled, returning empty")
            return []
        }

        guard let adapter = adapters[account.provider] else {
            print("[ActivityBar][RefreshProvider] ERROR: No adapter for provider \(account.provider)")
            throw ProviderError.notImplemented
        }

        guard let token = try await tokenStore.getToken(for: account.id), !token.isEmpty else {
            print("[ActivityBar][RefreshProvider] ERROR: No token found for account \(account.id)")
            throw ProviderError.authenticationFailed("No token found for account \(account.id)")
        }

        let (from, to) = calculateSingleDayRange(date)
        let dateStr = CacheKeyGenerator.dateString(from: date)
        print("[ActivityBar][RefreshProvider] Fetching single day: \(dateStr) (\(from) to \(to))")

        // Try fetching activities, with automatic token refresh on auth failure
        let allActivities = try await fetchWithAutoRefresh(
            account: account,
            token: token,
            adapter: adapter,
            from: from,
            to: to
        )

        // Filter activities to only include those matching the requested date
        // (provider may return activities from other dates due to API limitations)
        let activities = allActivities.filter { activity in
            CacheKeyGenerator.dateString(from: activity.timestamp) == dateStr
        }

        if activities.count != allActivities.count {
            print("[ActivityBar][RefreshProvider] Filtered \(allActivities.count) -> \(activities.count) activities for date \(dateStr)")
        }

        // Persist to per-day cache if available
        if let cache = cache {
            print("[ActivityBar][RefreshProvider] Saving to per-day cache...")
            await cache.saveActivitiesForDay(activities, accountId: account.id, date: dateStr)
        }

        return activities
    }

    // MARK: - Batch Date Range Fetch

    /// Fetch activities for a date range in a single request, grouped by day
    /// Much more efficient than fetching each day individually
    public func fetchActivitiesForDateRange(for account: Account, from: Date, to: Date) async throws -> [String: [UnifiedActivity]] {
        print("[ActivityBar][RefreshProvider] fetchActivitiesForDateRange called for account: \(account.id)")
        print("[ActivityBar][RefreshProvider]   range: \(from) to \(to)")

        guard account.isEnabled else {
            print("[ActivityBar][RefreshProvider] Account is disabled, returning empty")
            return [:]
        }

        guard let adapter = adapters[account.provider] else {
            print("[ActivityBar][RefreshProvider] ERROR: No adapter for provider \(account.provider)")
            throw ProviderError.notImplemented
        }

        guard let token = try await tokenStore.getToken(for: account.id), !token.isEmpty else {
            print("[ActivityBar][RefreshProvider] ERROR: No token found for account \(account.id)")
            throw ProviderError.authenticationFailed("No token found for account \(account.id)")
        }

        // Calculate proper date range (start of first day to end of last day)
        let calendar = Calendar.current
        let startOfFrom = calendar.startOfDay(for: from)
        let endOfTo = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: to)!

        print("[ActivityBar][RefreshProvider] Fetching date range: \(startOfFrom) to \(endOfTo)")

        // Fetch all activities in one request
        let activities = try await fetchWithAutoRefresh(
            account: account,
            token: token,
            adapter: adapter,
            from: startOfFrom,
            to: endOfTo
        )

        print("[ActivityBar][RefreshProvider] Got \(activities.count) activities for date range")

        // Generate all dates in the requested range
        var allDatesInRange: [String] = []
        var currentDate = startOfFrom
        while currentDate <= endOfTo {
            allDatesInRange.append(CacheKeyGenerator.dateString(from: currentDate))
            currentDate = calendar.date(byAdding: .day, value: 1, to: currentDate)!
        }

        // Group activities by day (only days with activities will have entries)
        var activitiesByDay: [String: [UnifiedActivity]] = [:]
        for activity in activities {
            let dateStr = CacheKeyGenerator.dateString(from: activity.timestamp)
            activitiesByDay[dateStr, default: []].append(activity)
        }

        // Save ALL days in range to cache (including empty ones)
        // This prevents re-fetching days that were checked but had no activities
        if let cache = cache {
            print("[ActivityBar][RefreshProvider] Saving \(allDatesInRange.count) days to per-day cache (\(activitiesByDay.count) with activities)...")
            for dateStr in allDatesInRange {
                let dayActivities = activitiesByDay[dateStr] ?? []
                await cache.saveActivitiesForDay(dayActivities, accountId: account.id, date: dateStr)
            }
        }

        // Include all dates in the result (empty arrays for days with no activities)
        for dateStr in allDatesInRange {
            if activitiesByDay[dateStr] == nil {
                activitiesByDay[dateStr] = []
            }
        }

        print("[ActivityBar][RefreshProvider] Grouped into \(activitiesByDay.count) days (\(activities.count) activities)")
        return activitiesByDay
    }

    // MARK: - Date Range

    /// Calculate the date range for fetching activities
    /// Uses end of current day to include all today's events (not just past ones)
    private func calculateDateRange() -> (from: Date, to: Date) {
        let now = Date()
        let calendar = Calendar.current
        let from = calendar.date(byAdding: .day, value: -daysBack, to: now)!

        // Use end of today (23:59:59) to include all of today's events
        let endOfToday = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: now)!
        return (from, endOfToday)
    }

    /// Calculate range for a single day (00:00:00 to 23:59:59)
    private func calculateSingleDayRange(_ date: Date) -> (from: Date, to: Date) {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(bySettingHour: 23, minute: 59, second: 59, of: startOfDay)!
        return (startOfDay, endOfDay)
    }

    // MARK: - Default Adapters

    /// Creates the default set of provider adapters
    private static func createDefaultAdapters() -> [Provider: ProviderAdapter] {
        [
            .gitlab: GitLabProviderAdapter(),
            .azureDevops: AzureDevOpsProviderAdapter(),
            .googleCalendar: GoogleCalendarProviderAdapter()
        ]
    }
}

// MARK: - Convenience Extension for DataCoordinator Integration

extension ActivityRefreshProvider {
    /// Creates a fully configured ActivityRefreshProvider with disk cache
    /// - Parameters:
    ///   - tokenStore: The token store for retrieving account tokens
    ///   - cacheDirectory: Optional custom cache directory
    ///   - daysBack: Number of days to fetch (default: 30)
    ///   - refreshService: Optional custom refresh service (defaults to TokenRefreshService)
    /// - Returns: A configured ActivityRefreshProvider
    public static func withDiskCache(
        tokenStore: TokenStore,
        cacheDirectory: URL? = nil,
        daysBack: Int = 30,
        refreshService: TokenRefreshing? = nil
    ) -> ActivityRefreshProvider {
        let cache = DiskActivityCache(cacheDirectory: cacheDirectory)
        return ActivityRefreshProvider(
            tokenStore: tokenStore,
            daysBack: daysBack,
            cache: cache,
            refreshService: refreshService
        )
    }
}
