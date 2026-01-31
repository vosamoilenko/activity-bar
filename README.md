# ActivityBar

A macOS menu bar application that aggregates your developer activities from multiple platforms into a unified view with a GitHub-style heatmap visualization.

## Features

- **Unified Activity Feed** - View commits, PRs, issues, meetings, and deployments from all your accounts
- **Heatmap Visualization** - GitHub-style contribution graph showing your activity patterns
- **Multi-Provider Support** - GitHub, GitLab, Azure DevOps, Google Calendar
- **Calendar Picker** - Browse activities by date or date range
- **Flexible Grouping** - Group activities by provider, by day, or view ungrouped
- **Launch at Login** - Start automatically when you log in
- **Offline Support** - Cached-first startup with background refresh
- **Deep Linking** - Click activities to open them in your browser

## Requirements

- macOS 14+ (Sonoma or later)
- Swift 5.9+
- Xcode 15+ (optional, for IDE development)
- Node.js 20+ (for activity-discovery module)

## Project Structure

```
ActivityBar/
├── ActivityBarApp/          # Swift macOS menu bar application
│   ├── Sources/
│   │   ├── App/            # UI views and entry point
│   │   ├── Core/           # State management and types
│   │   ├── Providers/      # OAuth and API adapters
│   │   └── Storage/        # Caching and token management
│   └── Tests/              # Unit tests
└── activity-discovery/      # TypeScript module for API integration
```

## Building & Running

### Swift App (ActivityBarApp)

```bash
cd ActivityBarApp

# Build
swift build

# Run (unsigned - no keychain access)
swift run ActivityBarApp

# Build, sign, and run (required for keychain/OAuth)
swift build && codesign --force --sign - .build/debug/ActivityBarApp && .build/debug/ActivityBarApp

# Run tests
swift test

# Build for release
swift build -c release
```

### Activity Discovery (TypeScript)

```bash
cd activity-discovery

# Install dependencies
npm install

# Type check
npm run typecheck

# Run tests
npm run test
```

## Troubleshooting

### Kill All Running Instances

If you need to terminate all running instances of ActivityBar:

```bash
# Kill all ActivityBar processes
pkill -f "ActivityBar"

# Or using killall
killall "ActivityBar"

# Combined approach (ignores errors if not running)
pkill -f "ActivityBar" 2>/dev/null; killall "ActivityBar" 2>/dev/null

pkill -9 ActivityBarApp
```

## Configuration

- **User Preferences**: Stored in UserDefaults (heatmap range, grouping, refresh interval)
- **OAuth Tokens**: Stored securely in macOS Keychain
- **Activity Cache**: Located at `~/Library/Caches/com.activitybar.cache/`

## Architecture

The app uses modern Swift patterns:
- `@Observable` and `@MainActor` for state management
- Protocol-driven design for extensibility
- Async/await for concurrent operations
- Cached-first startup with background refresh scheduling

See [AGENTS.md](ActivityBarApp/AGENTS.md) for detailed architecture documentation.

## License

Private project.
