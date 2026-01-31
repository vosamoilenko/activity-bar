import XCTest
@testable import Core

@MainActor
final class UserPreferencesTests: XCTestCase {

    // MARK: - HeatmapRange Tests

    func testHeatmapRangeDays() {
        XCTAssertEqual(HeatmapRange.days90.days, 90)
        XCTAssertEqual(HeatmapRange.days180.days, 180)
        XCTAssertEqual(HeatmapRange.days365.days, 365)
    }

    func testHeatmapRangeDisplayNames() {
        XCTAssertEqual(HeatmapRange.days90.displayName, "90 Days")
        XCTAssertEqual(HeatmapRange.days180.displayName, "180 Days")
        XCTAssertEqual(HeatmapRange.days365.displayName, "365 Days")
    }

    func testHeatmapRangeRawValues() {
        XCTAssertEqual(HeatmapRange.days90.rawValue, "90d")
        XCTAssertEqual(HeatmapRange.days180.rawValue, "180d")
        XCTAssertEqual(HeatmapRange.days365.rawValue, "365d")
    }

    func testHeatmapRangeCodable() throws {
        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        for range in HeatmapRange.allCases {
            let data = try encoder.encode(range)
            let decoded = try decoder.decode(HeatmapRange.self, from: data)
            XCTAssertEqual(decoded, range)
        }
    }

    // MARK: - UserPreferences Tests

    func testUserPreferencesDefaults() {
        let defaults = UserPreferences.defaults

        XCTAssertEqual(defaults.schemaVersion, UserPreferences.currentSchemaVersion)
        XCTAssertEqual(defaults.heatmapRange, .days90)
        XCTAssertTrue(defaults.showMeetings)
        XCTAssertEqual(defaults.refreshInterval, .fifteenMinutes)
    }

    func testUserPreferencesInit() {
        let prefs = UserPreferences(
            heatmapRange: .days365,
            showMeetings: false,
            refreshInterval: .oneHour
        )

        XCTAssertEqual(prefs.heatmapRange, .days365)
        XCTAssertFalse(prefs.showMeetings)
        XCTAssertEqual(prefs.refreshInterval, .oneHour)
    }

    func testUserPreferencesCodable() throws {
        let original = UserPreferences(
            heatmapRange: .days180,
            showMeetings: false,
            refreshInterval: .thirtyMinutes
        )

        let encoder = JSONEncoder()
        let decoder = JSONDecoder()

        let data = try encoder.encode(original)
        let decoded = try decoder.decode(UserPreferences.self, from: data)

        XCTAssertEqual(decoded, original)
    }

    func testUserPreferencesEquality() {
        let prefs1 = UserPreferences.defaults
        let prefs2 = UserPreferences.defaults

        XCTAssertEqual(prefs1, prefs2)

        var prefs3 = UserPreferences.defaults
        prefs3.showMeetings = false

        XCTAssertNotEqual(prefs1, prefs3)
    }

    // MARK: - PreferencesManager Tests

    func testPreferencesManagerInitWithDefaults() {
        let testDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let manager = PreferencesManager(defaults: testDefaults)

        XCTAssertEqual(manager.preferences, .defaults)
    }

    func testPreferencesManagerPersistence() {
        let testDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let manager = PreferencesManager(defaults: testDefaults)

        // Modify preferences
        manager.heatmapRange = .days365
        manager.showMeetings = false

        // Create new manager with same defaults
        let manager2 = PreferencesManager(defaults: testDefaults)

        XCTAssertEqual(manager2.heatmapRange, .days365)
        XCTAssertFalse(manager2.showMeetings)
    }

    func testPreferencesManagerResetToDefaults() {
        let testDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let manager = PreferencesManager(defaults: testDefaults)

        // Modify preferences
        manager.heatmapRange = .days365
        manager.showMeetings = false

        // Reset
        manager.resetToDefaults()

        XCTAssertEqual(manager.preferences, .defaults)
    }

    func testPreferencesManagerConvenienceAccessors() {
        let testDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let manager = PreferencesManager(defaults: testDefaults)

        manager.heatmapRange = .days180
        XCTAssertEqual(manager.preferences.heatmapRange, .days180)

        manager.showMeetings = false
        XCTAssertFalse(manager.preferences.showMeetings)

        manager.refreshInterval = .oneHour
        XCTAssertEqual(manager.preferences.refreshInterval, .oneHour)
    }

    // MARK: - Schema Version Tests

    func testSchemaVersion() {
        XCTAssertEqual(UserPreferences.currentSchemaVersion, 7)

        let prefs = UserPreferences.defaults
        XCTAssertEqual(prefs.schemaVersion, 7)
    }

    // MARK: - WeekStartDay Persistence Tests

    func testWeekStartDayPersistence() {
        let testDefaults = UserDefaults(suiteName: UUID().uuidString)!
        let manager = PreferencesManager(defaults: testDefaults)

        // Verify default is Sunday
        XCTAssertEqual(manager.weekStartDay, .sunday)

        // Change to Monday
        manager.weekStartDay = .monday

        // Create new manager with same defaults to verify persistence
        let manager2 = PreferencesManager(defaults: testDefaults)
        XCTAssertEqual(manager2.weekStartDay, .monday)

        // Change to Saturday
        manager2.weekStartDay = .saturday

        // Verify with third manager
        let manager3 = PreferencesManager(defaults: testDefaults)
        XCTAssertEqual(manager3.weekStartDay, .saturday)
    }

    func testCorruptedDataFallsBackToDefaults() {
        let testDefaults = UserDefaults(suiteName: UUID().uuidString)!

        // Write corrupted data
        testDefaults.set(Data("not valid json".utf8), forKey: "com.activitybar.userPreferences")

        // Manager should load defaults
        let manager = PreferencesManager(defaults: testDefaults)
        XCTAssertEqual(manager.preferences, .defaults)
    }

    // MARK: - RefreshInterval Tests

    func testRefreshIntervalSeconds() {
        XCTAssertEqual(RefreshInterval.fiveMinutes.seconds, 5 * 60)
        XCTAssertEqual(RefreshInterval.fifteenMinutes.seconds, 15 * 60)
        XCTAssertEqual(RefreshInterval.thirtyMinutes.seconds, 30 * 60)
        XCTAssertEqual(RefreshInterval.oneHour.seconds, 60 * 60)
        XCTAssertNil(RefreshInterval.manual.seconds)
    }

    func testRefreshIntervalDisplayNames() {
        XCTAssertEqual(RefreshInterval.fiveMinutes.displayName, "5 minutes")
        XCTAssertEqual(RefreshInterval.fifteenMinutes.displayName, "15 minutes")
        XCTAssertEqual(RefreshInterval.thirtyMinutes.displayName, "30 minutes")
        XCTAssertEqual(RefreshInterval.oneHour.displayName, "1 hour")
        XCTAssertEqual(RefreshInterval.manual.displayName, "Manual only")
    }

    // MARK: - WeekStartDay Tests

    func testWeekStartDayDisplayNames() {
        XCTAssertEqual(WeekStartDay.saturday.displayName, "Saturday")
        XCTAssertEqual(WeekStartDay.sunday.displayName, "Sunday")
        XCTAssertEqual(WeekStartDay.monday.displayName, "Monday")
    }

    func testWeekStartDayWeekdayValues() {
        XCTAssertEqual(WeekStartDay.sunday.weekdayValue, 1)
        XCTAssertEqual(WeekStartDay.monday.weekdayValue, 2)
        XCTAssertEqual(WeekStartDay.saturday.weekdayValue, 7)
    }

    // MARK: - PanelBlurMaterial Tests

    func testPanelBlurMaterialDisplayNames() {
        XCTAssertEqual(PanelBlurMaterial.none.displayName, "None (Solid)")
        XCTAssertEqual(PanelBlurMaterial.hudWindow.displayName, "HUD Window (Default)")
        XCTAssertEqual(PanelBlurMaterial.sidebar.displayName, "Sidebar")
    }
}
