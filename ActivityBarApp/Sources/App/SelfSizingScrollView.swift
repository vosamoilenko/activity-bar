import SwiftUI
import AppKit

/// A scroll view that sizes itself to fit its content, up to a maximum height.
/// Unlike SwiftUI's ScrollView, this reports proper intrinsic content size,
/// so the popup grows with content and only scrolls when exceeding maxHeight.
struct SelfSizingScrollView<Content: View>: NSViewRepresentable {
    let content: Content
    let maxHeight: CGFloat

    init(maxHeight: CGFloat, @ViewBuilder content: () -> Content) {
        self.content = content()
        self.maxHeight = maxHeight
    }

    func makeNSView(context: Context) -> SelfSizingScrollNSView {
        let nsView = SelfSizingScrollNSView(maxHeight: maxHeight)
        let hostingView = NSHostingView(rootView: content)
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        nsView.documentView = hostingView
        return nsView
    }

    func updateNSView(_ nsView: SelfSizingScrollNSView, context: Context) {
        nsView.maxHeight = maxHeight
        if let hostingView = nsView.documentView as? NSHostingView<Content> {
            hostingView.rootView = content
        }
        // Force recalculation of intrinsic size
        nsView.invalidateIntrinsicContentSize()
    }
}

/// Custom NSScrollView that reports intrinsic content size based on content
final class SelfSizingScrollNSView: NSScrollView {
    var maxHeight: CGFloat

    init(maxHeight: CGFloat) {
        self.maxHeight = maxHeight
        super.init(frame: .zero)

        // Configure scroll view
        hasVerticalScroller = true
        hasHorizontalScroller = false
        autohidesScrollers = true
        drawsBackground = false

        // Make it scroll vertically only when needed
        verticalScrollElasticity = .automatic
        horizontalScrollElasticity = .none
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize {
        guard let documentView = documentView else {
            return NSSize(width: NSView.noIntrinsicMetric, height: NSView.noIntrinsicMetric)
        }

        // Get the fitting size of the content
        let contentSize = documentView.fittingSize

        // Height is capped at maxHeight
        let height = min(contentSize.height, maxHeight)

        return NSSize(width: contentSize.width, height: height)
    }

    override func layout() {
        super.layout()

        // Ensure document view width matches scroll view width
        if let documentView = documentView {
            let contentWidth = bounds.width
            documentView.setFrameSize(NSSize(
                width: contentWidth,
                height: documentView.fittingSize.height
            ))
        }
    }
}
