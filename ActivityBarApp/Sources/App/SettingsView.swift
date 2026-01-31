import SwiftUI
import Core
import Providers
import Storage

/// Settings/Preferences window view
struct SettingsView: View {
    let appState: AppState
    let tokenStore: TokenStore
    let launchAtLoginManager: LaunchAtLoginManager
    var refreshScheduler: RefreshScheduler?
    var preferencesManager: PreferencesManager?
    var onPanelAppearanceChanged: (() -> Void)?

    var body: some View {
        TabView {
            AccountsSettingsView(appState: appState, tokenStore: tokenStore, refreshScheduler: refreshScheduler)
                .tabItem {
                    Label("Accounts", systemImage: "person.2")
                }

            GeneralSettingsView(
                launchAtLoginManager: launchAtLoginManager,
                refreshScheduler: refreshScheduler,
                preferencesManager: preferencesManager,
                onPanelAppearanceChanged: onPanelAppearanceChanged
            )
            .tabItem {
                Label("General", systemImage: "gear")
            }
        }
        .frame(minWidth: 600, idealWidth: 700, maxWidth: .infinity, minHeight: 480, idealHeight: 560, maxHeight: .infinity)
        .onAppear {
            print("[ActivityBar] SettingsView appeared (window should now be visible)")
        }
    }
}

/// Accounts settings tab - manages account login/logout/enable/disable
struct AccountsSettingsView: View {
    let appState: AppState
    let tokenStore: TokenStore
    var refreshScheduler: RefreshScheduler?

    /// Computed session reference
    private var session: Session { appState.session }

    /// Show add account sheet
    @State private var showingAddAccountSheet = false

    /// Login state for OAuth flow
    @State private var loginState: LoginState = .idle

    /// Error message from last failed operation
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Connected Accounts")
                .font(.headline)

            // Accounts list from AppState
            if session.accounts.isEmpty {
                List {
                    Text("No accounts configured")
                        .foregroundStyle(.secondary)
                }
                .listStyle(.inset)
            } else {
                List {
                    ForEach(session.accounts) { account in
                        AccountRowView(
                            account: account,
                            appState: appState,
                            tokenStore: tokenStore,
                            onRemove: { removeAccount(account) }
                        )
                    }
                }
                .listStyle(.inset)
            }

            // Error banner
            if let error = errorMessage {
                ErrorBannerView(message: error, onDismiss: { errorMessage = nil })
            }

            HStack {
                // Summary text
                Text("\(session.enabledAccounts.count) of \(session.accounts.count) accounts enabled")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Add Account...") {
                    showingAddAccountSheet = true
                }
                .disabled(loginState.isInProgress)
            }
        }
        .padding()
        .sheet(isPresented: $showingAddAccountSheet) {
            AddAccountSheet(
                appState: appState,
                tokenStore: tokenStore,
                loginState: $loginState,
                onComplete: { result, config in
                    handleOAuthResult(result, config: config)
                },
                onError: { error in
                    errorMessage = error.localizedDescription
                }
            )
        }
    }

    /// Handle successful OAuth result
    private func handleOAuthResult(_ result: OAuthResult, config: ProviderSpecificConfig?) {
        print("[ActivityBar][Settings] handleOAuthResult called")
        print("[ActivityBar][Settings]   provider: \(result.provider)")
        print("[ActivityBar][Settings]   accountId: \(result.accountId)")
        print("[ActivityBar][Settings]   displayName: \(result.displayName)")
        print("[ActivityBar][Settings]   host: \(result.host ?? "nil")")
        print("[ActivityBar][Settings]   token length: \(result.accessToken.count) chars")

        // Generate account ID using token key format (handles cloud vs self-hosted automatically)
        let accountId = TokenKeyGenerator.key(
            provider: result.provider,
            host: result.host,
            accountId: result.accountId
        )
        print("[ActivityBar][Settings] Generated accountId key: \(accountId)")
        if let host = result.host {
            print("[ActivityBar][Settings]   Normalized host: \(TokenKeyGenerator.normalizeHost(host))")
        }

        // Store token in keychain - using @MainActor Task to ensure proper sequencing
        Task { @MainActor in
            do {
                print("[ActivityBar][Settings] Storing token in keychain...")
                print("[ActivityBar][Settings]   accountId for storage: '\(accountId)'")
                print("[ActivityBar][Settings]   token first 20 chars: '\(String(result.accessToken.prefix(20)))...'")
                try await tokenStore.setToken(result.accessToken, for: accountId)
                print("[ActivityBar][Settings] Token stored successfully")

                // Verify token was actually stored
                if let storedToken = try await tokenStore.getToken(for: accountId) {
                    print("[ActivityBar][Settings] VERIFIED: Token retrieved from keychain, length: \(storedToken.count)")
                } else {
                    print("[ActivityBar][Settings] ERROR: Token NOT found after storing!")
                }

                // Store refresh token if available (for token renewal)
                if let refreshToken = result.refreshToken {
                    let refreshKey = accountId + ":refresh"
                    try await tokenStore.setToken(refreshToken, for: refreshKey)
                    print("[ActivityBar][Settings] Refresh token stored")
                }

                // Create and add account (normalize host for consistency)
                let normalizedHost = result.host.map { TokenKeyGenerator.normalizeHost($0) }
                // For Azure DevOps, use displayName for username matching since activities contain display names
                let usernameForMatching = result.provider == .azureDevops ? result.displayName : result.accountId
                let account = Account(
                    id: accountId,
                    provider: result.provider,
                    displayName: result.displayName,
                    host: normalizedHost,
                    organization: config?.organization,
                    projects: config?.projects,
                    calendarIds: config?.calendarIds,
                    authMethod: .oauth,
                    isEnabled: true,
                    username: usernameForMatching
                )
                print("[ActivityBar][Settings] Adding account to appState...")
                print("[ActivityBar][Settings]   account.id: \(account.id)")
                print("[ActivityBar][Settings]   account.provider: \(account.provider)")
                print("[ActivityBar][Settings]   account.isEnabled: \(account.isEnabled)")
                appState.addAccount(account)
                print("[ActivityBar][Settings] Account added. Total accounts: \(appState.session.accounts.count)")

                loginState = .completed(accountId: accountId)
                print("[ActivityBar][Settings] Login completed successfully")

                // Trigger a refresh to fetch data for the new account (use forceRefresh to bypass debounce)
                if let scheduler = refreshScheduler {
                    print("[ActivityBar][Settings] Force triggering refresh for new account...")
                    scheduler.forceRefresh()
                } else {
                    print("[ActivityBar][Settings] WARNING: refreshScheduler is nil, cannot trigger refresh!")
                }
            } catch {
                print("[ActivityBar][Settings] ERROR storing token: \(error)")
                errorMessage = "Failed to save token: \(error.localizedDescription)"
                loginState = .failed(error.localizedDescription)
            }
        }
    }

    /// Remove account (logout) - deletes token and cached data
    private func removeAccount(_ account: Account) {
        Task { @MainActor in
            // Remove account from AppState first (updates UI immediately)
            appState.removeAccount(id: account.id)

            // Clean up tokens (best effort - don't block UI on this)
            do {
                try await tokenStore.deleteToken(for: account.id)
                // Also delete refresh token if present
                try await tokenStore.deleteToken(for: account.id + ":refresh")
            } catch {
                // Log but don't show error - account is already removed from UI
                print("[ActivityBar] Warning: Failed to delete token for \(account.id): \(error.localizedDescription)")
            }

            // Clear all cached data for this account
            if let appDelegate = NSApplication.shared.delegate as? AppDelegate {
                await appDelegate.clearCacheForAccount(account.id)
            }
        }
    }
}

/// Row view for a single account in settings
struct AccountRowView: View {
    let account: Account
    let appState: AppState
    let tokenStore: TokenStore
    let onRemove: () -> Void

    /// Show confirmation dialog for removal
    @State private var showingRemoveConfirmation = false

    /// Show event types configuration sheet
    @State private var showingEventTypesSheet = false

    /// Show projects/calendars configuration sheet
    @State private var showingProjectsSheet = false

    /// Token validation state
    @State private var isValidating = false
    @State private var validationResult: TokenValidationResult?

    /// Token refresh state
    @State private var isRefreshing = false

    enum TokenValidationResult {
        case valid
        case expired(String)
        case error(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                // Provider icon indicator
                Circle()
                    .fill(providerColor)
                    .frame(width: 10, height: 10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(account.displayName)
                        .font(.body)

                    HStack(spacing: 4) {
                        Text(providerDisplayName)
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        if let host = account.host {
                            Text("• \(host)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }

                Spacer()

                // Enable/disable toggle
                Toggle("", isOn: Binding(
                    get: { account.isEnabled },
                    set: { _ in appState.toggleAccount(id: account.id) }
                ))
                .toggleStyle(.switch)
                .labelsHidden()

                // "My Events Only" toggle (for GitLab and Azure DevOps)
                if account.provider == .gitlab || account.provider == .azureDevops {
                    Button {
                        appState.toggleShowOnlyMyEvents(for: account.id)
                    } label: {
                        Image(systemName: account.showOnlyMyEvents ? "person.fill" : "person.2")
                            .foregroundStyle(account.showOnlyMyEvents ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(account.showOnlyMyEvents ? "Showing only my events" : "Showing all events")
                }

                // Calendars configuration button (Google Calendar only)
                if account.provider == .googleCalendar {
                    Button {
                        showingProjectsSheet = true
                    } label: {
                        HStack(spacing: 2) {
                            Image(systemName: hasCalendarFiltering ? "calendar.circle.fill" : "calendar.circle")
                                .foregroundStyle(hasCalendarFiltering ? .blue : .secondary)
                            if hasCalendarFiltering {
                                Text("\(enabledCalendarsCount)")
                                    .font(.caption2)
                                    .foregroundStyle(.blue)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                    .help(hasCalendarFiltering ? "\(enabledCalendarsCount) calendars selected" : "Configure calendars")

                    // Show Only Accepted Events toggle
                    Button {
                        appState.toggleShowOnlyAcceptedEvents(for: account.id)
                    } label: {
                        Image(systemName: account.showOnlyAcceptedEvents ? "checkmark.circle.fill" : "checkmark.circle")
                            .foregroundStyle(account.showOnlyAcceptedEvents ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(account.showOnlyAcceptedEvents ? "Showing only accepted events" : "Showing all events")

                    // Hide All-Day Events toggle
                    Button {
                        appState.toggleHideAllDayEvents(for: account.id)
                    } label: {
                        Image(systemName: account.hideAllDayEvents ? "calendar.badge.minus" : "calendar.badge.clock")
                            .foregroundStyle(account.hideAllDayEvents ? .blue : .secondary)
                    }
                    .buttonStyle(.plain)
                    .help(account.hideAllDayEvents ? "All-day events hidden" : "Showing all-day events")
                }

                // Event types configuration button
                Button {
                    showingEventTypesSheet = true
                } label: {
                    HStack(spacing: 2) {
                        Image(systemName: hasEventTypeFiltering ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                            .foregroundStyle(hasEventTypeFiltering ? .blue : .secondary)
                        if hasEventTypeFiltering {
                            Text("\(filteredEventTypesCount)")
                                .font(.caption2)
                                .foregroundStyle(.blue)
                        }
                    }
                }
                .buttonStyle(.plain)
                .help(hasEventTypeFiltering ? "Event filtering active (\(filteredEventTypesCount) hidden)" : "Configure event types")

                // Remove/logout button
                Button {
                    showingRemoveConfirmation = true
                } label: {
                    Image(systemName: "trash")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .help("Remove account")
                .confirmationDialog(
                    "Remove \(account.displayName)?",
                    isPresented: $showingRemoveConfirmation,
                    titleVisibility: .visible
                ) {
                    Button("Remove", role: .destructive) {
                        onRemove()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This will sign out and remove all cached data for this account. You can add it back later.")
                }
                .sheet(isPresented: $showingEventTypesSheet) {
                    AccountEventTypesSheet(account: account, appState: appState)
                }
                .sheet(isPresented: $showingProjectsSheet) {
                    AccountProjectsSheet(account: account, appState: appState, tokenStore: tokenStore)
                }
            }

            // Token management buttons
            HStack(spacing: 8) {
                Button {
                    validateToken()
                } label: {
                    HStack(spacing: 4) {
                        if isValidating {
                            ProgressView().scaleEffect(0.5)
                        } else {
                            Image(systemName: "checkmark.shield")
                        }
                        Text("Validate")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isValidating || isRefreshing)

                Button {
                    refreshToken()
                } label: {
                    HStack(spacing: 4) {
                        if isRefreshing {
                            ProgressView().scaleEffect(0.5)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                        Text("Refresh Token")
                    }
                    .font(.caption)
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(isValidating || isRefreshing)

                Spacer()

                // Validation result indicator
                if let result = validationResult {
                    validationResultView(result)
                }
            }
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }

    @ViewBuilder
    private func validationResultView(_ result: TokenValidationResult) -> some View {
        switch result {
        case .valid:
            HStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Valid")
                    .foregroundStyle(.green)
            }
            .font(.caption)
        case .expired(let message):
            CopyableErrorText(message: message, icon: "exclamationmark.triangle.fill", color: .orange)
        case .error(let message):
            CopyableErrorText(message: message, icon: "xmark.circle.fill", color: .red)
        }
    }

    private func validateToken() {
        isValidating = true
        validationResult = nil

        Task {
            do {
                guard let token = try await tokenStore.getToken(for: account.id) else {
                    await MainActor.run {
                        validationResult = .error("No token found")
                        isValidating = false
                    }
                    return
                }

                let result = try await validateTokenWithProvider(token: token)
                await MainActor.run {
                    validationResult = result
                    isValidating = false
                }
            } catch {
                await MainActor.run {
                    validationResult = .error(error.localizedDescription)
                    isValidating = false
                }
            }
        }
    }

    private func validateTokenWithProvider(token: String) async throws -> TokenValidationResult {
        switch account.provider {
        case .gitlab:
            let baseURL = account.host.map { "https://\($0)" } ?? "https://gitlab.com"
            let url = URL(string: "\(baseURL)/api/v4/user")!
            var request = URLRequest(url: url)
            request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")
            // Also try Bearer token for OAuth tokens
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .error("Invalid response")
            }

            if http.statusCode == 401 {
                // Try to get more details from response
                if let body = String(data: data, encoding: .utf8),
                   body.contains("expired") {
                    return .expired("Token expired")
                }
                return .expired("Token invalid (401)")
            }

            if (200...299).contains(http.statusCode) {
                return .valid
            }

            return .error("HTTP \(http.statusCode)")

        case .azureDevops:
            guard let org = account.organization else {
                return .error("No organization configured")
            }
            let url = URL(string: "https://dev.azure.com/\(org)/_apis/connectionData?api-version=7.0-preview")!
            var request = URLRequest(url: url)
            let credentials = ":\(token)"
            if let credData = credentials.data(using: .utf8) {
                request.setValue("Basic \(credData.base64EncodedString())", forHTTPHeaderField: "Authorization")
            }

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .error("Invalid response")
            }

            if http.statusCode == 401 || http.statusCode == 203 {
                return .expired("Token invalid")
            }

            if (200...299).contains(http.statusCode) {
                return .valid
            }

            return .error("HTTP \(http.statusCode)")

        case .googleCalendar:
            let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=1")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

            let (_, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                return .error("Invalid response")
            }

            if http.statusCode == 401 {
                return .expired("Token expired")
            }

            if (200...299).contains(http.statusCode) {
                return .valid
            }

            return .error("HTTP \(http.statusCode)")
        }
    }

    private func refreshToken() {
        isRefreshing = true
        validationResult = nil

        Task {
            do {
                let refreshKey = account.id + ":refresh"
                guard let refreshToken = try await tokenStore.getToken(for: refreshKey) else {
                    await MainActor.run {
                        validationResult = .error("No refresh token - re-authenticate")
                        isRefreshing = false
                    }
                    return
                }

                let newToken = try await refreshTokenWithProvider(refreshToken: refreshToken)

                // Store the new token
                try await tokenStore.setToken(newToken.accessToken, for: account.id)
                if let newRefresh = newToken.refreshToken {
                    try await tokenStore.setToken(newRefresh, for: refreshKey)
                }

                await MainActor.run {
                    validationResult = .valid
                    isRefreshing = false
                }
            } catch {
                await MainActor.run {
                    validationResult = .error(error.localizedDescription)
                    isRefreshing = false
                }
            }
        }
    }

    private func refreshTokenWithProvider(refreshToken: String) async throws -> (accessToken: String, refreshToken: String?) {
        switch account.provider {
        case .gitlab:
            // GitLab OAuth token refresh
            let baseURL = account.host.map { "https://\($0)" } ?? "https://gitlab.com"
            let url = URL(string: "\(baseURL)/oauth/token")!

            // Load OAuth credentials
            guard let credentials = await OAuthClientCredentials.shared.getCredentials(for: .gitlab) else {
                throw OAuthError.configurationError("No GitLab OAuth credentials configured")
            }

            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let body = [
                "grant_type=refresh_token",
                "refresh_token=\(refreshToken)",
                "client_id=\(credentials.clientId)",
                "client_secret=\(credentials.clientSecret)"
            ].joined(separator: "&")
            request.httpBody = body.data(using: String.Encoding.utf8)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OAuthError.networkError("Invalid response")
            }

            if http.statusCode != 200 {
                if let errorBody = String(data: data, encoding: .utf8) {
                    throw OAuthError.authorizationFailed("Refresh failed: \(errorBody)")
                }
                throw OAuthError.authorizationFailed("HTTP \(http.statusCode)")
            }

            struct TokenResponse: Decodable {
                let access_token: String
                let refresh_token: String?
            }
            let tokenResp = try JSONDecoder().decode(TokenResponse.self, from: data)
            return (tokenResp.access_token, tokenResp.refresh_token)

        case .googleCalendar:
            // Google OAuth token refresh
            guard let credentials = await OAuthClientCredentials.shared.getCredentials(for: .googleCalendar) else {
                throw OAuthError.configurationError("No Google OAuth credentials configured")
            }

            let url = URL(string: "https://oauth2.googleapis.com/token")!
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

            let body = [
                "grant_type=refresh_token",
                "refresh_token=\(refreshToken)",
                "client_id=\(credentials.clientId)",
                "client_secret=\(credentials.clientSecret)"
            ].joined(separator: "&")
            request.httpBody = body.data(using: String.Encoding.utf8)

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw OAuthError.networkError("Invalid response")
            }

            if http.statusCode != 200 {
                if let errorBody = String(data: data, encoding: .utf8) {
                    throw OAuthError.authorizationFailed("Refresh failed: \(errorBody)")
                }
                throw OAuthError.authorizationFailed("HTTP \(http.statusCode)")
            }

            struct TokenResponse: Decodable {
                let access_token: String
                let refresh_token: String?
            }
            let tokenResp = try JSONDecoder().decode(TokenResponse.self, from: data)
            // Google doesn't always return a new refresh token
            return (tokenResp.access_token, tokenResp.refresh_token ?? refreshToken)

        case .azureDevops:
            // Azure DevOps PATs don't support refresh - need to re-authenticate
            throw OAuthError.configurationError("Azure DevOps PATs cannot be refreshed. Please create a new PAT.")
        }
    }

    private var providerColor: Color {
        switch account.provider {
        case .gitlab: return .orange
        case .azureDevops: return .blue
        case .googleCalendar: return .red
        }
    }

    private var providerDisplayName: String {
        switch account.provider {
        case .gitlab: return "GitLab"
        case .azureDevops: return "Azure DevOps"
        case .googleCalendar: return "Google Calendar"
        }
    }

    /// Whether event type filtering is active (some types disabled)
    private var hasEventTypeFiltering: Bool {
        guard let enabled = account.enabledEventTypes else { return false }
        let relevantTypes = Set(account.relevantEventTypes)
        return enabled != relevantTypes
    }

    /// Number of event types that are filtered out (hidden)
    private var filteredEventTypesCount: Int {
        guard let enabled = account.enabledEventTypes else { return 0 }
        let relevantTypes = Set(account.relevantEventTypes)
        return relevantTypes.subtracting(enabled).count
    }

    /// Whether calendar filtering is active (Google Calendar only)
    private var hasCalendarFiltering: Bool {
        account.calendarIds != nil && !account.calendarIds!.isEmpty
    }

    /// Number of enabled calendars
    private var enabledCalendarsCount: Int {
        account.calendarIds?.count ?? 0
    }
}

/// Sheet for configuring which event types are enabled for an account
struct AccountEventTypesSheet: View {
    let account: Account
    let appState: AppState

    @Environment(\.dismiss) private var dismiss

    /// Local state for editing - initialized from account
    @State private var enabledTypes: Set<ActivityType>

    /// Relevant event types for this provider
    private var relevantTypes: [ActivityType] {
        account.relevantEventTypes
    }

    /// Whether all relevant types are enabled
    private var allEnabled: Bool {
        relevantTypes.allSatisfy { enabledTypes.contains($0) }
    }

    init(account: Account, appState: AppState) {
        self.account = account
        self.appState = appState
        // Initialize local state from account settings
        // If nil (all enabled), start with all relevant types
        let initial = account.enabledEventTypes ?? Set(ActivityType.relevantTypes(for: account.provider))
        _enabledTypes = State(initialValue: initial)
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header
            VStack(spacing: 4) {
                Text("Event Types")
                    .font(.headline)
                Text(account.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            // Description
            Text("Select which types of events to show from this account.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            // Event type toggles
            VStack(alignment: .leading, spacing: 8) {
                // Select all / none toggle
                HStack {
                    Button(allEnabled ? "Deselect All" : "Select All") {
                        if allEnabled {
                            enabledTypes.removeAll()
                        } else {
                            enabledTypes = Set(relevantTypes)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                    Spacer()
                }

                ForEach(relevantTypes, id: \.self) { eventType in
                    HStack {
                        Toggle(isOn: Binding(
                            get: { enabledTypes.contains(eventType) },
                            set: { isOn in
                                if isOn {
                                    enabledTypes.insert(eventType)
                                } else {
                                    enabledTypes.remove(eventType)
                                }
                            }
                        )) {
                            HStack(spacing: 8) {
                                Image(systemName: eventType.iconName)
                                    .frame(width: 20)
                                    .foregroundStyle(.secondary)
                                Text(eventType.displayName)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
            }
            .padding(.horizontal)

            Spacer()

            // Action buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    saveAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(enabledTypes.isEmpty)
            }
        }
        .padding(20)
        .frame(width: 300, height: 380)
    }

    private func saveAndDismiss() {
        // If all relevant types are enabled, store nil (meaning all enabled)
        // This keeps backwards compatibility and simplifies storage
        let typesToStore: Set<ActivityType>? = enabledTypes == Set(relevantTypes) ? nil : enabledTypes
        appState.updateEnabledEventTypes(for: account.id, types: typesToStore)
        dismiss()
    }
}

/// Sheet for configuring which calendars are enabled for a Google Calendar account
struct AccountProjectsSheet: View {
    let account: Account
    let appState: AppState
    let tokenStore: TokenStore

    @Environment(\.dismiss) private var dismiss

    /// Available calendars fetched from Google
    @State private var availableCalendars: [CalendarItem] = []
    /// Selected calendar IDs
    @State private var selectedIds: Set<String> = []
    /// Loading state
    @State private var isLoading = true
    /// Error message
    @State private var errorMessage: String?

    /// Represents a calendar that can be selected
    struct CalendarItem: Identifiable {
        let id: String
        let name: String
        let isPrimary: Bool
    }

    /// Whether all calendars are selected
    private var allSelected: Bool {
        !availableCalendars.isEmpty && availableCalendars.allSatisfy { selectedIds.contains($0.id) }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Header
            VStack(spacing: 4) {
                Text("Calendars")
                    .font(.headline)
                Text(account.displayName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("Select which calendars to show events from.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Divider()

            // Content
            if isLoading {
                Spacer()
                ProgressView("Loading calendars...")
                Spacer()
            } else if let error = errorMessage {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.title2)
                        .foregroundStyle(.orange)
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                    Button("Retry") {
                        Task { await loadCalendars() }
                    }
                    .buttonStyle(.bordered)
                }
                Spacer()
            } else if availableCalendars.isEmpty {
                Spacer()
                Text("No calendars found")
                    .foregroundStyle(.secondary)
                Spacer()
            } else {
                // Select all / none
                HStack {
                    Button(allSelected ? "Deselect All" : "Select All") {
                        if allSelected {
                            selectedIds.removeAll()
                        } else {
                            selectedIds = Set(availableCalendars.map { $0.id })
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                    Spacer()
                    Text("\(selectedIds.count) of \(availableCalendars.count) selected")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                // Calendars list
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(availableCalendars) { calendar in
                            VStack(alignment: .leading, spacing: 0) {
                                Toggle(isOn: Binding(
                                    get: { selectedIds.contains(calendar.id) },
                                    set: { isOn in
                                        if isOn {
                                            selectedIds.insert(calendar.id)
                                        } else {
                                            selectedIds.remove(calendar.id)
                                        }
                                    }
                                )) {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(calendar.name)
                                            .lineLimit(1)
                                        if calendar.isPrimary {
                                            Text("Primary")
                                                .font(.caption2)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                                .toggleStyle(.checkbox)
                                .padding(.vertical, 8)
                                .padding(.horizontal, 4)

                                if calendar.id != availableCalendars.last?.id {
                                    Divider()
                                        .padding(.leading, 24)
                                }
                            }
                        }
                    }
                }
                .frame(maxHeight: 320)
            }

            Spacer()

            // Action buttons
            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Save") {
                    saveAndDismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 400, height: 480)
        .task {
            await loadCalendars()
        }
    }

    private func loadCalendars() async {
        isLoading = true
        errorMessage = nil

        do {
            guard let token = try await tokenStore.getToken(for: account.id) else {
                errorMessage = "No token found for this account"
                isLoading = false
                return
            }

            let url = URL(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList?maxResults=250")!
            var request = URLRequest(url: url)
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Accept")

            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
                throw ProviderError.networkError("Failed to fetch Google calendars")
            }

            struct Response: Decodable {
                let items: [Calendar]?
            }
            struct Calendar: Decodable {
                let id: String
                let summary: String?
                let primary: Bool?
            }

            let decoded = try JSONDecoder().decode(Response.self, from: data)
            let calendars = (decoded.items ?? []).map {
                CalendarItem(id: $0.id, name: $0.summary ?? $0.id, isPrimary: $0.primary ?? false)
            }

            await MainActor.run {
                self.availableCalendars = calendars
                // Initialize selection from account settings
                if let calIds = account.calendarIds {
                    self.selectedIds = Set(calIds)
                } else {
                    // Default: select all
                    self.selectedIds = Set(calendars.map { $0.id })
                }
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func saveAndDismiss() {
        // Store nil if all calendars selected (meaning show all)
        let idsToStore: [String]? = selectedIds.count == availableCalendars.count ? nil : Array(selectedIds)
        appState.updateCalendarIds(for: account.id, calendarIds: idsToStore)
        dismiss()
    }
}

/// Sheet for adding a new account via OAuth
// Provider-specific configuration collected at account creation time
struct ProviderSpecificConfig: Sendable {
    var organization: String?
    var projects: [String]?
    var calendarIds: [String]?
}

struct AddAccountSheet: View {
    let appState: AppState
    let tokenStore: TokenStore
    @Binding var loginState: LoginState
    let onComplete: (OAuthResult, ProviderSpecificConfig?) -> Void
    let onError: (OAuthError) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Selected provider
    @State private var selectedProvider: Provider = .gitlab

    /// Authentication method
    private enum AuthMethod: String, CaseIterable {
        case oauth = "OAuth"
        case pat = "Personal Access Token"
    }
    @State private var authMethod: AuthMethod = .oauth  // Default to OAuth

    /// Personal Access Token input
    @State private var patInput: String = ""

    /// Host for self-hosted instances (GitLab)
    /// Loaded from ACTIVITYBAR_DEFAULT_GITLAB_HOST environment variable for development convenience
    @State private var customHost: String = ProcessInfo.processInfo.environment["ACTIVITYBAR_DEFAULT_GITLAB_HOST"] ?? ""

    /// Whether to show custom host field
    private var showCustomHost: Bool {
        selectedProvider == .gitlab
    }

    /// Whether PAT auth is available for the selected provider
    private var supportsPAT: Bool {
        selectedProvider == .gitlab || selectedProvider == .azureDevops
    }

    // Azure DevOps specific fields
    @State private var azureOrganization: String = ""
    @State private var azureProjectsText: String = ""
    private var showAzureFields: Bool { selectedProvider == .azureDevops }
    @State private var didApplyAzurePrefill: Bool = false

    // Google Calendar selection flow (post-OAuth)
    private enum GooglePhase: Equatable { case idle, selecting }
    @State private var googlePhase: GooglePhase = .idle
    @State private var googleOAuthResult: OAuthResult?
    private struct GoogleCalendar: Identifiable, Equatable { let id: String; let summary: String; let primary: Bool }
    @State private var googleCalendars: [GoogleCalendar] = []
    @State private var googleSelectedIds: Set<String> = []

    // Validation banner for this sheet
    @State private var validationError: String?

    var body: some View {
        VStack(spacing: 20) {
            Text("Add Account")
                .font(.headline)

            // Provider selection
            VStack(alignment: .leading, spacing: 8) {
                Text("Provider")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                Picker("Provider", selection: $selectedProvider) {
                    ForEach(Provider.allCases, id: \.self) { provider in
                        HStack {
                            Circle()
                                .fill(colorForProvider(provider))
                                .frame(width: 8, height: 8)
                            Text(displayNameForProvider(provider))
                        }
                        .tag(provider)
                    }
                }
                .pickerStyle(.radioGroup)
                .onChange(of: selectedProvider) { _, newValue in
                    // Reset auth method when switching providers
                    if newValue == .googleCalendar {
                        authMethod = .oauth
                    }
                    // Try applying Azure prefill when switching to Azure
                    if newValue == .azureDevops {
                        applyAzurePrefillIfAvailable()
                    }
                }
            }

            // Auth method selection (for providers that support PAT)
            if supportsPAT && googlePhase == .idle {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Authentication Method")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    Picker("Method", selection: $authMethod) {
                        Text("Personal Access Token").tag(AuthMethod.pat)
                        Text("OAuth (Browser)").tag(AuthMethod.oauth)
                    }
                    .pickerStyle(.segmented)
                }
            }

            // PAT input field
            if supportsPAT && authMethod == .pat && googlePhase == .idle {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Personal Access Token")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    SecureField("ghp_xxxx or glpat-xxxx", text: $patInput)
                        .textFieldStyle(.roundedBorder)

                    Text(patHelpText)
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Custom host for self-hosted instances
            if showCustomHost && googlePhase == .idle {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Host (optional)")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("gitlab.company.com", text: $customHost)
                        .textFieldStyle(.roundedBorder)

                    Text("Leave empty for gitlab.com")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Azure DevOps configuration
            if showAzureFields && googlePhase == .idle {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Azure DevOps Configuration")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    TextField("Organization (e.g. contoso)", text: $azureOrganization)
                        .textFieldStyle(.roundedBorder)

                    TextField("Projects (comma-separated)", text: $azureProjectsText)
                        .textFieldStyle(.roundedBorder)

                    Text("Provide the organization and one or more project names.")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            // Google Calendar selection (after OAuth)
            if googlePhase == .selecting {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Select Calendars")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)

                    if googleCalendars.isEmpty && loginState.isInProgress {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("Loading calendars...")
                                .foregroundStyle(.secondary)
                        }
                    } else if googleCalendars.isEmpty {
                        Text("No calendars available")
                            .foregroundStyle(.tertiary)
                    } else {
                        ScrollView {
                            VStack(alignment: .leading, spacing: 6) {
                                ForEach(googleCalendars) { cal in
                                    HStack {
                                        Toggle(isOn: .init(
                                            get: { googleSelectedIds.contains(cal.id) },
                                            set: { isOn in
                                                if isOn { googleSelectedIds.insert(cal.id) } else { googleSelectedIds.remove(cal.id) }
                                            }
                                        )) {
                                            Text(cal.summary)
                                        }
                                        .toggleStyle(.checkbox)
                                        Spacer()
                                        if cal.primary {
                                            Text("Primary")
                                                .font(.caption)
                                                .foregroundStyle(.tertiary)
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 160)
                    }
                }
            }

            if let error = validationError {
                CopyableErrorText(message: error, icon: "exclamationmark.triangle.fill", color: .orange)
            }

            // Login state indicator
            if loginState.isInProgress {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text(loginStateMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if case .failed(let message) = loginState {
                CopyableErrorText(message: message, icon: "exclamationmark.triangle.fill", color: .orange)
            }

            Spacer()

            // Action buttons
            HStack {
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)

                Spacer()

                if googlePhase == .selecting {
                    Button("Add Account") { completeGoogleSelection() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(googleSelectedIds.isEmpty || loginState.isInProgress)
                } else if supportsPAT && authMethod == .pat {
                    Button("Add Account") { startPATLogin() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(patInput.trimmingCharacters(in: .whitespaces).isEmpty || loginState.isInProgress)
                } else {
                    Button("Sign In...") { startOAuthFlow() }
                        .keyboardShortcut(.defaultAction)
                        .disabled(loginState.isInProgress)
                }
            }
        }
        .padding(20)
        .frame(width: 380, height: sheetHeight)
        .onAppear {
            // Try to prefill on appear if Azure is selected by default
            if selectedProvider == .azureDevops {
                applyAzurePrefillIfAvailable()
            }
        }
    }

    /// Dynamic sheet height based on current state
    private var sheetHeight: CGFloat {
        if googlePhase == .selecting {
            return 430
        }
        var height: CGFloat = 280  // Base height
        if supportsPAT { height += 50 }  // Auth method picker
        if supportsPAT && authMethod == .pat { height += 80 }  // PAT input
        if showCustomHost { height += 80 }  // Custom host field
        if showAzureFields { height += 80 }  // Azure fields
        return height
    }

    private var loginStateMessage: String {
        switch loginState {
        case .authenticating:
            return "Opening browser for authentication..."
        case .exchangingToken:
            return "Exchanging authorization code..."
        case .fetchingUserInfo:
            return "Fetching account information..."
        default:
            return ""
        }
    }

    private func colorForProvider(_ provider: Provider) -> Color {
        switch provider {
        case .gitlab: return .orange
        case .azureDevops: return .blue
        case .googleCalendar: return .red
        }
    }

    private func displayNameForProvider(_ provider: Provider) -> String {
        switch provider {
        case .gitlab: return "GitLab"
        case .azureDevops: return "Azure DevOps"
        case .googleCalendar: return "Google Calendar"
        }
    }

    private var patHelpText: String {
        switch selectedProvider {
        case .gitlab:
            return "Generate at: GitLab → Preferences → Access Tokens (scopes: read_api, read_user)"
        case .azureDevops:
            return "Generate at: Azure DevOps → User Settings → Personal access tokens"
        default:
            return ""
        }
    }

    /// Start PAT-based login for selected provider
    private func startPATLogin() {
        print("[ActivityBar][AddAccount] startPATLogin called for \(selectedProvider)")
        validationError = nil
        let token = patInput.trimmingCharacters(in: .whitespacesAndNewlines)

        guard !token.isEmpty else {
            print("[ActivityBar][AddAccount] ERROR: Empty token")
            validationError = "Please enter a Personal Access Token"
            return
        }
        print("[ActivityBar][AddAccount] Token length: \(token.count)")

        // Validate Azure config
        if selectedProvider == .azureDevops {
            let org = azureOrganization.trimmingCharacters(in: .whitespacesAndNewlines)
            let projects = azureProjectsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if org.isEmpty {
                validationError = "Organization is required for Azure DevOps"
                return
            }
            if projects.isEmpty {
                validationError = "At least one project is required for Azure DevOps"
                return
            }
        }

        loginState = .fetchingUserInfo
        print("[ActivityBar][AddAccount] Set loginState to fetchingUserInfo, starting validation...")

        Task {
            do {
                print("[ActivityBar][AddAccount] Calling validatePATAndGetUserInfo...")
                let result = try await validatePATAndGetUserInfo(token: token)
                print("[ActivityBar][AddAccount] Validation succeeded!")
                print("[ActivityBar][AddAccount]   accountId: \(result.accountId)")
                print("[ActivityBar][AddAccount]   displayName: \(result.displayName)")

                // Build provider-specific config
                var config: ProviderSpecificConfig? = nil
                if selectedProvider == .azureDevops {
                    let projects = azureProjectsText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    config = ProviderSpecificConfig(
                        organization: azureOrganization.trimmingCharacters(in: .whitespacesAndNewlines),
                        projects: projects.isEmpty ? nil : projects,
                        calendarIds: nil
                    )
                }

                print("[ActivityBar][AddAccount] Calling onComplete callback...")
                onComplete(result, config)
                print("[ActivityBar][AddAccount] Dismissing sheet...")
                dismiss()
            } catch {
                print("[ActivityBar][AddAccount] ERROR: \(error)")
                loginState = .failed(error.localizedDescription)
                validationError = error.localizedDescription
            }
        }
    }

    /// Validate PAT by fetching user info from the provider's API
    private func validatePATAndGetUserInfo(token: String) async throws -> OAuthResult {
        switch selectedProvider {
        case .gitlab:
            return try await validateGitLabPAT(token: token)
        case .azureDevops:
            return try await validateAzureDevOpsPAT(token: token)
        default:
            throw OAuthError.configurationError("PAT not supported for \(selectedProvider)")
        }
    }

    private func validateGitLabPAT(token: String) async throws -> OAuthResult {
        print("[ActivityBar][PAT] Validating GitLab PAT...")
        print("[ActivityBar][PAT] Token prefix: \(String(token.prefix(10)))...")

        let baseURL = customHost.isEmpty ? "https://gitlab.com" : customHost
        let url = URL(string: "\(baseURL)/api/v4/user")!
        var request = URLRequest(url: url)
        request.setValue(token, forHTTPHeaderField: "PRIVATE-TOKEN")

        print("[ActivityBar][PAT] Sending request to \(url)")
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            print("[ActivityBar][PAT] ERROR: Invalid response type")
            throw OAuthError.networkError("Invalid response")
        }
        print("[ActivityBar][PAT] Response status: \(http.statusCode)")

        if http.statusCode == 401 {
            print("[ActivityBar][PAT] ERROR: 401 Unauthorized")
            throw OAuthError.authorizationFailed("Invalid token - please check your PAT")
        }
        guard (200...299).contains(http.statusCode) else {
            print("[ActivityBar][PAT] ERROR: HTTP \(http.statusCode)")
            throw OAuthError.networkError("HTTP \(http.statusCode)")
        }

        struct GitLabUser: Decodable {
            let username: String
            let name: String?
            let id: Int
        }
        let user = try JSONDecoder().decode(GitLabUser.self, from: data)
        print("[ActivityBar][PAT] GitLab user: \(user.username) (name: \(user.name ?? "nil"))")

        return OAuthResult(
            provider: .gitlab,
            accessToken: token,
            accountId: user.username,
            displayName: user.name ?? user.username,
            host: customHost.isEmpty ? nil : customHost
        )
    }

    private func validateAzureDevOpsPAT(token: String) async throws -> OAuthResult {
        let org = azureOrganization.trimmingCharacters(in: .whitespacesAndNewlines)

        // Try both Basic auth variants: "user:token" then ":token"
        let basicVariants: [String] = ["user:\(token)", ":\(token)"]

        func attempt(with basic: String) async throws -> OAuthResult {
            guard let credData = basic.data(using: .utf8) else {
                throw OAuthError.configurationError("Failed to encode credentials")
            }
            let base64Creds = credData.base64EncodedString()

            func makeRequest(_ url: URL) -> URLRequest {
                var req = URLRequest(url: url)
                req.setValue("Basic \(base64Creds)", forHTTPHeaderField: "Authorization")
                req.setValue("application/json", forHTTPHeaderField: "Accept")
                req.setValue("ActivityBar/1.0", forHTTPHeaderField: "User-Agent")
                return req
            }

            // 1) Optionally validate token via profile endpoint (org-independent)
            // Note: This endpoint requires broader scopes than org-scoped PATs typically have.
            // We'll make this optional and rely on the organization-specific validation below.
            if let profileURL = URL(string: "https://app.vssps.visualstudio.com/_apis/profile/profiles/me?api-version=7.0-preview") {
                let (_, response) = try await URLSession.shared.data(for: makeRequest(profileURL))
                if let http = response as? HTTPURLResponse {
                    if !(200...299).contains(http.statusCode) && http.statusCode != 401 && http.statusCode != 203 {
                        // Log non-401 errors but don't fail - org-scoped PATs might not have profile access
                        print("[ActivityBar][Azure] Profile endpoint returned \(http.statusCode), continuing with org validation")
                    }
                }
            }

            // 2) Validate organization access via connectionData (primary then legacy)
            func fetchConnectionData(from urlString: String) async throws -> (displayName: String?, userId: String?) {
                guard let url = URL(string: urlString) else {
                    throw OAuthError.configurationError("Invalid URL: \(urlString)")
                }
                let (data, response) = try await URLSession.shared.data(for: makeRequest(url))
                guard let http = response as? HTTPURLResponse else { throw OAuthError.networkError("Invalid response") }
                if http.statusCode == 401 || http.statusCode == 203 {
                    throw OAuthError.authorizationFailed("Invalid token - please check your PAT")
                }
                if !(200...299).contains(http.statusCode) {
                    let body = String(data: data, encoding: .utf8) ?? ""
                    throw OAuthError.networkError("HTTP \(http.statusCode) for connectionData: \(body)")
                }
                struct AzureConnectionData: Decodable {
                    let authenticatedUser: AuthenticatedUser?
                    struct AuthenticatedUser: Decodable {
                        let providerDisplayName: String?
                        let id: String?
                    }
                }
                let connData = try JSONDecoder().decode(AzureConnectionData.self, from: data)
                return (connData.authenticatedUser?.providerDisplayName, connData.authenticatedUser?.id)
            }

            let primary = "https://dev.azure.com/\(org)/_apis/connectionData?api-version=7.0-preview"
            do {
                let (displayName, userId) = try await fetchConnectionData(from: primary)
                return OAuthResult(
                    provider: .azureDevops,
                    accessToken: token,
                    accountId: "\(org)/\(userId ?? org)",
                    displayName: displayName ?? org
                )
            } catch {
                let legacy = "https://\(org).visualstudio.com/_apis/connectionData?api-version=7.0-preview"
                let (displayName, userId) = try await fetchConnectionData(from: legacy)
                return OAuthResult(
                    provider: .azureDevops,
                    accessToken: token,
                    accountId: "\(org)/\(userId ?? org)",
                    displayName: displayName ?? org
                )
            }
        }

        var lastError: Error = OAuthError.authorizationFailed("Invalid token - please check your PAT")
        for variant in basicVariants {
            do {
                return try await attempt(with: variant)
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    // MARK: - Prefill helpers
    private func applyAzurePrefillIfAvailable() {
        guard !didApplyAzurePrefill else { return }
        guard let prefill = CredentialsPrefill.loadAzureCredentials() else { return }

        // Only fill empty fields to avoid overriding user input
        if patInput.isEmpty, let pat = prefill.pat { patInput = pat }
        if azureOrganization.isEmpty, let org = prefill.organization { azureOrganization = org }
        if azureProjectsText.isEmpty, let projs = prefill.projects, !projs.isEmpty {
            azureProjectsText = projs.joined(separator: ", ")
        }
        didApplyAzurePrefill = true
        print("[ActivityBar][Prefill] Applied Azure credentials prefill to inputs")
    }

    /// Start OAuth flow for selected provider
    private func startOAuthFlow() {
        // Reset errors and validate preconditions
        validationError = nil

        if selectedProvider == .azureDevops {
            let org = azureOrganization.trimmingCharacters(in: .whitespacesAndNewlines)
            let projects = azureProjectsText
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
            if org.isEmpty {
                validationError = "Organization is required for Azure DevOps"
                return
            }
            if projects.isEmpty {
                validationError = "At least one project is required for Azure DevOps"
                return
            }
        }

        loginState = .authenticating

        let coordinator = OAuthCoordinatorFactory.coordinator(for: selectedProvider)
        let host: String? = showCustomHost && !customHost.isEmpty ? customHost : nil

        Task {
            do {
                let result = try await coordinator.authenticate(host: host)

                // Build provider-specific config
                var config: ProviderSpecificConfig? = nil
                switch selectedProvider {
                case .azureDevops:
                    let projects = azureProjectsText
                        .split(separator: ",")
                        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        .filter { !$0.isEmpty }
                    config = ProviderSpecificConfig(
                        organization: azureOrganization.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : azureOrganization.trimmingCharacters(in: .whitespacesAndNewlines),
                        projects: projects.isEmpty ? nil : projects,
                        calendarIds: nil
                    )
                case .googleCalendar:
                    await presentGoogleCalendarSelection(oauth: result)
                    return
                default:
                    config = nil
                }

                onComplete(result, config)
                dismiss()
            } catch let error as OAuthError {
                loginState = .failed(error.localizedDescription)
                onError(error)
            } catch {
                let oauthError = OAuthError.authorizationFailed(error.localizedDescription)
                loginState = .failed(oauthError.localizedDescription)
                onError(oauthError)
            }
        }
    }

    // MARK: - Google Calendar selection helpers

    @MainActor
    private func presentGoogleCalendarSelection(oauth: OAuthResult) async {
        googleOAuthResult = oauth
        googleCalendars = []
        googleSelectedIds = []
        googlePhase = .selecting
        loginState = .fetchingUserInfo

        // Retry logic: OAuth token may need a moment to be fully active on Google's side
        var lastError: Error?
        for attempt in 1...3 {
            do {
                let calendars = try await fetchGoogleCalendars(accessToken: oauth.accessToken)
                googleCalendars = calendars
                // Preselect primary if available
                let primary = calendars.filter { $0.primary }.map { $0.id }
                googleSelectedIds = Set(primary)
                loginState = .idle
                return
            } catch {
                lastError = error
                if attempt < 3 {
                    // Short delay before retry to allow token propagation
                    try? await Task.sleep(nanoseconds: 500_000_000) // 0.5 seconds
                }
            }
        }

        // All retries failed
        if let error = lastError {
            validationError = "Failed to load calendars: \(error.localizedDescription)"
            loginState = .failed(error.localizedDescription)
        }
    }

    private func fetchGoogleCalendars(accessToken: String) async throws -> [GoogleCalendar] {
        guard var components = URLComponents(string: "https://www.googleapis.com/calendar/v3/users/me/calendarList") else {
            throw ProviderError.configurationError("Invalid Google Calendar URL")
        }
        components.queryItems = [
            URLQueryItem(name: "minAccessRole", value: "reader"),
            URLQueryItem(name: "maxResults", value: "250")
        ]
        guard let url = components.url else {
            throw ProviderError.configurationError("Failed to build calendarList URL")
        }

        var request = URLRequest(url: url)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw ProviderError.networkError("HTTP error listing calendars")
        }
        struct CalendarListResponse: Decodable { let items: [Item]? }
        struct Item: Decodable { let id: String; let summary: String?; let primary: Bool? }
        let decoded = try JSONDecoder().decode(CalendarListResponse.self, from: data)
        return (decoded.items ?? []).map { GoogleCalendar(id: $0.id, summary: $0.summary ?? $0.id, primary: $0.primary ?? false) }
    }

    private func completeGoogleSelection() {
        guard let oauth = googleOAuthResult else { return }
        guard !googleSelectedIds.isEmpty else {
            validationError = "Select at least one calendar"
            return
        }
        let config = ProviderSpecificConfig(organization: nil, projects: nil, calendarIds: Array(googleSelectedIds))
        onComplete(oauth, config)
        dismiss()
    }
}

/// General settings tab
/// ACTIVITY-025: Settings behavior and display preferences
struct GeneralSettingsView: View {
    let launchAtLoginManager: LaunchAtLoginManager
    var refreshScheduler: RefreshScheduler?
    var preferencesManager: PreferencesManager?
    var onPanelAppearanceChanged: (() -> Void)?

    var body: some View {
        Form {
            Section {
                LaunchAtLoginToggle(manager: launchAtLoginManager)
            }

            // ACTIVITY-025: Display preferences
            Section("Display") {
                if let prefs = preferencesManager {
                    Picker("Default Heatmap Range", selection: Binding(
                        get: { prefs.heatmapRange },
                        set: { prefs.heatmapRange = $0 }
                    )) {
                        ForEach(HeatmapRange.allCases, id: \.self) { range in
                            Text(range.displayName).tag(range)
                        }
                    }

                    Toggle("Show Meetings", isOn: Binding(
                        get: { prefs.showMeetings },
                        set: { prefs.showMeetings = $0 }
                    ))

                    Toggle("Show All-Day Events", isOn: Binding(
                        get: { prefs.showAllDayEvents },
                        set: { prefs.showAllDayEvents = $0 }
                    ))

                    Toggle("Show Event Author", isOn: Binding(
                        get: { prefs.showEventAuthor },
                        set: { prefs.showEventAuthor = $0 }
                    ))
                    Text("Display the author/owner of each event for debugging")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Default Heatmap Range", selection: .constant(HeatmapRange.days90)) {
                        ForEach(HeatmapRange.allCases, id: \.self) { range in
                            Text(range.displayName).tag(range)
                        }
                    }
                    .disabled(true)

                    Toggle("Show Meetings", isOn: .constant(true))
                        .disabled(true)

                    Toggle("Show All-Day Events", isOn: .constant(true))
                        .disabled(true)
                    Text("Group repeated commits and comments into expandable rows")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            // Calendar-specific settings
            Section("Calendar") {
                if let prefs = preferencesManager {
                    Picker("Start Week On", selection: Binding(
                        get: { prefs.weekStartDay },
                        set: { prefs.weekStartDay = $0 }
                    )) {
                        ForEach(WeekStartDay.allCases, id: \.self) { day in
                            Text(day.displayName).tag(day)
                        }
                    }
                } else {
                    Picker("Start Week On", selection: .constant(WeekStartDay.sunday)) {
                        ForEach(WeekStartDay.allCases, id: \.self) { day in
                            Text(day.displayName).tag(day)
                        }
                    }
                    .disabled(true)
                }
            }

            // ACTIVITY-024: Refresh interval configuration
            Section("Refresh") {
                if let scheduler = refreshScheduler {
                    Picker("Refresh Interval", selection: Binding(
                        get: { scheduler.interval },
                        set: { newValue in
                            scheduler.interval = newValue
                            // Also persist to preferences
                            preferencesManager?.refreshInterval = newValue
                        }
                    )) {
                        ForEach(RefreshInterval.allCases, id: \.self) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }

                    // Show current status
                    HStack {
                        Text("Status")
                        Spacer()
                        Text(scheduler.statusDescription)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Picker("Refresh Interval", selection: .constant(RefreshInterval.fifteenMinutes)) {
                        ForEach(RefreshInterval.allCases, id: \.self) { interval in
                            Text(interval.displayName).tag(interval)
                        }
                    }
                    .disabled(true)
                }
            }

            // Panel Appearance settings
            Section("Panel Appearance") {
                if let prefs = preferencesManager {
                    Picker("Blur Style", selection: Binding(
                        get: { prefs.panelBlurMaterial },
                        set: { newValue in
                            prefs.panelBlurMaterial = newValue
                            onPanelAppearanceChanged?()
                        }
                    )) {
                        ForEach(PanelBlurMaterial.allCases, id: \.self) { material in
                            Text(material.displayName).tag(material)
                        }
                    }

                    Text(prefs.panelBlurMaterial.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Panel Opacity")
                            Spacer()
                            Text("\(Int(prefs.panelTransparency * 100))%")
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                        Slider(
                            value: Binding(
                                get: { prefs.panelTransparency },
                                set: { newValue in
                                    prefs.panelTransparency = newValue
                                    onPanelAppearanceChanged?()
                                }
                            ),
                            in: 0.3...1.0,
                            step: 0.05
                        )
                    }

                    Text("Open the panel to preview changes in real-time.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Picker("Blur Style", selection: .constant(PanelBlurMaterial.hudWindow)) {
                        ForEach(PanelBlurMaterial.allCases, id: \.self) { material in
                            Text(material.displayName).tag(material)
                        }
                    }
                    .disabled(true)

                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Panel Opacity")
                            Spacer()
                            Text("95%")
                                .foregroundStyle(.secondary)
                        }
                        Slider(value: .constant(0.95), in: 0.3...1.0)
                            .disabled(true)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .padding()
    }
}

/// Launch at login toggle with error display
/// ACTIVITY-022: Settings toggle enables/disables launch at login
struct LaunchAtLoginToggle: View {
    let manager: LaunchAtLoginManager

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Launch at Login", isOn: Binding(
                    get: { manager.isEnabled },
                    set: { manager.setEnabled($0) }
                ))
                .disabled(manager.isUpdating)

                if manager.isUpdating {
                    ProgressView()
                        .scaleEffect(0.5)
                        .frame(width: 16, height: 16)
                }
            }

            // Status description for edge cases (requires approval, etc.)
            if manager.statusDescription == "Requires approval in System Settings" {
                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.yellow)
                        .font(.caption)
                    Text(manager.statusDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Settings") {
                        openLoginItemsSettings()
                    }
                    .font(.caption)
                    .buttonStyle(.link)
                }
            }

            // Error banner
            if let error = manager.lastError {
                ErrorBannerView(
                    message: error.localizedDescription,
                    onDismiss: { manager.clearError() }
                )
            }
        }
    }

    /// Open System Settings > Login Items
    private func openLoginItemsSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension") {
            NSWorkspace.shared.open(url)
        }
    }
}

// MARK: - Preview Token Store

/// In-memory token store for previews
private final class PreviewTokenStore: TokenStore, @unchecked Sendable {
    private var tokens: [String: String] = [:]

    func getToken(for accountId: String) async throws -> String? {
        tokens[accountId]
    }

    func setToken(_ token: String, for accountId: String) async throws {
        tokens[accountId] = token
    }

    func deleteToken(for accountId: String) async throws {
        tokens.removeValue(forKey: accountId)
    }

    func hasToken(for accountId: String) async throws -> Bool {
        tokens[accountId] != nil
    }

    func listAccountIds() async throws -> [String] {
        Array(tokens.keys)
    }
}

#Preview("Settings") {
    SettingsView(
        appState: AppState(),
        tokenStore: PreviewTokenStore(),
        launchAtLoginManager: LaunchAtLoginManager(),
        refreshScheduler: nil,
        preferencesManager: PreferencesManager()
    )
}

#Preview("Accounts") {
    AccountsSettingsView(appState: AppState(), tokenStore: PreviewTokenStore())
}

#Preview("Accounts With Data") {
    let appState = AppState()
    appState.session.accounts = [
        Account(id: "gl-1", provider: .gitlab, displayName: "Work GitLab", host: "gitlab.company.com"),
        Account(id: "az-1", provider: .azureDevops, displayName: "Azure DevOps", isEnabled: false)
    ]
    return AccountsSettingsView(appState: appState, tokenStore: PreviewTokenStore())
}

#Preview("Add Account") {
    AddAccountSheet(
        appState: AppState(),
        tokenStore: PreviewTokenStore(),
        loginState: .constant(.idle),
        onComplete: { _, _ in },
        onError: { _ in }
    )
}

#Preview("General") {
    GeneralSettingsView(
        launchAtLoginManager: LaunchAtLoginManager(),
        refreshScheduler: nil,
        preferencesManager: PreferencesManager()
    )
}

#Preview("Event Types - GitLab") {
    AccountEventTypesSheet(
        account: Account(id: "gl-1", provider: .gitlab, displayName: "Work GitLab"),
        appState: AppState()
    )
}

#Preview("Event Types - Azure DevOps") {
    AccountEventTypesSheet(
        account: Account(id: "az-1", provider: .azureDevops, displayName: "Azure DevOps", organization: "contoso", projects: ["Project1"]),
        appState: AppState()
    )
}

#Preview("Event Types - Google Calendar") {
    AccountEventTypesSheet(
        account: Account(id: "gc-1", provider: .googleCalendar, displayName: "Personal Calendar"),
        appState: AppState()
    )
}

#Preview("Projects - GitLab") {
    AccountProjectsSheet(
        account: Account(id: "gl-1", provider: .gitlab, displayName: "Work GitLab"),
        appState: AppState(),
        tokenStore: PreviewTokenStore()
    )
}

#Preview("Projects - Azure DevOps") {
    AccountProjectsSheet(
        account: Account(id: "az-1", provider: .azureDevops, displayName: "Azure DevOps", organization: "contoso"),
        appState: AppState(),
        tokenStore: PreviewTokenStore()
    )
}

#Preview("Calendars - Google") {
    AccountProjectsSheet(
        account: Account(id: "gc-1", provider: .googleCalendar, displayName: "Personal Calendar"),
        appState: AppState(),
        tokenStore: PreviewTokenStore()
    )
}

