import XCTest
@testable import Providers
@testable import Core
@testable import Storage

// MARK: - Mock Token Store

final class MockTokenStoreForRefresh: TokenStore, @unchecked Sendable {
    var tokens: [String: String] = [:]
    var getTokenCallCount = 0
    var setTokenCallCount = 0
    var deleteTokenCallCount = 0
    var lastSetToken: String?
    var lastSetAccountId: String?

    func getToken(for accountId: String) async throws -> String? {
        getTokenCallCount += 1
        return tokens[accountId]
    }

    func setToken(_ token: String, for accountId: String) async throws {
        setTokenCallCount += 1
        lastSetToken = token
        lastSetAccountId = accountId
        tokens[accountId] = token
    }

    func deleteToken(for accountId: String) async throws {
        deleteTokenCallCount += 1
        tokens.removeValue(forKey: accountId)
    }

    func hasToken(for accountId: String) async throws -> Bool {
        tokens[accountId] != nil
    }

    func listAccountIds() async throws -> [String] {
        Array(tokens.keys)
    }
}

// MARK: - Mock Token Refresh Service

final class MockTokenRefreshService: TokenRefreshing, @unchecked Sendable {
    var canRefreshResult = true
    var refreshTokenResult: String?
    var refreshTokenError: Error?
    var refreshTokenCallCount = 0
    var lastRefreshedAccount: Account?

    nonisolated func canRefresh(account: Account) -> Bool {
        canRefreshResult
    }

    func refreshToken(for account: Account, using tokenStore: TokenStore) async throws -> String {
        refreshTokenCallCount += 1
        lastRefreshedAccount = account

        if let error = refreshTokenError {
            throw error
        }

        if let result = refreshTokenResult {
            return result
        }

        throw ProviderError.authenticationFailed("No mock result configured")
    }
}

// MARK: - Mock Provider Adapter

final class MockProviderAdapter: ProviderAdapter, @unchecked Sendable {
    let provider: Provider
    var activitiesToReturn: [UnifiedActivity] = []
    var heatmapToReturn: [HeatMapBucket] = []
    var errorToThrow: Error?
    var fetchActivitiesCallCount = 0
    var fetchHeatmapCallCount = 0
    var lastToken: String?
    var failOnFirstCallOnly = false
    private var hasFailedOnce = false

    init(provider: Provider) {
        self.provider = provider
    }

    func fetchActivities(for account: Account, token: String, from: Date, to: Date) async throws -> [UnifiedActivity] {
        fetchActivitiesCallCount += 1
        lastToken = token

        if let error = errorToThrow {
            if failOnFirstCallOnly && hasFailedOnce {
                // Second call succeeds
                return activitiesToReturn
            }
            hasFailedOnce = true
            throw error
        }

        return activitiesToReturn
    }

    func fetchHeatmap(for account: Account, token: String, from: Date, to: Date) async throws -> [HeatMapBucket] {
        fetchHeatmapCallCount += 1
        lastToken = token

        if let error = errorToThrow {
            if failOnFirstCallOnly && hasFailedOnce {
                return heatmapToReturn
            }
            hasFailedOnce = true
            throw error
        }

        return heatmapToReturn
    }
}

// MARK: - TokenRefreshService Tests

final class TokenRefreshServiceTests: XCTestCase {

    // MARK: - canRefresh Tests

    func testCanRefresh_OAuthGitLabAccount_ReturnsTrue() {
        let service = TokenRefreshService()
        let account = Account(
            id: "gitlab:user1",
            provider: .gitlab,
            displayName: "GitLab User",
            authMethod: .oauth
        )

        XCTAssertTrue(service.canRefresh(account: account))
    }

    func testCanRefresh_OAuthGoogleAccount_ReturnsTrue() {
        let service = TokenRefreshService()
        let account = Account(
            id: "google-calendar:user@example.com",
            provider: .googleCalendar,
            displayName: "Google User",
            authMethod: .oauth
        )

        XCTAssertTrue(service.canRefresh(account: account))
    }

    func testCanRefresh_PATAccount_ReturnsFalse() {
        let service = TokenRefreshService()
        let account = Account(
            id: "gitlab:user1",
            provider: .gitlab,
            displayName: "GitLab User",
            authMethod: .pat
        )

        XCTAssertFalse(service.canRefresh(account: account))
    }

    func testCanRefresh_AzureDevOpsAccount_ReturnsFalse() {
        let service = TokenRefreshService()
        let account = Account(
            id: "azure:user1",
            provider: .azureDevops,
            displayName: "Azure User",
            organization: "myorg",
            authMethod: .oauth
        )

        XCTAssertFalse(service.canRefresh(account: account))
    }

    func testCanRefresh_AzureDevOpsPAT_ReturnsFalse() {
        let service = TokenRefreshService()
        let account = Account(
            id: "azure:user1",
            provider: .azureDevops,
            displayName: "Azure User",
            organization: "myorg",
            authMethod: .pat
        )

        XCTAssertFalse(service.canRefresh(account: account))
    }

    // MARK: - refreshToken Tests

    func testRefreshToken_NoRefreshTokenStored_ThrowsAuthError() async {
        let service = TokenRefreshService()
        let tokenStore = MockTokenStoreForRefresh()
        let account = Account(
            id: "gitlab:user1",
            provider: .gitlab,
            displayName: "GitLab User",
            authMethod: .oauth
        )

        // No refresh token stored

        do {
            _ = try await service.refreshToken(for: account, using: tokenStore)
            XCTFail("Should have thrown an error")
        } catch let error as ProviderError {
            if case .authenticationFailed(let message) = error {
                XCTAssertTrue(message.contains("refresh token"))
            } else {
                XCTFail("Expected authenticationFailed error, got \(error)")
            }
        } catch {
            XCTFail("Expected ProviderError, got \(error)")
        }
    }

    func testRefreshToken_EmptyRefreshToken_ThrowsAuthError() async {
        let service = TokenRefreshService()
        let tokenStore = MockTokenStoreForRefresh()
        tokenStore.tokens["gitlab:user1:refresh"] = ""

        let account = Account(
            id: "gitlab:user1",
            provider: .gitlab,
            displayName: "GitLab User",
            authMethod: .oauth
        )

        do {
            _ = try await service.refreshToken(for: account, using: tokenStore)
            XCTFail("Should have thrown an error")
        } catch let error as ProviderError {
            if case .authenticationFailed(let message) = error {
                XCTAssertTrue(message.contains("refresh token"))
            } else {
                XCTFail("Expected authenticationFailed error, got \(error)")
            }
        } catch {
            XCTFail("Expected ProviderError, got \(error)")
        }
    }

    func testRefreshToken_AzureDevOps_ThrowsConfigError() async {
        let service = TokenRefreshService()
        let tokenStore = MockTokenStoreForRefresh()
        tokenStore.tokens["azure:user1:refresh"] = "refresh_token"

        let account = Account(
            id: "azure:user1",
            provider: .azureDevops,
            displayName: "Azure User",
            organization: "myorg",
            authMethod: .oauth
        )

        do {
            _ = try await service.refreshToken(for: account, using: tokenStore)
            XCTFail("Should have thrown an error")
        } catch let error as ProviderError {
            if case .configurationError(let message) = error {
                XCTAssertTrue(message.contains("Azure DevOps"))
            } else {
                XCTFail("Expected configurationError, got \(error)")
            }
        } catch {
            XCTFail("Expected ProviderError, got \(error)")
        }
    }
}

// MARK: - ActivityRefreshProvider Auto-Refresh Tests

final class ActivityRefreshProviderAutoRefreshTests: XCTestCase {

    func testFetchActivities_Success_NoRefreshNeeded() async throws {
        let tokenStore = MockTokenStoreForRefresh()
        tokenStore.tokens["gitlab:user1"] = "valid_token"

        let mockAdapter = MockProviderAdapter(provider: .gitlab)
        mockAdapter.activitiesToReturn = [
            UnifiedActivity(
                id: "1",
                provider: .gitlab,
                accountId: "gitlab:user1",
                sourceId: "commit-1",
                type: .commit,
                timestamp: Date(),
                title: "Test commit",
                url: nil
            )
        ]

        let mockRefreshService = MockTokenRefreshService()

        let provider = ActivityRefreshProvider(
            tokenStore: tokenStore,
            adapters: [.gitlab: mockAdapter],
            refreshService: mockRefreshService
        )

        let account = Account(
            id: "gitlab:user1",
            provider: .gitlab,
            displayName: "GitLab User",
            authMethod: .oauth
        )

        let activities = try await provider.fetchActivities(for: account)

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(mockAdapter.fetchActivitiesCallCount, 1)
        XCTAssertEqual(mockRefreshService.refreshTokenCallCount, 0, "Should not refresh on success")
    }

    func testFetchActivities_AuthFailed_RefreshesAndRetries() async throws {
        let tokenStore = MockTokenStoreForRefresh()
        tokenStore.tokens["gitlab:user1"] = "expired_token"

        let mockAdapter = MockProviderAdapter(provider: .gitlab)
        mockAdapter.errorToThrow = ProviderError.authenticationFailed("HTTP 401")
        mockAdapter.failOnFirstCallOnly = true
        mockAdapter.activitiesToReturn = [
            UnifiedActivity(
                id: "1",
                provider: .gitlab,
                accountId: "gitlab:user1",
                sourceId: "commit-1",
                type: .commit,
                timestamp: Date(),
                title: "Test commit",
                url: nil
            )
        ]

        let mockRefreshService = MockTokenRefreshService()
        mockRefreshService.canRefreshResult = true
        mockRefreshService.refreshTokenResult = "new_valid_token"

        let provider = ActivityRefreshProvider(
            tokenStore: tokenStore,
            adapters: [.gitlab: mockAdapter],
            refreshService: mockRefreshService
        )

        let account = Account(
            id: "gitlab:user1",
            provider: .gitlab,
            displayName: "GitLab User",
            authMethod: .oauth
        )

        let activities = try await provider.fetchActivities(for: account)

        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(mockAdapter.fetchActivitiesCallCount, 2, "Should retry after refresh")
        XCTAssertEqual(mockRefreshService.refreshTokenCallCount, 1, "Should refresh once")
        XCTAssertEqual(mockAdapter.lastToken, "new_valid_token", "Should use new token on retry")
    }

    func testFetchActivities_AuthFailed_CannotRefresh_ThrowsError() async {
        let tokenStore = MockTokenStoreForRefresh()
        tokenStore.tokens["gitlab:user1"] = "expired_token"

        let mockAdapter = MockProviderAdapter(provider: .gitlab)
        mockAdapter.errorToThrow = ProviderError.authenticationFailed("HTTP 401")

        let mockRefreshService = MockTokenRefreshService()
        mockRefreshService.canRefreshResult = false // Cannot refresh (e.g., PAT account)

        let provider = ActivityRefreshProvider(
            tokenStore: tokenStore,
            adapters: [.gitlab: mockAdapter],
            refreshService: mockRefreshService
        )

        let account = Account(
            id: "gitlab:user1",
            provider: .gitlab,
            displayName: "GitLab User",
            authMethod: .pat  // PAT cannot be refreshed
        )

        do {
            _ = try await provider.fetchActivities(for: account)
            XCTFail("Should have thrown an error")
        } catch let error as ProviderError {
            if case .authenticationFailed = error {
                // Expected
            } else {
                XCTFail("Expected authenticationFailed, got \(error)")
            }
        } catch {
            XCTFail("Expected ProviderError, got \(error)")
        }

        XCTAssertEqual(mockAdapter.fetchActivitiesCallCount, 1, "Should not retry")
        XCTAssertEqual(mockRefreshService.refreshTokenCallCount, 0, "Should not attempt refresh")
    }

    func testFetchActivities_AuthFailed_RefreshFails_ThrowsError() async {
        let tokenStore = MockTokenStoreForRefresh()
        tokenStore.tokens["gitlab:user1"] = "expired_token"

        let mockAdapter = MockProviderAdapter(provider: .gitlab)
        mockAdapter.errorToThrow = ProviderError.authenticationFailed("HTTP 401")

        let mockRefreshService = MockTokenRefreshService()
        mockRefreshService.canRefreshResult = true
        mockRefreshService.refreshTokenError = ProviderError.authenticationFailed("Refresh token expired")

        let provider = ActivityRefreshProvider(
            tokenStore: tokenStore,
            adapters: [.gitlab: mockAdapter],
            refreshService: mockRefreshService
        )

        let account = Account(
            id: "gitlab:user1",
            provider: .gitlab,
            displayName: "GitLab User",
            authMethod: .oauth
        )

        do {
            _ = try await provider.fetchActivities(for: account)
            XCTFail("Should have thrown an error")
        } catch let error as ProviderError {
            if case .authenticationFailed(let message) = error {
                XCTAssertTrue(message.contains("refresh failed") || message.contains("re-authenticate"))
            } else {
                XCTFail("Expected authenticationFailed, got \(error)")
            }
        } catch {
            XCTFail("Expected ProviderError, got \(error)")
        }

        XCTAssertEqual(mockAdapter.fetchActivitiesCallCount, 1, "Should not retry after refresh failure")
        XCTAssertEqual(mockRefreshService.refreshTokenCallCount, 1, "Should attempt refresh once")
    }

    func testFetchActivities_NetworkError_DoesNotRefresh() async {
        let tokenStore = MockTokenStoreForRefresh()
        tokenStore.tokens["gitlab:user1"] = "valid_token"

        let mockAdapter = MockProviderAdapter(provider: .gitlab)
        mockAdapter.errorToThrow = ProviderError.networkError("Connection failed")

        let mockRefreshService = MockTokenRefreshService()
        mockRefreshService.canRefreshResult = true

        let provider = ActivityRefreshProvider(
            tokenStore: tokenStore,
            adapters: [.gitlab: mockAdapter],
            refreshService: mockRefreshService
        )

        let account = Account(
            id: "gitlab:user1",
            provider: .gitlab,
            displayName: "GitLab User",
            authMethod: .oauth
        )

        do {
            _ = try await provider.fetchActivities(for: account)
            XCTFail("Should have thrown an error")
        } catch let error as ProviderError {
            if case .networkError = error {
                // Expected - network errors should not trigger refresh
            } else {
                XCTFail("Expected networkError, got \(error)")
            }
        } catch {
            XCTFail("Expected ProviderError, got \(error)")
        }

        XCTAssertEqual(mockRefreshService.refreshTokenCallCount, 0, "Should not refresh for network errors")
    }

    // MARK: - Heatmap Auto-Refresh Tests

    func testFetchHeatmap_AuthFailed_RefreshesAndRetries() async throws {
        let tokenStore = MockTokenStoreForRefresh()
        tokenStore.tokens["gitlab:user1"] = "expired_token"

        let mockAdapter = MockProviderAdapter(provider: .gitlab)
        mockAdapter.errorToThrow = ProviderError.authenticationFailed("HTTP 401")
        mockAdapter.failOnFirstCallOnly = true
        mockAdapter.heatmapToReturn = [
            HeatMapBucket(date: "2025-01-01", count: 5)
        ]

        let mockRefreshService = MockTokenRefreshService()
        mockRefreshService.canRefreshResult = true
        mockRefreshService.refreshTokenResult = "new_valid_token"

        let provider = ActivityRefreshProvider(
            tokenStore: tokenStore,
            adapters: [.gitlab: mockAdapter],
            refreshService: mockRefreshService
        )

        let account = Account(
            id: "gitlab:user1",
            provider: .gitlab,
            displayName: "GitLab User",
            authMethod: .oauth
        )

        let buckets = try await provider.fetchHeatmap(for: account)

        XCTAssertEqual(buckets.count, 1)
        XCTAssertEqual(mockAdapter.fetchHeatmapCallCount, 2, "Should retry after refresh")
        XCTAssertEqual(mockRefreshService.refreshTokenCallCount, 1, "Should refresh once")
    }

    // MARK: - Disabled Account Tests

    func testFetchActivities_DisabledAccount_ReturnsEmpty() async throws {
        let tokenStore = MockTokenStoreForRefresh()
        let mockAdapter = MockProviderAdapter(provider: .gitlab)
        let mockRefreshService = MockTokenRefreshService()

        let provider = ActivityRefreshProvider(
            tokenStore: tokenStore,
            adapters: [.gitlab: mockAdapter],
            refreshService: mockRefreshService
        )

        let account = Account(
            id: "gitlab:user1",
            provider: .gitlab,
            displayName: "GitLab User",
            authMethod: .oauth,
            isEnabled: false
        )

        let activities = try await provider.fetchActivities(for: account)

        XCTAssertTrue(activities.isEmpty)
        XCTAssertEqual(mockAdapter.fetchActivitiesCallCount, 0, "Should not fetch for disabled account")
    }
}

// MARK: - Integration Tests

final class TokenRefreshIntegrationTests: XCTestCase {

    func testFullRefreshFlow_GitLabOAuth() async throws {
        // This test verifies the integration between components
        // Note: Actual network calls are not made - we test the flow

        let tokenStore = MockTokenStoreForRefresh()
        tokenStore.tokens["gitlab:user1"] = "expired_token"

        let mockAdapter = MockProviderAdapter(provider: .gitlab)
        mockAdapter.errorToThrow = ProviderError.authenticationFailed("HTTP 401")
        mockAdapter.failOnFirstCallOnly = true
        mockAdapter.activitiesToReturn = [
            UnifiedActivity(
                id: "1",
                provider: .gitlab,
                accountId: "gitlab:user1",
                sourceId: "mr-1",
                type: .pullRequest,
                timestamp: Date(),
                title: "Fix bug",
                url: nil
            )
        ]

        let mockRefreshService = MockTokenRefreshService()
        mockRefreshService.canRefreshResult = true
        mockRefreshService.refreshTokenResult = "refreshed_token"

        let provider = ActivityRefreshProvider(
            tokenStore: tokenStore,
            adapters: [.gitlab: mockAdapter],
            refreshService: mockRefreshService
        )

        let account = Account(
            id: "gitlab:user1",
            provider: .gitlab,
            displayName: "Test User",
            authMethod: .oauth
        )

        // First call fails with 401, triggers refresh, retry succeeds
        let activities = try await provider.fetchActivities(for: account)

        // Verify the flow
        XCTAssertEqual(activities.count, 1)
        XCTAssertEqual(activities[0].title, "Fix bug")

        // Verify adapter was called twice (initial + retry)
        XCTAssertEqual(mockAdapter.fetchActivitiesCallCount, 2)

        // Verify refresh was triggered
        XCTAssertEqual(mockRefreshService.refreshTokenCallCount, 1)

        // Verify the new token was used on retry
        XCTAssertEqual(mockAdapter.lastToken, "refreshed_token")
    }

    func testNoInfiniteLoop_RetryOnlyOnce() async {
        let tokenStore = MockTokenStoreForRefresh()
        tokenStore.tokens["gitlab:user1"] = "expired_token"

        let mockAdapter = MockProviderAdapter(provider: .gitlab)
        // Both initial and retry will fail with auth error
        mockAdapter.errorToThrow = ProviderError.authenticationFailed("HTTP 401")
        mockAdapter.failOnFirstCallOnly = false

        let mockRefreshService = MockTokenRefreshService()
        mockRefreshService.canRefreshResult = true
        mockRefreshService.refreshTokenResult = "still_bad_token"

        let provider = ActivityRefreshProvider(
            tokenStore: tokenStore,
            adapters: [.gitlab: mockAdapter],
            refreshService: mockRefreshService
        )

        let account = Account(
            id: "gitlab:user1",
            provider: .gitlab,
            displayName: "Test User",
            authMethod: .oauth
        )

        do {
            _ = try await provider.fetchActivities(for: account)
            XCTFail("Should have thrown")
        } catch {
            // Expected to fail after one retry
        }

        // Should only call adapter twice (initial + one retry)
        XCTAssertEqual(mockAdapter.fetchActivitiesCallCount, 2)
        // Should only refresh once
        XCTAssertEqual(mockRefreshService.refreshTokenCallCount, 1)
    }
}
