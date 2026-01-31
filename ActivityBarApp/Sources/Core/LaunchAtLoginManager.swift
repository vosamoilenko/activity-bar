import Foundation
import ServiceManagement

/// Error types for launch at login operations
public enum LaunchAtLoginError: LocalizedError, Equatable {
    case registrationFailed(String)
    case unregistrationFailed(String)
    case statusCheckFailed(String)
    case notSupported

    public var errorDescription: String? {
        switch self {
        case .registrationFailed(let reason):
            return "Failed to enable launch at login: \(reason)"
        case .unregistrationFailed(let reason):
            return "Failed to disable launch at login: \(reason)"
        case .statusCheckFailed(let reason):
            return "Failed to check launch at login status: \(reason)"
        case .notSupported:
            return "Launch at login is not supported in this environment"
        }
    }
}

/// Manages launch at login using SMAppService (macOS 13+)
/// ACTIVITY-022: Launch at Login support
@MainActor
@Observable
public final class LaunchAtLoginManager {
    /// Current launch at login status
    public private(set) var isEnabled: Bool = false

    /// Last error encountered (user-visible)
    public private(set) var lastError: LaunchAtLoginError?

    /// Whether checking/updating status is in progress
    public private(set) var isUpdating: Bool = false

    /// SMAppService instance for the main app
    private let appService: SMAppService

    public init() {
        self.appService = SMAppService.mainApp
        // Synchronously read initial status
        self.isEnabled = (appService.status == .enabled)
    }

    /// For testing: inject a custom service
    internal init(appService: SMAppService) {
        self.appService = appService
        self.isEnabled = (appService.status == .enabled)
    }

    // MARK: - Public API

    /// Toggle launch at login on or off
    public func setEnabled(_ enabled: Bool) {
        guard !isUpdating else { return }

        isUpdating = true
        lastError = nil

        do {
            if enabled {
                try appService.register()
            } else {
                try appService.unregister()
            }
            // Update status after successful operation
            isEnabled = enabled
        } catch {
            // Map error to user-friendly message
            let serviceError = error as NSError
            let reason = serviceError.localizedDescription

            if enabled {
                lastError = .registrationFailed(reason)
            } else {
                lastError = .unregistrationFailed(reason)
            }
        }

        isUpdating = false
    }

    /// Refresh status from system
    public func refreshStatus() {
        let status = appService.status
        isEnabled = (status == .enabled)

        // Clear error if status was successfully checked and matches expected
        if lastError != nil {
            lastError = nil
        }
    }

    /// Clear the last error
    public func clearError() {
        lastError = nil
    }

    /// Get human-readable status string
    public var statusDescription: String {
        let status = appService.status
        switch status {
        case .notRegistered:
            return "Not registered"
        case .enabled:
            return "Enabled"
        case .requiresApproval:
            return "Requires approval in System Settings"
        case .notFound:
            return "App not found"
        @unknown default:
            return "Unknown status"
        }
    }
}
