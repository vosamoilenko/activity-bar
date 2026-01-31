import AppKit
import SwiftUI

/// Environment key for tracking menu item highlight state
private struct MenuItemHighlightedKey: EnvironmentKey {
    static let defaultValue = false
}

/// Environment key for showing event author (debugging)
private struct ShowEventAuthorKey: EnvironmentKey {
    static let defaultValue = false
}

extension EnvironmentValues {
    /// Whether the current menu item is highlighted/selected
    var menuItemHighlighted: Bool {
        get { self[MenuItemHighlightedKey.self] }
        set { self[MenuItemHighlightedKey.self] = newValue }
    }

    /// Whether to show event author (for debugging)
    var showEventAuthor: Bool {
        get { self[ShowEventAuthorKey.self] }
        set { self[ShowEventAuthorKey.self] = newValue }
    }
}

/// Color styles that adapt based on menu item highlight state and appearance (light/dark)
enum MenuHighlightStyle {
    /// Selected menu item text color (white on highlight)
    static let selectionText = Color(nsColor: .selectedMenuItemTextColor)

    /// Normal primary text color (not highlighted)
    static let normalPrimaryText = Color(nsColor: .controlTextColor)

    /// Normal secondary text color (not highlighted)
    static let normalSecondaryText = Color(nsColor: .secondaryLabelColor)

    /// Primary text color (full opacity when highlighted)
    static func primary(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : self.normalPrimaryText
    }

    /// Secondary text color (86% opacity when highlighted)
    static func secondary(_ highlighted: Bool) -> Color {
        highlighted
            ? Color(nsColor: .selectedMenuItemTextColor).opacity(0.86)
            : self.normalSecondaryText
    }

    /// Tertiary text color (70% opacity when highlighted)
    static func tertiary(_ highlighted: Bool) -> Color {
        highlighted
            ? Color(nsColor: .selectedMenuItemTextColor).opacity(0.7)
            : Color(nsColor: .tertiaryLabelColor)
    }

    /// Error text color (red when not highlighted, white when highlighted)
    static func error(_ highlighted: Bool) -> Color {
        highlighted ? self.selectionText : Color(nsColor: .systemRed)
    }

    /// Selection background color
    static func selectionBackground(_ highlighted: Bool) -> Color {
        highlighted ? Color(nsColor: .selectedContentBackgroundColor) : .clear
    }
}

/// Focus ring style for menu items
enum MenuFocusRingStyle {
    static let type: NSFocusRingType = .none
}
