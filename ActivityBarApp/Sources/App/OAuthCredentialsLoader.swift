import Foundation
import Core
import Providers

/// Loads OAuth client credentials at startup.
///
/// Priority order:
/// 1. Environment variables
/// 2. Hardcoded defaults in AuthDefaults.swift (for distribution)
///
/// Expected environment variables (optional per provider):
/// - `ACTIVITYBAR_GITLAB_CLIENT_ID`, `ACTIVITYBAR_GITLAB_CLIENT_SECRET`
/// - `ACTIVITYBAR_AZURE_CLIENT_ID`, `ACTIVITYBAR_AZURE_CLIENT_SECRET`
/// - `ACTIVITYBAR_GOOGLE_CLIENT_ID`, `ACTIVITYBAR_GOOGLE_CLIENT_SECRET`
@MainActor
enum OAuthCredentialsLoader {
    static func loadFromEnvironment() async {
        let env = ProcessInfo.processInfo.environment

        func configure(
            provider: Provider,
            idKey: String,
            secretKey: String
        ) async {
            guard let clientId = env[idKey], let clientSecret = env[secretKey],
                  !clientId.isEmpty, !clientSecret.isEmpty else {
                print("[ActivityBar][OAuth] No credentials for \(provider) in env (\(idKey), \(secretKey))")
                return
            }
            await OAuthClientCredentials.shared.setCredentials(
                clientId: clientId,
                clientSecret: clientSecret,
                for: provider
            )
            print("[ActivityBar][OAuth] Configured credentials for \(provider) from environment")
        }

        await configure(provider: .gitlab, idKey: "ACTIVITYBAR_GITLAB_CLIENT_ID", secretKey: "ACTIVITYBAR_GITLAB_CLIENT_SECRET")
        await configure(provider: .azureDevops, idKey: "ACTIVITYBAR_AZURE_CLIENT_ID", secretKey: "ACTIVITYBAR_AZURE_CLIENT_SECRET")
        await configure(provider: .googleCalendar, idKey: "ACTIVITYBAR_GOOGLE_CLIENT_ID", secretKey: "ACTIVITYBAR_GOOGLE_CLIENT_SECRET")

        // Fallback: use hardcoded defaults from AuthDefaults.swift (for distribution builds)
        await loadFromAuthDefaults()
    }

    /// Load credentials from hardcoded AuthDefaults (for distribution builds)
    private static func loadFromAuthDefaults() async {
        // GitLab
        if !(await OAuthClientCredentials.shared.hasCredentials(for: .gitlab)) {
            let clientId = ActivityBarAuthDefaults.gitlabClientID
            let clientSecret = ActivityBarAuthDefaults.gitlabClientSecret
            if !clientId.isEmpty && !clientSecret.isEmpty {
                await OAuthClientCredentials.shared.setCredentials(
                    clientId: clientId,
                    clientSecret: clientSecret,
                    for: .gitlab
                )
                print("[ActivityBar][OAuth] Configured GitLab credentials from AuthDefaults")
            }
        }

        // Azure DevOps
        if !(await OAuthClientCredentials.shared.hasCredentials(for: .azureDevops)) {
            let clientId = ActivityBarAuthDefaults.azureClientID
            let clientSecret = ActivityBarAuthDefaults.azureClientSecret
            if !clientId.isEmpty && !clientSecret.isEmpty {
                await OAuthClientCredentials.shared.setCredentials(
                    clientId: clientId,
                    clientSecret: clientSecret,
                    for: .azureDevops
                )
                print("[ActivityBar][OAuth] Configured Azure DevOps credentials from AuthDefaults")
            }
        }

        // Google Calendar
        if !(await OAuthClientCredentials.shared.hasCredentials(for: .googleCalendar)) {
            let clientId = ActivityBarAuthDefaults.googleClientID
            let clientSecret = ActivityBarAuthDefaults.googleClientSecret
            if !clientId.isEmpty && !clientSecret.isEmpty {
                await OAuthClientCredentials.shared.setCredentials(
                    clientId: clientId,
                    clientSecret: clientSecret,
                    for: .googleCalendar
                )
                print("[ActivityBar][OAuth] Configured Google Calendar credentials from AuthDefaults")
            }
        }
    }
}
