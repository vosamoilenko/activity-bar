import SwiftUI
import Core

/// Content view displayed when clicking the menu bar item
struct MenuBarContentView: View {
    let appState: AppState
    var refreshScheduler: RefreshScheduler?
    var preferencesManager: PreferencesManager?
    var dataCoordinator: DataCoordinator?
    var onRefresh: (() -> Void)?
    var onOpenSettings: (() -> Void)?

    /// Computed session reference for convenience
    private var session: Session { appState.session }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header - fixed at top
            HStack {
                Text("Activity")
                    .font(.headline)
                Spacer()

                // Show refresh indicator when refreshing
                if session.isRefreshing || (refreshScheduler?.isRefreshing ?? false) {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                }

                Button {
                    print("[ActivityBar] Gear clicked: opening Settings via presenter closure")
                    onOpenSettings?()
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.plain)
            }
            .padding(.bottom, 4)
            .padding(.horizontal)
            .padding(.top)

            Divider()
                .padding(.horizontal)

            // Scrollable content area
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // Heatmap view using filtered activity counts
                    // ACTIVITY-017: Range selection highlights in heatmap
                    HeatmapView(
                        buckets: filteredHeatmapBuckets,
                        selectedDate: session.selectedDate,
                        selectedRange: session.selectedRange,
                        weekStartDay: preferencesManager?.weekStartDay ?? .sunday,
                        onDateSelected: { date in
                            appState.selectDate(date)
                            // Trigger day load if not already loaded
                            let dateStr = Session.dateString(from: date)
                            if !session.isDayLoaded(dateStr) {
                                Task {
                                    await dataCoordinator?.loadDay(date)
                                }
                            }
                        }
                    )

                    Divider()

                    // Activity list header with date info
                    HStack {
                        Text(activityListTitle)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text("\(filteredActivities.count)")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }

                    // ACTIVITY-058: Activity list with state management
                    activityListContent
                }
                .padding(.horizontal)
                .padding(.vertical, 12)
            }

            // Footer - fixed at bottom
            Divider()
                .padding(.horizontal)

            HStack {
                // ACTIVITY-023: Offline mode shows cached data with indicator
                // ACTIVITY-024: Show scheduler status
                if session.isOffline {
                    HStack(spacing: 4) {
                        Image(systemName: "wifi.slash")
                            .foregroundStyle(.secondary)
                        Text("Offline")
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                } else if let scheduler = refreshScheduler {
                    Text(scheduler.statusDescription)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    Text(lastUpdatedText)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Spacer()
                Button("Refresh") {
                    onRefresh?()
                }
                .buttonStyle(.plain)
                .font(.caption)
                .disabled(session.isRefreshing || (refreshScheduler?.isRefreshing ?? false))
            }
            .padding(.horizontal)
            .padding(.bottom)
            .padding(.top, 8)
        }
        .frame(width: 320)
        .frame(maxHeight: (NSScreen.main?.visibleFrame.height ?? 800) - 50)
    }

    // MARK: - Computed Properties

    private var activityListTitle: String {
        if session.selectedRange != nil {
            return "Selected Range"
        } else {
            let formatter = DateFormatter()
            formatter.dateStyle = .medium
            formatter.timeStyle = .none
            let dateStr = formatter.string(from: session.selectedDate)
            return Calendar.current.isDateInToday(session.selectedDate)
                ? "Today's Activities"
                : dateStr
        }
    }

    private var lastUpdatedText: String {
        guard let lastRefreshed = session.lastRefreshed else {
            return "Last updated: --"
        }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated
        return "Updated \(formatter.localizedString(for: lastRefreshed, relativeTo: Date()))"
    }

    /// Filter a list of activities based on account and global preferences
    private func filterActivities(_ activities: [UnifiedActivity]) -> [UnifiedActivity] {
        var result = activities

        // Build a lookup for account settings
        let accountSettings: [String: Account] = Dictionary(
            uniqueKeysWithValues: session.accounts.map { ($0.id, $0) }
        )

        // Filter based on per-account settings
        result = result.filter { activity in
            guard let account = accountSettings[activity.accountId] else { return true }

            // Check event type filtering
            if !account.isEventTypeEnabled(activity.type) {
                return false
            }

            // Check calendar filtering for Google Calendar
            if account.provider == .googleCalendar {
                if !account.isCalendarEnabled(activity.calendarId) {
                    return false
                }
            } else {
                // Check "show only my events" filter for GitLab/Azure DevOps
                let author = activity.participants?.first
                if !account.isMyEvent(author: author) {
                    return false
                }
            }

            return true
        }

        // Apply global preferences filtering
        if let prefs = preferencesManager {
            // Filter out meetings if disabled globally
            if !prefs.showMeetings {
                result = result.filter { $0.type != .meeting }
            }

            // Filter out all-day events if disabled globally
            if !prefs.showAllDayEvents {
                result = result.filter { $0.isAllDay != true }
            }
        }

        return result
    }

    /// ACTIVITY-025: Filter activities based on preferences (e.g., hide meetings, all-day events)
    /// Also filters based on per-account event type and project/calendar settings
    private var filteredActivities: [UnifiedActivity] {
        filterActivities(session.selectedActivities)
    }

    /// Compute heatmap buckets from filtered activities (respects all filters)
    private var filteredHeatmapBuckets: [HeatMapBucket] {
        let allActivities = filterActivities(session.allActivities)

        // Group by date
        var countsByDate: [String: Int] = [:]
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd"
        dateFormatter.timeZone = TimeZone(identifier: "UTC")

        for activity in allActivities {
            let dateStr = dateFormatter.string(from: activity.timestamp)
            countsByDate[dateStr, default: 0] += 1
        }

        // Convert to buckets
        return countsByDate.map { HeatMapBucket(date: $0.key, count: $0.value) }
            .sorted { $0.date < $1.date }
    }

    /// ACTIVITY-058: Activity list content with state management
    @ViewBuilder
    private var activityListContent: some View {
        // Determine current state
        let hasAccounts = !session.accounts.isEmpty
        let hasEnabledAccounts = !session.enabledAccounts.isEmpty
        let isInitialLoad = !appState.hasLoadedFromCache
        let isRefreshing = session.isRefreshing || (refreshScheduler?.isRefreshing ?? false)
        let hasError = appState.lastError != nil
        let activities = filteredActivities

        // Check if selected day is loading
        let selectedDateStr = Session.dateString(from: session.selectedDate)
        let isDayLoading = session.isDayLoading(selectedDateStr)

        if !hasAccounts {
            // No accounts configured at all
            EmptyStateView(
                title: "No accounts connected",
                subtitle: "Open Settings to add a GitLab, Azure DevOps, or Google Calendar account."
            )
        } else if !hasEnabledAccounts {
            // Accounts exist but all are disabled
            EmptyStateView(
                title: "All accounts disabled",
                subtitle: "Enable at least one account in Settings to see activities."
            )
        } else if isInitialLoad && isRefreshing {
            // Initial load in progress
            LoadingStateView(text: "Loading activities…")
        } else if isDayLoading {
            // Selected day is being loaded
            LoadingStateView(text: "Loading \(selectedDateStr)…")
        } else if hasError && activities.isEmpty {
            // Error state with no cached data to show
            ErrorStateView(
                message: appState.lastError ?? "Failed to load activities",
                onRetry: {
                    onRefresh?()
                }
            )
        } else if activities.isEmpty {
            // No activities for selected date/range
            let dateText = session.selectedRange != nil ? "this range" : "this day"
            EmptyStateView(
                title: "No activities",
                subtitle: "No activities found for \(dateText). Try selecting a different date."
            )
        } else {
            // Normal state: show activities
            // ACTIVITY-057: Added keyboard navigation support
            // Show now indicator when viewing today's activities (single day selection only)
            let showNowIndicator = session.selectedRange == nil && Calendar.current.isDateInToday(session.selectedDate)
            ActivityListView(
                activities: Array(activities.prefix(30)),
                showNowIndicator: showNowIndicator,
                onActivityTapped: { activity in
                    // Open URL if available
                    if let url = activity.url {
                        NSWorkspace.shared.open(url)
                    }
                },
                onEscapePressed: {
                    // MenuBarExtra with window style auto-closes on Escape
                    // This callback is here for potential future use
                }
            )
            .environment(\.showEventAuthor, preferencesManager?.showEventAuthor ?? false)
            .environment(\.showEventType, preferencesManager?.showEventType ?? false)
            .environment(\.showEventBranch, preferencesManager?.showEventBranch ?? true)

            if activities.count > 30 {
                Text("+\(activities.count - 30) more activities")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 4)
            }

            // Error banner when we have cached data but refresh failed
            if let error = appState.lastError {
                CopyableErrorText(message: error, icon: "exclamationmark.triangle.fill", color: .orange)
                    .padding(.top, 4)
            }
        }
    }
}

#Preview {
    MenuBarContentView(
        appState: AppState(),
        refreshScheduler: nil,
        preferencesManager: nil,
        dataCoordinator: nil,
        onRefresh: nil,
        onOpenSettings: nil
    )
}

#Preview("With Data") {
    let appState = AppState()
    appState.session.heatmapBuckets = [
        HeatMapBucket(date: "2026-01-19", count: 5),
        HeatMapBucket(date: "2026-01-18", count: 3)
    ]
    appState.session.activitiesByAccount["test"] = [
        UnifiedActivity(
            id: "1",
            provider: .gitlab,
            accountId: "test",
            sourceId: "src1",
            type: .commit,
            timestamp: Date(),
            title: "Fix bug in login"
        ),
        UnifiedActivity(
            id: "2",
            provider: .gitlab,
            accountId: "test",
            sourceId: "src2",
            type: .pullRequest,
            timestamp: Date().addingTimeInterval(-3600),
            title: "Add new feature"
        )
    ]
    appState.session.accounts = [Account(id: "test", provider: .gitlab, displayName: "Test")]
    return MenuBarContentView(
        appState: appState,
        refreshScheduler: nil,
        preferencesManager: nil,
        dataCoordinator: nil,
        onRefresh: nil,
        onOpenSettings: nil
    )
}

#Preview("With Many Activities - Should Scroll") {
    let appState = AppState()
    appState.session.heatmapBuckets = [
        HeatMapBucket(date: "2026-01-19", count: 15),
        HeatMapBucket(date: "2026-01-18", count: 8)
    ]
    // Create 30 activities to test scrolling
    var activities: [UnifiedActivity] = []
    for i in 1...30 {
        activities.append(UnifiedActivity(
            id: "\(i)",
            provider: .gitlab,
            accountId: "test",
            sourceId: "src\(i)",
            type: i % 3 == 0 ? .pullRequest : (i % 3 == 1 ? .commit : .issue),
            timestamp: Date().addingTimeInterval(Double(-i * 3600)),
            title: "Activity item number \(i) with a longer description"
        ))
    }
    appState.session.activitiesByAccount["test"] = activities
    appState.session.accounts = [Account(id: "test", provider: .gitlab, displayName: "Test")]
    return MenuBarContentView(
        appState: appState,
        refreshScheduler: nil,
        preferencesManager: nil,
        dataCoordinator: nil,
        onRefresh: nil,
        onOpenSettings: nil
    )
}
