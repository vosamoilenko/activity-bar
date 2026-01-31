import SwiftUI
import Core
import Providers
import Storage
import os.log

private let logger = Logger(subsystem: "com.activitybar.app", category: "App")

/// Main app entry point - minimal SwiftUI shell
/// All menu bar logic moved to AppDelegate using pure AppKit NSStatusItem
/// because MenuBarExtra has fundamental issues with window management
@main
struct ActivityBarApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    init() {
        logger.info("ActivityBarApp init called")
        print("[ActivityBar] App struct initialized")
        // Load OAuth credentials from environment for development
        Task { await OAuthCredentialsLoader.loadFromEnvironment() }
    }

    var body: some Scene {
        // Settings window only - menu bar handled by AppDelegate with NSStatusItem
        Settings {
            SettingsView(
                appState: appDelegate.appState,
                tokenStore: appDelegate.tokenStore,
                launchAtLoginManager: appDelegate.launchAtLoginManager,
                refreshScheduler: appDelegate.refreshScheduler,
                preferencesManager: appDelegate.preferencesManager,
                onPanelAppearanceChanged: { [weak appDelegate] in
                    appDelegate?.updatePanelAppearance()
                }
            )
        }
    }
}

/// App delegate using pure AppKit NSStatusItem for menu bar
/// MenuBarExtra has fundamental issues with window management - this approach is stable
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    // MARK: - Status Bar

    /// The status bar item (menu bar icon)
    private var statusItem: NSStatusItem!

    // MARK: - App State

    /// Root application state shared across all views
    let appState = AppState()

    /// Data coordinator for cache loading and background refresh
    var dataCoordinator: DataCoordinator?

    /// Refresh scheduler for periodic and manual refresh (ACTIVITY-024)
    var refreshScheduler: RefreshScheduler?

    /// Token store for keychain access (shared across settings)
    let tokenStore: TokenStore = KeychainTokenStore()

    /// Disk cache provider for cached-first startup (ACTIVITY-023)
    let diskCacheProvider = DiskCacheProvider()

    /// Launch at login manager (ACTIVITY-022)
    let launchAtLoginManager = LaunchAtLoginManager()

    /// User preferences manager (ACTIVITY-025)
    let preferencesManager = PreferencesManager()

    /// Activity window controller - created eagerly in applicationDidFinishLaunching
    var activityWindowController: ActivityWindowController!

    // MARK: - NSApplicationDelegate

    /// Called on main thread - use MainActor.assumeIsolated for synchronous setup
    nonisolated func applicationDidFinishLaunching(_ notification: Notification) {
        // This runs on main thread, so we can safely assume MainActor isolation
        MainActor.assumeIsolated {
            logger.info("AppDelegate: applicationDidFinishLaunching")
            print("[ActivityBar] AppDelegate: applicationDidFinishLaunching called")

            #if DEBUG
            if CommandLine.arguments.contains("--test-scroll") {
                print("[ActivityBar] Running scroll view test...")
                NSApp.setActivationPolicy(.regular)
                testScrollViewBehavior()
                return
            }
            #endif

            // Show in Dock as a normal app
            NSApp.setActivationPolicy(.regular)
            print("[ActivityBar] Activation policy set to .regular")

            // Create window controller FIRST (before any UI)
            activityWindowController = ActivityWindowController(appDelegate: self)
            print("[ActivityBar] ActivityWindowController created")

            // Set up the status bar item (pure AppKit - no MenuBarExtra)
            setupStatusItem()

            // Initialize data loading asynchronously (doesn't block UI)
            Task {
                await initializeCoordinatorAndLoadCache()
            }

            // Show the main activity window on launch
            activityWindowController.show()
        }
    }

    nonisolated func applicationWillTerminate(_ notification: Notification) {
        print("[ActivityBar] App terminating")
    }

    // MARK: - Status Item Setup (Pure AppKit)

    private func setupStatusItem() {
        print("[ActivityBar] Setting up NSStatusItem")

        // Create status item in system status bar
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        // Configure button
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "chart.bar.fill", accessibilityDescription: "Activity")
            button.action = #selector(statusItemClicked(_:))
            button.target = self
            // Right-click shows menu, left-click toggles window
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }

        // Create context menu for right-click
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Show Activity", action: #selector(showActivity), keyEquivalent: "a"))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: "q"))

        // Store menu for right-click
        statusItem.menu = nil  // Don't auto-show menu, we handle clicks manually

        print("[ActivityBar] NSStatusItem setup complete")
    }

    @objc private func statusItemClicked(_ sender: NSStatusBarButton) {
        guard let event = NSApp.currentEvent else { return }

        if event.type == .rightMouseUp {
            // Right-click: show menu
            let menu = NSMenu()
            menu.addItem(NSMenuItem(title: "Show Activity", action: #selector(showActivity), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ""))
            menu.addItem(NSMenuItem.separator())
            menu.addItem(NSMenuItem(title: "Quit", action: #selector(quitApp), keyEquivalent: ""))

            statusItem.menu = menu
            statusItem.button?.performClick(nil)
            statusItem.menu = nil  // Reset so left-click works again
        } else {
            // Left-click: toggle activity window
            showActivity()
        }
    }

    @objc func showActivity() {
        print("[ActivityBar] showActivity called")
        activityWindowController.toggle()
    }

    @objc func showSettings() {
        print("[ActivityBar] showSettings called")
        SettingsWindowController.shared.show(
            appState: appState,
            tokenStore: tokenStore,
            launchAtLoginManager: launchAtLoginManager,
            refreshScheduler: refreshScheduler,
            preferencesManager: preferencesManager,
            onPanelAppearanceChanged: { [weak self] in
                self?.updatePanelAppearance()
            }
        )
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    // MARK: - Data Initialization

    /// Initialize the data coordinator and load from cache
    func initializeCoordinatorAndLoadCache() async {
        guard dataCoordinator == nil else { return }

        appState.accountsPersistence = diskCacheProvider

        let refreshProvider = ActivityRefreshProvider.withDiskCache(
            tokenStore: tokenStore,
            daysBack: 30
        )

        let coordinator = DataCoordinator(
            appState: appState,
            cacheProvider: diskCacheProvider,
            refreshProvider: refreshProvider
        )
        dataCoordinator = coordinator

        let scheduler = RefreshScheduler(
            interval: preferencesManager.refreshInterval,
            debounceInterval: 30,
            onRefresh: { [weak coordinator] in
                guard let coordinator = coordinator else { return }
                await coordinator.refreshInBackground()
            }
        )
        refreshScheduler = scheduler

        await coordinator.loadFromCache()

        scheduler.start()

        // Only trigger immediate refresh if any visible days need fetching
        let needsRefresh = await coordinator.needsInitialFetch()
        if needsRefresh {
            print("[ActivityBar] Some heatmap days need fetching, triggering refresh")
            Task.detached { @MainActor in
                try? await Task.sleep(for: .milliseconds(100))
                scheduler.triggerRefresh()
            }
        } else {
            print("[ActivityBar] All heatmap days cached, skipping initial refresh")
        }
    }

    /// Trigger manual refresh from UI
    func triggerRefresh() {
        refreshScheduler?.forceRefresh()
    }

    /// Update panel appearance in real-time (called from settings)
    func updatePanelAppearance() {
        activityWindowController?.updatePanelAppearance()
    }

    /// Clear all cached data for an account (called when account is removed)
    func clearCacheForAccount(_ accountId: String) async {
        await diskCacheProvider.clearCache(for: accountId)
        print("[ActivityBar] Cleared cache for account: \(accountId)")
    }
}
