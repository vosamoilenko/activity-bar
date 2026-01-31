import Foundation
import Core
import Storage

/// Protocol for token refresh operations, enabling testability
public protocol TokenRefreshing: Sendable {
    /// Check if an account supports automatic token refresh
    /// - Parameter account: The account to check
    /// - Returns: true if the account can have its token refreshed automatically
    func canRefresh(account: Account) -> Bool

    /// Refresh the OAuth token for an account
    /// - Parameters:
    ///   - account: The account to refresh the token for
    ///   - tokenStore: The token store for retrieving/storing tokens
    /// - Returns: The new access token
    /// - Throws: ProviderError on failure
    func refreshToken(for account: Account, using tokenStore: TokenStore) async throws -> String
}

/// Service that handles automatic OAuth token refresh for all providers
///
/// This actor provides centralized token refresh functionality with:
/// - Provider-specific refresh logic (GitLab, Google Calendar)
/// - Protection against concurrent refresh attempts for the same account
/// - Automatic token storage after refresh
///
/// Usage:
/// ```swift
/// let refreshService = TokenRefreshService()
/// if refreshService.canRefresh(account: account) {
///     let newToken = try await refreshService.refreshToken(for: account, using: tokenStore)
/// }
/// ```
public actor TokenRefreshService: TokenRefreshing {
    /// Tracks accounts currently being refreshed to prevent duplicate refresh attempts
    private var refreshingAccounts: Set<String> = []

    /// Continuations waiting for a refresh to complete (for deduplication)
    private var pendingRefreshes: [String: [CheckedContinuation<String, Error>]] = [:]

    public init() {}

    // MARK: - TokenRefreshing Protocol

    /// Check if an account supports automatic token refresh
    /// Only OAuth accounts (not PATs) for GitLab and Google Calendar can be refreshed
    nonisolated public func canRefresh(account: Account) -> Bool {
        // Only OAuth authentication method can be refreshed
        guard account.authMethod == .oauth else {
            return false
        }

        // Azure DevOps doesn't support OAuth token refresh (uses PATs)
        guard account.provider != .azureDevops else {
            return false
        }

        return true
    }

    /// Refresh the OAuth token for an account
    /// - Parameters:
    ///   - account: The account to refresh the token for
    ///   - tokenStore: The token store for retrieving/storing tokens
    /// - Returns: The new access token
    /// - Throws: ProviderError.authenticationFailed if refresh fails
    public func refreshToken(for account: Account, using tokenStore: TokenStore) async throws -> String {
        print("[ActivityBar][TokenRefresh] Attempting to refresh token for account: \(account.id)")

        // Check if this account is already being refreshed
        if refreshingAccounts.contains(account.id) {
            print("[ActivityBar][TokenRefresh] Refresh already in progress for \(account.id), waiting...")
            // Wait for the existing refresh to complete
            return try await withCheckedThrowingContinuation { continuation in
                if pendingRefreshes[account.id] == nil {
                    pendingRefreshes[account.id] = []
                }
                pendingRefreshes[account.id]?.append(continuation)
            }
        }

        // Mark as refreshing
        refreshingAccounts.insert(account.id)

        do {
            let newToken = try await performRefresh(for: account, using: tokenStore)

            // Resume any waiting continuations with the new token
            let waitingContinuations = pendingRefreshes.removeValue(forKey: account.id) ?? []
            for continuation in waitingContinuations {
                continuation.resume(returning: newToken)
            }

            refreshingAccounts.remove(account.id)
            return newToken
        } catch {
            // Resume any waiting continuations with the error
            let waitingContinuations = pendingRefreshes.removeValue(forKey: account.id) ?? []
            for continuation in waitingContinuations {
                continuation.resume(throwing: error)
            }

            refreshingAccounts.remove(account.id)
            throw error
        }
    }

    // MARK: - Private Implementation

    /// Perform the actual token refresh
    private func performRefresh(for account: Account, using tokenStore: TokenStore) async throws -> String {
        // Get the refresh token from storage
        let refreshKey = account.id + ":refresh"
        guard let refreshToken = try await tokenStore.getToken(for: refreshKey), !refreshToken.isEmpty else {
            print("[ActivityBar][TokenRefresh] No refresh token found for \(account.id)")
            throw ProviderError.authenticationFailed("No refresh token stored - please re-authenticate")
        }

        print("[ActivityBar][TokenRefresh] Found refresh token, attempting refresh for provider: \(account.provider)")

        // Perform provider-specific refresh
        let result: (accessToken: String, refreshToken: String?)

        switch account.provider {
        case .gitlab:
            result = try await refreshGitLabToken(refreshToken: refreshToken, host: account.host)
        case .googleCalendar:
            result = try await refreshGoogleToken(refreshToken: refreshToken)
        case .azureDevops:
            // Should not reach here due to canRefresh check, but handle defensively
            throw ProviderError.configurationError("Azure DevOps does not support token refresh")
        }

        // Store the new access token
        try await tokenStore.setToken(result.accessToken, for: account.id)
        print("[ActivityBar][TokenRefresh] Stored new access token for \(account.id)")

        // Store the new refresh token if provided
        if let newRefreshToken = result.refreshToken {
            try await tokenStore.setToken(newRefreshToken, for: refreshKey)
            print("[ActivityBar][TokenRefresh] Stored new refresh token for \(account.id)")
        }

        print("[ActivityBar][TokenRefresh] Token refresh completed successfully for \(account.id)")
        return result.accessToken
    }

    /// Refresh a GitLab OAuth token
    private func refreshGitLabToken(refreshToken: String, host: String?) async throws -> (accessToken: String, refreshToken: String?) {
        // Get OAuth credentials
        guard let credentials = await OAuthClientCredentials.shared.getCredentials(for: .gitlab) else {
            throw ProviderError.configurationError("No GitLab OAuth credentials configured")
        }

        // Build the token endpoint URL
        let baseURL = host.map { "https://\($0)" } ?? "https://gitlab.com"
        guard let url = URL(string: "\(baseURL)/oauth/token") else {
            throw ProviderError.configurationError("Invalid GitLab token endpoint URL")
        }

        // Build the refresh request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)",
            "client_id=\(credentials.clientId)",
            "client_secret=\(credentials.clientSecret)"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        print("[ActivityBar][TokenRefresh] Sending refresh request to \(url)")

        // Execute the request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Not an HTTP response")
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[ActivityBar][TokenRefresh] GitLab refresh failed: HTTP \(httpResponse.statusCode) - \(errorBody)")
            throw ProviderError.authenticationFailed("Token refresh failed: \(errorBody)")
        }

        // Parse the response
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
        }

        do {
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            return (tokenResponse.access_token, tokenResponse.refresh_token)
        } catch {
            throw ProviderError.decodingFailed("Failed to decode token response: \(error.localizedDescription)")
        }
    }

    /// Refresh a Google Calendar OAuth token
    private func refreshGoogleToken(refreshToken: String) async throws -> (accessToken: String, refreshToken: String?) {
        // Get OAuth credentials
        guard let credentials = await OAuthClientCredentials.shared.getCredentials(for: .googleCalendar) else {
            throw ProviderError.configurationError("No Google OAuth credentials configured")
        }

        guard let url = URL(string: "https://oauth2.googleapis.com/token") else {
            throw ProviderError.configurationError("Invalid Google token endpoint URL")
        }

        // Build the refresh request
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            "grant_type=refresh_token",
            "refresh_token=\(refreshToken)",
            "client_id=\(credentials.clientId)",
            "client_secret=\(credentials.clientSecret)"
        ].joined(separator: "&")
        request.httpBody = body.data(using: .utf8)

        print("[ActivityBar][TokenRefresh] Sending refresh request to Google")

        // Execute the request
        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ProviderError.invalidResponse("Not an HTTP response")
        }

        if httpResponse.statusCode != 200 {
            let errorBody = String(data: data, encoding: .utf8) ?? "Unknown error"
            print("[ActivityBar][TokenRefresh] Google refresh failed: HTTP \(httpResponse.statusCode) - \(errorBody)")
            throw ProviderError.authenticationFailed("Token refresh failed: \(errorBody)")
        }

        // Parse the response
        struct TokenResponse: Decodable {
            let access_token: String
            let refresh_token: String?
        }

        do {
            let tokenResponse = try JSONDecoder().decode(TokenResponse.self, from: data)
            // Google doesn't always return a new refresh token, so keep the existing one
            return (tokenResponse.access_token, tokenResponse.refresh_token ?? refreshToken)
        } catch {
            throw ProviderError.decodingFailed("Failed to decode token response: \(error.localizedDescription)")
        }
    }
}
