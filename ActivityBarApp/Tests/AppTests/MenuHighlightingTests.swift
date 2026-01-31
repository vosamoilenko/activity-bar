import AppKit
import SwiftUI
import Testing
@testable import App

@Suite("MenuHighlighting Tests")
struct MenuHighlightingTests {

    // MARK: - Environment Key Tests

    @Test("MenuItemHighlighted environment key has false default value")
    func environmentKeyDefaultValue() {
        let environmentValues = EnvironmentValues()
        #expect(environmentValues.menuItemHighlighted == false)
    }

    @Test("MenuItemHighlighted environment key can be set to true")
    func environmentKeySetTrue() {
        var environmentValues = EnvironmentValues()
        environmentValues.menuItemHighlighted = true
        #expect(environmentValues.menuItemHighlighted == true)
    }

    @Test("MenuItemHighlighted environment key can be toggled")
    func environmentKeyToggle() {
        var environmentValues = EnvironmentValues()
        #expect(environmentValues.menuItemHighlighted == false)
        environmentValues.menuItemHighlighted = true
        #expect(environmentValues.menuItemHighlighted == true)
        environmentValues.menuItemHighlighted = false
        #expect(environmentValues.menuItemHighlighted == false)
    }

    // MARK: - MenuHighlightStyle Primary Tests

    @Test("Primary style returns normalPrimaryText when not highlighted")
    func primaryNotHighlighted() {
        let color = MenuHighlightStyle.primary(false)
        let expected = MenuHighlightStyle.normalPrimaryText
        #expect(color == expected)
    }

    @Test("Primary style returns selectionText when highlighted")
    func primaryHighlighted() {
        let color = MenuHighlightStyle.primary(true)
        let expected = MenuHighlightStyle.selectionText
        #expect(color == expected)
    }

    @Test("Primary style normalPrimaryText uses controlTextColor")
    func primaryNormalUsesControlTextColor() {
        let color = MenuHighlightStyle.normalPrimaryText
        let expected = Color(nsColor: .controlTextColor)
        #expect(color == expected)
    }

    // MARK: - MenuHighlightStyle Secondary Tests

    @Test("Secondary style returns normalSecondaryText when not highlighted")
    func secondaryNotHighlighted() {
        let color = MenuHighlightStyle.secondary(false)
        let expected = MenuHighlightStyle.normalSecondaryText
        #expect(color == expected)
    }

    @Test("Secondary style returns selectionText with 0.86 opacity when highlighted")
    func secondaryHighlighted() {
        let color = MenuHighlightStyle.secondary(true)
        let expected = Color(nsColor: .selectedMenuItemTextColor).opacity(0.86)
        #expect(color == expected)
    }

    @Test("Secondary style normalSecondaryText uses secondaryLabelColor")
    func secondaryNormalUsesSecondaryLabelColor() {
        let color = MenuHighlightStyle.normalSecondaryText
        let expected = Color(nsColor: .secondaryLabelColor)
        #expect(color == expected)
    }

    // MARK: - MenuHighlightStyle Tertiary Tests

    @Test("Tertiary style returns tertiaryLabelColor when not highlighted")
    func tertiaryNotHighlighted() {
        let color = MenuHighlightStyle.tertiary(false)
        let expected = Color(nsColor: .tertiaryLabelColor)
        #expect(color == expected)
    }

    @Test("Tertiary style returns selectionText with 0.7 opacity when highlighted")
    func tertiaryHighlighted() {
        let color = MenuHighlightStyle.tertiary(true)
        let expected = Color(nsColor: .selectedMenuItemTextColor).opacity(0.7)
        #expect(color == expected)
    }

    // MARK: - MenuHighlightStyle Error Tests

    @Test("Error style returns systemRed when not highlighted")
    func errorNotHighlighted() {
        let color = MenuHighlightStyle.error(false)
        let expected = Color(nsColor: .systemRed)
        #expect(color == expected)
    }

    @Test("Error style returns selectionText when highlighted")
    func errorHighlighted() {
        let color = MenuHighlightStyle.error(true)
        let expected = MenuHighlightStyle.selectionText
        #expect(color == expected)
    }

    // MARK: - MenuHighlightStyle Selection Background Tests

    @Test("Selection background returns clear when not highlighted")
    func selectionBackgroundNotHighlighted() {
        let color = MenuHighlightStyle.selectionBackground(false)
        #expect(color == .clear)
    }

    @Test("Selection background returns selectedContentBackgroundColor when highlighted")
    func selectionBackgroundHighlighted() {
        let color = MenuHighlightStyle.selectionBackground(true)
        let expected = Color(nsColor: .selectedContentBackgroundColor)
        #expect(color == expected)
    }

    // MARK: - MenuHighlightStyle Static Color Tests

    @Test("selectionText uses selectedMenuItemTextColor")
    func selectionTextColor() {
        let color = MenuHighlightStyle.selectionText
        let expected = Color(nsColor: .selectedMenuItemTextColor)
        #expect(color == expected)
    }

    // MARK: - MenuFocusRingStyle Tests

    @Test("MenuFocusRingStyle type is none")
    func focusRingTypeIsNone() {
        #expect(MenuFocusRingStyle.type == .none)
    }

    // MARK: - Integration Tests

    @Test("Primary, secondary, tertiary have consistent behavior when not highlighted")
    func consistentNonHighlightedBehavior() {
        let primary = MenuHighlightStyle.primary(false)
        let secondary = MenuHighlightStyle.secondary(false)
        let tertiary = MenuHighlightStyle.tertiary(false)

        // All should return their normal variants (not selection text)
        #expect(primary == MenuHighlightStyle.normalPrimaryText)
        #expect(secondary == MenuHighlightStyle.normalSecondaryText)
        #expect(tertiary != MenuHighlightStyle.selectionText)
    }

    @Test("Primary, secondary, tertiary use selectionText base when highlighted")
    func consistentHighlightedBehavior() {
        // All highlighted styles should be based on selectionText
        // Primary: full opacity, Secondary: 0.86, Tertiary: 0.7
        let primary = MenuHighlightStyle.primary(true)
        let secondary = MenuHighlightStyle.secondary(true)
        let tertiary = MenuHighlightStyle.tertiary(true)

        #expect(primary == MenuHighlightStyle.selectionText)
        #expect(secondary == Color(nsColor: .selectedMenuItemTextColor).opacity(0.86))
        #expect(tertiary == Color(nsColor: .selectedMenuItemTextColor).opacity(0.7))
    }

    @Test("Opacity progression: primary (1.0) > secondary (0.86) > tertiary (0.7)")
    func opacityProgression() {
        // This test documents the opacity hierarchy when highlighted
        // Primary: 100% (1.0), Secondary: 86% (0.86), Tertiary: 70% (0.7)
        let primaryBase = MenuHighlightStyle.selectionText
        let secondary = Color(nsColor: .selectedMenuItemTextColor).opacity(0.86)
        let tertiary = Color(nsColor: .selectedMenuItemTextColor).opacity(0.7)

        #expect(MenuHighlightStyle.primary(true) == primaryBase)
        #expect(MenuHighlightStyle.secondary(true) == secondary)
        #expect(MenuHighlightStyle.tertiary(true) == tertiary)
    }

    @Test("All styles respond to highlight state changes")
    func allStylesRespondToHighlightChanges() {
        // Each style should return different colors for highlighted vs not highlighted
        #expect(MenuHighlightStyle.primary(true) != MenuHighlightStyle.primary(false))
        #expect(MenuHighlightStyle.secondary(true) != MenuHighlightStyle.secondary(false))
        #expect(MenuHighlightStyle.tertiary(true) != MenuHighlightStyle.tertiary(false))
        #expect(MenuHighlightStyle.error(true) != MenuHighlightStyle.error(false))
        #expect(MenuHighlightStyle.selectionBackground(true) != MenuHighlightStyle.selectionBackground(false))
    }

    // MARK: - Dark/Light Mode Adaptation Tests

    @Test("Normal colors use system colors that adapt to appearance")
    func normalColorsAdaptToAppearance() {
        // These colors should adapt automatically based on system appearance
        // We can't test the actual color values, but we can verify they use NSColor
        let primary = MenuHighlightStyle.normalPrimaryText
        let secondary = MenuHighlightStyle.normalSecondaryText

        // The fact that these are created from NSColor means they'll adapt
        #expect(primary == Color(nsColor: .controlTextColor))
        #expect(secondary == Color(nsColor: .secondaryLabelColor))
    }

    @Test("Selection colors use system colors that adapt to appearance")
    func selectionColorsAdaptToAppearance() {
        let selection = MenuHighlightStyle.selectionText
        let background = MenuHighlightStyle.selectionBackground(true)

        #expect(selection == Color(nsColor: .selectedMenuItemTextColor))
        #expect(background == Color(nsColor: .selectedContentBackgroundColor))
    }
}
