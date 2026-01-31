# ActivityBar

A macOS menu bar application that aggregates and displays your development activity from multiple sources in a unified dashboard.

![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-blue)
![Swift](https://img.shields.io/badge/swift-5.9%2B-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Overview

ActivityBar lives in your menu bar and shows a consolidated view of your recent development activity across GitLab, Azure DevOps, and Google Calendar. See commits, pull requests, issues, code reviews, and meetings all in one place with a visual heatmap showing your activity patterns over time.

## Features

- **Unified Activity Feed** - View commits, pull requests, issues, code reviews, and meetings from multiple providers in a single timeline
- **Activity Heatmap** - 13-week visual heatmap showing your daily activity distribution with per-provider breakdown
- **Smart Activity Grouping** - Similar activities (e.g., multiple commits to the same branch) are automatically collapsed for cleaner viewing
- **Multiple Provider Support**
  - GitLab (gitlab.com and self-hosted instances)
  - Azure DevOps
  - Google Calendar
- **OAuth Authentication** - Secure OAuth 2.0 flows for all providers with automatic token refresh
- **Offline Mode** - Gracefully degrades when network is unavailable, showing cached data
- **Keyboard Navigation** - Navigate activities with arrow keys, open with Enter
- **Per-Day Caching** - Efficient caching strategy that loads only what you need
- **Customizable Appearance** - Multiple blur materials, transparency settings, and week start preferences

## Requirements

- macOS 13.0 (Ventura) or later
- Swift 5.9+
- Xcode 15+ (for development)

## Installation

### From Source

```bash
# Clone the repository
git clone https://github.com/yourusername/activity-bar.git
cd activity-bar/ActivityBarApp

# Run directly (no Xcode required)
swift run ActivityBarApp

# Or build for release and run
swift build -c release
.build/release/ActivityBarApp

# Or open in Xcode
open Package.swift
```

### Pre-built App

Download the latest `ActivityBarApp.app` from the releases page and drag it to your Applications folder.

## Quick Start

1. **Launch ActivityBar** - The app icon appears in your menu bar
2. **Click the icon** - Opens the activity panel
3. **Add an account** - Click the gear icon → Accounts → Add Account
4. **Select a provider** - Choose GitLab, Azure DevOps, or Google Calendar
5. **Authenticate** - Complete the OAuth flow in your browser
6. **View your activity** - Activities appear in the panel, heatmap shows your patterns

## Configuration

### Adding Accounts

1. Open Settings (gear icon in the activity panel)
2. Go to the "Accounts" tab
3. Click "Add Account..."
4. Select your provider and authenticate

You can add multiple accounts from the same or different providers.

### General Settings

| Setting | Description |
|---------|-------------|
| **Refresh Interval** | How often to fetch new data (5min, 15min, 30min, 1hr, or manual) |
| **Launch at Login** | Start ActivityBar when you log in |
| **Panel Blur Material** | Visual effect behind the panel (11 options) |
| **Panel Transparency** | How transparent the panel background is |
| **Week Start Day** | First day of the week in the heatmap (Sunday or Monday) |

### Provider-Specific Configuration

#### GitLab
- Supports both gitlab.com and self-hosted instances
- Specify custom host URL for self-hosted GitLab

#### Azure DevOps
- Configure organization URL
- Optionally filter to specific projects

#### Google Calendar
- Select which calendars to monitor
- Option to show only events where you're an attendee

## Architecture

ActivityBar follows a modular architecture:

```
ActivityBarApp/
├── Sources/
│   ├── App/          # SwiftUI views and window management
│   ├── Core/         # Business logic, state management, scheduling
│   ├── Providers/    # Provider adapters, OAuth, HTTP client
│   └── Storage/      # Disk cache, keychain storage
├── Tests/            # Unit tests
└── Package.swift     # Swift package manifest
```

See [Architecture Documentation](docs/architecture.md) for detailed technical information.

## Data Model

### Activity Types

| Type | Providers | Description |
|------|-----------|-------------|
| Commit | GitLab, Azure | Code commits |
| Pull Request | GitLab, Azure | Merge/pull requests |
| Issue | GitLab, Azure | Issue tracking |
| Issue Comment | GitLab, Azure | Comments on issues |
| Code Review | GitLab, Azure | Code review feedback |
| Meeting | Google Calendar | Calendar events |
| Work Item | Azure | Azure work items |
| Deployment | Azure | Deployment events |

### Unified Activity

All activities are normalized to a common `UnifiedActivity` structure with:
- Unique ID (`provider:accountId:sourceId`)
- Timestamp and optional end time
- Author information with avatar
- Labels and metadata
- URL for opening in browser

## Keyboard Shortcuts

| Key | Action |
|-----|--------|
| ↑/↓ | Navigate between activities |
| Enter | Open selected activity URL |
| Esc | Close the panel |

## Data Storage

- **Cache Location**: `~/Library/Caches/com.activitybar/`
- **Credentials**: Stored in macOS Keychain
- **Preferences**: Stored in UserDefaults (`com.activitybar` domain)

Cache is organized by day for efficient loading:
```
~/Library/Caches/com.activitybar/
├── activities/
│   └── {accountId}/
│       └── {date}.json
├── heatmap_{accountId}.json
├── accounts.json
└── day_index.json
```

## Development

### Prerequisites

- Xcode 15+
- Swift 5.9+

### Building

```bash
cd ActivityBarApp

# Debug build
swift build

# Release build (optimized)
swift build -c release
```

### Running

```bash
# Run directly without building separately
swift run ActivityBarApp

# Or run the built executable
.build/debug/ActivityBarApp

# Or run release build
.build/release/ActivityBarApp
```

**Note**: No Xcode required - Swift Package Manager handles everything from the command line.

### Testing

```bash
swift test

# Run specific test target
swift test --filter CoreTests
```

For OAuth testing, create a `.env` file with your client credentials (see `.env.example`).

### TL;DR

Build, sign, and run (one command):
```bash
cd ActivityBarApp && swift build -c release && codesign -s - -f .build/release/ActivityBarApp && .build/release/ActivityBarApp
```

See [Development Guide](docs/development.md) for more details.

## Related Components

### activity-discovery

The `activity-discovery/` directory contains a TypeScript module that defines the unified activity schema and provides normalization utilities. While the Swift app doesn't execute this code directly, the schemas ensure consistency between potential backend services and the macOS app.

## Troubleshooting

### Activities not loading
1. Check your network connection
2. Verify account authentication in Settings
3. Try manual refresh (refresh button in panel footer)

### OAuth flow fails
1. Ensure your browser can open popup windows
2. Check that the OAuth callback URL is correctly configured
3. For self-hosted GitLab, verify the host URL is correct

### High memory usage
1. Check that per-day caching is working (day_index.json exists)
2. Clear cache if needed (delete contents of cache folder)

## License

MIT License - see [LICENSE](LICENSE) for details.

## Contributing

Contributions are welcome! Please read our contributing guidelines before submitting pull requests.

## Acknowledgments

- Built with SwiftUI and AppKit
- Uses SF Symbols for iconography
- OAuth implementations follow RFC 6749
