import Foundation

/// Refresh interval options
/// ACTIVITY-024: Configurable refresh frequency
public enum RefreshInterval: String, CaseIterable, Sendable, Codable {
    case fiveMinutes = "5m"
    case fifteenMinutes = "15m"
    case thirtyMinutes = "30m"
    case oneHour = "1h"
    case manual = "manual"

    /// Interval in seconds (nil for manual)
    public var seconds: TimeInterval? {
        switch self {
        case .fiveMinutes: return 5 * 60
        case .fifteenMinutes: return 15 * 60
        case .thirtyMinutes: return 30 * 60
        case .oneHour: return 60 * 60
        case .manual: return nil
        }
    }

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .fiveMinutes: return "5 minutes"
        case .fifteenMinutes: return "15 minutes"
        case .thirtyMinutes: return "30 minutes"
        case .oneHour: return "1 hour"
        case .manual: return "Manual only"
        }
    }
}

/// Manages periodic refresh scheduling and manual refresh triggers
/// ACTIVITY-024: Refresh scheduler and background updates
@MainActor
@Observable
public final class RefreshScheduler {
    /// Current refresh interval setting
    public var interval: RefreshInterval {
        didSet {
            // Restart timer when interval changes
            restartTimer()
        }
    }

    /// Whether a refresh is currently in progress
    public private(set) var isRefreshing: Bool = false

    /// Last successful refresh timestamp
    public private(set) var lastRefreshed: Date?

    /// Error from last refresh attempt (nil if successful)
    public private(set) var lastError: String?

    /// Debounce window (minimum time between refresh triggers)
    public let debounceInterval: TimeInterval

    /// Callback invoked when refresh should happen
    private let onRefresh: () async -> Void

    /// Internal timer for scheduled refreshes
    private var timer: Timer?

    /// Timestamp of last refresh trigger (for debouncing)
    private var lastTriggerTime: Date?

    /// Track if scheduler is active
    public private(set) var isActive: Bool = false

    /// Initialize scheduler with refresh callback
    /// - Parameters:
    ///   - interval: Initial refresh interval (default: 15 minutes)
    ///   - debounceInterval: Minimum time between triggers (default: 30 seconds)
    ///   - onRefresh: Async callback invoked when refresh should occur
    public init(
        interval: RefreshInterval = .fifteenMinutes,
        debounceInterval: TimeInterval = 30,
        onRefresh: @escaping () async -> Void
    ) {
        self.interval = interval
        self.debounceInterval = debounceInterval
        self.onRefresh = onRefresh
    }

    // MARK: - Lifecycle

    /// Start the scheduler (begins timer if interval is not manual)
    public func start() {
        guard !isActive else { return }
        isActive = true
        startTimerIfNeeded()
    }

    /// Stop the scheduler (cancels timer)
    public func stop() {
        isActive = false
        stopTimer()
    }

    // MARK: - Refresh Control

    /// Trigger a refresh (manual or from timer)
    /// Debounces rapid successive calls
    public func triggerRefresh() {
        print("[ActivityBar][RefreshScheduler] triggerRefresh called")

        // Check debounce
        if let lastTrigger = lastTriggerTime,
           Date().timeIntervalSince(lastTrigger) < debounceInterval {
            print("[ActivityBar][RefreshScheduler] Debounced - too soon since last trigger")
            return
        }

        // Check if already refreshing
        guard !isRefreshing else {
            print("[ActivityBar][RefreshScheduler] Already refreshing, skipping")
            return
        }

        print("[ActivityBar][RefreshScheduler] Starting refresh...")
        lastTriggerTime = Date()
        performRefresh()
    }

    /// Force a refresh, bypassing debounce (for user-initiated actions)
    public func forceRefresh() {
        print("[ActivityBar][RefreshScheduler] forceRefresh called")
        guard !isRefreshing else {
            print("[ActivityBar][RefreshScheduler] Already refreshing, skipping force refresh")
            return
        }

        print("[ActivityBar][RefreshScheduler] Force starting refresh...")
        lastTriggerTime = Date()
        performRefresh()
    }

    // MARK: - Internal

    private func performRefresh() {
        print("[ActivityBar][RefreshScheduler] performRefresh called")
        isRefreshing = true
        lastError = nil

        Task { @MainActor in
            print("[ActivityBar][RefreshScheduler] Calling onRefresh closure...")
            do {
                // Timeout for priority refresh (today + yesterday)
                // Background fetch of older days runs separately and is not affected
                try await withTimeout(seconds: 60) { [onRefresh] in
                    await onRefresh()
                }
                print("[ActivityBar][RefreshScheduler] onRefresh completed successfully")
                self.lastRefreshed = Date()
                self.lastError = nil
            } catch {
                print("[ActivityBar][RefreshScheduler] onRefresh failed: \(error)")
                self.lastError = error.localizedDescription
            }
            self.isRefreshing = false
            print("[ActivityBar][RefreshScheduler] Refresh done, isRefreshing = false")
        }
    }

    private func startTimerIfNeeded() {
        guard isActive else { return }
        guard let seconds = interval.seconds else {
            // Manual mode - no timer
            return
        }

        stopTimer()

        timer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.triggerRefresh()
            }
        }

        // Also ensure timer fires on common run loop modes
        if let timer = timer {
            RunLoop.main.add(timer, forMode: .common)
        }
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
    }

    private func restartTimer() {
        if isActive {
            stopTimer()
            startTimerIfNeeded()
        }
    }

    // MARK: - Status

    /// Time until next scheduled refresh (nil for manual or if not active)
    public var timeUntilNextRefresh: TimeInterval? {
        guard isActive,
              let seconds = interval.seconds,
              let lastTrigger = lastTriggerTime else {
            return nil
        }
        let elapsed = Date().timeIntervalSince(lastTrigger)
        let remaining = seconds - elapsed
        return remaining > 0 ? remaining : 0
    }

    /// Human-readable status for UI
    public var statusDescription: String {
        if isRefreshing {
            return "Refreshing..."
        }
        if let error = lastError {
            return "Error: \(error)"
        }
        if let lastRefreshed = lastRefreshed {
            let formatter = RelativeDateTimeFormatter()
            formatter.unitsStyle = .abbreviated
            return "Updated \(formatter.localizedString(for: lastRefreshed, relativeTo: Date()))"
        }
        return "Not yet refreshed"
    }
}

// MARK: - Timeout Helper

/// Execute an async operation with a timeout
private func withTimeout<T>(
    seconds: TimeInterval,
    operation: @escaping () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask {
            try await operation()
        }

        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw RefreshTimeoutError()
        }

        guard let result = try await group.next() else {
            throw RefreshTimeoutError()
        }

        group.cancelAll()
        return result
    }
}

/// Error thrown when refresh times out
struct RefreshTimeoutError: LocalizedError {
    var errorDescription: String? {
        "Refresh timed out"
    }
}
