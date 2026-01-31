import Foundation

/// Protocol for persisting accounts to disk
public protocol AccountsPersistence: Sendable {
    func saveAccounts(_ accounts: [Account]) async
}

/// Date range selection for activity filtering
public struct DateRange: Equatable, Sendable {
    public let start: Date
    public let end: Date

    public init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }

    /// Single day range
    public static func singleDay(_ date: Date) -> DateRange {
        let calendar = Calendar.current
        let startOfDay = calendar.startOfDay(for: date)
        let endOfDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)!
        return DateRange(start: startOfDay, end: endOfDay)
    }

    /// Today's date range
    public static var today: DateRange {
        singleDay(Date())
    }
}

/// Session data: cached activities, heatmap, and selection state
/// Separates mutable session data from configuration
@MainActor
@Observable
public final class Session {
    /// All accounts (enabled and disabled)
    public var accounts: [Account]

    /// Cached activities keyed by account ID
    public var activitiesByAccount: [String: [UnifiedActivity]]

    /// Aggregated heatmap buckets (combined across all enabled accounts)
    public var heatmapBuckets: [HeatMapBucket]

    /// Currently selected date (defaults to today)
    public var selectedDate: Date

    /// Optional date range selection (nil means single day selection)
    public var selectedRange: DateRange?

    /// Last successful refresh timestamp
    public var lastRefreshed: Date?

    /// Whether a refresh is currently in progress
    public var isRefreshing: Bool

    /// Whether the app is in offline mode (network unavailable or refresh failed)
    /// ACTIVITY-023: Offline mode shows cached data with indicator
    public var isOffline: Bool

    // MARK: - Per-Day Caching State

    /// Days currently loaded in memory (yyyy-MM-dd format)
    public var loadedDays: Set<String>

    /// Activity counts per day for quick heatmap computation (unfiltered)
    /// Key is date string (yyyy-MM-dd), value is total count across all accounts
    public var dayActivityCounts: [String: Int]

    /// Days currently being loaded
    public var loadingDays: Set<String>

    public init(
        accounts: [Account] = [],
        activitiesByAccount: [String: [UnifiedActivity]] = [:],
        heatmapBuckets: [HeatMapBucket] = [],
        selectedDate: Date = Date(),
        selectedRange: DateRange? = nil,
        lastRefreshed: Date? = nil,
        isRefreshing: Bool = false,
        isOffline: Bool = false,
        loadedDays: Set<String> = [],
        dayActivityCounts: [String: Int] = [:],
        loadingDays: Set<String> = []
    ) {
        self.accounts = accounts
        self.activitiesByAccount = activitiesByAccount
        self.heatmapBuckets = heatmapBuckets
        self.selectedDate = selectedDate
        self.selectedRange = selectedRange
        self.lastRefreshed = lastRefreshed
        self.isRefreshing = isRefreshing
        self.isOffline = isOffline
        self.loadedDays = loadedDays
        self.dayActivityCounts = dayActivityCounts
        self.loadingDays = loadingDays
    }

    /// Check if a specific day is loaded in memory
    public func isDayLoaded(_ dateString: String) -> Bool {
        loadedDays.contains(dateString)
    }

    /// Check if a specific day is currently being loaded
    public func isDayLoading(_ dateString: String) -> Bool {
        loadingDays.contains(dateString)
    }

    // MARK: - Computed Properties

    /// Enabled accounts only
    public var enabledAccounts: [Account] {
        accounts.filter { $0.isEnabled }
    }

    /// Activities for the current selection (date or range)
    public var selectedActivities: [UnifiedActivity] {
        let range = selectedRange ?? DateRange.singleDay(selectedDate)
        return activitiesInRange(range)
    }

    /// All activities from enabled accounts combined
    public var allActivities: [UnifiedActivity] {
        enabledAccounts.flatMap { account in
            activitiesByAccount[account.id] ?? []
        }
    }

    /// Activities within a date range from enabled accounts, sorted by timestamp descending
    public func activitiesInRange(_ range: DateRange) -> [UnifiedActivity] {
        allActivities
            .filter { $0.timestamp >= range.start && $0.timestamp < range.end }
            .sorted { $0.timestamp > $1.timestamp }
    }

    /// Get heatmap count for a specific date
    public func heatmapCount(for date: Date) -> Int {
        let dateString = Self.dateString(from: date)
        return heatmapBuckets.first { $0.date == dateString }?.count ?? 0
    }

    /// Helper to format date as YYYY-MM-DD
    public static func dateString(from date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter.string(from: date)
    }
}

/// Root application state
/// Orchestrates session data and coordinates updates from cache/network
@MainActor
@Observable
public final class AppState {
    /// Active session containing accounts, activities, and selections
    public let session: Session

    /// Error message if last operation failed
    public var lastError: String?

    /// Whether the app has completed initial data load from cache
    public var hasLoadedFromCache: Bool

    /// Cache provider for persisting accounts (optional, set by DataCoordinator)
    public var accountsPersistence: AccountsPersistence?

    public init(
        session: Session? = nil,
        lastError: String? = nil,
        hasLoadedFromCache: Bool = false
    ) {
        self.session = session ?? Session()
        self.lastError = lastError
        self.hasLoadedFromCache = hasLoadedFromCache
    }

    // MARK: - State Updates

    /// Update accounts list (called when accounts are added/removed/toggled)
    public func updateAccounts(_ accounts: [Account]) {
        session.accounts = accounts
        persistAccounts()
    }

    /// Add a new account
    public func addAccount(_ account: Account) {
        session.accounts.append(account)
        persistAccounts()
    }

    /// Remove account by ID
    public func removeAccount(id: String) {
        session.accounts.removeAll { $0.id == id }
        session.activitiesByAccount.removeValue(forKey: id)
        persistAccounts()
    }

    /// Toggle account enabled state
    public func toggleAccount(id: String) {
        guard let index = session.accounts.firstIndex(where: { $0.id == id }) else { return }
        session.accounts[index].isEnabled.toggle()
        persistAccounts()
    }

    /// Update enabled event types for an account
    public func updateEnabledEventTypes(for accountId: String, types: Set<ActivityType>?) {
        guard let index = session.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        session.accounts[index].enabledEventTypes = types
        persistAccounts()
    }

    /// Update calendar IDs for a Google Calendar account
    public func updateCalendarIds(for accountId: String, calendarIds: [String]?) {
        guard let index = session.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        // Create a new account with updated calendarIds since it's a let property
        let old = session.accounts[index]
        let updated = Account(
            id: old.id,
            provider: old.provider,
            displayName: old.displayName,
            host: old.host,
            organization: old.organization,
            projects: old.projects,
            calendarIds: calendarIds,
            authMethod: old.authMethod,
            isEnabled: old.isEnabled,
            enabledEventTypes: old.enabledEventTypes,
            username: old.username,
            showOnlyMyEvents: old.showOnlyMyEvents,
            showOnlyAcceptedEvents: old.showOnlyAcceptedEvents,
            hideAllDayEvents: old.hideAllDayEvents
        )
        session.accounts[index] = updated
        persistAccounts()
    }

    /// Toggle "show only my events" filter for an account
    public func toggleShowOnlyMyEvents(for accountId: String) {
        guard let index = session.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        session.accounts[index].showOnlyMyEvents.toggle()
        persistAccounts()
    }

    /// Toggle "show only accepted events" filter for a Google Calendar account
    public func toggleShowOnlyAcceptedEvents(for accountId: String) {
        guard let index = session.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        session.accounts[index].showOnlyAcceptedEvents.toggle()
        persistAccounts()
    }

    /// Toggle "hide all-day events" filter for a Google Calendar account
    public func toggleHideAllDayEvents(for accountId: String) {
        guard let index = session.accounts.firstIndex(where: { $0.id == accountId }) else { return }
        session.accounts[index].hideAllDayEvents.toggle()
        persistAccounts()
    }

    /// Persist accounts to disk cache
    private func persistAccounts() {
        guard let persistence = accountsPersistence else { return }
        Task {
            await persistence.saveAccounts(session.accounts)
        }
    }

    /// Update cached activities for an account
    public func updateActivities(_ activities: [UnifiedActivity], for accountId: String) {
        session.activitiesByAccount[accountId] = activities
    }

    /// Update heatmap data
    public func updateHeatmap(_ buckets: [HeatMapBucket]) {
        session.heatmapBuckets = buckets
    }

    /// Merge heatmap buckets from multiple sources (aggregates counts by date)
    public func mergeHeatmap(from accountBuckets: [[HeatMapBucket]]) {
        var merged: [String: HeatMapBucket] = [:]

        for buckets in accountBuckets {
            for bucket in buckets {
                if let existing = merged[bucket.date] {
                    // Merge counts and breakdowns
                    var newBreakdown: [Provider: Int] = existing.breakdown ?? [:]
                    if let bucketBreakdown = bucket.breakdown {
                        for (provider, count) in bucketBreakdown {
                            newBreakdown[provider, default: 0] += count
                        }
                    }
                    merged[bucket.date] = HeatMapBucket(
                        date: bucket.date,
                        count: existing.count + bucket.count,
                        breakdown: newBreakdown.isEmpty ? nil : newBreakdown
                    )
                } else {
                    merged[bucket.date] = bucket
                }
            }
        }

        session.heatmapBuckets = merged.values.sorted { $0.date < $1.date }
    }

    /// Select a specific date
    public func selectDate(_ date: Date) {
        session.selectedDate = date
        session.selectedRange = nil
    }

    /// Select a date range
    public func selectRange(_ range: DateRange) {
        session.selectedRange = range
    }

    /// Mark refresh started
    public func startRefresh() {
        session.isRefreshing = true
        lastError = nil
    }

    /// Mark refresh completed
    /// ACTIVITY-023: Updates offline status based on refresh success/failure
    public func finishRefresh(error: String? = nil) {
        session.isRefreshing = false
        if error == nil {
            session.lastRefreshed = Date()
            session.isOffline = false  // Successfully refreshed - we're online
        } else {
            // Refresh failed - mark as offline to show indicator
            session.isOffline = true
        }
        lastError = error
    }

    /// Mark initial cache load complete
    public func markCacheLoaded() {
        hasLoadedFromCache = true
    }

    /// Clear all error state
    public func clearError() {
        lastError = nil
    }

    /// Set offline mode status
    /// ACTIVITY-023: Used when network becomes unavailable
    public func setOffline(_ offline: Bool) {
        session.isOffline = offline
    }

    // MARK: - Per-Day Cache Management

    /// Mark a day as loaded and add its activities
    public func markDayLoaded(_ dateString: String, activities: [UnifiedActivity]) {
        session.loadedDays.insert(dateString)
        session.loadingDays.remove(dateString)

        // Merge activities into per-account storage
        var activitiesByAccount: [String: [UnifiedActivity]] = [:]
        for activity in activities {
            activitiesByAccount[activity.accountId, default: []].append(activity)
        }

        for (accountId, dayActivities) in activitiesByAccount {
            var existing = session.activitiesByAccount[accountId] ?? []
            // Remove any activities for this date before adding new ones
            let datePrefix = dateString
            existing.removeAll { activity in
                Session.dateString(from: activity.timestamp) == datePrefix
            }
            existing.append(contentsOf: dayActivities)
            existing.sort { $0.timestamp > $1.timestamp }
            session.activitiesByAccount[accountId] = existing
        }
    }

    /// Mark a day as currently loading
    public func markDayLoading(_ dateString: String) {
        session.loadingDays.insert(dateString)
    }

    /// Update day activity counts from day index (for heatmap)
    public func updateDayActivityCounts(_ counts: [String: Int]) {
        session.dayActivityCounts = counts
        // Also update heatmap buckets from these counts
        session.heatmapBuckets = counts.map { HeatMapBucket(date: $0.key, count: $0.value) }
            .sorted { $0.date < $1.date }
    }

    /// Clear all loaded days (used when accounts change)
    public func clearLoadedDays() {
        session.loadedDays.removeAll()
        session.loadingDays.removeAll()
        session.activitiesByAccount.removeAll()
    }
}
