import SwiftUI
import Core

/// Controller for the main activity window opened from menu bar
/// Fully @MainActor isolated for safety
@MainActor
final class ActivityWindowController: NSObject, NSWindowDelegate {
    private var window: NSWindow?
    private var visualEffectView: NSVisualEffectView?

    // Direct references to AppDelegate-owned objects
    private weak var appDelegate: AppDelegate?

    init(appDelegate: AppDelegate) {
        print("[ActivityBar] ActivityWindowController.init() called")
        self.appDelegate = appDelegate
        super.init()
        print("[ActivityBar] ActivityWindowController initialized")
    }

    // MARK: - NSWindowDelegate

    private var savedOriginX: CGFloat?
    private var isLiveResizing = false

    nonisolated func windowWillResize(_ sender: NSWindow, to frameSize: NSSize) -> NSSize {
        // Keep width fixed at 340, only allow height changes
        return NSSize(width: 340, height: frameSize.height)
    }

    nonisolated func windowWillStartLiveResize(_ notification: Notification) {
        guard let window = notification.object as? NSWindow else { return }
        MainActor.assumeIsolated {
            self.savedOriginX = window.frame.origin.x
            self.isLiveResizing = true
        }
    }

    nonisolated func windowDidResize(_ notification: Notification) {
        // Continuously correct x position during live resize
        guard let window = notification.object as? NSWindow else { return }
        MainActor.assumeIsolated {
            guard self.isLiveResizing, let savedX = self.savedOriginX else { return }
            let currentX = window.frame.origin.x
            if abs(currentX - savedX) > 0.5 {
                // Use setFrameOrigin to avoid triggering additional resize events
                window.setFrameOrigin(NSPoint(x: savedX, y: window.frame.origin.y))
            }
        }
    }

    nonisolated func windowDidEndLiveResize(_ notification: Notification) {
        MainActor.assumeIsolated {
            self.isLiveResizing = false
            self.savedOriginX = nil
        }
    }

    /// Update panel appearance in real-time (called when settings change)
    func updatePanelAppearance() {
        guard let appDelegate = appDelegate, let visualEffectView = visualEffectView else { return }

        let blurMaterial = appDelegate.preferencesManager.panelBlurMaterial
        let transparency = appDelegate.preferencesManager.panelTransparency

        // Apply blur material
        if blurMaterial == .none {
            visualEffectView.material = .windowBackground
            visualEffectView.state = .inactive
        } else {
            visualEffectView.material = blurMaterial.toNSMaterial()
            visualEffectView.state = .active
        }

        // Apply transparency
        visualEffectView.alphaValue = CGFloat(transparency)
    }

    func toggle() {
        print("[ActivityBar] ActivityWindowController.toggle() called, window=\(window != nil), isVisible=\(window?.isVisible ?? false)")
        if let window = window, window.isVisible {
            close()
        } else {
            show()
        }
    }

    func show() {
        print("[ActivityBar] ActivityWindowController.show() called")
        guard let appDelegate = appDelegate else {
            print("[ActivityBar] ERROR: appDelegate is nil!")
            return
        }

        if window == nil {
            createWindow()
        }

        guard let window = window else {
            print("[ActivityBar] ERROR: window is nil after createWindow!")
            return
        }

        print("[ActivityBar] Creating MenuBarContentView...")

        // Update content
        let contentView = MenuBarContentView(
            appState: appDelegate.appState,
            refreshScheduler: appDelegate.refreshScheduler,
            preferencesManager: appDelegate.preferencesManager,
            dataCoordinator: appDelegate.dataCoordinator,
            onRefresh: { [weak appDelegate] in appDelegate?.triggerRefresh() },
            onOpenSettings: { [weak appDelegate] in appDelegate?.showSettings() }
        )

        // Create visual effect view for blurred background
        let effectView = NSVisualEffectView()
        effectView.blendingMode = .behindWindow
        self.visualEffectView = effectView

        // Apply appearance settings from preferences
        updatePanelAppearance()

        // Embed SwiftUI content in visual effect view
        let hostingView = NSHostingView(rootView: contentView)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        effectView.addSubview(hostingView)

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])

        window.contentView = effectView

        print("[ActivityBar] Positioning window...")
        positionWindow()

        print("[ActivityBar] Making window visible...")
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        print("[ActivityBar] Window should now be visible")
    }

    func close() {
        print("[ActivityBar] ActivityWindowController.close() called")
        window?.orderOut(nil)
    }

    private func createWindow() {
        print("[ActivityBar] Creating NSWindow...")
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 340, height: 600),
            styleMask: [.titled, .closable, .resizable, .miniaturizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        newWindow.title = "Activity"
        newWindow.titlebarAppearsTransparent = true
        newWindow.titleVisibility = .hidden
        newWindow.isMovableByWindowBackground = true
        newWindow.level = .normal  // Normal window level (not floating)
        newWindow.collectionBehavior = [.managed]  // Normal window behavior
        newWindow.backgroundColor = .clear  // Transparent for visual effect
        newWindow.isOpaque = false  // Allow transparency

        // Size constraints - fixed width, variable height
        newWindow.minSize = NSSize(width: 340, height: 300)
        newWindow.maxSize = NSSize(width: 340, height: 2000)

        // CRITICAL: Prevent window from deallocating when closed
        // Without this, our reference becomes a dangling pointer and causes crash
        // See: https://github.com/onmyway133/blog/issues/312
        newWindow.isReleasedWhenClosed = false

        // Keep window visible (don't hide on deactivate)
        newWindow.hidesOnDeactivate = false

        // Set delegate to control resize behavior
        newWindow.delegate = self

        self.window = newWindow
        print("[ActivityBar] NSWindow created successfully")
    }

    private func positionWindow() {
        guard let window = window, let screen = NSScreen.main else { return }

        if let contentView = window.contentView {
            let fittingSize = contentView.fittingSize
            let maxHeight = screen.visibleFrame.height - 50

            let width = max(fittingSize.width, 340)
            let height = min(fittingSize.height, maxHeight)
            window.setContentSize(NSSize(width: width, height: height))
        }

        // Center window on screen
        window.center()
    }
}
