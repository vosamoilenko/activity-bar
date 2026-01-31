import Foundation

/// Heatmap range options for display
/// ACTIVITY-025: User can configure default heatmap range
public enum HeatmapRange: String, CaseIterable, Sendable, Codable {
    case days90 = "90d"
    case days180 = "180d"
    case days365 = "365d"

    /// Number of days in this range
    public var days: Int {
        switch self {
        case .days90: return 90
        case .days180: return 180
        case .days365: return 365
        }
    }

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .days90: return "90 Days"
        case .days180: return "180 Days"
        case .days365: return "365 Days"
        }
    }
}

/// Panel blur material options
/// Maps to NSVisualEffectView.Material
public enum PanelBlurMaterial: String, CaseIterable, Sendable, Codable {
    case none = "none"
    case titlebar = "titlebar"
    case menu = "menu"
    case popover = "popover"
    case sidebar = "sidebar"
    case headerView = "headerView"
    case sheet = "sheet"
    case windowBackground = "windowBackground"
    case hudWindow = "hudWindow"
    case fullScreenUI = "fullScreenUI"
    case underWindowBackground = "underWindowBackground"

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .none: return "None (Solid)"
        case .titlebar: return "Title Bar"
        case .menu: return "Menu"
        case .popover: return "Popover"
        case .sidebar: return "Sidebar"
        case .headerView: return "Header"
        case .sheet: return "Sheet"
        case .windowBackground: return "Window Background"
        case .hudWindow: return "HUD Window (Default)"
        case .fullScreenUI: return "Full Screen UI"
        case .underWindowBackground: return "Under Window"
        }
    }

    /// Description of the blur effect
    public var description: String {
        switch self {
        case .none: return "No blur effect, solid background"
        case .titlebar: return "Title bar style blur"
        case .menu: return "Menu style, medium blur"
        case .popover: return "Popover style, light blur"
        case .sidebar: return "Sidebar style blur"
        case .headerView: return "Header style blur"
        case .sheet: return "Sheet style blur"
        case .windowBackground: return "Window background, light blur"
        case .hudWindow: return "HUD window, medium dark blur"
        case .fullScreenUI: return "Full screen UI, heavy blur"
        case .underWindowBackground: return "Under window, subtle blur"
        }
    }
}

#if canImport(AppKit)
import AppKit

extension PanelBlurMaterial {
    /// Convert to NSVisualEffectView.Material
    public func toNSMaterial() -> NSVisualEffectView.Material {
        switch self {
        case .none: return .windowBackground
        case .titlebar: return .titlebar
        case .menu: return .menu
        case .popover: return .popover
        case .sidebar: return .sidebar
        case .headerView: return .headerView
        case .sheet: return .sheet
        case .windowBackground: return .windowBackground
        case .hudWindow: return .hudWindow
        case .fullScreenUI: return .fullScreenUI
        case .underWindowBackground: return .underWindowBackground
        }
    }
}
#endif

/// First day of the week for heatmap display
public enum WeekStartDay: String, CaseIterable, Sendable, Codable {
    case saturday = "saturday"
    case sunday = "sunday"
    case monday = "monday"

    /// Human-readable display name
    public var displayName: String {
        switch self {
        case .saturday: return "Saturday"
        case .sunday: return "Sunday"
        case .monday: return "Monday"
        }
    }

    /// Calendar weekday value (1 = Sunday in Gregorian calendar)
    public var weekdayValue: Int {
        switch self {
        case .sunday: return 1
        case .monday: return 2
        case .saturday: return 7
        }
    }
}

/// User preferences model with schema versioning
/// ACTIVITY-025: Settings persisted locally with schema versioning
public struct UserPreferences: Codable, Sendable, Equatable {
    /// Schema version for migration support
    public static let currentSchemaVersion = 7

    /// Schema version stored with the data
    public var schemaVersion: Int

    // MARK: - Display Preferences

    /// Default heatmap range
    public var heatmapRange: HeatmapRange

    /// Whether to show meeting activities
    public var showMeetings: Bool

    /// Whether to show all-day calendar events
    public var showAllDayEvents: Bool

    /// Whether to show event author/owner (for debugging)
    public var showEventAuthor: Bool

    // MARK: - Calendar Preferences

    /// First day of the week for heatmap display
    public var weekStartDay: WeekStartDay

    // MARK: - Refresh Preferences

    /// Refresh interval (stored separately for persistence)
    public var refreshInterval: RefreshInterval

    // MARK: - Appearance Preferences

    /// Panel blur material
    public var panelBlurMaterial: PanelBlurMaterial

    /// Panel transparency (0.0 = fully transparent, 1.0 = fully opaque)
    public var panelTransparency: Double

    // MARK: - Initialization

    public init(
        schemaVersion: Int = currentSchemaVersion,
        heatmapRange: HeatmapRange = .days90,
        showMeetings: Bool = true,
        showAllDayEvents: Bool = true,
        showEventAuthor: Bool = true,
        weekStartDay: WeekStartDay = .sunday,
        refreshInterval: RefreshInterval = .fifteenMinutes,
        panelBlurMaterial: PanelBlurMaterial = .hudWindow,
        panelTransparency: Double = 0.95
    ) {
        self.schemaVersion = schemaVersion
        self.heatmapRange = heatmapRange
        self.showMeetings = showMeetings
        self.showAllDayEvents = showAllDayEvents
        self.showEventAuthor = showEventAuthor
        self.weekStartDay = weekStartDay
        self.refreshInterval = refreshInterval
        self.panelBlurMaterial = panelBlurMaterial
        self.panelTransparency = panelTransparency
    }

    /// Default preferences
    public static let defaults = UserPreferences()
}

/// Manages loading and saving user preferences
/// ACTIVITY-025: Settings persisted locally with schema versioning
@MainActor
@Observable
public final class PreferencesManager {
    /// Current user preferences
    public var preferences: UserPreferences {
        didSet {
            save()
        }
    }

    /// Storage key for UserDefaults
    private let storageKey = "com.activitybar.userPreferences"

    /// UserDefaults instance
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.preferences = Self.load(from: defaults, key: "com.activitybar.userPreferences")
    }

    // MARK: - Persistence

    /// Load preferences from storage
    private static func load(from defaults: UserDefaults, key: String) -> UserPreferences {
        guard let data = defaults.data(forKey: key) else {
            return .defaults
        }

        do {
            var prefs = try JSONDecoder().decode(UserPreferences.self, from: data)

            // Migrate if needed
            if prefs.schemaVersion < UserPreferences.currentSchemaVersion {
                prefs = migrate(prefs)
            }

            return prefs
        } catch {
            // On decode failure, return defaults
            return .defaults
        }
    }

    /// Save preferences to storage
    private func save() {
        do {
            let data = try JSONEncoder().encode(preferences)
            defaults.set(data, forKey: storageKey)
        } catch {
            // Silently fail - preferences will be lost but app continues
        }
    }

    /// Migrate preferences from older schema versions
    private static func migrate(_ old: UserPreferences) -> UserPreferences {
        var migrated = old

        // Migration from version 1 to 2: add showAllDayEvents
        if old.schemaVersion < 2 {
            migrated.showAllDayEvents = true  // Default to showing all-day events
        }

        // Migration from version 3 to 4: add weekStartDay
        if old.schemaVersion < 4 {
            migrated.weekStartDay = .sunday  // Default to Sunday (traditional calendar)
        }

        // Migration from version 4 to 5: add panel appearance settings
        if old.schemaVersion < 5 {
            migrated.panelBlurMaterial = .hudWindow  // Default to HUD window blur
            migrated.panelTransparency = 0.95  // Default to 95% opaque
        }

        // Migration from version 6 to 7: add showEventAuthor
        if old.schemaVersion < 7 {
            migrated.showEventAuthor = true  // Default to showing author
        }

        migrated.schemaVersion = UserPreferences.currentSchemaVersion
        return migrated
    }

    /// Reset preferences to defaults
    public func resetToDefaults() {
        preferences = .defaults
    }

    // MARK: - Convenience Accessors

    /// Heatmap range preference
    public var heatmapRange: HeatmapRange {
        get { preferences.heatmapRange }
        set {
            preferences.heatmapRange = newValue
            save()
        }
    }

    /// Show meetings preference
    public var showMeetings: Bool {
        get { preferences.showMeetings }
        set {
            preferences.showMeetings = newValue
            save()
        }
    }

    /// Refresh interval preference
    public var refreshInterval: RefreshInterval {
        get { preferences.refreshInterval }
        set {
            preferences.refreshInterval = newValue
            save()
        }
    }

    /// Show all-day events preference
    public var showAllDayEvents: Bool {
        get { preferences.showAllDayEvents }
        set {
            preferences.showAllDayEvents = newValue
            save()
        }
    }

    /// Week start day preference
    public var weekStartDay: WeekStartDay {
        get { preferences.weekStartDay }
        set {
            preferences.weekStartDay = newValue
            save()
        }
    }

    /// Panel blur material preference
    public var panelBlurMaterial: PanelBlurMaterial {
        get { preferences.panelBlurMaterial }
        set {
            preferences.panelBlurMaterial = newValue
            save()
        }
    }

    /// Panel transparency preference (0.0-1.0)
    public var panelTransparency: Double {
        get { preferences.panelTransparency }
        set {
            preferences.panelTransparency = newValue
            save()
        }
    }

    /// Show event author preference (for debugging)
    public var showEventAuthor: Bool {
        get { preferences.showEventAuthor }
        set {
            preferences.showEventAuthor = newValue
            save()
        }
    }
}
