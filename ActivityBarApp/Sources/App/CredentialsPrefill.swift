import Foundation

struct AzurePrefill: Sendable {
    let organization: String?
    let pat: String?
    let projects: [String]?
}

enum CredentialsPrefill {
    /// Loads Azure prefill from environment variables.
    ///
    /// Environment variables:
    /// - ACTIVITYBAR_AZURE_ORGANISATION: Azure DevOps organization name
    /// - ACTIVITYBAR_AZURE_PAT: Personal Access Token
    /// - ACTIVITYBAR_AZURE_PROJECTS: Comma-separated list of project names
    static func loadAzureCredentials() -> AzurePrefill? {
        let env = ProcessInfo.processInfo.environment

        let org = env["ACTIVITYBAR_AZURE_ORGANISATION"]
        let pat = env["ACTIVITYBAR_AZURE_PAT"]
        let projectsStr = env["ACTIVITYBAR_AZURE_PROJECTS"]

        // Return nil if no env vars are set
        guard org != nil || pat != nil || projectsStr != nil else {
            return nil
        }

        var projects: [String]? = nil
        if let projectsStr = projectsStr, !projectsStr.isEmpty {
            projects = projectsStr
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                .filter { !$0.isEmpty }
        }

        return AzurePrefill(organization: org, pat: pat, projects: projects)
    }
}
