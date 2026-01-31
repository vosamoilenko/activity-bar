import SwiftUI

/// A custom layout that arranges its children in a flowing manner, wrapping to the next line when exceeding available width.
///
/// FlowLayout is useful for displaying collections of variable-width items (like label chips or tags) where items should
/// wrap naturally when they don't fit on a single line. Items flow left-to-right, top-to-bottom.
///
/// Example:
/// ```swift
/// FlowLayout(itemSpacing: 6, lineSpacing: 4) {
///     ForEach(labels) { label in
///         LabelChipView(label: label)
///     }
/// }
/// ```
struct FlowLayout: Layout {
    /// Horizontal spacing between items on the same line
    let itemSpacing: CGFloat

    /// Vertical spacing between lines
    let lineSpacing: CGFloat

    /// Creates a FlowLayout with configurable spacing.
    ///
    /// - Parameters:
    ///   - itemSpacing: Horizontal spacing between items (default: 6pt)
    ///   - lineSpacing: Vertical spacing between lines (default: 4pt)
    init(itemSpacing: CGFloat = 6, lineSpacing: CGFloat = 4) {
        self.itemSpacing = itemSpacing
        self.lineSpacing = lineSpacing
    }

    /// Calculates the size that fits the given proposal.
    ///
    /// - Parameters:
    ///   - proposal: The proposed size constraints
    ///   - subviews: The child views to layout
    ///   - cache: Layout cache (unused in this implementation)
    /// - Returns: The computed size that fits all subviews
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache _: inout ()) -> CGSize {
        let width = proposal.width ?? 240
        return measure(in: width, subviews: subviews).size
    }

    /// Places all subviews within the given bounds.
    ///
    /// - Parameters:
    ///   - bounds: The container bounds to place subviews in
    ///   - proposal: The proposed size (unused, bounds.width is used instead)
    ///   - subviews: The child views to layout
    ///   - cache: Layout cache (unused in this implementation)
    func placeSubviews(in bounds: CGRect, proposal _: ProposedViewSize, subviews: Subviews, cache _: inout ()) {
        let result = measure(in: bounds.width, subviews: subviews)
        for placement in result.placements {
            placement.subview.place(
                at: CGPoint(x: bounds.minX + placement.origin.x, y: bounds.minY + placement.origin.y),
                proposal: ProposedViewSize(width: placement.size.width, height: placement.size.height)
            )
        }
    }

    // MARK: - Private Types

    /// Represents the placement of a single subview
    private struct Placement {
        let subview: LayoutSubview
        let origin: CGPoint
        let size: CGSize
    }

    /// Result of measuring layout, containing total size and placement for each subview
    private struct MeasureResult {
        let size: CGSize
        let placements: [Placement]
    }

    // MARK: - Private Methods

    /// Measures the layout and calculates placement for all subviews.
    ///
    /// This is the core layout algorithm:
    /// 1. Start at x=0, y=0 with rowHeight=0
    /// 2. For each subview:
    ///    - If it doesn't fit on current row (x + width > availableWidth), wrap to next line
    ///    - Place subview at current (x, y)
    ///    - Advance x by (width + itemSpacing)
    ///    - Track maximum row height
    /// 3. Return total size and all placements
    ///
    /// - Parameters:
    ///   - availableWidth: The maximum width available for layout
    ///   - subviews: The child views to measure
    /// - Returns: MeasureResult containing total size and placements
    private func measure(in availableWidth: CGFloat, subviews: Subviews) -> MeasureResult {
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        var placements: [Placement] = []
        placements.reserveCapacity(subviews.count)

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)

            // Check if we need to wrap to next line
            // Note: (x > 0) check ensures first item on a row doesn't trigger wrap
            let exceeds = (x > 0) && (x + size.width > availableWidth)
            if exceeds {
                // Wrap to next line
                x = 0
                y += rowHeight + lineSpacing
                rowHeight = 0
            }

            // Place subview at current position
            placements.append(Placement(subview: subview, origin: CGPoint(x: x, y: y), size: size))

            // Advance position and track metrics
            x += size.width + itemSpacing
            rowHeight = max(rowHeight, size.height)
            maxX = max(maxX, x)
        }

        let totalHeight = y + rowHeight
        return MeasureResult(
            size: CGSize(width: min(maxX, availableWidth), height: totalHeight),
            placements: placements
        )
    }
}
