import Core
import Foundation
import Security

/// Storage module
/// Handles disk cache for activity snapshots and keychain access for tokens.

// MARK: - Day Index Structures

/// Status of a cached day
public struct DayStatus: Codable, Sendable, Equatable {
    /// When the day was fetched
    public let fetchedAt: Date
    /// Number of activities for this day (unfiltered, for heatmap)
    public let count: Int

    public init(fetchedAt: Date, count: Int) {
        self.fetchedAt = fetchedAt
        self.count = count
    }
}

/// Index tracking which days have been fetched per account
public struct DayIndex: Codable, Sendable {
    /// accountId -> date string (yyyy-MM-dd) -> status
    public var accounts: [String: [String: DayStatus]]

    public init(accounts: [String: [String: DayStatus]] = [:]) {
        self.accounts = accounts
    }

    /// Get status for a specific day
    public func status(for accountId: String, date: String) -> DayStatus? {
        accounts[accountId]?[date]
    }

    /// Check if a day has been fetched for an account
    public func isDayFetched(accountId: String, date: String) -> Bool {
        accounts[accountId]?[date] != nil
    }

    /// Get all fetched dates for an account
    public func fetchedDates(for accountId: String) -> [String] {
        guard let dates = accounts[accountId] else { return [] }
        return Array(dates.keys)
    }

    /// Get activity count for a day (for heatmap)
    public func count(for accountId: String, date: String) -> Int {
        accounts[accountId]?[date]?.count ?? 0
    }

    /// Compute aggregated heatmap buckets across all accounts
    public func computeHeatmapBuckets() -> [HeatMapBucket] {
        var countsByDate: [String: Int] = [:]
        for (_, dates) in accounts {
            for (date, status) in dates {
                countsByDate[date, default: 0] += status.count
            }
        }
        return countsByDate.map { HeatMapBucket(date: $0.key, count: $0.value) }
            .sorted { $0.date < $1.date }
    }
}

/// Cache protocol for activity storage
public protocol ActivityCache: Sendable {
    func loadActivities(for account: Account, from: Date, to: Date) async -> [UnifiedActivity]?
    func saveActivities(_ activities: [UnifiedActivity], for account: Account, from: Date, to: Date) async
    func loadHeatmap(for account: Account) async -> [HeatMapBucket]?
    func saveHeatmap(_ buckets: [HeatMapBucket], for account: Account) async
    func loadAccounts() async -> [Account]
    func saveAccounts(_ accounts: [Account]) async
    func loadAllActivities() async -> [String: [UnifiedActivity]]
    func loadAllHeatmaps() async -> [HeatMapBucket]
    func clearCache(for accountId: String) async
    func clearAllCache() async

    // MARK: - Per-Day Cache Methods

    /// Load activities for a specific day
    func loadActivitiesForDay(accountId: String, date: String) async -> [UnifiedActivity]?

    /// Save activities for a specific day
    func saveActivitiesForDay(_ activities: [UnifiedActivity], accountId: String, date: String) async

    /// Check if a day has been fetched
    func isDayFetched(accountId: String, date: String) async -> Bool

    /// Get the day index
    func getDayIndex() async -> DayIndex

    /// Update the day index for a specific day
    func updateDayIndex(accountId: String, date: String, count: Int) async

    /// Load activities for multiple days
    func loadActivitiesForDays(accountId: String, dates: [String]) async -> [UnifiedActivity]

    /// Check if today's cache is stale (needs refresh)
    func isTodayCacheStale(accountId: String) async -> Bool
}

// MARK: - Cache Configuration

/// TTL policies for different cache types
public enum CacheTTL {
    /// Activities list cache: 1 hour
    public static let activitiesTTL: TimeInterval = 60 * 60

    /// Heatmap cache: 6 hours (changes less frequently)
    public static let heatmapTTL: TimeInterval = 60 * 60 * 6

    /// Accounts cache: no expiry (user-managed)
    public static let accountsTTL: TimeInterval = .infinity

    /// Today's activities cache: 15 minutes (events still happening)
    public static let todayTTL: TimeInterval = 60 * 15

    /// Past days cache: no expiry (history doesn't change)
    public static let pastDayTTL: TimeInterval = .infinity
}

/// Cache key generator for consistent file naming
public enum CacheKeyGenerator {
    /// Generate cache key for activities
    public static func activitiesKey(accountId: String, from: Date, to: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withFullDate]
        let fromStr = formatter.string(from: from)
        let toStr = formatter.string(from: to)
        // Sanitize accountId for use as filename component
        let safeAccountId = accountId.replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return "activities_\(safeAccountId)_\(fromStr)_\(toStr)"
    }

    /// Generate cache key for heatmap
    public static func heatmapKey(accountId: String) -> String {
        let safeAccountId = accountId.replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
        return "heatmap_\(safeAccountId)"
    }

    /// Cache key for accounts list
    public static let accountsKey = "accounts"

    /// Cache key for all activities index
    public static let activitiesIndexKey = "activities_index"

    /// Cache key for day index
    public static let dayIndexKey = "day_index"

    /// Sanitize account ID for use in file paths
    public static func sanitizeAccountId(_ accountId: String) -> String {
        accountId.replacingOccurrences(of: ":", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }

    /// Format date as yyyy-MM-dd string
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
}

// MARK: - Disk Activity Cache

/// Disk-based cache for activity data with TTL support
/// Cache format mirrors activity-discovery output exactly (JSON)
public final class DiskActivityCache: ActivityCache, @unchecked Sendable {
    /// Directory for cache files
    private let cacheDirectory: URL

    /// File manager for disk operations
    private let fileManager: FileManager

    /// JSON encoder configured for activity-discovery compatible output
    private let encoder: JSONEncoder

    /// JSON decoder for loading cached data
    private let decoder: JSONDecoder

    /// Queue for serializing cache access
    private let queue = DispatchQueue(label: "com.activitybar.diskcache", qos: .utility)

    /// Creates a new disk cache
    /// - Parameter cacheDirectory: Optional custom cache directory (defaults to app's caches directory)
    public init(cacheDirectory: URL? = nil) {
        let fm = FileManager.default
        self.fileManager = fm

        if let dir = cacheDirectory {
            self.cacheDirectory = dir
        } else {
            // Use app's standard caches directory
            let cachesDir = fm.urls(for: .cachesDirectory, in: .userDomainMask).first!
            self.cacheDirectory = cachesDir.appendingPathComponent("com.activitybar.cache", isDirectory: true)
        }

        // Create cache directory if needed
        try? fm.createDirectory(at: self.cacheDirectory, withIntermediateDirectories: true)

        // Configure encoder/decoder for activity-discovery compatible output
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder = encoder

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        self.decoder = decoder
    }

    // MARK: - Activity Operations

    public func loadActivities(for account: Account, from: Date, to: Date) async -> [UnifiedActivity]? {
        let key = CacheKeyGenerator.activitiesKey(accountId: account.id, from: from, to: to)
        return await loadCacheEntry(key: key, type: [UnifiedActivity].self, ttl: CacheTTL.activitiesTTL)
    }

    public func saveActivities(_ activities: [UnifiedActivity], for account: Account, from: Date, to: Date) async {
        let key = CacheKeyGenerator.activitiesKey(accountId: account.id, from: from, to: to)
        await saveCacheEntry(key: key, value: activities)

        // Update activities index
        await updateActivitiesIndex(accountId: account.id, key: key)
    }

    public func loadAllActivities() async -> [String: [UnifiedActivity]] {
        await withCheckedContinuation { continuation in
            queue.async {
                var result: [String: [UnifiedActivity]] = [:]

                // Load index to find all cached activity files per account
                guard let index = self.loadCacheEntrySync(
                    key: CacheKeyGenerator.activitiesIndexKey,
                    type: [String: [String]].self,  // accountId -> [cacheKeys]
                    ttl: .infinity
                ) else {
                    continuation.resume(returning: result)
                    return
                }

                for (accountId, cacheKeys) in index {
                    var accountActivities: [UnifiedActivity] = []
                    for cacheKey in cacheKeys {
                        if let activities = self.loadCacheEntrySync(
                            key: cacheKey,
                            type: [UnifiedActivity].self,
                            ttl: CacheTTL.activitiesTTL
                        ) {
                            accountActivities.append(contentsOf: activities)
                        }
                    }
                    if !accountActivities.isEmpty {
                        // Sort by timestamp descending
                        accountActivities.sort { $0.timestamp > $1.timestamp }
                        result[accountId] = accountActivities
                    }
                }

                continuation.resume(returning: result)
            }
        }
    }

    // MARK: - Heatmap Operations

    public func loadHeatmap(for account: Account) async -> [HeatMapBucket]? {
        let key = CacheKeyGenerator.heatmapKey(accountId: account.id)
        return await loadCacheEntry(key: key, type: [HeatMapBucket].self, ttl: CacheTTL.heatmapTTL)
    }

    public func saveHeatmap(_ buckets: [HeatMapBucket], for account: Account) async {
        let key = CacheKeyGenerator.heatmapKey(accountId: account.id)
        await saveCacheEntry(key: key, value: buckets)
    }

    public func loadAllHeatmaps() async -> [HeatMapBucket] {
        // Load accounts to get their heatmaps
        let accounts = await loadAccounts()
        var allBuckets: [HeatMapBucket] = []

        for account in accounts where account.isEnabled {
            if let buckets = await loadHeatmap(for: account) {
                allBuckets.append(contentsOf: buckets)
            }
        }

        // Merge buckets by date (aggregate counts)
        return mergeBuckets(allBuckets)
    }

    // MARK: - Account Operations

    public func loadAccounts() async -> [Account] {
        return await loadCacheEntry(
            key: CacheKeyGenerator.accountsKey,
            type: [Account].self,
            ttl: CacheTTL.accountsTTL
        ) ?? []
    }

    public func saveAccounts(_ accounts: [Account]) async {
        await saveCacheEntry(key: CacheKeyGenerator.accountsKey, value: accounts)
    }

    // MARK: - Clear Operations

    public func clearCache(for accountId: String) async {
        await withCheckedContinuation { continuation in
            queue.async {
                // Remove old-style activities for this account
                if var index = self.loadCacheEntrySync(
                    key: CacheKeyGenerator.activitiesIndexKey,
                    type: [String: [String]].self,
                    ttl: .infinity
                ) {
                    if let keys = index[accountId] {
                        for key in keys {
                            self.deleteCacheFile(key: key)
                        }
                    }
                    index.removeValue(forKey: accountId)
                    self.saveCacheEntrySync(key: CacheKeyGenerator.activitiesIndexKey, value: index)
                }

                // Remove per-day activities directory for this account
                let accountDir = self.activitiesDirectory(for: accountId)
                try? self.fileManager.removeItem(at: accountDir)

                // Remove from day index
                if var dayIndex = self.loadCacheEntrySync(
                    key: CacheKeyGenerator.dayIndexKey,
                    type: DayIndex.self,
                    ttl: .infinity
                ) {
                    dayIndex.accounts.removeValue(forKey: accountId)
                    self.saveCacheEntrySync(key: CacheKeyGenerator.dayIndexKey, value: dayIndex)
                }

                // Remove heatmap for this account
                let heatmapKey = CacheKeyGenerator.heatmapKey(accountId: accountId)
                self.deleteCacheFile(key: heatmapKey)

                continuation.resume()
            }
        }
    }

    public func clearAllCache() async {
        await withCheckedContinuation { continuation in
            queue.async {
                try? self.fileManager.removeItem(at: self.cacheDirectory)
                try? self.fileManager.createDirectory(
                    at: self.cacheDirectory,
                    withIntermediateDirectories: true
                )
                continuation.resume()
            }
        }
    }

    // MARK: - Per-Day Cache Operations

    /// Directory for per-day activity files
    private func activitiesDirectory(for accountId: String) -> URL {
        let safeAccountId = CacheKeyGenerator.sanitizeAccountId(accountId)
        return cacheDirectory
            .appendingPathComponent("activities", isDirectory: true)
            .appendingPathComponent(safeAccountId, isDirectory: true)
    }

    /// File path for a specific day's activities
    private func dayFilePath(accountId: String, date: String) -> URL {
        activitiesDirectory(for: accountId).appendingPathComponent("\(date).json")
    }

    public func loadActivitiesForDay(accountId: String, date: String) async -> [UnifiedActivity]? {
        await withCheckedContinuation { continuation in
            queue.async {
                let fileURL = self.dayFilePath(accountId: accountId, date: date)

                guard self.fileManager.fileExists(atPath: fileURL.path) else {
                    continuation.resume(returning: nil)
                    return
                }

                // Always return cached data - TTL is checked separately for refresh decisions
                guard let data = try? Data(contentsOf: fileURL) else {
                    continuation.resume(returning: nil)
                    return
                }

                let activities = try? self.decoder.decode([UnifiedActivity].self, from: data)
                continuation.resume(returning: activities)
            }
        }
    }

    /// Check if today's cache is stale (older than TTL)
    public func isTodayCacheStale(accountId: String) async -> Bool {
        await withCheckedContinuation { continuation in
            queue.async {
                let today = CacheKeyGenerator.dateString(from: Date())
                let fileURL = self.dayFilePath(accountId: accountId, date: today)

                guard self.fileManager.fileExists(atPath: fileURL.path) else {
                    // No cache = stale (needs fetch)
                    continuation.resume(returning: true)
                    return
                }

                guard let attributes = try? self.fileManager.attributesOfItem(atPath: fileURL.path),
                      let modificationDate = attributes[.modificationDate] as? Date else {
                    continuation.resume(returning: true)
                    return
                }

                let isStale = Date().timeIntervalSince(modificationDate) > CacheTTL.todayTTL
                continuation.resume(returning: isStale)
            }
        }
    }

    public func saveActivitiesForDay(_ activities: [UnifiedActivity], accountId: String, date: String) async {
        await withCheckedContinuation { continuation in
            queue.async {
                // Ensure directory exists
                let dir = self.activitiesDirectory(for: accountId)
                try? self.fileManager.createDirectory(at: dir, withIntermediateDirectories: true)

                let fileURL = self.dayFilePath(accountId: accountId, date: date)

                guard let data = try? self.encoder.encode(activities) else {
                    continuation.resume()
                    return
                }

                try? data.write(to: fileURL, options: .atomic)
                continuation.resume()
            }
        }

        // Update day index
        await updateDayIndex(accountId: accountId, date: date, count: activities.count)
    }

    public func isDayFetched(accountId: String, date: String) async -> Bool {
        let index = await getDayIndex()
        return index.isDayFetched(accountId: accountId, date: date)
    }

    public func getDayIndex() async -> DayIndex {
        await withCheckedContinuation { continuation in
            queue.async {
                let result = self.loadCacheEntrySync(
                    key: CacheKeyGenerator.dayIndexKey,
                    type: DayIndex.self,
                    ttl: .infinity
                ) ?? DayIndex()
                continuation.resume(returning: result)
            }
        }
    }

    public func updateDayIndex(accountId: String, date: String, count: Int) async {
        await withCheckedContinuation { continuation in
            queue.async {
                var index = self.loadCacheEntrySync(
                    key: CacheKeyGenerator.dayIndexKey,
                    type: DayIndex.self,
                    ttl: .infinity
                ) ?? DayIndex()

                // Update or create account entry
                if index.accounts[accountId] == nil {
                    index.accounts[accountId] = [:]
                }
                index.accounts[accountId]![date] = DayStatus(fetchedAt: Date(), count: count)

                self.saveCacheEntrySync(key: CacheKeyGenerator.dayIndexKey, value: index)
                continuation.resume()
            }
        }
    }

    public func loadActivitiesForDays(accountId: String, dates: [String]) async -> [UnifiedActivity] {
        var allActivities: [UnifiedActivity] = []
        for date in dates {
            if let activities = await loadActivitiesForDay(accountId: accountId, date: date) {
                allActivities.append(contentsOf: activities)
            }
        }
        return allActivities.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Private Helpers

    private func loadCacheEntry<T: Decodable>(key: String, type: T.Type, ttl: TimeInterval) async -> T? {
        await withCheckedContinuation { continuation in
            queue.async {
                let result = self.loadCacheEntrySync(key: key, type: type, ttl: ttl)
                continuation.resume(returning: result)
            }
        }
    }

    private func loadCacheEntrySync<T: Decodable>(key: String, type: T.Type, ttl: TimeInterval) -> T? {
        let fileURL = cacheFileURL(for: key)

        guard fileManager.fileExists(atPath: fileURL.path) else {
            return nil
        }

        // Check TTL
        if ttl != .infinity {
            guard let attributes = try? fileManager.attributesOfItem(atPath: fileURL.path),
                  let modificationDate = attributes[.modificationDate] as? Date else {
                return nil
            }

            if Date().timeIntervalSince(modificationDate) > ttl {
                // Cache expired - delete and return nil
                try? fileManager.removeItem(at: fileURL)
                return nil
            }
        }

        // Load and decode
        guard let data = try? Data(contentsOf: fileURL) else {
            return nil
        }

        return try? decoder.decode(type, from: data)
    }

    private func saveCacheEntry<T: Encodable>(key: String, value: T) async {
        await withCheckedContinuation { continuation in
            queue.async {
                self.saveCacheEntrySync(key: key, value: value)
                continuation.resume()
            }
        }
    }

    private func saveCacheEntrySync<T: Encodable>(key: String, value: T) {
        let fileURL = cacheFileURL(for: key)

        guard let data = try? encoder.encode(value) else {
            return
        }

        try? data.write(to: fileURL, options: .atomic)
    }

    private func deleteCacheFile(key: String) {
        let fileURL = cacheFileURL(for: key)
        try? fileManager.removeItem(at: fileURL)
    }

    private func cacheFileURL(for key: String) -> URL {
        cacheDirectory.appendingPathComponent("\(key).json")
    }

    private func updateActivitiesIndex(accountId: String, key: String) async {
        await withCheckedContinuation { continuation in
            queue.async {
                var index = self.loadCacheEntrySync(
                    key: CacheKeyGenerator.activitiesIndexKey,
                    type: [String: [String]].self,
                    ttl: .infinity
                ) ?? [:]

                var keys = index[accountId] ?? []
                if !keys.contains(key) {
                    keys.append(key)
                    index[accountId] = keys
                    self.saveCacheEntrySync(key: CacheKeyGenerator.activitiesIndexKey, value: index)
                }

                continuation.resume()
            }
        }
    }

    /// Merge heatmap buckets by date, summing counts
    private func mergeBuckets(_ buckets: [HeatMapBucket]) -> [HeatMapBucket] {
        var bucketsByDate: [String: HeatMapBucket] = [:]

        for bucket in buckets {
            if let existing = bucketsByDate[bucket.date] {
                // Merge: sum counts and combine breakdowns
                var mergedBreakdown: [Provider: Int] = existing.breakdown ?? [:]
                if let newBreakdown = bucket.breakdown {
                    for (provider, count) in newBreakdown {
                        mergedBreakdown[provider, default: 0] += count
                    }
                }
                bucketsByDate[bucket.date] = HeatMapBucket(
                    date: bucket.date,
                    count: existing.count + bucket.count,
                    breakdown: mergedBreakdown.isEmpty ? nil : mergedBreakdown
                )
            } else {
                bucketsByDate[bucket.date] = bucket
            }
        }

        return Array(bucketsByDate.values).sorted { $0.date < $1.date }
    }
}

// MARK: - Disk Cache Provider (CacheProvider Implementation)

/// Implements CacheProvider protocol using DiskActivityCache
/// Also conforms to AccountsPersistence for automatic account saving
public final class DiskCacheProvider: CacheProvider, @unchecked Sendable {
    private let cache: DiskActivityCache

    public init(cache: DiskActivityCache? = nil) {
        self.cache = cache ?? DiskActivityCache()
    }

    public func loadCachedActivities() async -> [String: [UnifiedActivity]] {
        await cache.loadAllActivities()
    }

    public func loadCachedHeatmap() async -> [HeatMapBucket] {
        await cache.loadAllHeatmaps()
    }

    public func loadCachedAccounts() async -> [Account] {
        await cache.loadAccounts()
    }

    /// Saves activities to cache (called after refresh)
    public func saveActivities(_ activities: [UnifiedActivity], for account: Account, from: Date, to: Date) async {
        await cache.saveActivities(activities, for: account, from: from, to: to)
    }

    /// Saves heatmap to cache (called after refresh)
    public func saveHeatmap(_ buckets: [HeatMapBucket], for account: Account) async {
        await cache.saveHeatmap(buckets, for: account)
    }

    /// Saves accounts list to cache
    public func saveAccounts(_ accounts: [Account]) async {
        await cache.saveAccounts(accounts)
    }

    /// Clears cache for a specific account
    public func clearCache(for accountId: String) async {
        await cache.clearCache(for: accountId)
    }
}

// MARK: - PerDayCacheProvider Conformance

extension DiskCacheProvider: PerDayCacheProvider {
    public func loadDayIndex() async -> [String: [String: DayIndexEntry]] {
        let index = await cache.getDayIndex()
        // Convert DayStatus to DayIndexEntry
        var result: [String: [String: DayIndexEntry]] = [:]
        for (accountId, dates) in index.accounts {
            var dateEntries: [String: DayIndexEntry] = [:]
            for (date, status) in dates {
                dateEntries[date] = DayIndexEntry(fetchedAt: status.fetchedAt, count: status.count)
            }
            result[accountId] = dateEntries
        }
        return result
    }

    public func loadActivitiesForDay(accountId: String, date: String) async -> [UnifiedActivity]? {
        await cache.loadActivitiesForDay(accountId: accountId, date: date)
    }

    public func saveActivitiesForDay(_ activities: [UnifiedActivity], accountId: String, date: String) async {
        await cache.saveActivitiesForDay(activities, accountId: accountId, date: date)
    }

    public func isTodayCacheStale(accountId: String) async -> Bool {
        await cache.isTodayCacheStale(accountId: accountId)
    }
}

// MARK: - AccountsPersistence Conformance

extension DiskCacheProvider: AccountsPersistence {
    // saveAccounts already implemented above
}

// MARK: - Token Store

/// Errors that can occur during token store operations
public enum TokenStoreError: Error, Sendable, Equatable {
    case keychainError(OSStatus)
    case dataEncodingError
    case dataDecodingError
    case unexpectedError(String)

    public var localizedDescription: String {
        switch self {
        case .keychainError(let status):
            if status == errSecSuccess {
                return "Keychain error: Unexpected success status returned as error (code 0)"
            }
            if let message = SecCopyErrorMessageString(status, nil) as String? {
                return "Keychain error (\(status)): \(message)"
            }
            return "Keychain error: OSStatus \(status)"
        case .dataEncodingError:
            return "Failed to encode token data"
        case .dataDecodingError:
            return "Failed to decode token data"
        case .unexpectedError(let message):
            return "Unexpected error: \(message)"
        }
    }
}

/// Token store protocol for secure credential storage
public protocol TokenStore: Sendable {
    /// Retrieves a token for the given account ID
    /// - Parameter accountId: The unique account identifier (e.g., "github:myaccount" or "gitlab:self-hosted.com:myaccount")
    /// - Returns: The stored token, or nil if not found
    /// - Throws: TokenStoreError on keychain access failure
    func getToken(for accountId: String) async throws -> String?

    /// Stores a token for the given account ID
    /// - Parameters:
    ///   - token: The token to store
    ///   - accountId: The unique account identifier
    /// - Throws: TokenStoreError on keychain access failure
    func setToken(_ token: String, for accountId: String) async throws

    /// Deletes the token for the given account ID
    /// - Parameter accountId: The unique account identifier
    /// - Throws: TokenStoreError on keychain access failure (except for item not found)
    func deleteToken(for accountId: String) async throws

    /// Checks if a token exists for the given account ID
    /// - Parameter accountId: The unique account identifier
    /// - Returns: true if a token exists, false otherwise
    func hasToken(for accountId: String) async throws -> Bool

    /// Lists all account IDs that have stored tokens
    /// - Returns: Array of account IDs with stored tokens
    func listAccountIds() async throws -> [String]
}

// MARK: - Keychain Token Store

/// Single keychain item holding all account tokens as JSON
/// This minimizes password prompts: 1 prompt to load all tokens at startup
private struct TokenPair: Codable {
    var access: String?
    var refresh: String?
}

/// Keychain-backed implementation of TokenStore using a SINGLE keychain item for all tokens
/// All tokens stored as JSON blob in one keychain entry, cached in memory for the session
public final class KeychainTokenStore: TokenStore, @unchecked Sendable {
    /// Service name used to identify the single token blob in the keychain
    public let serviceName: String

    /// Access group for keychain sharing (nil for no sharing)
    public let accessGroup: String?

    /// Queue for serializing keychain access
    private let queue = DispatchQueue(label: "com.activitybar.tokenstore", qos: .userInitiated)

    /// In-memory cache of all tokens (loaded once from keychain)
    /// Key: accountId (base, without :refresh suffix)
    /// Value: TokenPair with access and refresh tokens
    private var tokenCache: [String: TokenPair] = [:]

    /// Whether the cache has been loaded from keychain
    private var cacheLoaded = false

    /// Creates a new KeychainTokenStore
    /// - Parameters:
    ///   - serviceName: Service name for keychain items (default: "com.activitybar.tokens")
    ///   - accessGroup: Optional access group for keychain sharing between apps
    public init(serviceName: String = "com.activitybar.tokens", accessGroup: String? = nil) {
        self.serviceName = serviceName
        self.accessGroup = accessGroup
    }

    public func getToken(for accountId: String) async throws -> String? {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let token = try self.getTokenSync(for: accountId)
                    continuation.resume(returning: token)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func setToken(_ token: String, for accountId: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.setTokenSync(token, for: accountId)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func deleteToken(for accountId: String) async throws {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    try self.deleteTokenSync(for: accountId)
                    continuation.resume()
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    public func hasToken(for accountId: String) async throws -> Bool {
        let token = try await getToken(for: accountId)
        return token != nil
    }

    public func listAccountIds() async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let accountIds = try self.listAccountIdsSync()
                    continuation.resume(returning: accountIds)
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Synchronous Keychain Operations

    /// Load all tokens from keychain into memory cache (called once)
    /// This is the ONLY read from keychain - triggers one password prompt max
    private func loadCacheIfNeeded() throws {
        guard !cacheLoaded else { return }

        print("[ActivityBar][Keychain] Loading all tokens from keychain (single item)...")

        var query = baseQuery()
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)

        if status == errSecItemNotFound {
            // No tokens stored yet, start with empty cache
            print("[ActivityBar][Keychain] No tokens found in keychain, starting fresh")
            tokenCache = [:]
            cacheLoaded = true
            return
        }

        guard status == errSecSuccess else {
            throw TokenStoreError.keychainError(status)
        }

        guard let data = result as? Data else {
            throw TokenStoreError.dataDecodingError
        }

        // Decode JSON blob
        do {
            tokenCache = try JSONDecoder().decode([String: TokenPair].self, from: data)
            print("[ActivityBar][Keychain] Loaded \(tokenCache.count) accounts from keychain")
        } catch {
            print("[ActivityBar][Keychain] Failed to decode token cache: \(error)")
            // Start fresh if corrupted
            tokenCache = [:]
        }

        cacheLoaded = true
    }

    /// Save entire token cache to keychain (single write)
    private func saveCacheToKeychain() throws {
        print("[ActivityBar][Keychain] Saving \(tokenCache.count) accounts to keychain...")

        let data = try JSONEncoder().encode(tokenCache)

        let query = baseQuery()

        // Try update first
        let updateAttributes: [String: Any] = [
            kSecValueData as String: data
        ]

        let updateStatus = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)

        if updateStatus == errSecSuccess {
            print("[ActivityBar][Keychain] Updated token cache successfully")
            return
        }

        if updateStatus == errSecItemNotFound {
            // Item doesn't exist, add it
            var addQuery = query
            addQuery[kSecValueData as String] = data
            addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

            guard addStatus == errSecSuccess else {
                print("[ActivityBar][Keychain] Failed to add token cache: \(addStatus)")
                throw TokenStoreError.keychainError(addStatus)
            }

            print("[ActivityBar][Keychain] Created token cache successfully")
            return
        }

        // Other error - try delete and recreate
        print("[ActivityBar][Keychain] Update failed (\(updateStatus)), recreating...")
        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock

        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)

        guard addStatus == errSecSuccess else {
            print("[ActivityBar][Keychain] Failed to recreate token cache: \(addStatus)")
            throw TokenStoreError.keychainError(addStatus)
        }

        print("[ActivityBar][Keychain] Recreated token cache successfully")
    }

    /// Extract base account ID and token type from accountId
    /// accountId can be: "provider:account" or "provider:account:refresh"
    /// Returns: (baseAccountId, isRefreshToken)
    private func parseAccountId(_ accountId: String) -> (base: String, isRefresh: Bool) {
        if accountId.hasSuffix(":refresh") {
            let base = String(accountId.dropLast(":refresh".count))
            return (base, true)
        }
        return (accountId, false)
    }

    private func getTokenSync(for accountId: String) throws -> String? {
        // Load cache from keychain if not already loaded
        try loadCacheIfNeeded()

        let (baseAccountId, isRefresh) = parseAccountId(accountId)

        guard let pair = tokenCache[baseAccountId] else {
            return nil
        }

        return isRefresh ? pair.refresh : pair.access
    }

    private func setTokenSync(_ token: String, for accountId: String) throws {
        // Load cache from keychain if not already loaded
        try loadCacheIfNeeded()

        let (baseAccountId, isRefresh) = parseAccountId(accountId)

        // Get or create token pair for this account
        var pair = tokenCache[baseAccountId] ?? TokenPair()

        // Update the appropriate token
        if isRefresh {
            pair.refresh = token
        } else {
            pair.access = token
        }

        // Update cache
        tokenCache[baseAccountId] = pair

        // Write entire cache back to keychain
        try saveCacheToKeychain()
    }

    private func deleteTokenSync(for accountId: String) throws {
        // Load cache from keychain if not already loaded
        try loadCacheIfNeeded()

        let (baseAccountId, isRefresh) = parseAccountId(accountId)

        if isRefresh {
            // Delete only the refresh token, keep access token
            if var pair = tokenCache[baseAccountId] {
                pair.refresh = nil
                tokenCache[baseAccountId] = pair
                try saveCacheToKeychain()
            }
        } else {
            // Delete entire account (both access and refresh tokens)
            tokenCache.removeValue(forKey: baseAccountId)
            try saveCacheToKeychain()
        }
    }

    private func listAccountIdsSync() throws -> [String] {
        // Load cache from keychain if not already loaded
        try loadCacheIfNeeded()

        // Return all base account IDs from the cache
        return Array(tokenCache.keys)
    }

    /// Base query for the SINGLE keychain item holding all tokens
    private func baseQuery() -> [String: Any] {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: serviceName,
            kSecAttrAccount as String: "all-tokens"  // Single item for all accounts
        ]

        if let accessGroup = accessGroup {
            query[kSecAttrAccessGroup as String] = accessGroup
        }

        return query
    }
}

// MARK: - Token Key Generation Helpers

/// Helper to generate consistent account IDs for token storage
///
/// Key formats:
/// - Cloud providers: `{provider}:{accountId}` (e.g., `github:username`, `gitlab:username`)
/// - Self-hosted: `{provider}:{normalizedHost}:{accountId}` (e.g., `gitlab:git.company.com:username`)
///
/// The host is normalized to ensure consistency:
/// - Protocol stripped (https://, http://)
/// - Trailing slashes removed
/// - Lowercased
public enum TokenKeyGenerator {

    /// Normalizes a host URL to a consistent format for key generation
    /// - Parameter host: The host URL (e.g., "https://git.company.com/", "git.company.com")
    /// - Returns: Normalized host (e.g., "git.company.com")
    public static func normalizeHost(_ host: String) -> String {
        var normalized = host.lowercased()

        // Remove protocol
        if let range = normalized.range(of: "://") {
            normalized = String(normalized[range.upperBound...])
        }

        // Remove trailing slashes and paths
        if let slashIndex = normalized.firstIndex(of: "/") {
            normalized = String(normalized[..<slashIndex])
        }

        // Remove trailing whitespace
        normalized = normalized.trimmingCharacters(in: .whitespacesAndNewlines)

        return normalized
    }

    /// Generates a token key for a cloud provider account
    /// - Parameters:
    ///   - provider: The provider type
    ///   - accountId: The account identifier within that provider
    /// - Returns: A combined key like "github:myaccount"
    public static func key(provider: Provider, accountId: String) -> String {
        "\(provider.rawValue):\(accountId)"
    }

    /// Generates a token key for a self-hosted provider account
    /// - Parameters:
    ///   - provider: The provider type
    ///   - host: The host URL (will be normalized)
    ///   - accountId: The account identifier
    /// - Returns: A combined key like "gitlab:git.company.com:myaccount"
    public static func key(provider: Provider, host: String, accountId: String) -> String {
        let normalizedHost = normalizeHost(host)
        return "\(provider.rawValue):\(normalizedHost):\(accountId)"
    }

    /// Generates a token key, automatically handling cloud vs self-hosted
    /// - Parameters:
    ///   - provider: The provider type
    ///   - host: Optional host for self-hosted instances (nil for cloud)
    ///   - accountId: The account identifier
    /// - Returns: The appropriate key format
    public static func key(provider: Provider, host: String?, accountId: String) -> String {
        if let host = host, !host.isEmpty {
            return key(provider: provider, host: host, accountId: accountId)
        } else {
            return key(provider: provider, accountId: accountId)
        }
    }

    /// Parses a token key back into its components
    /// - Parameter key: The combined key
    /// - Returns: A tuple of (provider raw value, host or nil, accountId)
    public static func parse(_ key: String) -> (provider: String, host: String?, accountId: String)? {
        let parts = key.split(separator: ":", maxSplits: 2).map(String.init)

        switch parts.count {
        case 2:
            return (parts[0], nil, parts[1])
        case 3:
            return (parts[0], parts[1], parts[2])
        default:
            return nil
        }
    }
}
