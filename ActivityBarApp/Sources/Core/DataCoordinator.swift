import Foundation

/// Protocol for loading cached data
/// Implementers provide actual disk/memory cache access
public protocol CacheProvider: Sendable {
    /// Load all cached activities for all accounts
    func loadCachedActivities() async -> [String: [UnifiedActivity]]

    /// Load all cached heatmap buckets
    func loadCachedHeatmap() async -> [HeatMapBucket]

    /// Load cached accounts
    func loadCachedAccounts() async -> [Account]
}

/// Extended cache provider with per-day support
public protocol PerDayCacheProvider: CacheProvider {
    /// Load the day index
    func loadDayIndex() async -> [String: [String: DayIndexEntry]]

    /// Load activities for a specific day from cache
    func loadActivitiesForDay(accountId: String, date: String) async -> [UnifiedActivity]?

    /// Save activities for a specific day
    func saveActivitiesForDay(_ activities: [UnifiedActivity], accountId: String, date: String) async

    /// Check if today's cache is stale (needs background refresh)
    func isTodayCacheStale(accountId: String) async -> Bool
}

/// Day index entry for CacheProvider compatibility
public struct DayIndexEntry: Sendable {
    public let fetchedAt: Date
    public let count: Int

    public init(fetchedAt: Date, count: Int) {
        self.fetchedAt = fetchedAt
        self.count = count
    }
}

/// Protocol for fetching fresh data from providers
/// Implementers provide actual network access
public protocol RefreshProvider: Sendable {
    /// Fetch fresh activities for an account
    func fetchActivities(for account: Account) async throws -> [UnifiedActivity]

    /// Fetch fresh heatmap data for an account
    func fetchHeatmap(for account: Account) async throws -> [HeatMapBucket]
}

/// Extended refresh provider with single-day fetch support
public protocol PerDayRefreshProvider: RefreshProvider {
    /// Fetch activities for a specific day
    func fetchActivitiesForDay(for account: Account, date: Date) async throws -> [UnifiedActivity]

    /// Fetch activities for a date range and return results grouped by day
    /// This is more efficient than fetching each day individually
    func fetchActivitiesForDateRange(for account: Account, from: Date, to: Date) async throws -> [String: [UnifiedActivity]]
}

/// Coordinates data loading from cache and background refresh
/// Ensures overlay renders immediately from cache while refreshing in background
@MainActor
public final class DataCoordinator {
    private let appState: AppState
    private let cacheProvider: CacheProvider?
    private let refreshProvider: RefreshProvider?

    /// Number of weeks visible on heatmap (matches HeatmapView.weeksToShow)
    private let heatmapWeeks: Int = 13

    /// Optional per-day cache provider (cast from cacheProvider if supported)
    private var perDayCacheProvider: PerDayCacheProvider? {
        cacheProvider as? PerDayCacheProvider
    }

    /// Optional per-day refresh provider (cast from refreshProvider if supported)
    private var perDayRefreshProvider: PerDayRefreshProvider? {
        refreshProvider as? PerDayRefreshProvider
    }

    /// Tracks if initial cache load is complete
    public private(set) var hasLoadedCache = false

    /// Tracks if a refresh is in progress
    public private(set) var isRefreshing = false

    public init(
        appState: AppState,
        cacheProvider: CacheProvider? = nil,
        refreshProvider: RefreshProvider? = nil
    ) {
        self.appState = appState
        self.cacheProvider = cacheProvider
        self.refreshProvider = refreshProvider
    }

    // MARK: - Cache Loading

    /// Load all data from cache immediately (called at app launch)
    /// New strategy: Load day index + today's activities only
    public func loadFromCache() async {
        guard let cache = cacheProvider else {
            appState.markCacheLoaded()
            hasLoadedCache = true
            return
        }

        // Load accounts first
        let accounts = await cache.loadCachedAccounts()
        appState.updateAccounts(accounts)

        // Try per-day loading first
        if let perDayCache = perDayCacheProvider {
            await loadFromPerDayCache(perDayCache)
        } else {
            // Fallback to legacy loading
            await loadFromLegacyCache(cache)
        }

        appState.markCacheLoaded()
        hasLoadedCache = true
    }

    /// Load using per-day cache structure
    private func loadFromPerDayCache(_ cache: PerDayCacheProvider) async {
        print("[ActivityBar][DataCoordinator] Loading from per-day cache")

        // Load day index to get heatmap counts
        let dayIndex = await cache.loadDayIndex()

        // Compute aggregated counts for heatmap
        var countsByDate: [String: Int] = [:]
        for (_, dates) in dayIndex {
            for (date, entry) in dates {
                countsByDate[date, default: 0] += entry.count
            }
        }
        appState.updateDayActivityCounts(countsByDate)
        print("[ActivityBar][DataCoordinator] Loaded day index with \(countsByDate.count) days")

        // Load all visible heatmap days from cache IN PARALLEL
        let visibleDates = calculateVisibleHeatmapDates()
        print("[ActivityBar][DataCoordinator] Heatmap shows \(visibleDates.count) days, loading all in parallel")

        let enabledAccounts = appState.session.enabledAccounts

        // Load all days for all accounts in parallel
        let allResults = await withTaskGroup(of: (String, [UnifiedActivity]).self) { group in
            for dateStr in visibleDates {
                for account in enabledAccounts {
                    group.addTask {
                        let activities = await cache.loadActivitiesForDay(accountId: account.id, date: dateStr) ?? []
                        return (dateStr, activities)
                    }
                }
            }

            // Aggregate results by date
            var activitiesByDate: [String: [UnifiedActivity]] = [:]
            for await (dateStr, activities) in group {
                activitiesByDate[dateStr, default: []].append(contentsOf: activities)
            }
            return activitiesByDate
        }

        // Mark all days as loaded
        for (dateStr, activities) in allResults {
            appState.markDayLoaded(dateStr, activities: activities)
        }

        let totalActivities = allResults.values.reduce(0) { $0 + $1.count }
        print("[ActivityBar][DataCoordinator] Loaded \(totalActivities) activities from cache across \(allResults.count) days")
    }

    /// Calculate all dates visible on the heatmap (13 weeks back from today)
    private func calculateVisibleHeatmapDates() -> [String] {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: Date())

        // Calculate start date (13 weeks back, aligned to week start)
        let totalDays = heatmapWeeks * 7
        guard let startDate = calendar.date(byAdding: .day, value: -(totalDays - 1), to: today) else {
            return [todayDateString()]
        }

        // Generate all dates from start to today
        var dates: [String] = []
        var currentDate = startDate
        while currentDate <= today {
            dates.append(Self.dateString(from: currentDate))
            guard let nextDate = calendar.date(byAdding: .day, value: 1, to: currentDate) else { break }
            currentDate = nextDate
        }

        return dates
    }

    /// Check if any visible heatmap days need fetching (missing or today is stale)
    public func needsInitialFetch() async -> Bool {
        guard let cache = perDayCacheProvider else {
            // No per-day cache - always refresh
            return true
        }

        let enabledAccounts = appState.session.enabledAccounts

        // Check if today's cache is stale for any account (in parallel)
        let staleResults = await withTaskGroup(of: Bool.self) { group in
            for account in enabledAccounts {
                group.addTask {
                    await cache.isTodayCacheStale(accountId: account.id)
                }
            }
            for await isStale in group {
                if isStale { return true }
            }
            return false
        }

        if staleResults {
            return true
        }

        // Check if any visible days are missing from cache (sample check - not all days)
        // Only check today and a few random days to avoid slow sequential check
        let todayStr = todayDateString()
        for account in enabledAccounts {
            let activities = await cache.loadActivitiesForDay(accountId: account.id, date: todayStr)
            if activities == nil {
                print("[ActivityBar][DataCoordinator] Today \(todayStr) missing for account \(account.id)")
                return true
            }
        }

        return false
    }

    /// Get list of days that need to be fetched (missing from cache)
    public func getMissingDays() async -> [String] {
        guard let cache = perDayCacheProvider else {
            return calculateVisibleHeatmapDates()
        }

        let visibleDates = calculateVisibleHeatmapDates()
        let enabledAccounts = appState.session.enabledAccounts

        // Check all days in parallel
        let missingDays = await withTaskGroup(of: String?.self) { group in
            for dateStr in visibleDates {
                group.addTask {
                    // Check if any account is missing this day
                    for account in enabledAccounts {
                        let activities = await cache.loadActivitiesForDay(accountId: account.id, date: dateStr)
                        if activities == nil {
                            return dateStr
                        }
                    }
                    return nil
                }
            }

            var missing: Set<String> = []
            for await result in group {
                if let dateStr = result {
                    missing.insert(dateStr)
                }
            }
            return missing
        }

        // Sort from oldest to newest
        return missingDays.sorted()
    }

    /// Load using legacy cache structure (all activities at once)
    private func loadFromLegacyCache(_ cache: CacheProvider) async {
        print("[ActivityBar][DataCoordinator] Loading from legacy cache")

        let activitiesMap = await cache.loadCachedActivities()
        for (accountId, activities) in activitiesMap {
            appState.updateActivities(activities, for: accountId)
        }

        let heatmap = await cache.loadCachedHeatmap()
        appState.updateHeatmap(heatmap)
    }

    // MARK: - Per-Day Loading

    /// Load a specific day's activities (from cache or network)
    /// Called when user clicks on a day in the heatmap
    public func loadDay(_ date: Date) async {
        let dateStr = Self.dateString(from: date)
        await loadDayByString(dateStr)
    }

    /// Load a specific day by date string
    public func loadDayByString(_ dateStr: String) async {
        // Skip if already loaded or loading
        guard !appState.session.isDayLoaded(dateStr) else {
            print("[ActivityBar][DataCoordinator] Day \(dateStr) already loaded")
            return
        }
        guard !appState.session.isDayLoading(dateStr) else {
            print("[ActivityBar][DataCoordinator] Day \(dateStr) already loading")
            return
        }

        appState.markDayLoading(dateStr)

        // Try cache first
        if let perDayCache = perDayCacheProvider {
            let cached = await loadDayFromCache(dateStr, using: perDayCache)
            if cached {
                return
            }
        }

        // Fetch from network
        await fetchDayFromNetwork(dateStr)
    }

    /// Load day from per-day cache
    @discardableResult
    private func loadDayFromCache(_ dateStr: String, using cache: PerDayCacheProvider) async -> Bool {
        var allActivities: [UnifiedActivity] = []

        for account in appState.session.enabledAccounts {
            if let activities = await cache.loadActivitiesForDay(accountId: account.id, date: dateStr) {
                allActivities.append(contentsOf: activities)
            }
        }

        if !allActivities.isEmpty {
            print("[ActivityBar][DataCoordinator] Loaded \(allActivities.count) activities from cache for \(dateStr)")
            appState.markDayLoaded(dateStr, activities: allActivities)
            return true
        }

        return false
    }

    /// Fetch day from network using per-day refresh provider
    private func fetchDayFromNetwork(_ dateStr: String) async {
        guard let refresher = perDayRefreshProvider else {
            print("[ActivityBar][DataCoordinator] No per-day refresh provider for day fetch")
            appState.session.loadingDays.remove(dateStr)
            return
        }

        guard let date = Self.date(from: dateStr) else {
            print("[ActivityBar][DataCoordinator] Invalid date string: \(dateStr)")
            appState.session.loadingDays.remove(dateStr)
            return
        }

        var allActivities: [UnifiedActivity] = []
        var errors: [String] = []

        for account in appState.session.enabledAccounts {
            do {
                let activities = try await refresher.fetchActivitiesForDay(for: account, date: date)
                allActivities.append(contentsOf: activities)
                print("[ActivityBar][DataCoordinator] Fetched \(activities.count) activities for \(account.id) on \(dateStr)")
            } catch {
                print("[ActivityBar][DataCoordinator] Error fetching \(dateStr) for \(account.id): \(error)")
                errors.append("\(account.displayName): \(error.localizedDescription)")
            }
        }

        appState.markDayLoaded(dateStr, activities: allActivities)

        if !errors.isEmpty {
            appState.lastError = errors.joined(separator: "; ")
        }
    }

    // MARK: - Date Helpers

    /// Get today's date as string
    private func todayDateString() -> String {
        Self.dateString(from: Date())
    }

    /// Format date as yyyy-MM-dd
    public static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }

    /// Parse yyyy-MM-dd string to date
    public static func date(from string: String) -> Date? {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.date(from: string)
    }

    // MARK: - Background Refresh

    /// Refresh data from providers in background
    /// New strategy: Fetch all visible heatmap days that are missing, plus today
    public func refreshInBackground() async {
        print("[ActivityBar][DataCoordinator] refreshInBackground called")
        print("[ActivityBar][DataCoordinator]   isRefreshing: \(isRefreshing)")
        print("[ActivityBar][DataCoordinator]   refreshProvider: \(refreshProvider != nil ? "set" : "nil")")

        guard !isRefreshing else {
            print("[ActivityBar][DataCoordinator] Already refreshing, skipping")
            return
        }

        isRefreshing = true
        appState.startRefresh()

        let enabledAccounts = appState.session.enabledAccounts
        print("[ActivityBar][DataCoordinator] Found \(enabledAccounts.count) enabled accounts")

        // Use per-day refresh if available, otherwise fall back to full refresh
        if let perDayRefresher = perDayRefreshProvider {
            await refreshVisibleDays(using: perDayRefresher, accounts: enabledAccounts)
        } else if let refresher = refreshProvider {
            await refreshAllDays(using: refresher, accounts: enabledAccounts)
        } else {
            print("[ActivityBar][DataCoordinator] ERROR: No refresh provider set!")
        }

        isRefreshing = false
        print("[ActivityBar][DataCoordinator] refreshInBackground done")
    }

    /// Background task for fetching older days
    private var backgroundFetchTask: Task<Void, Never>?

    /// Maximum days to fetch in a single batch (API-friendly limit)
    /// Most APIs handle 1-2 weeks of data well without pagination issues
    private let maxDaysPerBatch = 14

    /// Refresh all visible heatmap days using batch fetching
    /// Strategy: Fetch last 2 days first, then older days in weekly batches in background
    private func refreshVisibleDays(using refresher: PerDayRefreshProvider, accounts: [Account]) async {
        // Get days that need fetching
        let missingDays = await getMissingDays()
        let todayStr = todayDateString()
        let yesterdayStr = yesterdayDateString()

        // Always include today and yesterday (priority days)
        var allDaysToFetch = Set(missingDays)
        allDaysToFetch.insert(todayStr)
        allDaysToFetch.insert(yesterdayStr)

        let sortedDays = allDaysToFetch.sorted()

        // Split into priority days (last 2) and background days (older)
        let priorityDays = sortedDays.filter { $0 >= yesterdayStr }
        let backgroundDays = sortedDays.filter { $0 < yesterdayStr }

        print("[ActivityBar][DataCoordinator] Priority fetch: \(priorityDays.count) days (today + yesterday)")
        print("[ActivityBar][DataCoordinator] Background fetch: \(backgroundDays.count) older days in \(maxDaysPerBatch)-day batches")

        // Phase 1: Fetch priority days using batch method
        let errors = await fetchDateRangeBatch(days: priorityDays, using: refresher, accounts: accounts)

        // Finish the main refresh after priority days are done
        finishRefresh(errors: errors)

        // Phase 2: Fetch older days in background using weekly batches (non-blocking)
        if !backgroundDays.isEmpty {
            startBackgroundBatchFetch(days: backgroundDays, refresher: refresher, accounts: accounts)
        }
    }

    /// Fetch a set of days using batch date range fetching
    /// Respects maxDaysPerBatch limit to avoid API issues
    private func fetchDateRangeBatch(days: [String], using refresher: PerDayRefreshProvider, accounts: [Account]) async -> [String] {
        guard !days.isEmpty else { return [] }

        let sortedDays = days.sorted()
        guard let fromDate = Self.date(from: sortedDays.first!),
              let toDate = Self.date(from: sortedDays.last!) else {
            return ["Invalid date range"]
        }

        print("[ActivityBar][DataCoordinator] Batch fetching \(days.count) days (\(sortedDays.first!) to \(sortedDays.last!)) for \(accounts.count) accounts")

        // Mark all days as loading
        for dateStr in days {
            if !appState.session.isDayLoaded(dateStr) && !appState.session.isDayLoading(dateStr) {
                appState.markDayLoading(dateStr)
            }
        }

        // Fetch all accounts in parallel
        let results = await withTaskGroup(of: (activitiesByDay: [String: [UnifiedActivity]], error: String?).self) { group in
            for account in accounts {
                group.addTask {
                    do {
                        let activitiesByDay = try await refresher.fetchActivitiesForDateRange(
                            for: account,
                            from: fromDate,
                            to: toDate
                        )
                        return (activitiesByDay, nil)
                    } catch {
                        let errorMsg = "\(account.displayName): \(error.localizedDescription)"
                        print("[ActivityBar][DataCoordinator] Error batch fetching for \(account.id): \(error)")
                        return ([:], errorMsg)
                    }
                }
            }

            // Aggregate results from all accounts
            var aggregatedByDay: [String: [UnifiedActivity]] = [:]
            var errors: [String] = []

            for await result in group {
                for (dateStr, activities) in result.activitiesByDay {
                    aggregatedByDay[dateStr, default: []].append(contentsOf: activities)
                }
                if let error = result.error {
                    errors.append(error)
                }
            }

            return (aggregatedByDay, errors)
        }

        // Update state for each day in the batch
        let daysSet = Set(days)
        for dateStr in daysSet {
            let dayActivities = results.0[dateStr] ?? []
            appState.markDayLoaded(dateStr, activities: dayActivities)

            // Update heatmap count
            var counts = appState.session.dayActivityCounts
            counts[dateStr] = dayActivities.count
            appState.updateDayActivityCounts(counts)
        }

        let totalActivities = results.0.values.reduce(0) { $0 + $1.count }
        print("[ActivityBar][DataCoordinator] Batch fetch complete: \(totalActivities) activities across \(results.0.count) days")

        return results.1
    }

    /// Split days into batches of maxDaysPerBatch
    private func splitIntoBatches(_ days: [String]) -> [[String]] {
        let sortedDays = days.sorted(by: >) // Newest first
        var batches: [[String]] = []

        var currentBatch: [String] = []
        for day in sortedDays {
            currentBatch.append(day)
            if currentBatch.count >= maxDaysPerBatch {
                batches.append(currentBatch)
                currentBatch = []
            }
        }
        if !currentBatch.isEmpty {
            batches.append(currentBatch)
        }

        return batches
    }

    /// Start background batch fetching of older days in weekly chunks (non-blocking)
    private func startBackgroundBatchFetch(days: [String], refresher: PerDayRefreshProvider, accounts: [Account]) {
        // Cancel any existing background fetch
        backgroundFetchTask?.cancel()

        backgroundFetchTask = Task { [weak self] in
            guard let self = self else { return }

            // Split into batches (newest first)
            let batches = self.splitIntoBatches(days)
            print("[ActivityBar][DataCoordinator] Starting background fetch: \(days.count) days in \(batches.count) batches")

            for (index, batch) in batches.enumerated() {
                if Task.isCancelled {
                    print("[ActivityBar][DataCoordinator] Background fetch cancelled at batch \(index + 1)")
                    return
                }

                print("[ActivityBar][DataCoordinator] Fetching batch \(index + 1)/\(batches.count): \(batch.count) days")
                _ = await self.fetchDateRangeBatch(days: batch, using: refresher, accounts: accounts)
            }

            if !Task.isCancelled {
                print("[ActivityBar][DataCoordinator] Background fetch completed: \(batches.count) batches, \(days.count) days total")
            }
        }
    }

    /// Get yesterday's date as string
    private func yesterdayDateString() -> String {
        let calendar = Calendar.current
        let yesterday = calendar.date(byAdding: .day, value: -1, to: Date())!
        return Self.dateString(from: yesterday)
    }

    /// Legacy full refresh (all days at once)
    private func refreshAllDays(using refresher: RefreshProvider, accounts: [Account]) async {
        var errors: [String] = []
        var allHeatmapBuckets: [[HeatMapBucket]] = []

        for account in accounts {
            print("[ActivityBar][DataCoordinator] Refreshing account: \(account.id)")
            do {
                let activities = try await refresher.fetchActivities(for: account)
                print("[ActivityBar][DataCoordinator]   Got \(activities.count) activities")
                appState.updateActivities(activities, for: account.id)

                let heatmap = try await refresher.fetchHeatmap(for: account)
                print("[ActivityBar][DataCoordinator]   Got \(heatmap.count) heatmap buckets")
                allHeatmapBuckets.append(heatmap)
            } catch {
                print("[ActivityBar][DataCoordinator]   ERROR: \(error)")
                errors.append("\(account.displayName): \(error.localizedDescription)")
            }
        }

        if !allHeatmapBuckets.isEmpty {
            appState.mergeHeatmap(from: allHeatmapBuckets)
        }

        finishRefresh(errors: errors)
    }

    /// Common finish refresh logic
    private func finishRefresh(errors: [String]) {
        if errors.isEmpty {
            print("[ActivityBar][DataCoordinator] Refresh completed successfully")
            appState.finishRefresh()
        } else {
            print("[ActivityBar][DataCoordinator] Refresh completed with \(errors.count) errors")
            appState.finishRefresh(error: errors.joined(separator: "; "))
        }
    }

    /// Manual refresh trigger (from UI)
    public func triggerRefresh() {
        Task {
            await refreshInBackground()
        }
    }
}

// MARK: - Default Implementations (Stubs)

/// In-memory cache provider for testing and initial development
/// Uses data already in AppState as "cache"
public final class InMemoryCacheProvider: CacheProvider, @unchecked Sendable {
    private let accounts: [Account]
    private let activities: [String: [UnifiedActivity]]
    private let heatmap: [HeatMapBucket]

    public init(
        accounts: [Account] = [],
        activities: [String: [UnifiedActivity]] = [:],
        heatmap: [HeatMapBucket] = []
    ) {
        self.accounts = accounts
        self.activities = activities
        self.heatmap = heatmap
    }

    public func loadCachedActivities() async -> [String: [UnifiedActivity]] {
        activities
    }

    public func loadCachedHeatmap() async -> [HeatMapBucket] {
        heatmap
    }

    public func loadCachedAccounts() async -> [Account] {
        accounts
    }
}

/// Stub refresh provider that returns empty data
/// To be replaced with actual provider implementations
public final class StubRefreshProvider: RefreshProvider, @unchecked Sendable {
    public init() {}

    public func fetchActivities(for account: Account) async throws -> [UnifiedActivity] {
        []
    }

    public func fetchHeatmap(for account: Account) async throws -> [HeatMapBucket] {
        []
    }
}
