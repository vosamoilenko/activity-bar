# UI Components Guide

This document describes the UI component architecture and available components in ActivityBar.

## Table of Contents

- [Overview](#overview)
- [Window Management](#window-management)
- [Main Content Structure](#main-content-structure)
- [Heatmap Components](#heatmap-components)
- [Activity List Components](#activity-list-components)
- [Activity Type Views](#activity-type-views)
- [Shared Components](#shared-components)
- [Settings Views](#settings-views)
- [Styling and Theming](#styling-and-theming)

## Overview

ActivityBar's UI is built with SwiftUI, with AppKit integration for menu bar functionality. The UI follows these principles:

- **Declarative** - State drives the UI
- **Composable** - Small, reusable components
- **Responsive** - Adapts to content and user preferences
- **Accessible** - Supports keyboard navigation and VoiceOver

### Component Hierarchy

```
ActivityBarApp
├── AppDelegate (manages NSStatusItem)
└── ActivityWindowController
    └── MenuBarContentView
        ├── Header (title, refresh, settings)
        ├── HeatmapView
        ├── ActivityListView
        │   ├── CollapsibleActivityGroupView
        │   └── ActivityRowView (per activity type)
        └── Footer (offline indicator, last updated)
```

## Window Management

### ActivityWindowController

Manages the main activity panel window.

**File:** `Sources/App/ActivityWindowController.swift`

**Responsibilities:**
- Creates and positions the window relative to menu bar
- Applies visual effect (blur) background
- Handles window show/hide
- Manages window constraints

**Usage:**

```swift
let controller = ActivityWindowController(appState: appState, ...)
controller.showWindow()  // Show below menu bar icon
controller.hideWindow()
controller.toggleWindow()
```

**Window Properties:**
- Fixed width: 340 points
- Variable height based on content
- NSVisualEffectView background with configurable material
- No title bar (styleMask: .borderless)

### SettingsWindow

Manages the settings/preferences window.

**File:** `Sources/App/SettingsWindow.swift`

**Usage:**

```swift
let settingsWindow = SettingsWindow(appState: appState, ...)
settingsWindow.show()
```

## Main Content Structure

### MenuBarContentView

The root content view for the activity panel.

**File:** `Sources/App/MenuBarContentView.swift`

**Structure:**

```swift
struct MenuBarContentView: View {
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Activity")
                Spacer()
                RefreshButton()
                SettingsButton()
            }

            Divider()

            // Scrollable content
            ScrollView {
                VStack {
                    HeatmapView(...)
                    ActivityListHeader(...)
                    ActivityListView(...)
                }
            }

            Divider()

            // Footer
            HStack {
                OfflineIndicator()
                Spacer()
                LastUpdatedText()
                RefreshButton()
            }
        }
    }
}
```

**Props:**

| Property | Type | Description |
|----------|------|-------------|
| `appState` | `AppState` | Root application state |
| `onSettingsClicked` | `() -> Void` | Settings button callback |
| `onRefresh` | `() -> Void` | Manual refresh callback |

## Heatmap Components

### HeatmapView

Displays a 13-week activity heatmap grid.

**File:** `Sources/App/HeatmapView.swift`

**Features:**
- Shows daily activity counts as colored cells
- Supports date selection on click
- Hover tooltips with date and count
- Configurable week start day (Sunday/Monday)
- Range selection support

**Visual Design:**

```
     Mon Tue Wed Thu Fri Sat Sun
W-12  □   □   ■   □   □   □   □
W-11  □   ■   ■   □   □   □   □
...
W-1   □   ■   ■   ■   □   □   □
W-0   ■   ■   ?   ?   ?   ?   ?  (current week, future days hidden)
```

Cell colors based on activity count:
- 0: Light gray
- 1-3: Light green
- 4-6: Medium green
- 7-9: Dark green
- 10+: Darkest green

**Props:**

| Property | Type | Description |
|----------|------|-------------|
| `buckets` | `[HeatMapBucket]` | Activity counts by date |
| `selectedDate` | `Date?` | Currently selected date |
| `weekStartDay` | `WeekStartDay` | Sunday or Monday |
| `onDateSelected` | `(Date) -> Void` | Date tap callback |

**Usage:**

```swift
HeatmapView(
    buckets: appState.session.heatmapBuckets,
    selectedDate: appState.session.selectedDate,
    weekStartDay: preferences.weekStartDay,
    onDateSelected: { date in
        appState.selectDate(date)
    }
)
```

## Activity List Components

### ActivityListView

Displays a scrollable list of activities with keyboard navigation.

**File:** `Sources/App/ActivityListView.swift`

**Features:**
- Groups activities using `ActivityCollapser`
- Keyboard navigation (↑/↓ to navigate, Enter to open)
- "Now" indicator for today's activities
- Sorted by timestamp (newest first)

**Props:**

| Property | Type | Description |
|----------|------|-------------|
| `activities` | `[UnifiedActivity]` | Activities to display |
| `selectedDate` | `Date?` | Filter to specific date |

**Usage:**

```swift
ActivityListView(
    activities: appState.allActivities,
    selectedDate: appState.session.selectedDate
)
```

### CollapsibleActivityGroupView

Displays a group of collapsed similar activities.

**File:** `Sources/App/CollapsibleActivityGroupView.swift`

**Example:** "5 commits to main on my-repo"

**Props:**

| Property | Type | Description |
|----------|------|-------------|
| `group` | `CollapsedActivityGroup` | The collapsed group |
| `isExpanded` | `Bool` | Whether group is expanded |
| `onToggle` | `() -> Void` | Toggle expansion |

### ActivityCollapser

Groups similar activities for cleaner display.

**File:** `Sources/Core/ActivityCollapsing.swift`

**Collapsing Rules:**
- Commits on the same branch/project within 2 hours → "N commits to branch"
- Comments on the same issue/PR within 2 hours → "N comments on Issue #X"
- Other activities remain individual

**Usage:**

```swift
let displayItems = ActivityCollapser.collapse(activities)
// Returns [DisplayableActivity] - either single activities or groups
```

## Activity Type Views

Each activity type has a dedicated view component.

### CommitActivityView

Displays a commit activity.

**File:** `Sources/App/CommitActivityView.swift`

**Shows:**
- Commit SHA (7 characters)
- Commit message
- Repository name
- Author avatar
- Relative timestamp

### PullRequestActivityView

Displays a pull request/merge request.

**File:** `Sources/App/PullRequestActivityView.swift`

**Shows:**
- PR/MR number and title
- Draft badge (if draft)
- Source → Target branch
- Labels (as colored chips)
- Comment count badge
- Reviewer avatars
- Author avatar

### IssueActivityView

Displays an issue activity.

**File:** `Sources/App/IssueActivityView.swift`

**Shows:**
- Issue number and title
- Labels (as colored chips)
- Comment count badge
- Author avatar

### CommentActivityView

Displays a comment activity.

**File:** `Sources/App/CommentActivityView.swift`

**Shows:**
- Comment preview text
- Target (issue/PR) reference
- Author avatar
- Thread context

### CodeReviewActivityView

Displays a code review activity.

**File:** `Sources/App/CodeReviewActivityView.swift`

**Shows:**
- Review state (approved, changes requested, etc.)
- Target PR reference
- Reviewer avatar

### ActivityRowView

Generic fallback view for activity types without dedicated views.

**File:** `Sources/App/ActivityRowView.swift`

**Shows:**
- Activity type icon
- Title
- Subtitle (if available)
- Relative timestamp

## Shared Components

### AvatarView

Displays a user avatar with fallback.

**File:** `Sources/App/AvatarView.swift`

**Props:**

| Property | Type | Description |
|----------|------|-------------|
| `url` | `URL?` | Avatar image URL |
| `size` | `CGFloat` | Avatar diameter (default: 24) |
| `fallbackInitials` | `String?` | Initials if no image |

**Usage:**

```swift
AvatarView(url: activity.authorAvatarURL, size: 20)
```

### AvatarStackView

Displays multiple avatars in a compact stack.

**Shows overlapping avatars with "+N" for overflow.**

**Props:**

| Property | Type | Description |
|----------|------|-------------|
| `participants` | `[Participant]` | List of participants |
| `maxVisible` | `Int` | Max avatars before "+N" (default: 3) |
| `size` | `CGFloat` | Individual avatar size |

### LabelChipView

Displays a colored label chip.

**File:** `Sources/App/LabelChipView.swift`

**Props:**

| Property | Type | Description |
|----------|------|-------------|
| `label` | `ActivityLabel` | Label with name and color |

**Usage:**

```swift
LabelChipView(label: ActivityLabel(name: "bug", color: "#ff0000"))
```

### ProviderBadgeView

Displays a provider icon/badge.

**File:** `Sources/App/ProviderBadgeView.swift`

**Props:**

| Property | Type | Description |
|----------|------|-------------|
| `provider` | `Provider` | The provider to display |
| `showName` | `Bool` | Whether to show provider name |

### MenuStatBadge

Displays a count badge with icon.

**File:** `Sources/App/MenuStatBadge.swift`

**Props:**

| Property | Type | Description |
|----------|------|-------------|
| `count` | `Int` | Number to display |
| `icon` | `String` | SF Symbol name |

**Usage:**

```swift
MenuStatBadge(count: activity.commentCount ?? 0, icon: "bubble.left")
```

### RecentItemRowView

Container view for activity rows with consistent layout.

**File:** `Sources/App/RecentItemRowView.swift`

**Structure:**

```swift
HStack {
    AvatarView(...)
    VStack {
        titleRow      // Title + badges
        metadataRow   // Subtitle, timestamp, etc.
    }
}
```

### RelativeTimeFormatter

Formats dates as relative time strings.

**File:** `Sources/App/RelativeTimeFormatter.swift`

**Examples:**
- "just now" (< 1 minute)
- "5m ago" (minutes)
- "2h ago" (hours)
- "yesterday"
- "3 days ago"
- "Jan 15" (> 7 days)

**Usage:**

```swift
Text(RelativeTimeFormatter.string(from: activity.timestamp))
```

### ActivityIconMapper

Maps activity types to SF Symbol icons.

**File:** `Sources/App/ActivityIconMapper.swift`

| Activity Type | Icon |
|--------------|------|
| `.commit` | `arrow.triangle.branch` |
| `.pullRequest` | `arrow.triangle.pull` |
| `.issue` | `exclamationmark.circle` |
| `.issueComment` | `bubble.left` |
| `.codeReview` | `checkmark.circle` |
| `.meeting` | `calendar` |
| `.workItem` | `checklist` |
| `.deployment` | `shippingbox` |

## Settings Views

### SettingsView

Root settings view with tab navigation.

**File:** `Sources/App/SettingsView.swift`

**Tabs:**
- Accounts
- General

### AccountsSettingsView

Manages connected accounts.

**Features:**
- List connected accounts with enable/disable toggles
- Add new account flow
- Remove account
- Provider-specific configuration

### GeneralSettingsView

General app preferences.

**Settings:**
- Refresh interval selector
- Launch at login toggle
- Panel blur material picker
- Panel transparency slider
- Week start day picker

### CalendarPickerView

Calendar selection for Google Calendar accounts.

**File:** `Sources/App/CalendarPickerView.swift`

**Features:**
- Lists available calendars from Google account
- Checkbox selection for each calendar
- "Show only my events" toggle

## Styling and Theming

### Environment Values

Custom environment values for consistent styling:

```swift
// Menu item highlighting
@Environment(\.menuItemHighlighted) var isHighlighted

// Used in activity rows for hover effects
```

### Menu Highlighting

**File:** `Sources/App/MenuHighlighting.swift`

Provides visual feedback for focused/hovered menu items:

```swift
extension View {
    func menuItemStyle(isHighlighted: Bool) -> some View {
        self
            .background(isHighlighted ? Color.accentColor.opacity(0.2) : Color.clear)
            .foregroundColor(isHighlighted ? .primary : .secondary)
    }
}
```

### Visual Effect Materials

Panel background uses `NSVisualEffectView`:

```swift
enum PanelBlurMaterial: String, CaseIterable {
    case none
    case titlebar
    case menu
    case popover
    case sidebar
    // ... etc

    var nsMaterial: NSVisualEffectView.Material? {
        switch self {
        case .none: return nil
        case .titlebar: return .titlebar
        case .menu: return .menu
        // ...
        }
    }
}
```

### Color Palette

Activity type colors for heatmap:

```swift
extension Color {
    static let heatmapLevel0 = Color.gray.opacity(0.2)
    static let heatmapLevel1 = Color.green.opacity(0.3)
    static let heatmapLevel2 = Color.green.opacity(0.5)
    static let heatmapLevel3 = Color.green.opacity(0.7)
    static let heatmapLevel4 = Color.green.opacity(0.9)
}
```

### Typography

Uses system fonts with semantic sizing:

```swift
Text(title).font(.headline)
Text(subtitle).font(.subheadline)
Text(metadata).font(.caption)
Text(timestamp).font(.caption2).foregroundColor(.secondary)
```

## State Views

### StateViews

Handles loading, error, and empty states.

**File:** `Sources/App/StateViews.swift`

**Components:**

```swift
// Loading state
LoadingView()

// Error state
ErrorView(error: error, onRetry: { ... })

// Empty state
EmptyStateView(message: "No activities yet")
```

**Usage in ActivityListView:**

```swift
var body: some View {
    if isLoading {
        LoadingView()
    } else if let error = error {
        ErrorView(error: error, onRetry: refresh)
    } else if activities.isEmpty {
        EmptyStateView(message: "No activities for this date")
    } else {
        // Activity list
    }
}
```

## Keyboard Navigation

The activity list supports keyboard navigation:

| Key | Action |
|-----|--------|
| ↑ | Select previous activity |
| ↓ | Select next activity |
| Enter | Open selected activity URL |
| Esc | Close panel |

Implementation uses `onKeyPress` modifier (macOS 14+) or `NSEvent` monitoring.

## Accessibility

Components support VoiceOver:

```swift
ActivityRowView(activity: activity)
    .accessibilityLabel("\(activity.type.displayName): \(activity.title)")
    .accessibilityHint("Double tap to open in browser")
    .accessibilityAddTraits(.isButton)
```

Heatmap cells are grouped:

```swift
HeatmapCell(date: date, count: count)
    .accessibilityLabel("\(dateFormatter.string(from: date)), \(count) activities")
```
