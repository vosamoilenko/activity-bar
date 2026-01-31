# Development Guide

This document provides instructions for developing and contributing to ActivityBar.

## Table of Contents

- [Prerequisites](#prerequisites)
- [Getting Started](#getting-started)
- [Project Structure](#project-structure)
- [Building](#building)
- [Running](#running)
- [Testing](#testing)
- [Debugging](#debugging)
- [Code Style](#code-style)
- [Common Tasks](#common-tasks)

## Prerequisites

### Required Software

- **macOS 13.0+** (Ventura or later)
- **Xcode 15+** with Command Line Tools
- **Swift 5.9+**

### Optional

- **Visual Studio Code** with Swift extension for editing
- **SwiftLint** for linting (optional but recommended)

### Verify Installation

```bash
# Check Swift version
swift --version
# Swift version 5.9 or higher

# Check Xcode
xcodebuild -version
# Xcode 15.0 or higher
```

## Getting Started

### Clone the Repository

```bash
git clone https://github.com/yourusername/activity-bar.git
cd activity-bar
```

### Set Up OAuth Credentials

For testing with real providers, you'll need OAuth credentials:

1. Copy the example environment file:
   ```bash
   cp .env.example .env
   ```

2. Edit `.env` with your OAuth credentials (see [Configuration Guide](configuration.md#oauth-credentials-development))

3. Load environment variables before running:
   ```bash
   export $(cat .env | xargs)
   ```

### Open in Xcode

```bash
cd ActivityBarApp
open Package.swift
```

Xcode will resolve package dependencies automatically.

## Project Structure

```
activity-bar/
├── .env.example              # Example environment variables
├── README.md                 # Project readme
├── docs/                     # Documentation
│   ├── architecture.md
│   ├── providers.md
│   ├── configuration.md
│   ├── development.md        # This file
│   └── ui-components.md
├── ActivityBarApp/           # Main Swift application
│   ├── Package.swift         # Swift package manifest
│   ├── Sources/
│   │   ├── App/              # UI layer (SwiftUI views)
│   │   ├── Core/             # Business logic
│   │   ├── Providers/        # Provider integrations
│   │   └── Storage/          # Persistence layer
│   └── Tests/
│       ├── AppTests/         # UI component tests
│       ├── CoreTests/        # Core logic tests
│       ├── ProvidersTests/   # Provider tests
│       └── StorageTests/     # Storage tests
└── activity-discovery/       # TypeScript schema module
    ├── package.json
    ├── providers/            # Provider implementations
    ├── schemas/              # Type definitions
    └── tests/                # Tests
```

## Building

### Command Line

```bash
cd ActivityBarApp

# Debug build
swift build

# Release build
swift build -c release

# Clean build
swift package clean
swift build
```

### Xcode

1. Open `Package.swift` in Xcode
2. Select the `ActivityBarApp` scheme
3. Press `Cmd+B` to build

### Build Artifacts

- Debug: `.build/debug/ActivityBarApp`
- Release: `.build/release/ActivityBarApp`

## Running

### From Command Line

```bash
cd ActivityBarApp

# Run debug build
swift run ActivityBarApp

# Run with environment variables
export $(cat ../.env | xargs) && swift run ActivityBarApp
```

### From Xcode

1. Select `ActivityBarApp` scheme
2. Press `Cmd+R` to run
3. The app icon appears in the menu bar

### Accessing the App

- **Left-click** the menu bar icon to open the activity panel
- **Right-click** for the context menu (Settings, Quit)

## Testing

### Run All Tests

```bash
cd ActivityBarApp
swift test
```

### Run Specific Test Suite

```bash
# Run only Core tests
swift test --filter CoreTests

# Run only Provider tests
swift test --filter ProvidersTests

# Run a specific test class
swift test --filter DataCoordinatorTests

# Run a specific test method
swift test --filter "DataCoordinatorTests.testLoadFromCache"
```

### Run Tests in Xcode

1. Open `Package.swift` in Xcode
2. Press `Cmd+U` to run all tests
3. Use the Test navigator (Cmd+6) to run specific tests

### Test Coverage

```bash
# Generate coverage report
swift test --enable-code-coverage

# View coverage
xcrun llvm-cov report .build/debug/ActivityBarAppPackageTests.xctest/Contents/MacOS/ActivityBarAppPackageTests -instr-profile=.build/debug/codecov/default.profdata
```

### Writing Tests

Tests are organized by layer:

```
Tests/
├── AppTests/           # UI component tests
│   ├── ActivityRowViewTests.swift
│   ├── HeatmapViewTests.swift
│   └── ...
├── CoreTests/          # Business logic tests
│   ├── AppStateTests.swift
│   ├── DataCoordinatorTests.swift
│   └── ...
├── ProvidersTests/     # Provider adapter tests
│   ├── ProvidersTests.swift
│   └── TokenRefreshServiceTests.swift
└── StorageTests/       # Cache and storage tests
    ├── StorageTests.swift
    └── ProjectStoreTests.swift
```

**Example test:**

```swift
import XCTest
@testable import ActivityBarApp

final class DataCoordinatorTests: XCTestCase {
    var coordinator: DataCoordinator!
    var mockCache: MockActivityCache!
    var mockProvider: MockRefreshProvider!

    override func setUp() {
        super.setUp()
        mockCache = MockActivityCache()
        mockProvider = MockRefreshProvider()
        coordinator = DataCoordinator(
            cache: mockCache,
            provider: mockProvider
        )
    }

    func testLoadFromCache() async throws {
        // Given
        mockCache.stubbedActivities = [testActivity]

        // When
        await coordinator.loadFromCache()

        // Then
        XCTAssertTrue(coordinator.cacheLoadComplete)
        XCTAssertEqual(coordinator.activities.count, 1)
    }
}
```

## Debugging

### Xcode Debugger

1. Set breakpoints by clicking the gutter
2. Run with `Cmd+R`
3. Use the debug navigator to inspect variables

### Console Logging

The app uses `os.log` for structured logging:

```swift
import os.log

private let logger = Logger(subsystem: "com.activitybar", category: "DataCoordinator")

logger.debug("Loading cache for \(accountId)")
logger.error("Failed to fetch: \(error.localizedDescription)")
```

View logs in Console.app or with:

```bash
log stream --predicate 'subsystem == "com.activitybar"' --level debug
```

### Network Debugging

For debugging API requests:

1. **Charles Proxy** - Intercept HTTPS traffic
2. **Console.app** - View URLSession logs
3. Add request/response logging in `HTTPClient`:

```swift
#if DEBUG
logger.debug("Request: \(request.url?.absoluteString ?? "")")
logger.debug("Response: \(String(data: data, encoding: .utf8) ?? "")")
#endif
```

### Cache Debugging

Inspect cached data:

```bash
# View accounts
cat ~/Library/Caches/com.activitybar/accounts.json | jq

# View day index
cat ~/Library/Caches/com.activitybar/day_index.json | jq

# View activities for a day
cat ~/Library/Caches/com.activitybar/activities/{accountId}/2024-01-15.json | jq
```

### Keychain Debugging

View stored tokens (requires Keychain Access.app):

1. Open Keychain Access
2. Search for "com.activitybar"
3. View/delete stored credentials

Or use command line:

```bash
security find-generic-password -s "com.activitybar" -a "{accountId}"
```

## Code Style

### Swift Style Guidelines

- Use Swift's official API Design Guidelines
- Prefer explicit types for public APIs
- Use `async/await` for asynchronous code
- Use actors for thread-safe shared state
- Use `@MainActor` for UI-related code

### File Organization

Each file should follow this structure:

```swift
// 1. Imports (alphabetical)
import Foundation
import SwiftUI

// 2. MARK comments for sections
// MARK: - Types

// 3. Public types first
public struct MyPublicType { }

// MARK: - Private Types

// 4. Private/internal types
private struct InternalType { }

// MARK: - Extensions

// 5. Extensions at the end
extension MyPublicType { }
```

### Naming Conventions

| Type | Convention | Example |
|------|------------|---------|
| Types | PascalCase | `UnifiedActivity` |
| Functions | camelCase | `fetchActivities()` |
| Variables | camelCase | `isRefreshing` |
| Constants | camelCase | `maxRetries` |
| Protocols | PascalCase + -able/-ible/-ing | `RefreshProvider` |

### Documentation

Use DocC-style comments for public APIs:

```swift
/// Fetches activities for the specified account.
///
/// - Parameters:
///   - account: The account to fetch activities for
///   - from: Start date of the range
///   - to: End date of the range
/// - Returns: Array of unified activities
/// - Throws: `ProviderError` if the request fails
public func fetchActivities(
    for account: Account,
    from: Date,
    to: Date
) async throws -> [UnifiedActivity]
```

## Common Tasks

### Adding a New Activity Type

1. Add the case to `ActivityType` in `Types.swift`:
   ```swift
   public enum ActivityType: String, Codable {
       // ...existing cases
       case newType
   }
   ```

2. Update `displayName` and `iconName` computed properties

3. If needed, create a new activity view:
   ```swift
   struct NewTypeActivityView: View {
       let activity: UnifiedActivity
       var body: some View { ... }
   }
   ```

4. Update `ActivityListView` to handle the new type

### Adding a New Provider

See [Providers Guide - Adding New Providers](providers.md#adding-new-providers)

### Adding a New Setting

1. Add the property to `PreferencesManager`:
   ```swift
   @AppStorage("newSetting") public var newSetting: Bool = false
   ```

2. Add UI in `SettingsView`:
   ```swift
   Toggle("New Setting", isOn: $preferences.newSetting)
   ```

3. Use the setting where needed:
   ```swift
   if preferencesManager.newSetting { ... }
   ```

### Updating the Cache Schema

If changing cached data structures:

1. Update the relevant `Codable` struct
2. Consider migration for existing caches
3. Update tests
4. Increment cache version if breaking change

### Adding Tests

1. Create test file in appropriate `Tests/` subdirectory
2. Import the module with `@testable`:
   ```swift
   @testable import ActivityBarApp
   ```
3. Create mock dependencies as needed
4. Write test methods prefixed with `test`

### Creating a Release Build

```bash
cd ActivityBarApp

# Build release
swift build -c release

# Create app bundle (if not using Xcode archive)
# The pre-built app bundle is at ActivityBarApp.app/
```

For distribution:
1. Archive in Xcode: Product → Archive
2. Sign with Developer ID
3. Notarize with Apple
4. Export for distribution

## Troubleshooting Development Issues

### Package Resolution Fails

```bash
swift package reset
swift package resolve
```

### Build Errors After Xcode Update

```bash
# Clean derived data
rm -rf ~/Library/Developer/Xcode/DerivedData

# Reset package cache
swift package reset
```

### OAuth Not Working

1. Check environment variables are set
2. Verify callback URLs match OAuth app configuration
3. Check Console.app for OAuth-related errors

### Tests Timing Out

For async tests, increase timeout or mock network calls:

```swift
func testAsyncOperation() async throws {
    // Use expectations with longer timeout
    let expectation = expectation(description: "operation completes")

    // Or mock the network layer
    mockProvider.stubbedResult = testData
}
```
