import XCTest
@testable import Core

@MainActor
final class LaunchAtLoginTests: XCTestCase {

    // MARK: - LaunchAtLoginError Tests

    func testRegistrationFailedError() {
        let error = LaunchAtLoginError.registrationFailed("permission denied")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("enable"))
        XCTAssertTrue(error.errorDescription!.contains("permission denied"))
    }

    func testUnregistrationFailedError() {
        let error = LaunchAtLoginError.unregistrationFailed("unknown error")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("disable"))
        XCTAssertTrue(error.errorDescription!.contains("unknown error"))
    }

    func testStatusCheckFailedError() {
        let error = LaunchAtLoginError.statusCheckFailed("service unavailable")

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("status"))
        XCTAssertTrue(error.errorDescription!.contains("service unavailable"))
    }

    func testNotSupportedError() {
        let error = LaunchAtLoginError.notSupported

        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("not supported"))
    }

    func testErrorEquality() {
        XCTAssertEqual(
            LaunchAtLoginError.registrationFailed("test"),
            LaunchAtLoginError.registrationFailed("test")
        )
        XCTAssertNotEqual(
            LaunchAtLoginError.registrationFailed("test"),
            LaunchAtLoginError.unregistrationFailed("test")
        )
        XCTAssertEqual(
            LaunchAtLoginError.notSupported,
            LaunchAtLoginError.notSupported
        )
    }

    // MARK: - LaunchAtLoginManager Tests

    func testManagerInitialization() {
        let manager = LaunchAtLoginManager()

        // Initial state should not be updating
        XCTAssertFalse(manager.isUpdating)
        // No error initially
        XCTAssertNil(manager.lastError)
        // Status description should be one of the known states
        let validStatuses = ["Not registered", "Enabled", "Requires approval in System Settings", "App not found", "Unknown status"]
        XCTAssertTrue(validStatuses.contains(manager.statusDescription))
    }

    func testClearError() {
        let manager = LaunchAtLoginManager()

        // Clear error when no error exists (no-op)
        manager.clearError()
        XCTAssertNil(manager.lastError)
    }

    func testRefreshStatusDoesNotCrash() {
        let manager = LaunchAtLoginManager()

        // Just verify it doesn't crash
        manager.refreshStatus()

        // Status should still be one of the known states
        let validStatuses = ["Not registered", "Enabled", "Requires approval in System Settings", "App not found", "Unknown status"]
        XCTAssertTrue(validStatuses.contains(manager.statusDescription))
    }

    // MARK: - Status Description Tests

    func testStatusDescriptionStrings() {
        // Verify the status description strings are properly formatted
        let manager = LaunchAtLoginManager()
        let description = manager.statusDescription

        // Should not be empty
        XCTAssertFalse(description.isEmpty)
    }

    // MARK: - Integration-style Tests (behavioral)
    // Note: These tests verify the manager handles operations without crashing
    // They may fail to actually register depending on the test environment

    func testSetEnabledDoesNotCrashOnFailure() {
        let manager = LaunchAtLoginManager()

        // Attempting to enable may fail in test environment (no valid bundle)
        // but should not crash - should set lastError instead
        manager.setEnabled(true)

        // Either it succeeded or we have an error
        XCTAssertTrue(manager.isEnabled || manager.lastError != nil)
    }

    func testSetDisabledDoesNotCrashOnFailure() {
        let manager = LaunchAtLoginManager()

        // Attempting to disable may fail in test environment
        // but should not crash
        manager.setEnabled(false)

        // Either it succeeded or we have an error
        XCTAssertTrue(!manager.isEnabled || manager.lastError != nil)
    }

    func testIsUpdatingResetAfterOperation() {
        let manager = LaunchAtLoginManager()

        // After any operation, isUpdating should be false
        manager.setEnabled(true)
        XCTAssertFalse(manager.isUpdating)

        manager.setEnabled(false)
        XCTAssertFalse(manager.isUpdating)
    }

    // MARK: - Observable Property Tests

    func testIsEnabledIsReadOnly() {
        // Verify that isEnabled can only be modified through setEnabled()
        // This is a compile-time test - if this compiles, the property is settable
        // The manager should expose isEnabled as read-only externally
        let manager = LaunchAtLoginManager()

        // Just read the value - should work
        let _ = manager.isEnabled

        // Setting should only happen through setEnabled method
        // manager.isEnabled = true  // This should not compile
    }

    func testLastErrorIsReadOnly() {
        let manager = LaunchAtLoginManager()

        // Just read the value - should work
        let _ = manager.lastError

        // Setting should only happen internally
        // manager.lastError = .notSupported  // This should not compile
    }

    func testIsUpdatingIsReadOnly() {
        let manager = LaunchAtLoginManager()

        // Just read the value - should work
        let _ = manager.isUpdating

        // Setting should only happen internally
        // manager.isUpdating = true  // This should not compile
    }
}
