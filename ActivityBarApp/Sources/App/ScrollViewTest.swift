import SwiftUI
import Core

// Test harness for verifying SelfSizingScrollView behavior
// Run with: swift run ActivityBarApp --test-scroll
#if DEBUG

// Keep window references alive
var testWindows: [NSWindow] = []

@MainActor
func testScrollViewBehavior() {
    // Test 1: Minimal content - should be small
    let smallAppState = AppState()
    smallAppState.session.accounts = [Account(id: "test", provider: .gitlab, displayName: "Test")]
    smallAppState.session.activitiesByAccount["test"] = [
        UnifiedActivity(id: "1", provider: .gitlab, accountId: "test", sourceId: "s1", type: .commit, timestamp: Date(), title: "One activity")
    ]
    smallAppState.hasLoadedFromCache = true

    // Test 2: Many activities - should scroll
    let largeAppState = AppState()
    largeAppState.session.accounts = [Account(id: "test", provider: .gitlab, displayName: "Test")]
    var activities: [UnifiedActivity] = []
    // Use today's timestamps so they show up in "Today's Activities"
    let now = Date()
    for i in 1...50 {
        activities.append(UnifiedActivity(
            id: "\(i)",
            provider: .gitlab,
            accountId: "test",
            sourceId: "src\(i)",
            type: i % 3 == 0 ? .pullRequest : (i % 2 == 0 ? .issue : .commit),
            timestamp: now.addingTimeInterval(Double(-i * 60)), // Minutes ago, still today
            title: "Activity item \(i) - this is a longer title to test wrapping behavior"
        ))
    }
    largeAppState.session.activitiesByAccount["test"] = activities
    largeAppState.hasLoadedFromCache = true

    // Create windows for both - keep references
    let smallWindow = NSWindow(
        contentRect: NSRect(x: 100, y: 200, width: 340, height: 800),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    smallWindow.title = "Small Content (should fit)"
    smallWindow.contentView = NSHostingView(rootView:
        MenuBarContentView(
            appState: smallAppState,
            refreshScheduler: nil,
            preferencesManager: nil,
            onRefresh: nil,
            onOpenSettings: nil
        )
        .background(Color(NSColor.windowBackgroundColor))
    )
    smallWindow.center()
    smallWindow.setFrameOrigin(NSPoint(x: 100, y: 200))
    testWindows.append(smallWindow)
    smallWindow.makeKeyAndOrderFront(nil)

    let largeWindow = NSWindow(
        contentRect: NSRect(x: 500, y: 200, width: 340, height: 800),
        styleMask: [.titled, .closable, .resizable],
        backing: .buffered,
        defer: false
    )
    largeWindow.title = "Many Activities (should scroll)"
    largeWindow.contentView = NSHostingView(rootView:
        MenuBarContentView(
            appState: largeAppState,
            refreshScheduler: nil,
            preferencesManager: nil,
            onRefresh: nil,
            onOpenSettings: nil
        )
        .background(Color(NSColor.windowBackgroundColor))
    )
    largeWindow.setFrameOrigin(NSPoint(x: 500, y: 200))
    testWindows.append(largeWindow)
    largeWindow.makeKeyAndOrderFront(nil)

    NSApp.activate(ignoringOtherApps: true)

    print("Test windows created. Check if:")
    print("1. Small window - content fits, no scrolling needed")
    print("2. Large window - content scrolls when there's lots of activities")
}
#endif
