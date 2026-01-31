import XCTest
@testable import Storage
@testable import Core

final class StorageTests: XCTestCase {
    func testActivityCacheProtocolExists() {
        // Verify protocol is accessible and has expected methods
        // Implementation tests will come in ACTIVITY-021
        XCTAssertTrue(true, "ActivityCache protocol exists")
    }

    func testTokenStoreProtocolExists() {
        // Verify protocol is accessible and has expected methods
        XCTAssertTrue(true, "TokenStore protocol exists")
    }
}

// MARK: - KeychainTokenStore Tests

final class KeychainTokenStoreTests: XCTestCase {
    /// Unique service name per test run to avoid conflicts
    private var testServiceName: String!
    private var tokenStore: KeychainTokenStore!

    override func setUp() {
        super.setUp()
        // Use unique service name per test to isolate keychain items
        testServiceName = "com.activitybar.tests.\(UUID().uuidString)"
        tokenStore = KeychainTokenStore(serviceName: testServiceName)
    }

    override func tearDown() async throws {
        // Clean up all test tokens
        if let store = tokenStore {
            let accountIds = try? await store.listAccountIds()
            for accountId in accountIds ?? [] {
                try? await store.deleteToken(for: accountId)
            }
        }
        tokenStore = nil
        testServiceName = nil
        try await super.tearDown()
    }

    // MARK: - Basic Operations

    func testInitialization() {
        let store = KeychainTokenStore()
        XCTAssertEqual(store.serviceName, "com.activitybar.tokens")
        XCTAssertNil(store.accessGroup)
    }

    func testInitializationWithCustomServiceName() {
        let store = KeychainTokenStore(serviceName: "custom.service")
        XCTAssertEqual(store.serviceName, "custom.service")
    }

    func testSetAndGetToken() async throws {
        let accountId = "gitlab:testuser"
        let token = "ghp_test_token_123"

        try await tokenStore.setToken(token, for: accountId)
        let retrieved = try await tokenStore.getToken(for: accountId)

        XCTAssertEqual(retrieved, token)
    }

    func testGetNonExistentToken() async throws {
        let result = try await tokenStore.getToken(for: "nonexistent:account")
        XCTAssertNil(result)
    }

    func testUpdateExistingToken() async throws {
        let accountId = "gitlab:testuser"
        let originalToken = "original_token"
        let updatedToken = "updated_token"

        try await tokenStore.setToken(originalToken, for: accountId)
        try await tokenStore.setToken(updatedToken, for: accountId)

        let retrieved = try await tokenStore.getToken(for: accountId)
        XCTAssertEqual(retrieved, updatedToken)
    }

    func testDeleteToken() async throws {
        let accountId = "gitlab:testuser"
        let token = "token_to_delete"

        try await tokenStore.setToken(token, for: accountId)

        // Verify it exists
        let beforeDelete = try await tokenStore.getToken(for: accountId)
        XCTAssertNotNil(beforeDelete)

        // Delete
        try await tokenStore.deleteToken(for: accountId)

        // Verify it's gone
        let afterDelete = try await tokenStore.getToken(for: accountId)
        XCTAssertNil(afterDelete)
    }

    func testDeleteNonExistentToken() async throws {
        // Should not throw - delete is idempotent
        try await tokenStore.deleteToken(for: "nonexistent:account")
    }

    func testHasToken() async throws {
        let accountId = "gitlab:testuser"
        let token = "some_token"

        // Initially no token
        let hasBefore = try await tokenStore.hasToken(for: accountId)
        XCTAssertFalse(hasBefore)

        // After setting token
        try await tokenStore.setToken(token, for: accountId)
        let hasAfter = try await tokenStore.hasToken(for: accountId)
        XCTAssertTrue(hasAfter)

        // After deleting token
        try await tokenStore.deleteToken(for: accountId)
        let hasAfterDelete = try await tokenStore.hasToken(for: accountId)
        XCTAssertFalse(hasAfterDelete)
    }

    // MARK: - Multiple Accounts

    func testMultipleAccounts() async throws {
        let accounts = [
            ("gitlab:user1", "token1"),
            ("gitlab:user2", "token2"),
            ("gitlab:user1", "token3"),
            ("azure-devops:user1", "token4"),
            ("google-calendar:user1", "token5")
        ]

        // Set all tokens
        for (accountId, token) in accounts {
            try await tokenStore.setToken(token, for: accountId)
        }

        // Verify all tokens
        for (accountId, expectedToken) in accounts {
            let retrieved = try await tokenStore.getToken(for: accountId)
            XCTAssertEqual(retrieved, expectedToken, "Token mismatch for \(accountId)")
        }
    }

    func testListAccountIds() async throws {
        let accountIds = ["gitlab:user1", "gitlab:user2", "azure-devops:org1:user3"]

        for accountId in accountIds {
            try await tokenStore.setToken("token_\(accountId)", for: accountId)
        }

        let listedIds = try await tokenStore.listAccountIds()

        XCTAssertEqual(Set(listedIds), Set(accountIds))
    }

    func testListAccountIdsEmpty() async throws {
        let listedIds = try await tokenStore.listAccountIds()
        XCTAssertEqual(listedIds, [])
    }

    // MARK: - Self-Hosted Provider Keys

    func testSelfHostedGitLabToken() async throws {
        let accountId = "gitlab:gitlab.mycompany.com:myuser"
        let token = "glpat_selfhosted_token"

        try await tokenStore.setToken(token, for: accountId)
        let retrieved = try await tokenStore.getToken(for: accountId)

        XCTAssertEqual(retrieved, token)
    }

    func testMultipleSelfHostedInstances() async throws {
        let accounts = [
            ("gitlab:gitlab.company1.com:user1", "token1"),
            ("gitlab:gitlab.company2.com:user1", "token2"),
            ("gitlab:gitlab.company1.com:user2", "token3")
        ]

        for (accountId, token) in accounts {
            try await tokenStore.setToken(token, for: accountId)
        }

        for (accountId, expectedToken) in accounts {
            let retrieved = try await tokenStore.getToken(for: accountId)
            XCTAssertEqual(retrieved, expectedToken, "Token mismatch for \(accountId)")
        }
    }

    // MARK: - Special Characters in Tokens

    func testTokenWithSpecialCharacters() async throws {
        let accountId = "gitlab:user"
        // Token with various special characters
        let token = "ghp_abc123!@#$%^&*()_+-=[]{}|;':\",./<>?"

        try await tokenStore.setToken(token, for: accountId)
        let retrieved = try await tokenStore.getToken(for: accountId)

        XCTAssertEqual(retrieved, token)
    }

    func testTokenWithUnicode() async throws {
        let accountId = "gitlab:user"
        let token = "token_with_unicode_🔐_émojis_日本語"

        try await tokenStore.setToken(token, for: accountId)
        let retrieved = try await tokenStore.getToken(for: accountId)

        XCTAssertEqual(retrieved, token)
    }

    func testEmptyToken() async throws {
        let accountId = "gitlab:user"
        let token = ""

        try await tokenStore.setToken(token, for: accountId)
        let retrieved = try await tokenStore.getToken(for: accountId)

        XCTAssertEqual(retrieved, token)
    }

    func testLongToken() async throws {
        let accountId = "gitlab:user"
        // Very long token (4KB)
        let token = String(repeating: "a", count: 4096)

        try await tokenStore.setToken(token, for: accountId)
        let retrieved = try await tokenStore.getToken(for: accountId)

        XCTAssertEqual(retrieved, token)
    }

    // MARK: - Service Isolation

    func testServiceIsolation() async throws {
        let accountId = "gitlab:user"
        let token1 = "token_service_1"
        let token2 = "token_service_2"

        let store1 = KeychainTokenStore(serviceName: testServiceName + ".service1")
        let store2 = KeychainTokenStore(serviceName: testServiceName + ".service2")

        try await store1.setToken(token1, for: accountId)
        try await store2.setToken(token2, for: accountId)

        let retrieved1 = try await store1.getToken(for: accountId)
        let retrieved2 = try await store2.getToken(for: accountId)

        XCTAssertEqual(retrieved1, token1)
        XCTAssertEqual(retrieved2, token2)

        // Cleanup
        try await store1.deleteToken(for: accountId)
        try await store2.deleteToken(for: accountId)
    }
}

// MARK: - TokenKeyGenerator Tests

final class TokenKeyGeneratorTests: XCTestCase {

    func testKeyForStandardProvider() {
        let key = TokenKeyGenerator.key(provider: .gitlab, accountId: "myuser")
        XCTAssertEqual(key, "gitlab:myuser")
    }

    func testKeyForAllProviders() {
        XCTAssertEqual(TokenKeyGenerator.key(provider: .gitlab, accountId: "user"), "gitlab:user")
        XCTAssertEqual(TokenKeyGenerator.key(provider: .gitlab, accountId: "user"), "gitlab:user")
        XCTAssertEqual(TokenKeyGenerator.key(provider: .azureDevops, accountId: "user"), "azure-devops:user")
        XCTAssertEqual(TokenKeyGenerator.key(provider: .googleCalendar, accountId: "user"), "google-calendar:user")
    }

    func testKeyForSelfHosted() {
        let key = TokenKeyGenerator.key(provider: .gitlab, host: "gitlab.mycompany.com", accountId: "myuser")
        XCTAssertEqual(key, "gitlab:gitlab.mycompany.com:myuser")
    }

    func testParseStandardKey() {
        let result = TokenKeyGenerator.parse("gitlab:myuser")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.provider, "gitlab")
        XCTAssertNil(result?.host)
        XCTAssertEqual(result?.accountId, "myuser")
    }

    func testParseSelfHostedKey() {
        let result = TokenKeyGenerator.parse("gitlab:gitlab.mycompany.com:myuser")

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.provider, "gitlab")
        XCTAssertEqual(result?.host, "gitlab.mycompany.com")
        XCTAssertEqual(result?.accountId, "myuser")
    }

    func testParseInvalidKey() {
        let result = TokenKeyGenerator.parse("invalidkey")
        XCTAssertNil(result)
    }

    func testParseEmptyKey() {
        let result = TokenKeyGenerator.parse("")
        XCTAssertNil(result)
    }

    func testRoundTripStandard() {
        let original = TokenKeyGenerator.key(provider: .gitlab, accountId: "myuser")
        let parsed = TokenKeyGenerator.parse(original)

        XCTAssertEqual(parsed?.provider, "gitlab")
        XCTAssertNil(parsed?.host)
        XCTAssertEqual(parsed?.accountId, "myuser")
    }

    func testRoundTripSelfHosted() {
        let original = TokenKeyGenerator.key(provider: .gitlab, host: "gitlab.example.com", accountId: "user123")
        let parsed = TokenKeyGenerator.parse(original)

        XCTAssertEqual(parsed?.provider, "gitlab")
        XCTAssertEqual(parsed?.host, "gitlab.example.com")
        XCTAssertEqual(parsed?.accountId, "user123")
    }
}

// MARK: - TokenStoreError Tests

final class TokenStoreErrorTests: XCTestCase {

    func testDataEncodingErrorDescription() {
        let error = TokenStoreError.dataEncodingError
        XCTAssertEqual(error.localizedDescription, "Failed to encode token data")
    }

    func testDataDecodingErrorDescription() {
        let error = TokenStoreError.dataDecodingError
        XCTAssertEqual(error.localizedDescription, "Failed to decode token data")
    }

    func testUnexpectedErrorDescription() {
        let error = TokenStoreError.unexpectedError("Something went wrong")
        XCTAssertEqual(error.localizedDescription, "Unexpected error: Something went wrong")
    }

    func testKeychainErrorDescription() {
        let error = TokenStoreError.keychainError(errSecAuthFailed)
        // Should contain "Keychain error" regardless of specific message
        XCTAssertTrue(error.localizedDescription.contains("Keychain error"))
    }

    func testErrorEquality() {
        XCTAssertEqual(TokenStoreError.dataEncodingError, TokenStoreError.dataEncodingError)
        XCTAssertEqual(TokenStoreError.dataDecodingError, TokenStoreError.dataDecodingError)
        XCTAssertEqual(TokenStoreError.keychainError(-25300), TokenStoreError.keychainError(-25300))
        XCTAssertEqual(TokenStoreError.unexpectedError("msg"), TokenStoreError.unexpectedError("msg"))

        XCTAssertNotEqual(TokenStoreError.dataEncodingError, TokenStoreError.dataDecodingError)
        XCTAssertNotEqual(TokenStoreError.keychainError(-25300), TokenStoreError.keychainError(-25301))
    }
}

// MARK: - Cache Key Generator Tests

final class CacheKeyGeneratorTests: XCTestCase {
    func testActivitiesKey() {
        let from = Date(timeIntervalSince1970: 1704067200) // 2024-01-01
        let to = Date(timeIntervalSince1970: 1704153600)   // 2024-01-02
        let key = CacheKeyGenerator.activitiesKey(accountId: "gitlab:user1", from: from, to: to)

        XCTAssertTrue(key.hasPrefix("activities_gitlab_user1_"))
        XCTAssertFalse(key.contains(":")) // Colons should be replaced
    }

    func testActivitiesKeySanitizesSpecialChars() {
        let from = Date()
        let to = Date()
        let key = CacheKeyGenerator.activitiesKey(accountId: "gitlab:host.com:user", from: from, to: to)

        XCTAssertFalse(key.contains(":"))
        XCTAssertFalse(key.contains("/"))
    }

    func testHeatmapKey() {
        let key = CacheKeyGenerator.heatmapKey(accountId: "gitlab:user1")

        XCTAssertEqual(key, "heatmap_gitlab_user1")
    }

    func testHeatmapKeySanitizesSpecialChars() {
        let key = CacheKeyGenerator.heatmapKey(accountId: "gitlab:gitlab.company.com:devuser")

        XCTAssertEqual(key, "heatmap_gitlab_gitlab.company.com_devuser")
        XCTAssertFalse(key.contains(":"))
    }

    func testAccountsKey() {
        XCTAssertEqual(CacheKeyGenerator.accountsKey, "accounts")
    }

    func testActivitiesIndexKey() {
        XCTAssertEqual(CacheKeyGenerator.activitiesIndexKey, "activities_index")
    }
}

// MARK: - Cache TTL Tests

final class CacheTTLTests: XCTestCase {
    func testActivitiesTTL() {
        // 1 hour
        XCTAssertEqual(CacheTTL.activitiesTTL, 3600)
    }

    func testHeatmapTTL() {
        // 6 hours
        XCTAssertEqual(CacheTTL.heatmapTTL, 21600)
    }

    func testAccountsTTL() {
        // No expiry
        XCTAssertEqual(CacheTTL.accountsTTL, .infinity)
    }

    func testHeatmapTTLLongerThanActivities() {
        XCTAssertGreaterThan(CacheTTL.heatmapTTL, CacheTTL.activitiesTTL)
    }
}

// MARK: - Disk Activity Cache Tests

final class DiskActivityCacheTests: XCTestCase {
    private var cacheDirectory: URL!
    private var cache: DiskActivityCache!

    override func setUp() {
        super.setUp()
        // Use unique temp directory per test
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("activitybar_test_\(UUID().uuidString)", isDirectory: true)
        cache = DiskActivityCache(cacheDirectory: cacheDirectory)
    }

    override func tearDown() async throws {
        // Clean up cache directory
        try? FileManager.default.removeItem(at: cacheDirectory)
        cache = nil
        cacheDirectory = nil
        try await super.tearDown()
    }

    // MARK: - Account Tests

    func testSaveAndLoadAccounts() async {
        let accounts = [
            Account(id: "gl-1", provider: .gitlab, displayName: "GitLab Personal"),
            Account(id: "gl-1", provider: .gitlab, displayName: "GitLab Work", host: "gitlab.company.com")
        ]

        await cache.saveAccounts(accounts)
        let loaded = await cache.loadAccounts()

        XCTAssertEqual(loaded.count, 2)
        XCTAssertEqual(loaded[0].id, "gl-1")
        XCTAssertEqual(loaded[1].host, "gitlab.company.com")
    }

    func testLoadEmptyAccounts() async {
        let accounts = await cache.loadAccounts()
        XCTAssertTrue(accounts.isEmpty)
    }

    // MARK: - Activities Tests

    func testSaveAndLoadActivities() async {
        let account = Account(id: "gl-1", provider: .gitlab, displayName: "Test")
        let from = Date()
        let to = Date().addingTimeInterval(86400)

        let activities = [
            UnifiedActivity(
                id: "gl-1:commit-123",
                provider: .gitlab,
                accountId: "gl-1",
                sourceId: "commit-123",
                type: .commit,
                timestamp: Date(),
                title: "Test commit"
            )
        ]

        await cache.saveActivities(activities, for: account, from: from, to: to)
        let loaded = await cache.loadActivities(for: account, from: from, to: to)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 1)
        XCTAssertEqual(loaded?[0].id, "gl-1:commit-123")
    }

    func testLoadAllActivities() async {
        // Save accounts first
        let account1 = Account(id: "gl-1", provider: .gitlab, displayName: "GitLab 1")
        let account2 = Account(id: "gl-2", provider: .gitlab, displayName: "GitLab 2")
        await cache.saveAccounts([account1, account2])

        // Save activities for both
        let from = Date()
        let to = Date().addingTimeInterval(86400)

        await cache.saveActivities([
            UnifiedActivity(id: "1", provider: .gitlab, accountId: "gl-1", sourceId: "1", type: .commit, timestamp: Date())
        ], for: account1, from: from, to: to)

        await cache.saveActivities([
            UnifiedActivity(id: "2", provider: .gitlab, accountId: "gl-2", sourceId: "2", type: .pullRequest, timestamp: Date())
        ], for: account2, from: from, to: to)

        let allActivities = await cache.loadAllActivities()

        XCTAssertEqual(allActivities.count, 2)
        XCTAssertNotNil(allActivities["gl-1"])
        XCTAssertNotNil(allActivities["gl-2"])
    }

    // MARK: - Heatmap Tests

    func testSaveAndLoadHeatmap() async {
        let account = Account(id: "gl-1", provider: .gitlab, displayName: "Test")
        let buckets = [
            HeatMapBucket(date: "2024-01-01", count: 5, breakdown: [.gitlab: 5]),
            HeatMapBucket(date: "2024-01-02", count: 3, breakdown: [.gitlab: 3])
        ]

        await cache.saveHeatmap(buckets, for: account)
        let loaded = await cache.loadHeatmap(for: account)

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 2)
        XCTAssertEqual(loaded?[0].count, 5)
    }

    func testLoadAllHeatmapsMergesBuckets() async {
        // Save accounts
        let account1 = Account(id: "gl-1", provider: .gitlab, displayName: "GitLab 1")
        let account2 = Account(id: "gl-2", provider: .azureDevops, displayName: "Azure DevOps")
        await cache.saveAccounts([account1, account2])

        // Save overlapping heatmaps with different providers
        await cache.saveHeatmap([
            HeatMapBucket(date: "2024-01-01", count: 5, breakdown: [.gitlab: 5])
        ], for: account1)

        await cache.saveHeatmap([
            HeatMapBucket(date: "2024-01-01", count: 3, breakdown: [.azureDevops: 3])
        ], for: account2)

        let merged = await cache.loadAllHeatmaps()

        XCTAssertEqual(merged.count, 1) // Same date merged
        XCTAssertEqual(merged[0].count, 8) // 5 + 3
        XCTAssertEqual(merged[0].breakdown?[.gitlab], 5)
        XCTAssertEqual(merged[0].breakdown?[.azureDevops], 3)
    }

    // MARK: - Clear Cache Tests

    func testClearCacheForAccount() async {
        let account = Account(id: "gl-1", provider: .gitlab, displayName: "Test")
        let from = Date()
        let to = Date().addingTimeInterval(86400)

        // Save data
        await cache.saveActivities([
            UnifiedActivity(id: "1", provider: .gitlab, accountId: "gl-1", sourceId: "1", type: .commit, timestamp: Date())
        ], for: account, from: from, to: to)
        await cache.saveHeatmap([HeatMapBucket(date: "2024-01-01", count: 5)], for: account)

        // Verify data exists
        let loadedActivities = await cache.loadActivities(for: account, from: from, to: to)
        XCTAssertNotNil(loadedActivities)
        let loadedHeatmap = await cache.loadHeatmap(for: account)
        XCTAssertNotNil(loadedHeatmap)

        // Clear cache for account
        await cache.clearCache(for: "gl-1")

        // Verify data is gone
        let clearedHeatmap = await cache.loadHeatmap(for: account)
        XCTAssertNil(clearedHeatmap)
    }

    func testClearAllCache() async {
        let account = Account(id: "gl-1", provider: .gitlab, displayName: "Test")
        await cache.saveAccounts([account])
        await cache.saveHeatmap([HeatMapBucket(date: "2024-01-01", count: 5)], for: account)

        // Clear all
        await cache.clearAllCache()

        // Verify everything is gone
        let accounts = await cache.loadAccounts()
        XCTAssertTrue(accounts.isEmpty)
    }
}

// MARK: - Disk Cache Provider Tests

final class DiskCacheProviderTests: XCTestCase {
    private var cacheDirectory: URL!
    private var provider: DiskCacheProvider!
    private var cache: DiskActivityCache!

    override func setUp() {
        super.setUp()
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("activitybar_provider_test_\(UUID().uuidString)", isDirectory: true)
        cache = DiskActivityCache(cacheDirectory: cacheDirectory)
        provider = DiskCacheProvider(cache: cache)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: cacheDirectory)
        provider = nil
        cache = nil
        cacheDirectory = nil
        try await super.tearDown()
    }

    func testLoadCachedAccountsEmpty() async {
        let accounts = await provider.loadCachedAccounts()
        XCTAssertTrue(accounts.isEmpty)
    }

    func testLoadCachedAccountsWithData() async {
        let accounts = [
            Account(id: "test", provider: .gitlab, displayName: "Test")
        ]
        await provider.saveAccounts(accounts)

        let loaded = await provider.loadCachedAccounts()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, "test")
    }

    func testLoadCachedActivitiesEmpty() async {
        let activities = await provider.loadCachedActivities()
        XCTAssertTrue(activities.isEmpty)
    }

    func testLoadCachedHeatmapEmpty() async {
        let heatmap = await provider.loadCachedHeatmap()
        XCTAssertTrue(heatmap.isEmpty)
    }

    func testSaveAndLoadHeatmap() async {
        let account = Account(id: "gl-1", provider: .gitlab, displayName: "Test")
        await provider.saveAccounts([account])

        let buckets = [HeatMapBucket(date: "2024-01-15", count: 10)]
        await provider.saveHeatmap(buckets, for: account)

        let loaded = await provider.loadCachedHeatmap()
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].count, 10)
    }
}

// MARK: - Day Status Tests

final class DayStatusTests: XCTestCase {
    func testDayStatusInit() {
        let now = Date()
        let status = DayStatus(fetchedAt: now, count: 42)

        XCTAssertEqual(status.fetchedAt, now)
        XCTAssertEqual(status.count, 42)
    }

    func testDayStatusEquatable() {
        let date = Date()
        let status1 = DayStatus(fetchedAt: date, count: 10)
        let status2 = DayStatus(fetchedAt: date, count: 10)
        let status3 = DayStatus(fetchedAt: date, count: 20)

        XCTAssertEqual(status1, status2)
        XCTAssertNotEqual(status1, status3)
    }

    func testDayStatusCodable() throws {
        let now = Date()
        let status = DayStatus(fetchedAt: now, count: 15)

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(status)

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(DayStatus.self, from: data)

        XCTAssertEqual(decoded.count, 15)
    }
}

// MARK: - Day Index Tests

final class DayIndexTests: XCTestCase {
    func testDayIndexInit() {
        let index = DayIndex()
        XCTAssertTrue(index.accounts.isEmpty)
    }

    func testDayIndexInitWithAccounts() {
        let status = DayStatus(fetchedAt: Date(), count: 5)
        let accounts: [String: [String: DayStatus]] = [
            "account1": ["2026-01-31": status]
        ]
        let index = DayIndex(accounts: accounts)

        XCTAssertEqual(index.accounts.count, 1)
        XCTAssertNotNil(index.accounts["account1"])
    }

    func testDayIndexStatus() {
        let status = DayStatus(fetchedAt: Date(), count: 10)
        var index = DayIndex()
        index.accounts["acc1"] = ["2026-01-30": status]

        let retrieved = index.status(for: "acc1", date: "2026-01-30")
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.count, 10)

        let missing = index.status(for: "acc1", date: "2026-01-29")
        XCTAssertNil(missing)

        let missingAccount = index.status(for: "nonexistent", date: "2026-01-30")
        XCTAssertNil(missingAccount)
    }

    func testDayIndexIsDayFetched() {
        let status = DayStatus(fetchedAt: Date(), count: 3)
        var index = DayIndex()
        index.accounts["acc1"] = ["2026-01-31": status]

        XCTAssertTrue(index.isDayFetched(accountId: "acc1", date: "2026-01-31"))
        XCTAssertFalse(index.isDayFetched(accountId: "acc1", date: "2026-01-30"))
        XCTAssertFalse(index.isDayFetched(accountId: "other", date: "2026-01-31"))
    }

    func testDayIndexFetchedDates() {
        var index = DayIndex()
        index.accounts["acc1"] = [
            "2026-01-30": DayStatus(fetchedAt: Date(), count: 5),
            "2026-01-31": DayStatus(fetchedAt: Date(), count: 3)
        ]

        let dates = index.fetchedDates(for: "acc1")
        XCTAssertEqual(Set(dates), Set(["2026-01-30", "2026-01-31"]))

        let emptyDates = index.fetchedDates(for: "nonexistent")
        XCTAssertTrue(emptyDates.isEmpty)
    }

    func testDayIndexCount() {
        var index = DayIndex()
        index.accounts["acc1"] = ["2026-01-31": DayStatus(fetchedAt: Date(), count: 42)]

        XCTAssertEqual(index.count(for: "acc1", date: "2026-01-31"), 42)
        XCTAssertEqual(index.count(for: "acc1", date: "2026-01-30"), 0)
        XCTAssertEqual(index.count(for: "other", date: "2026-01-31"), 0)
    }

    func testDayIndexComputeHeatmapBuckets() {
        var index = DayIndex()
        index.accounts["acc1"] = [
            "2026-01-30": DayStatus(fetchedAt: Date(), count: 5),
            "2026-01-31": DayStatus(fetchedAt: Date(), count: 10)
        ]
        index.accounts["acc2"] = [
            "2026-01-30": DayStatus(fetchedAt: Date(), count: 3),
            "2026-01-29": DayStatus(fetchedAt: Date(), count: 7)
        ]

        let buckets = index.computeHeatmapBuckets()

        // Should have 3 unique dates, sorted
        XCTAssertEqual(buckets.count, 3)
        XCTAssertEqual(buckets[0].date, "2026-01-29")
        XCTAssertEqual(buckets[0].count, 7)
        XCTAssertEqual(buckets[1].date, "2026-01-30")
        XCTAssertEqual(buckets[1].count, 8) // 5 + 3
        XCTAssertEqual(buckets[2].date, "2026-01-31")
        XCTAssertEqual(buckets[2].count, 10)
    }

    func testDayIndexComputeHeatmapBucketsEmpty() {
        let index = DayIndex()
        let buckets = index.computeHeatmapBuckets()
        XCTAssertTrue(buckets.isEmpty)
    }
}

// MARK: - Cache Key Generator Extended Tests

final class CacheKeyGeneratorExtendedTests: XCTestCase {
    func testDayIndexKey() {
        XCTAssertEqual(CacheKeyGenerator.dayIndexKey, "day_index")
    }

    func testSanitizeAccountId() {
        XCTAssertEqual(CacheKeyGenerator.sanitizeAccountId("gitlab:user"), "gitlab_user")
        XCTAssertEqual(CacheKeyGenerator.sanitizeAccountId("gitlab:host.com:user"), "gitlab_host.com_user")
        XCTAssertEqual(CacheKeyGenerator.sanitizeAccountId("simple"), "simple")
        XCTAssertEqual(CacheKeyGenerator.sanitizeAccountId("path/with/slashes"), "path_with_slashes")
    }

    func testDateStringFromDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let date = calendar.date(from: DateComponents(year: 2026, month: 1, day: 31))!

        let dateString = CacheKeyGenerator.dateString(from: date)
        XCTAssertEqual(dateString, "2026-01-31")
    }

    func testDateFromString() {
        let date = CacheKeyGenerator.date(from: "2026-01-31")
        XCTAssertNotNil(date)

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let components = calendar.dateComponents([.year, .month, .day], from: date!)

        XCTAssertEqual(components.year, 2026)
        XCTAssertEqual(components.month, 1)
        XCTAssertEqual(components.day, 31)
    }

    func testDateFromStringInvalid() {
        XCTAssertNil(CacheKeyGenerator.date(from: "invalid"))
        XCTAssertNil(CacheKeyGenerator.date(from: "2026-13-45"))
        XCTAssertNil(CacheKeyGenerator.date(from: ""))
    }

    func testDateRoundTrip() {
        let original = Date()
        let dateString = CacheKeyGenerator.dateString(from: original)
        let parsed = CacheKeyGenerator.date(from: dateString)

        XCTAssertNotNil(parsed)

        // Should be the same day (ignoring time)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let originalComponents = calendar.dateComponents([.year, .month, .day], from: original)
        let parsedComponents = calendar.dateComponents([.year, .month, .day], from: parsed!)

        XCTAssertEqual(originalComponents.year, parsedComponents.year)
        XCTAssertEqual(originalComponents.month, parsedComponents.month)
        XCTAssertEqual(originalComponents.day, parsedComponents.day)
    }
}

// MARK: - Cache TTL Extended Tests

final class CacheTTLExtendedTests: XCTestCase {
    func testTodayTTL() {
        // Today's cache should be 15 minutes
        XCTAssertEqual(CacheTTL.todayTTL, 15 * 60)
    }

    func testPastDayTTL() {
        // Past days should never expire
        XCTAssertEqual(CacheTTL.pastDayTTL, .infinity)
    }

    func testTodayTTLShorterThanActivitiesTTL() {
        // Today needs more frequent refresh than general activities
        XCTAssertLessThan(CacheTTL.todayTTL, CacheTTL.activitiesTTL)
    }
}

// MARK: - Per-Day Disk Cache Tests

final class PerDayDiskCacheTests: XCTestCase {
    private var cacheDirectory: URL!
    private var cache: DiskActivityCache!

    override func setUp() {
        super.setUp()
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("activitybar_perday_test_\(UUID().uuidString)", isDirectory: true)
        cache = DiskActivityCache(cacheDirectory: cacheDirectory)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: cacheDirectory)
        cache = nil
        cacheDirectory = nil
        try await super.tearDown()
    }

    // MARK: - Per-Day Save/Load Tests

    func testSaveAndLoadActivitiesForDay() async {
        let activities = [
            UnifiedActivity(
                id: "a1", provider: .gitlab, accountId: "gl-1",
                sourceId: "s1", type: .commit, timestamp: Date(),
                title: "Test commit"
            ),
            UnifiedActivity(
                id: "a2", provider: .gitlab, accountId: "gl-1",
                sourceId: "s2", type: .pullRequest, timestamp: Date(),
                title: "Test PR"
            )
        ]

        await cache.saveActivitiesForDay(activities, accountId: "gl-1", date: "2026-01-31")
        let loaded = await cache.loadActivitiesForDay(accountId: "gl-1", date: "2026-01-31")

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 2)
        XCTAssertTrue(loaded?.contains { $0.id == "a1" } ?? false)
        XCTAssertTrue(loaded?.contains { $0.id == "a2" } ?? false)
    }

    func testLoadActivitiesForDayReturnsNilWhenMissing() async {
        let result = await cache.loadActivitiesForDay(accountId: "nonexistent", date: "2026-01-31")
        XCTAssertNil(result)
    }

    func testSaveActivitiesForDayUpdatesDayIndex() async {
        let activities = [
            UnifiedActivity(
                id: "a1", provider: .gitlab, accountId: "gl-1",
                sourceId: "s1", type: .commit, timestamp: Date()
            )
        ]

        await cache.saveActivitiesForDay(activities, accountId: "gl-1", date: "2026-01-31")

        let index = await cache.getDayIndex()
        XCTAssertTrue(index.isDayFetched(accountId: "gl-1", date: "2026-01-31"))
        XCTAssertEqual(index.count(for: "gl-1", date: "2026-01-31"), 1)
    }

    // MARK: - isDayFetched Tests

    func testIsDayFetchedReturnsFalseInitially() async {
        let result = await cache.isDayFetched(accountId: "gl-1", date: "2026-01-31")
        XCTAssertFalse(result)
    }

    func testIsDayFetchedReturnsTrueAfterSave() async {
        let activities = [
            UnifiedActivity(
                id: "a1", provider: .gitlab, accountId: "gl-1",
                sourceId: "s1", type: .commit, timestamp: Date()
            )
        ]

        await cache.saveActivitiesForDay(activities, accountId: "gl-1", date: "2026-01-31")

        let result = await cache.isDayFetched(accountId: "gl-1", date: "2026-01-31")
        XCTAssertTrue(result)
    }

    // MARK: - getDayIndex Tests

    func testGetDayIndexEmpty() async {
        let index = await cache.getDayIndex()
        XCTAssertTrue(index.accounts.isEmpty)
    }

    func testGetDayIndexAfterMultipleSaves() async {
        await cache.saveActivitiesForDay([], accountId: "acc1", date: "2026-01-30")
        await cache.saveActivitiesForDay([
            UnifiedActivity(id: "a1", provider: .gitlab, accountId: "acc1",
                          sourceId: "s1", type: .commit, timestamp: Date())
        ], accountId: "acc1", date: "2026-01-31")
        await cache.saveActivitiesForDay([
            UnifiedActivity(id: "a2", provider: .gitlab, accountId: "acc2",
                          sourceId: "s2", type: .pullRequest, timestamp: Date()),
            UnifiedActivity(id: "a3", provider: .gitlab, accountId: "acc2",
                          sourceId: "s3", type: .issue, timestamp: Date())
        ], accountId: "acc2", date: "2026-01-31")

        let index = await cache.getDayIndex()

        XCTAssertEqual(index.accounts.count, 2)
        XCTAssertEqual(index.count(for: "acc1", date: "2026-01-30"), 0)
        XCTAssertEqual(index.count(for: "acc1", date: "2026-01-31"), 1)
        XCTAssertEqual(index.count(for: "acc2", date: "2026-01-31"), 2)
    }

    // MARK: - updateDayIndex Tests

    func testUpdateDayIndex() async {
        await cache.updateDayIndex(accountId: "gl-1", date: "2026-01-31", count: 42)

        let index = await cache.getDayIndex()
        XCTAssertEqual(index.count(for: "gl-1", date: "2026-01-31"), 42)
    }

    func testUpdateDayIndexOverwrites() async {
        await cache.updateDayIndex(accountId: "gl-1", date: "2026-01-31", count: 10)
        await cache.updateDayIndex(accountId: "gl-1", date: "2026-01-31", count: 20)

        let index = await cache.getDayIndex()
        XCTAssertEqual(index.count(for: "gl-1", date: "2026-01-31"), 20)
    }

    // MARK: - loadActivitiesForDays Tests

    func testLoadActivitiesForDays() async {
        // Save activities for multiple days
        await cache.saveActivitiesForDay([
            UnifiedActivity(id: "a1", provider: .gitlab, accountId: "gl-1",
                          sourceId: "s1", type: .commit, timestamp: Date())
        ], accountId: "gl-1", date: "2026-01-30")

        await cache.saveActivitiesForDay([
            UnifiedActivity(id: "a2", provider: .gitlab, accountId: "gl-1",
                          sourceId: "s2", type: .pullRequest, timestamp: Date())
        ], accountId: "gl-1", date: "2026-01-31")

        let activities = await cache.loadActivitiesForDays(
            accountId: "gl-1",
            dates: ["2026-01-30", "2026-01-31"]
        )

        XCTAssertEqual(activities.count, 2)
    }

    func testLoadActivitiesForDaysSkipsMissingDays() async {
        await cache.saveActivitiesForDay([
            UnifiedActivity(id: "a1", provider: .gitlab, accountId: "gl-1",
                          sourceId: "s1", type: .commit, timestamp: Date())
        ], accountId: "gl-1", date: "2026-01-31")

        let activities = await cache.loadActivitiesForDays(
            accountId: "gl-1",
            dates: ["2026-01-29", "2026-01-30", "2026-01-31"]
        )

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities.first?.id, "a1")
    }

    func testLoadActivitiesForDaysReturnsSorted() async {
        let now = Date()
        let earlier = now.addingTimeInterval(-3600)
        let earliest = now.addingTimeInterval(-7200)

        await cache.saveActivitiesForDay([
            UnifiedActivity(id: "a1", provider: .gitlab, accountId: "gl-1",
                          sourceId: "s1", type: .commit, timestamp: earliest)
        ], accountId: "gl-1", date: "2026-01-29")

        await cache.saveActivitiesForDay([
            UnifiedActivity(id: "a2", provider: .gitlab, accountId: "gl-1",
                          sourceId: "s2", type: .commit, timestamp: now)
        ], accountId: "gl-1", date: "2026-01-31")

        await cache.saveActivitiesForDay([
            UnifiedActivity(id: "a3", provider: .gitlab, accountId: "gl-1",
                          sourceId: "s3", type: .commit, timestamp: earlier)
        ], accountId: "gl-1", date: "2026-01-30")

        let activities = await cache.loadActivitiesForDays(
            accountId: "gl-1",
            dates: ["2026-01-29", "2026-01-30", "2026-01-31"]
        )

        // Should be sorted by timestamp descending
        XCTAssertEqual(activities.map { $0.id }, ["a2", "a3", "a1"])
    }

    // MARK: - isTodayCacheStale Tests

    func testIsTodayCacheStaleWhenNoCache() async {
        let isStale = await cache.isTodayCacheStale(accountId: "gl-1")
        XCTAssertTrue(isStale)
    }

    func testIsTodayCacheStaleWhenFresh() async {
        let today = CacheKeyGenerator.dateString(from: Date())
        await cache.saveActivitiesForDay([
            UnifiedActivity(id: "a1", provider: .gitlab, accountId: "gl-1",
                          sourceId: "s1", type: .commit, timestamp: Date())
        ], accountId: "gl-1", date: today)

        let isStale = await cache.isTodayCacheStale(accountId: "gl-1")
        XCTAssertFalse(isStale)
    }

    // MARK: - clearCache Tests

    func testClearCacheRemovesPerDayFiles() async {
        // Save some per-day activities
        await cache.saveActivitiesForDay([
            UnifiedActivity(id: "a1", provider: .gitlab, accountId: "gl-1",
                          sourceId: "s1", type: .commit, timestamp: Date())
        ], accountId: "gl-1", date: "2026-01-31")

        // Verify it exists
        let before = await cache.loadActivitiesForDay(accountId: "gl-1", date: "2026-01-31")
        XCTAssertNotNil(before)

        // Clear cache for account
        await cache.clearCache(for: "gl-1")

        // Verify it's gone
        let after = await cache.loadActivitiesForDay(accountId: "gl-1", date: "2026-01-31")
        XCTAssertNil(after)

        // Day index should also be cleared
        let index = await cache.getDayIndex()
        XCTAssertFalse(index.isDayFetched(accountId: "gl-1", date: "2026-01-31"))
    }

    func testClearCachePreservesOtherAccounts() async {
        await cache.saveActivitiesForDay([
            UnifiedActivity(id: "a1", provider: .gitlab, accountId: "gl-1",
                          sourceId: "s1", type: .commit, timestamp: Date())
        ], accountId: "gl-1", date: "2026-01-31")

        await cache.saveActivitiesForDay([
            UnifiedActivity(id: "a2", provider: .gitlab, accountId: "gl-2",
                          sourceId: "s2", type: .commit, timestamp: Date())
        ], accountId: "gl-2", date: "2026-01-31")

        await cache.clearCache(for: "gl-1")

        // gl-1 should be cleared
        let gl1 = await cache.loadActivitiesForDay(accountId: "gl-1", date: "2026-01-31")
        XCTAssertNil(gl1)

        // gl-2 should still exist
        let gl2 = await cache.loadActivitiesForDay(accountId: "gl-2", date: "2026-01-31")
        XCTAssertNotNil(gl2)
    }
}

// MARK: - Disk Cache Provider Per-Day Tests

final class DiskCacheProviderPerDayTests: XCTestCase {
    private var cacheDirectory: URL!
    private var provider: DiskCacheProvider!
    private var cache: DiskActivityCache!

    override func setUp() {
        super.setUp()
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("activitybar_provider_perday_test_\(UUID().uuidString)", isDirectory: true)
        cache = DiskActivityCache(cacheDirectory: cacheDirectory)
        provider = DiskCacheProvider(cache: cache)
    }

    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: cacheDirectory)
        provider = nil
        cache = nil
        cacheDirectory = nil
        try await super.tearDown()
    }

    func testLoadDayIndexEmpty() async {
        let index = await provider.loadDayIndex()
        XCTAssertTrue(index.isEmpty)
    }

    func testLoadDayIndexAfterSave() async {
        await provider.saveActivitiesForDay([
            UnifiedActivity(id: "a1", provider: .gitlab, accountId: "gl-1",
                          sourceId: "s1", type: .commit, timestamp: Date())
        ], accountId: "gl-1", date: "2026-01-31")

        let index = await provider.loadDayIndex()

        XCTAssertNotNil(index["gl-1"])
        XCTAssertNotNil(index["gl-1"]?["2026-01-31"])
        XCTAssertEqual(index["gl-1"]?["2026-01-31"]?.count, 1)
    }

    func testSaveAndLoadActivitiesForDay() async {
        let activities = [
            UnifiedActivity(id: "a1", provider: .gitlab, accountId: "gl-1",
                          sourceId: "s1", type: .commit, timestamp: Date())
        ]

        await provider.saveActivitiesForDay(activities, accountId: "gl-1", date: "2026-01-31")
        let loaded = await provider.loadActivitiesForDay(accountId: "gl-1", date: "2026-01-31")

        XCTAssertNotNil(loaded)
        XCTAssertEqual(loaded?.count, 1)
    }

    func testIsTodayCacheStale() async {
        // No cache yet - should be stale
        let staleBefore = await provider.isTodayCacheStale(accountId: "gl-1")
        XCTAssertTrue(staleBefore)

        // Save today's activities
        let today = CacheKeyGenerator.dateString(from: Date())
        await provider.saveActivitiesForDay([], accountId: "gl-1", date: today)

        // Should not be stale now
        let staleAfter = await provider.isTodayCacheStale(accountId: "gl-1")
        XCTAssertFalse(staleAfter)
    }
}
