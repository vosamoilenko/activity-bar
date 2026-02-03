import SwiftUI
import AppKit
import Core
import Storage

@MainActor
final class SettingsWindowController: NSWindowController {
    static let shared = SettingsWindowController()

    private override init(window: NSWindow?) {
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show(
        appState: AppState,
        tokenStore: TokenStore,
        launchAtLoginManager: LaunchAtLoginManager,
        refreshScheduler: RefreshScheduler?,
        preferencesManager: PreferencesManager,
        onPanelAppearanceChanged: (() -> Void)? = nil,
        onClearCache: ((String) async -> Void)? = nil
    ) {
        print("[ActivityBar] SettingsWindowController.show called")

        // Build SwiftUI settings view with current dependencies
        let rootView = SettingsView(
            appState: appState,
            tokenStore: tokenStore,
            launchAtLoginManager: launchAtLoginManager,
            refreshScheduler: refreshScheduler,
            preferencesManager: preferencesManager,
            onPanelAppearanceChanged: onPanelAppearanceChanged,
            onClearCache: onClearCache
        )

        let hosting = NSHostingController(rootView: rootView)

        if let window = self.window {
            // Reuse existing window, just replace content controller
            print("[ActivityBar] Reusing existing Settings window")
            window.contentViewController = hosting
        } else {
            // Create a new window on first use
            print("[ActivityBar] Creating Settings window")
            let window = NSWindow(
                contentViewController: hosting
            )
            window.title = "Settings"
            window.setContentSize(NSSize(width: 700, height: 520))
            window.minSize = NSSize(width: 600, height: 440)
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.isReleasedWhenClosed = false
            self.window = window
        }

        NSApp.activate(ignoringOtherApps: true)
        self.window?.center()
        self.window?.makeKeyAndOrderFront(nil)
        print("[ActivityBar] Settings window should now be key and visible")
    }
}
