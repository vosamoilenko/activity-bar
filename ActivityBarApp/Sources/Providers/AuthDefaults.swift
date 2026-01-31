import Foundation
import Core

/// Default OAuth App credentials for ActivityBar.
/// These are public OAuth App credentials (not secrets) - safe to include in client apps.
///
/// To register your own GitLab OAuth App:
/// 1. Go to your GitLab instance → Settings → Applications
/// 2. Create a new OAuth application
/// 3. Set callback URL to: activitybar://oauth/callback
/// 4. Replace these values with your app's credentials
public enum ActivityBarAuthDefaults {
    // GitLab OAuth App credentials (optional)
    public static let gitlabClientID = ""
    public static let gitlabClientSecret = ""

    // Azure DevOps credentials (optional)
    public static let azureClientID = ""
    public static let azureClientSecret = ""

    // Google Calendar credentials (optional)
    public static let googleClientID = ""
    public static let googleClientSecret = ""
}
