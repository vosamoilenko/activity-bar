import Core
import Foundation
import AuthenticationServices
#if os(macOS)
import AppKit
#endif

/// Providers module
/// Contains API adapters for fetching activity data from providers.
/// All provider logic follows contracts defined in activity-discovery.

// MARK: - Activity Logger

/// Centralized logger for ActivityBar with file output support
public final class ActivityLogger: @unchecked Sendable {
    public static let shared = ActivityLogger()

    private let logFileURL: URL
    private let queue = DispatchQueue(label: "com.activitybar.logger", qos: .utility)
    private let dateFormatter: DateFormatter

    private init() {
        // Try to write logs to the activity-discovery repo if available
        let fm = FileManager.default
        let homeDir = fm.homeDirectoryForCurrentUser

        // Check common developer paths for the activity-bar repo
        let possiblePaths = [
            homeDir.appendingPathComponent("Developer/activity-bar/activity-discovery/logs"),
            homeDir.appendingPathComponent("dev/activity-bar/activity-discovery/logs"),
            homeDir.appendingPathComponent("projects/activity-bar/activity-discovery/logs"),
            homeDir.appendingPathComponent("Library/Logs/ActivityBar")  // Fallback
        ]

        var logDir: URL = homeDir.appendingPathComponent("Library/Logs/ActivityBar")
        for path in possiblePaths {
            // Check if parent directory exists (activity-discovery)
            let parentDir = path.deletingLastPathComponent()
            if fm.fileExists(atPath: parentDir.path) {
                logDir = path
                break
            }
        }

        try? fm.createDirectory(at: logDir, withIntermediateDirectories: true)

        // New log file per app session with sortable timestamp: activity_YYYY-MM-DD_HH-MM-SS.log
        let df = DateFormatter()
        df.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let timestampStr = df.string(from: Date())
        logFileURL = logDir.appendingPathComponent("activity_\(timestampStr).log")

        // Time formatter for log entries
        dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "HH:mm:ss.SSS"

        // Log file location on startup
        print("[ActivityBar] Log file: \(logFileURL.path)")
    }

    /// Log a message with provider context
    public func log(_ provider: String, _ message: String) {
        let time = dateFormatter.string(from: Date())
        let entry = "[\(time)][\(provider)] \(message)"

        // Console output
        print(entry)

        // File output
        queue.async { [weak self] in
            guard let self = self else { return }
            let line = entry + "\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: self.logFileURL.path) {
                    if let handle = try? FileHandle(forWritingTo: self.logFileURL) {
                        handle.seekToEndOfFile()
                        handle.write(data)
                        try? handle.close()
                    }
                } else {
                    try? data.write(to: self.logFileURL)
                }
            }
        }
    }

    /// Log HTTP request/response in concise format
    public func logHTTP(_ provider: String, method: String, path: String, status: Int, bytes: Int) {
        let sizeStr = formatBytes(bytes)
        log(provider, "\(status) \(method) \(path) → \(sizeStr)")
    }

    /// Log HTTP error
    public func logHTTPError(_ provider: String, method: String, path: String, status: Int, error: String) {
        log(provider, "❌ \(status) \(method) \(path): \(error)")
    }

    /// Log fetch results summary
    public func logFetchSummary(_ provider: String, results: [(String, Int)]) {
        let parts = results.filter { $0.1 > 0 }.map { "\($0.1) \($0.0)" }
        if parts.isEmpty {
            log(provider, "Fetched: (none)")
        } else {
            log(provider, "Fetched: \(parts.joined(separator: ", "))")
        }
    }

    /// Get path to current log file
    public var currentLogFile: URL { logFileURL }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes)B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1fKB", Double(bytes) / 1024.0)
        } else {
            return String(format: "%.1fMB", Double(bytes) / (1024.0 * 1024.0))
        }
    }
}

// MARK: - Provider Errors

/// Errors that can occur during provider fetch operations
public enum ProviderError: Error, Sendable, Equatable {
    case networkError(String)
    case authenticationFailed(String)
    case rateLimited(retryAfter: Int?)
    case invalidResponse(String)
    case decodingFailed(String)
    case configurationError(String)
    case notImplemented

    public var localizedDescription: String {
        switch self {
        case .networkError(let message):
            return "Network error: \(message)"
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .rateLimited(let retryAfter):
            if let seconds = retryAfter {
                return "Rate limited. Retry after \(seconds) seconds"
            }
            return "Rate limited. Please try again later"
        case .invalidResponse(let message):
            return "Invalid response: \(message)"
        case .decodingFailed(let message):
            return "Failed to decode response: \(message)"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .notImplemented:
            return "This provider is not yet implemented"
        }
    }
}

// MARK: - Heatmap Generator

/// Utility for generating heatmap buckets from activities
public enum HeatmapGenerator {
    /// Generate heatmap buckets from activities
    public static func generateBuckets(from activities: [UnifiedActivity]) -> [HeatMapBucket] {
        var bucketsByDate: [String: (count: Int, breakdown: [Provider: Int])] = [:]

        for activity in activities {
            let dateString = DateFormatting.dateString(from: activity.timestamp)
            if bucketsByDate[dateString] == nil {
                bucketsByDate[dateString] = (count: 0, breakdown: [:])
            }
            bucketsByDate[dateString]!.count += 1
            bucketsByDate[dateString]!.breakdown[activity.provider, default: 0] += 1
        }

        return bucketsByDate.map { date, data in
            HeatMapBucket(date: date, count: data.count, breakdown: data.breakdown)
        }.sorted { $0.date < $1.date }
    }

    /// Merge multiple heatmap bucket arrays
    public static func mergeBuckets(_ bucketArrays: [[HeatMapBucket]]) -> [HeatMapBucket] {
        var merged: [String: (count: Int, breakdown: [Provider: Int])] = [:]

        for buckets in bucketArrays {
            for bucket in buckets {
                if merged[bucket.date] == nil {
                    merged[bucket.date] = (count: 0, breakdown: [:])
                }
                merged[bucket.date]!.count += bucket.count
                if let breakdown = bucket.breakdown {
                    for (provider, count) in breakdown {
                        merged[bucket.date]!.breakdown[provider, default: 0] += count
                    }
                }
            }
        }

        return merged.map { date, data in
            HeatMapBucket(date: date, count: data.count, breakdown: data.breakdown)
        }.sorted { $0.date < $1.date }
    }
}

// MARK: - Provider Adapter Protocol

/// Protocol for provider-specific activity fetching
/// Implementations mirror activity-discovery fetch patterns
public protocol ProviderAdapter: Sendable {
    /// The provider this adapter handles
    var provider: Provider { get }

    /// Fetch activities for an account within a time range
    /// - Parameters:
    ///   - account: The account to fetch activities for
    ///   - token: The authentication token
    ///   - from: Start of time range (inclusive)
    ///   - to: End of time range (inclusive)
    /// - Returns: Array of unified activities
    func fetchActivities(for account: Account, token: String, from: Date, to: Date) async throws -> [UnifiedActivity]

    /// Fetch heatmap data for an account within a time range
    /// - Parameters:
    ///   - account: The account to fetch heatmap for
    ///   - token: The authentication token
    ///   - from: Start of time range
    ///   - to: End of time range
    /// - Returns: Array of heatmap buckets (aggregated by day)
    func fetchHeatmap(for account: Account, token: String, from: Date, to: Date) async throws -> [HeatMapBucket]
}

// MARK: - Base HTTP Networking Layer

/// Base networking layer for provider API calls
/// Provides common HTTP functionality with rate limiting awareness
public actor HTTPClient {
    /// Shared instance for general use
    public static let shared = HTTPClient()

    private let session: URLSession
    private let decoder: JSONDecoder

    /// Rate limit state per domain
    private var rateLimitState: [String: RateLimitInfo] = [:]

    public init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
    }

    /// Execute an HTTP request with automatic error handling and rate limit tracking
    /// - Parameters:
    ///   - request: The URL request to execute
    ///   - providerName: Optional provider name for logging context
    /// - Returns: The response data
    public func executeRequest(_ request: URLRequest, providerName: String? = nil) async throws -> Data {
        let method = request.httpMethod ?? "GET"
        let path = request.url?.path ?? "/"
        let provider = providerName ?? detectProvider(from: request.url)

        // Check if we're rate limited for this domain
        if let host = request.url?.host {
            if let rateLimitInfo = rateLimitState[host], rateLimitInfo.isLimited {
                ActivityLogger.shared.log(provider, "⏳ Rate limited for \(host)")
                throw ProviderError.rateLimited(retryAfter: rateLimitInfo.retryAfterSeconds)
            }
        }

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            ActivityLogger.shared.logHTTPError(provider, method: method, path: path, status: 0, error: "Not HTTP response")
            throw ProviderError.invalidResponse("Not an HTTP response")
        }

        // Track rate limit headers
        if let host = request.url?.host {
            updateRateLimitState(from: httpResponse, for: host)
        }

        // Handle HTTP errors
        switch httpResponse.statusCode {
        case 200...299:
            ActivityLogger.shared.logHTTP(provider, method: method, path: path, status: httpResponse.statusCode, bytes: data.count)
            return data
        case 401, 403:
            let body = String(data: data, encoding: .utf8)?.prefix(100) ?? ""
            ActivityLogger.shared.logHTTPError(provider, method: method, path: path, status: httpResponse.statusCode, error: "Auth failed: \(body)")
            throw ProviderError.authenticationFailed("HTTP \(httpResponse.statusCode)")
        case 429:
            let retryAfter = httpResponse.value(forHTTPHeaderField: "Retry-After").flatMap(Int.init)
            ActivityLogger.shared.logHTTPError(provider, method: method, path: path, status: 429, error: "Rate limited, retry: \(retryAfter ?? -1)s")
            throw ProviderError.rateLimited(retryAfter: retryAfter)
        default:
            let body = String(data: data, encoding: .utf8)?.prefix(100) ?? "Unknown"
            ActivityLogger.shared.logHTTPError(provider, method: method, path: path, status: httpResponse.statusCode, error: String(body))
            throw ProviderError.networkError("HTTP \(httpResponse.statusCode): \(body)")
        }
    }

    /// Detect provider name from URL
    private func detectProvider(from url: URL?) -> String {
        guard let host = url?.host?.lowercased() else { return "HTTP" }
        if host.contains("dev.azure.com") || host.contains("visualstudio.com") {
            return "Azure"
        } else if host.contains("gitlab") {
            return "GitLab"
        } else if host.contains("github") {
            return "GitHub"
        } else if host.contains("googleapis.com") {
            return "Google"
        }
        return "HTTP"
    }

    /// Execute an HTTP request and decode the response as JSON
    /// - Parameters:
    ///   - request: The URL request to execute
    ///   - type: The type to decode to
    /// - Returns: The decoded response
    public func executeRequest<T: Decodable>(_ request: URLRequest, decoding type: T.Type) async throws -> T {
        let data = try await executeRequest(request)

        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ProviderError.decodingFailed(error.localizedDescription)
        }
    }

    /// Execute a GraphQL query
    /// - Parameters:
    ///   - endpoint: The GraphQL endpoint URL
    ///   - query: The GraphQL query string
    ///   - variables: Query variables
    ///   - token: Bearer token for authorization
    /// - Returns: The response data
    public func executeGraphQL(
        endpoint: URL,
        query: String,
        variables: [String: Any] = [:],
        token: String
    ) async throws -> Data {
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("ActivityBar/1.0", forHTTPHeaderField: "User-Agent")

        let body: [String: Any] = [
            "query": query,
            "variables": variables
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        return try await executeRequest(request)
    }

    /// Update rate limit state based on response headers
    private func updateRateLimitState(from response: HTTPURLResponse, for host: String) {
        // GitHub: X-RateLimit-Remaining, X-RateLimit-Reset
        // GitLab: RateLimit-Remaining, RateLimit-Reset
        let remaining = response.value(forHTTPHeaderField: "X-RateLimit-Remaining")
            ?? response.value(forHTTPHeaderField: "RateLimit-Remaining")
        let reset = response.value(forHTTPHeaderField: "X-RateLimit-Reset")
            ?? response.value(forHTTPHeaderField: "RateLimit-Reset")

        if let remainingStr = remaining, let remainingCount = Int(remainingStr),
           let resetStr = reset, let resetTime = TimeInterval(resetStr) {
            rateLimitState[host] = RateLimitInfo(
                remaining: remainingCount,
                resetTime: Date(timeIntervalSince1970: resetTime)
            )
        }
    }

    /// Clear rate limit state (useful for testing)
    public func clearRateLimitState() {
        rateLimitState.removeAll()
    }
}

/// Rate limit tracking information
private struct RateLimitInfo {
    let remaining: Int
    let resetTime: Date

    var isLimited: Bool {
        remaining <= 0 && Date() < resetTime
    }

    var retryAfterSeconds: Int? {
        guard isLimited else { return nil }
        return max(0, Int(resetTime.timeIntervalSinceNow))
    }
}

// MARK: - Pagination Helpers

/// Pagination state for cursor-based pagination (GitHub)
public struct CursorPagination: Sendable {
    public var cursor: String?
    public var hasNextPage: Bool

    public init(cursor: String? = nil, hasNextPage: Bool = true) {
        self.cursor = cursor
        self.hasNextPage = hasNextPage
    }

    public static let initial = CursorPagination(cursor: nil, hasNextPage: true)
}

/// Pagination state for page-based pagination (GitLab, Azure DevOps)
public struct PagePagination: Sendable {
    public var page: Int
    public var perPage: Int
    public var hasNextPage: Bool

    public init(page: Int = 1, perPage: Int = 100, hasNextPage: Bool = true) {
        self.page = page
        self.perPage = perPage
        self.hasNextPage = hasNextPage
    }

    public static let initial = PagePagination(page: 1, perPage: 100, hasNextPage: true)

    public mutating func nextPage() {
        page += 1
    }
}

// MARK: - Request Builder Helpers

/// Helper to build URL requests with common patterns
public struct RequestBuilder {
    /// Build a REST API request
    /// - Parameters:
    ///   - baseURL: The base URL for the API
    ///   - path: The API path
    ///   - queryItems: Query parameters
    ///   - token: The authentication token
    ///   - tokenHeader: The header name for the token (default: "Authorization")
    ///   - tokenPrefix: The prefix for the token value (default: "Bearer ")
    /// - Returns: A configured URLRequest
    public static func buildRequest(
        baseURL: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        token: String,
        tokenHeader: String = "Authorization",
        tokenPrefix: String = "Bearer "
    ) throws -> URLRequest {
        guard var components = URLComponents(string: baseURL) else {
            throw ProviderError.configurationError("Invalid base URL: \(baseURL)")
        }

        components.path = path
        if !queryItems.isEmpty {
            components.queryItems = queryItems
        }

        guard let url = components.url else {
            throw ProviderError.configurationError("Failed to build URL")
        }

        var request = URLRequest(url: url)
        request.setValue("\(tokenPrefix)\(token)", forHTTPHeaderField: tokenHeader)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("ActivityBar/1.0", forHTTPHeaderField: "User-Agent")

        return request
    }

    /// Build a GitLab API request
    /// - Uses PRIVATE-TOKEN header for Personal Access Tokens
    /// - Uses Authorization: Bearer header for OAuth tokens
    public static func buildGitLabRequest(
        baseURL: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        token: String,
        authMethod: AuthMethod = .pat
    ) throws -> URLRequest {
        let tokenHeader: String
        let tokenPrefix: String

        switch authMethod {
        case .oauth:
            tokenHeader = "Authorization"
            tokenPrefix = "Bearer "
        case .pat:
            tokenHeader = "PRIVATE-TOKEN"
            tokenPrefix = ""
        }

        return try buildRequest(
            baseURL: baseURL,
            path: "/api/v4\(path)",
            queryItems: queryItems,
            token: token,
            tokenHeader: tokenHeader,
            tokenPrefix: tokenPrefix
        )
    }

    /// Build an Azure DevOps API request (uses Basic auth)
    public static func buildAzureDevOpsRequest(
        organization: String,
        path: String,
        queryItems: [URLQueryItem] = [],
        token: String
    ) throws -> URLRequest {
        let baseURL = "https://dev.azure.com"
        // Prepend organization to path since buildRequest replaces the path component
        let fullPath = "/\(organization)\(path)"
        let basicAuth = Data(":\(token)".utf8).base64EncodedString()

        var request = try buildRequest(
            baseURL: baseURL,
            path: fullPath,
            queryItems: queryItems,
            token: basicAuth,
            tokenHeader: "Authorization",
            tokenPrefix: "Basic "
        )

        // Add API version (use 7.0-preview as some endpoints like /connectionData require it)
        var items = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false)?.queryItems } ?? []
        items.append(URLQueryItem(name: "api-version", value: "7.0-preview"))
        if var components = request.url.flatMap({ URLComponents(url: $0, resolvingAgainstBaseURL: false) }) {
            components.queryItems = items
            request.url = components.url
        }

        return request
    }
}

// MARK: - Date Formatting Helpers

/// Date formatting utilities for API requests and responses
public struct DateFormatting {
    /// ISO8601 formatter for API requests
    private static let iso8601FormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let iso8601FormatterWithoutFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    /// Simple date formatter for YYYY-MM-DD
    private static let dateOnlyFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(identifier: "UTC")
        return formatter
    }()

    /// Format date as ISO8601 string
    public static func iso8601String(from date: Date) -> String {
        iso8601FormatterWithoutFractional.string(from: date)
    }

    /// Format date as YYYY-MM-DD string (UTC)
    public static func dateString(from date: Date) -> String {
        dateOnlyFormatter.string(from: date)
    }

    /// Parse ISO8601 string to Date (handles both with and without fractional seconds)
    public static func parseISO8601(_ string: String) -> Date? {
        // Try without fractional first (more common from APIs like Google Calendar)
        if let date = iso8601FormatterWithoutFractional.date(from: string) {
            return date
        }
        // Fallback to with fractional seconds
        return iso8601FormatterWithFractional.date(from: string)
    }

    /// Parse date string (YYYY-MM-DD) to Date
    public static func parseDate(_ string: String) -> Date? {
        dateOnlyFormatter.date(from: string)
    }
}

// MARK: - OAuth Configuration

/// Configuration for OAuth providers
/// Scopes and endpoints match those validated in activity-discovery
public struct OAuthConfiguration: Sendable {
    /// GitLab OAuth configuration (cloud)
    /// Scopes: read_api, read_user (per activity-discovery)
    public static let gitlab = OAuthConfiguration(
        authorizationEndpoint: "https://gitlab.com/oauth/authorize",
        tokenEndpoint: "https://gitlab.com/oauth/token",
        userInfoEndpoint: "https://gitlab.com/api/v4/user",
        scopes: ["read_api", "read_user"],
        callbackScheme: "activitybar"
    )

    /// Google Calendar OAuth configuration
    /// Scope: calendar.readonly (per activity-discovery)
    public static let googleCalendar = OAuthConfiguration(
        authorizationEndpoint: "https://accounts.google.com/o/oauth2/v2/auth",
        tokenEndpoint: "https://oauth2.googleapis.com/token",
        userInfoEndpoint: "https://www.googleapis.com/oauth2/v2/userinfo",
        scopes: ["https://www.googleapis.com/auth/calendar.readonly", "https://www.googleapis.com/auth/userinfo.email", "https://www.googleapis.com/auth/userinfo.profile"],
        callbackScheme: "activitybar"
    )

    /// Azure DevOps OAuth configuration
    /// Uses Azure AD for OAuth - scopes are Azure DevOps specific
    public static let azureDevOps = OAuthConfiguration(
        authorizationEndpoint: "https://app.vssps.visualstudio.com/oauth2/authorize",
        tokenEndpoint: "https://app.vssps.visualstudio.com/oauth2/token",
        userInfoEndpoint: "https://dev.azure.com/_apis/profile/profiles/me?api-version=7.0-preview",
        scopes: ["vso.code", "vso.work"],
        callbackScheme: "activitybar"
    )

    public let authorizationEndpoint: String
    public let tokenEndpoint: String
    public let userInfoEndpoint: String
    public let scopes: [String]
    public let callbackScheme: String

    public init(
        authorizationEndpoint: String,
        tokenEndpoint: String,
        userInfoEndpoint: String,
        scopes: [String],
        callbackScheme: String
    ) {
        self.authorizationEndpoint = authorizationEndpoint
        self.tokenEndpoint = tokenEndpoint
        self.userInfoEndpoint = userInfoEndpoint
        self.scopes = scopes
        self.callbackScheme = callbackScheme
    }

    /// Creates a self-hosted GitLab configuration
    public static func gitlabSelfHosted(host: String) -> OAuthConfiguration {
        let baseURL = host.hasPrefix("https://") ? host : "https://\(host)"
        return OAuthConfiguration(
            authorizationEndpoint: "\(baseURL)/oauth/authorize",
            tokenEndpoint: "\(baseURL)/oauth/token",
            userInfoEndpoint: "\(baseURL)/api/v4/user",
            scopes: ["read_api", "read_user"],
            callbackScheme: "activitybar"
        )
    }
}

/// OAuth client credentials - loaded from environment or configuration
/// These must be set before OAuth flows can work
public actor OAuthClientCredentials {
    public static let shared = OAuthClientCredentials()

    private var credentials: [Provider: (clientId: String, clientSecret: String)] = [:]

    private init() {}

    /// Set credentials for a provider
    public func setCredentials(clientId: String, clientSecret: String, for provider: Provider) {
        credentials[provider] = (clientId, clientSecret)
    }

    /// Get credentials for a provider
    public func getCredentials(for provider: Provider) -> (clientId: String, clientSecret: String)? {
        credentials[provider]
    }

    /// Check if credentials are configured for a provider
    public func hasCredentials(for provider: Provider) -> Bool {
        credentials[provider] != nil
    }
}

// MARK: - OAuth Errors

/// Errors that can occur during OAuth flow
public enum OAuthError: Error, Sendable, Equatable {
    case userCancelled
    case authorizationFailed(String)
    case tokenExchangeFailed(String)
    case networkError(String)
    case invalidResponse
    case configurationError(String)
    case missingCredentials

    public var localizedDescription: String {
        switch self {
        case .userCancelled:
            return "Authentication was cancelled"
        case .authorizationFailed(let message):
            return "Authorization failed: \(message)"
        case .tokenExchangeFailed(let message):
            return "Token exchange failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .invalidResponse:
            return "Invalid response from server"
        case .configurationError(let message):
            return "Configuration error: \(message)"
        case .missingCredentials:
            return "OAuth credentials not configured. Please configure client ID and secret."
        }
    }
}

/// Result of a successful OAuth flow
public struct OAuthResult: Sendable {
    /// The provider this result is from
    public let provider: Provider
    /// The access token for API calls
    public let accessToken: String
    /// Optional refresh token for token renewal
    public let refreshToken: String?
    /// Account ID from the provider (e.g., username or user ID)
    public let accountId: String
    /// Display name for the account
    public let displayName: String
    /// Host for self-hosted instances (nil for cloud services)
    public let host: String?

    public init(
        provider: Provider,
        accessToken: String,
        refreshToken: String? = nil,
        accountId: String,
        displayName: String,
        host: String? = nil
    ) {
        self.provider = provider
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.accountId = accountId
        self.displayName = displayName
        self.host = host
    }
}

/// Login state for tracking OAuth flow progress
public enum LoginState: Sendable, Equatable {
    case idle
    case authenticating
    case exchangingToken
    case fetchingUserInfo
    case completed(accountId: String)
    case failed(String)

    public var isInProgress: Bool {
        switch self {
        case .authenticating, .exchangingToken, .fetchingUserInfo:
            return true
        default:
            return false
        }
    }
}

/// Protocol for OAuth coordinators that handle provider-specific authentication
/// Each provider implements this to handle its specific OAuth flow
public protocol OAuthCoordinator: Sendable {
    /// The provider this coordinator handles
    var provider: Provider { get }

    /// Initiates the OAuth flow for this provider
    /// - Parameter host: Optional host for self-hosted instances (e.g., "gitlab.company.com")
    /// - Returns: OAuthResult with token and account info
    /// - Throws: OAuthError if authentication fails
    func authenticate(host: String?) async throws -> OAuthResult
}

// MARK: - Localhost OAuth Server

/// A simple HTTP server that listens for OAuth callbacks on localhost
/// Used for OAuth providers that require http://127.0.0.1 redirect URIs for desktop apps
@MainActor
public final class LocalOAuthServer {
    private var serverSocket: Int32 = -1
    private var port: UInt16 = 0
    private let requestedPort: UInt16

    public var redirectURI: String {
        "http://127.0.0.1:\(port)/callback"
    }

    /// Initialize with optional fixed port (0 = random available port)
    public init(port: UInt16 = 0) {
        self.requestedPort = port
    }

    /// Starts the server on the configured port (or random if 0)
    public func start() throws {
        serverSocket = socket(AF_INET, SOCK_STREAM, 0)
        guard serverSocket >= 0 else {
            throw OAuthError.configurationError("Failed to create socket")
        }

        var reuse: Int32 = 1
        setsockopt(serverSocket, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        var addr = sockaddr_in()
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = requestedPort.bigEndian // Use requested port (0 = system chooses)
        addr.sin_addr.s_addr = inet_addr("127.0.0.1")

        let bindResult = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                bind(serverSocket, sockaddrPtr, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }

        guard bindResult == 0 else {
            close(serverSocket)
            throw OAuthError.configurationError("Failed to bind socket")
        }

        // Get the assigned port
        var assignedAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)
        withUnsafeMutablePointer(to: &assignedAddr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                getsockname(serverSocket, sockaddrPtr, &addrLen)
            }
        }
        port = UInt16(bigEndian: assignedAddr.sin_port)

        guard listen(serverSocket, 1) == 0 else {
            close(serverSocket)
            throw OAuthError.configurationError("Failed to listen on socket")
        }

        print("[LocalOAuthServer] Listening on port \(port)")
    }

    /// Waits for OAuth callback and returns the authorization code
    public func waitForCallback() async throws -> String {
        guard serverSocket >= 0 else {
            throw OAuthError.configurationError("Server not started")
        }

        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async { [self] in
                var clientAddr = sockaddr_in()
                var clientAddrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

                let clientSocket = withUnsafeMutablePointer(to: &clientAddr) { ptr in
                    ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPtr in
                        accept(self.serverSocket, sockaddrPtr, &clientAddrLen)
                    }
                }

                guard clientSocket >= 0 else {
                    continuation.resume(throwing: OAuthError.authorizationFailed("Failed to accept connection"))
                    return
                }

                defer { close(clientSocket) }

                // Read the HTTP request
                var buffer = [UInt8](repeating: 0, count: 4096)
                let bytesRead = read(clientSocket, &buffer, buffer.count)

                guard bytesRead > 0 else {
                    continuation.resume(throwing: OAuthError.authorizationFailed("Failed to read request"))
                    return
                }

                let requestString = String(bytes: buffer[0..<bytesRead], encoding: .utf8) ?? ""

                // Parse the request to extract the code
                // Request looks like: GET /callback?code=xxx&state=yyy HTTP/1.1
                guard let firstLine = requestString.components(separatedBy: "\r\n").first,
                      let pathPart = firstLine.components(separatedBy: " ").dropFirst().first,
                      let components = URLComponents(string: "http://localhost\(pathPart)"),
                      let queryItems = components.queryItems else {
                    self.sendResponse(to: clientSocket, success: false, message: "Invalid callback request")
                    continuation.resume(throwing: OAuthError.invalidResponse)
                    return
                }

                // Check for error
                if let error = queryItems.first(where: { $0.name == "error" })?.value {
                    let description = queryItems.first(where: { $0.name == "error_description" })?.value ?? error
                    self.sendResponse(to: clientSocket, success: false, message: description)
                    continuation.resume(throwing: OAuthError.authorizationFailed(description))
                    return
                }

                guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
                    self.sendResponse(to: clientSocket, success: false, message: "No authorization code received")
                    continuation.resume(throwing: OAuthError.invalidResponse)
                    return
                }

                self.sendResponse(to: clientSocket, success: true, message: "Authorization successful! You can close this window.")
                continuation.resume(returning: code)
            }
        }
    }

    private func sendResponse(to socket: Int32, success: Bool, message: String) {
        let html = """
        <!DOCTYPE html>
        <html>
        <head><title>ActivityBar - \(success ? "Success" : "Error")</title></head>
        <body style="font-family: -apple-system, sans-serif; display: flex; justify-content: center; align-items: center; height: 100vh; margin: 0; background: \(success ? "#f0fff0" : "#fff0f0");">
            <div style="text-align: center;">
                <h1>\(success ? "✓" : "✗")</h1>
                <p>\(message)</p>
                <p style="color: #666; font-size: 14px;">You can close this window.</p>
            </div>
        </body>
        </html>
        """
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/html\r\nContent-Length: \(html.utf8.count)\r\nConnection: close\r\n\r\n\(html)"
        _ = response.withCString { ptr in
            write(socket, ptr, strlen(ptr))
        }
    }

    /// Stops the server
    public func stop() {
        if serverSocket >= 0 {
            close(serverSocket)
            serverSocket = -1
            print("[LocalOAuthServer] Stopped")
        }
    }

    deinit {
        if serverSocket >= 0 {
            close(serverSocket)
        }
    }
}

// MARK: - Base OAuth Coordinator

/// Base class providing common OAuth functionality using ASWebAuthenticationSession
@MainActor
public class BaseOAuthCoordinator {
    /// Performs the OAuth authorization flow using ASWebAuthenticationSession
    /// - Parameters:
    ///   - authURL: The authorization URL to open
    ///   - callbackScheme: The URL scheme to listen for callback
    /// - Returns: The callback URL containing the authorization code
    func performAuthorizationFlow(authURL: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: authURL,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError {
                    if error.code == .canceledLogin {
                        continuation.resume(throwing: OAuthError.userCancelled)
                    } else {
                        continuation.resume(throwing: OAuthError.authorizationFailed(error.localizedDescription))
                    }
                } else if let error = error {
                    continuation.resume(throwing: OAuthError.authorizationFailed(error.localizedDescription))
                } else if let callbackURL = callbackURL {
                    continuation.resume(returning: callbackURL)
                } else {
                    continuation.resume(throwing: OAuthError.invalidResponse)
                }
            }

            session.prefersEphemeralWebBrowserSession = false
            session.presentationContextProvider = WebAuthContextProvider.shared

            if !session.start() {
                continuation.resume(throwing: OAuthError.authorizationFailed("Failed to start authentication session"))
            }
        }
    }

    /// Extracts authorization code from callback URL
    func extractAuthorizationCode(from callbackURL: URL) throws -> String {
        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let queryItems = components.queryItems else {
            throw OAuthError.invalidResponse
        }

        // Check for error in callback
        if let error = queryItems.first(where: { $0.name == "error" })?.value {
            let description = queryItems.first(where: { $0.name == "error_description" })?.value ?? error
            throw OAuthError.authorizationFailed(description)
        }

        guard let code = queryItems.first(where: { $0.name == "code" })?.value else {
            throw OAuthError.invalidResponse
        }

        return code
    }

    /// Exchanges authorization code for tokens
    func exchangeCodeForToken(
        code: String,
        tokenEndpoint: String,
        clientId: String,
        clientSecret: String,
        redirectURI: String,
        additionalParams: [String: String] = [:]
    ) async throws -> (accessToken: String, refreshToken: String?) {
        guard let tokenURL = URL(string: tokenEndpoint) else {
            throw OAuthError.configurationError("Invalid token endpoint URL")
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        var bodyParams = [
            "grant_type": "authorization_code",
            "code": code,
            "client_id": clientId,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI
        ]

        for (key, value) in additionalParams {
            bodyParams[key] = value
        }

        let bodyString = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw OAuthError.invalidResponse
        }

        guard httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OAuthError.tokenExchangeFailed("HTTP \(httpResponse.statusCode): \(body)")
        }

        // Parse response - handle both JSON and form-encoded responses
        if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            guard let accessToken = json["access_token"] as? String else {
                throw OAuthError.tokenExchangeFailed("No access token in response")
            }
            let refreshToken = json["refresh_token"] as? String
            return (accessToken, refreshToken)
        } else if let bodyString = String(data: data, encoding: .utf8) {
            // GitHub returns form-encoded response by default
            let params = Dictionary(uniqueKeysWithValues: bodyString.split(separator: "&").compactMap { part -> (String, String)? in
                let pair = part.split(separator: "=", maxSplits: 1)
                guard pair.count == 2 else { return nil }
                return (String(pair[0]), String(pair[1]).removingPercentEncoding ?? String(pair[1]))
            })

            guard let accessToken = params["access_token"] else {
                throw OAuthError.tokenExchangeFailed("No access token in response")
            }
            let refreshToken = params["refresh_token"]
            return (accessToken, refreshToken)
        }

        throw OAuthError.invalidResponse
    }
}

/// Provides presentation context for ASWebAuthenticationSession
@MainActor
private class WebAuthContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    static let shared = WebAuthContextProvider()

    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        // Return the key window or create one if needed
        if let window = NSApplication.shared.keyWindow {
            return window
        }
        // Fallback to first window
        return NSApplication.shared.windows.first ?? NSWindow()
    }
}

// MARK: - GitLab OAuth Coordinator

/// GitLab OAuth coordinator supporting both cloud and self-hosted instances
/// Scopes: read_api, read_user (per activity-discovery)
public final class GitLabOAuthCoordinator: BaseOAuthCoordinator, OAuthCoordinator, @unchecked Sendable {
    public let provider = Provider.gitlab

    public override init() {
        super.init()
    }

    public func authenticate(host: String?) async throws -> OAuthResult {
        // Get client credentials
        guard let credentials = await OAuthClientCredentials.shared.getCredentials(for: .gitlab) else {
            throw OAuthError.missingCredentials
        }

        let clientId = credentials.clientId
        let clientSecret = credentials.clientSecret

        // Use self-hosted config if host provided, otherwise cloud
        let config = host != nil ? OAuthConfiguration.gitlabSelfHosted(host: host!) : OAuthConfiguration.gitlab

        // Use localhost OAuth server with FIXED port (GitLab requires exact URL match)
        // User must set GitLab callback URL to: http://127.0.0.1:8765/callback
        let server = LocalOAuthServer(port: 8765)
        try server.start()
        let redirectURI = server.redirectURI

        defer { server.stop() }

        // Build authorization URL
        var authComponents = URLComponents(string: config.authorizationEndpoint)!
        authComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: UUID().uuidString)
        ]

        guard let authURL = authComponents.url else {
            throw OAuthError.configurationError("Failed to build authorization URL")
        }

        // Debug: Print the exact authorization URL
        print("[ActivityBar][GitLab] ========================================")
        print("[ActivityBar][GitLab] Authorization URL: \(authURL.absoluteString)")
        print("[ActivityBar][GitLab] Redirect URI: \(redirectURI)")
        print("[ActivityBar][GitLab] REQUIRED GitLab Callback URL: http://127.0.0.1:8765/callback")
        print("[ActivityBar][GitLab] Client ID: \(clientId.prefix(12))...")
        print("[ActivityBar][GitLab] ========================================")

        // Open authorization URL in default browser
        NSWorkspace.shared.open(authURL)

        // Wait for callback on localhost server
        let code = try await server.waitForCallback()

        // Exchange code for token
        let (accessToken, refreshToken) = try await exchangeCodeForToken(
            code: code,
            tokenEndpoint: config.tokenEndpoint,
            clientId: clientId,
            clientSecret: clientSecret,
            redirectURI: redirectURI
        )

        // Fetch user info
        let userInfo = try await fetchGitLabUserInfo(accessToken: accessToken, userInfoEndpoint: config.userInfoEndpoint)

        return OAuthResult(
            provider: .gitlab,
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountId: userInfo.username,
            displayName: userInfo.displayName,
            host: host
        )
    }

    private func fetchGitLabUserInfo(accessToken: String, userInfoEndpoint: String) async throws -> (username: String, displayName: String) {
        guard let url = URL(string: userInfoEndpoint) else {
            throw OAuthError.configurationError("Invalid user info endpoint")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OAuthError.authorizationFailed("Failed to fetch user info")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let username = json["username"] as? String else {
            throw OAuthError.invalidResponse
        }

        let displayName = json["name"] as? String ?? username
        return (username, displayName)
    }
}

// MARK: - Azure DevOps OAuth Coordinator

/// Azure DevOps OAuth coordinator
/// Uses Azure DevOps OAuth flow with vso.code and vso.work scopes
public final class AzureDevOpsOAuthCoordinator: BaseOAuthCoordinator, OAuthCoordinator, @unchecked Sendable {
    public let provider = Provider.azureDevops
    private let config = OAuthConfiguration.azureDevOps

    public override init() {
        super.init()
    }

    public func authenticate(host: String?) async throws -> OAuthResult {
        // Get client credentials
        guard let credentials = await OAuthClientCredentials.shared.getCredentials(for: .azureDevops) else {
            throw OAuthError.missingCredentials
        }

        let clientId = credentials.clientId
        let clientSecret = credentials.clientSecret
        let redirectURI = "\(config.callbackScheme)://oauth/callback"

        // Build authorization URL
        var authComponents = URLComponents(string: config.authorizationEndpoint)!
        authComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "Assertion"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "state", value: UUID().uuidString)
        ]

        guard let authURL = authComponents.url else {
            throw OAuthError.configurationError("Failed to build authorization URL")
        }

        // Perform authorization flow
        let callbackURL = try await performAuthorizationFlow(authURL: authURL, callbackScheme: config.callbackScheme)
        let code = try extractAuthorizationCode(from: callbackURL)

        // Exchange code for token - Azure DevOps uses different params
        let (accessToken, refreshToken) = try await exchangeAzureDevOpsToken(
            code: code,
            clientId: clientId,
            clientSecret: clientSecret,
            redirectURI: redirectURI
        )

        // Fetch user info
        let userInfo = try await fetchAzureDevOpsUserInfo(accessToken: accessToken)

        return OAuthResult(
            provider: .azureDevops,
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountId: userInfo.id,
            displayName: userInfo.displayName,
            host: nil
        )
    }

    private func exchangeAzureDevOpsToken(
        code: String,
        clientId: String,
        clientSecret: String,
        redirectURI: String
    ) async throws -> (accessToken: String, refreshToken: String?) {
        guard let tokenURL = URL(string: config.tokenEndpoint) else {
            throw OAuthError.configurationError("Invalid token endpoint URL")
        }

        var request = URLRequest(url: tokenURL)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let bodyParams = [
            "client_assertion_type": "urn:ietf:params:oauth:client-assertion-type:jwt-bearer",
            "client_assertion": clientSecret,
            "grant_type": "urn:ietf:params:oauth:grant-type:jwt-bearer",
            "assertion": code,
            "redirect_uri": redirectURI
        ]

        let bodyString = bodyParams
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
        request.httpBody = bodyString.data(using: .utf8)

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            let body = String(data: data, encoding: .utf8) ?? "Unknown error"
            throw OAuthError.tokenExchangeFailed("HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0): \(body)")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let accessToken = json["access_token"] as? String else {
            throw OAuthError.tokenExchangeFailed("No access token in response")
        }

        let refreshToken = json["refresh_token"] as? String
        return (accessToken, refreshToken)
    }

    private func fetchAzureDevOpsUserInfo(accessToken: String) async throws -> (id: String, displayName: String) {
        guard let url = URL(string: "https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=7.0-preview") else {
            throw OAuthError.configurationError("Invalid user info endpoint")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OAuthError.authorizationFailed("Failed to fetch user info")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let id = json["id"] as? String else {
            throw OAuthError.invalidResponse
        }

        let displayName = json["displayName"] as? String ?? id
        return (id, displayName)
    }
}

// MARK: - Google Calendar OAuth Coordinator

/// Google Calendar OAuth coordinator
/// Uses localhost redirect for Desktop OAuth client type
/// Scope: calendar.readonly (per activity-discovery)
public final class GoogleCalendarOAuthCoordinator: BaseOAuthCoordinator, OAuthCoordinator, @unchecked Sendable {
    public let provider = Provider.googleCalendar
    private let config = OAuthConfiguration.googleCalendar

    public override init() {
        super.init()
    }

    public func authenticate(host: String?) async throws -> OAuthResult {
        // Get client credentials
        guard let credentials = await OAuthClientCredentials.shared.getCredentials(for: .googleCalendar) else {
            throw OAuthError.missingCredentials
        }

        let clientId = credentials.clientId
        let clientSecret = credentials.clientSecret

        // Start local OAuth server for callback
        let server = LocalOAuthServer()
        try server.start()
        let redirectURI = server.redirectURI

        defer { server.stop() }

        // Build authorization URL
        var authComponents = URLComponents(string: config.authorizationEndpoint)!
        authComponents.queryItems = [
            URLQueryItem(name: "client_id", value: clientId),
            URLQueryItem(name: "redirect_uri", value: redirectURI),
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "scope", value: config.scopes.joined(separator: " ")),
            URLQueryItem(name: "access_type", value: "offline"),
            URLQueryItem(name: "prompt", value: "consent"),
            URLQueryItem(name: "state", value: UUID().uuidString)
        ]

        guard let authURL = authComponents.url else {
            throw OAuthError.configurationError("Failed to build authorization URL")
        }

        // Open authorization URL in default browser
        NSWorkspace.shared.open(authURL)

        // Wait for callback on localhost server
        let code = try await server.waitForCallback()

        // Exchange code for token
        let (accessToken, refreshToken) = try await exchangeCodeForToken(
            code: code,
            tokenEndpoint: config.tokenEndpoint,
            clientId: clientId,
            clientSecret: clientSecret,
            redirectURI: redirectURI
        )

        // Fetch user info
        let userInfo = try await fetchGoogleUserInfo(accessToken: accessToken)

        return OAuthResult(
            provider: .googleCalendar,
            accessToken: accessToken,
            refreshToken: refreshToken,
            accountId: userInfo.email,
            displayName: userInfo.displayName,
            host: nil
        )
    }

    private func fetchGoogleUserInfo(accessToken: String) async throws -> (email: String, displayName: String) {
        guard let url = URL(string: config.userInfoEndpoint) else {
            throw OAuthError.configurationError("Invalid user info endpoint")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw OAuthError.authorizationFailed("Failed to fetch user info")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let email = json["email"] as? String else {
            throw OAuthError.invalidResponse
        }

        let displayName = json["name"] as? String ?? email
        return (email, displayName)
    }
}

// MARK: - OAuth Coordinator Factory

/// Factory for creating OAuth coordinators per provider
public enum OAuthCoordinatorFactory {
    /// Creates an OAuth coordinator for the specified provider
    /// - Parameter provider: The provider to create a coordinator for
    /// - Returns: An OAuthCoordinator instance for the provider
    @MainActor
    public static func coordinator(for provider: Provider) -> OAuthCoordinator {
        switch provider {
        case .gitlab:
            return GitLabOAuthCoordinator()
        case .azureDevops:
            return AzureDevOpsOAuthCoordinator()
        case .googleCalendar:
            return GoogleCalendarOAuthCoordinator()
        }
    }
}
