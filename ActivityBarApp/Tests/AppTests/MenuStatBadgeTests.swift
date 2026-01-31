import SwiftUI
import Testing
@testable import App

@Suite("StatValueFormatter Tests")
struct StatValueFormatterTests {
    @Test("Formats values under 1000 as-is")
    func formatsSmallValues() {
        #expect(StatValueFormatter.compact(0) == "0")
        #expect(StatValueFormatter.compact(5) == "5")
        #expect(StatValueFormatter.compact(42) == "42")
        #expect(StatValueFormatter.compact(999) == "999")
    }

    @Test("Formats 1k-10k with one decimal place")
    func formatsThousandsWithDecimal() {
        #expect(StatValueFormatter.compact(1000) == "1K")
        #expect(StatValueFormatter.compact(1234) == "1.2K")
        #expect(StatValueFormatter.compact(1567) == "1.6K")
        #expect(StatValueFormatter.compact(9999) == "10K")
    }

    @Test("Formats 10k-1M as whole thousands")
    func formatsLargeThousands() {
        #expect(StatValueFormatter.compact(10_000) == "10K")
        #expect(StatValueFormatter.compact(42_000) == "42K")
        #expect(StatValueFormatter.compact(999_999) == "999K")
    }

    @Test("Formats 1M-10M with one decimal place")
    func formatsMillionsWithDecimal() {
        #expect(StatValueFormatter.compact(1_000_000) == "1M")
        #expect(StatValueFormatter.compact(1_234_567) == "1.2M")
        #expect(StatValueFormatter.compact(5_678_901) == "5.7M")
        #expect(StatValueFormatter.compact(9_999_999) == "10M")
    }

    @Test("Formats 10M-1B as whole millions")
    func formatsLargeMillions() {
        #expect(StatValueFormatter.compact(10_000_000) == "10M")
        #expect(StatValueFormatter.compact(42_000_000) == "42M")
        #expect(StatValueFormatter.compact(999_999_999) == "999M")
    }

    @Test("Caps values at 999M for billions")
    func capsBillionValues() {
        #expect(StatValueFormatter.compact(1_000_000_000) == "999M")
        #expect(StatValueFormatter.compact(5_000_000_000) == "999M")
        #expect(StatValueFormatter.compact(Int.max) == "999M")
    }

    @Test("Removes .0 decimal suffix")
    func removesZeroDecimal() {
        #expect(StatValueFormatter.compact(1000) == "1K")
        #expect(StatValueFormatter.compact(2000) == "2K")
        #expect(StatValueFormatter.compact(1_000_000) == "1M")
    }

    @Test("Handles edge cases for 10.0 rounding")
    func handlesRoundingEdgeCases() {
        #expect(StatValueFormatter.compact(9999) == "10K")
        #expect(StatValueFormatter.compact(9_999_999) == "10M")
    }
}

@Suite("MenuStatBadge Tests")
struct MenuStatBadgeTests {
    @Test("Initializes with value and systemImage")
    func initializesWithValueAndIcon() {
        let badge = MenuStatBadge(value: 42, systemImage: "text.bubble")
        #expect(badge.valueText == "42")
        #expect(badge.systemImage == "text.bubble")
        #expect(badge.label == nil)
    }

    @Test("Initializes with label, value, and systemImage")
    func initializesWithLabelValueAndIcon() {
        let badge = MenuStatBadge(label: "Comments", value: 5, systemImage: "text.bubble")
        #expect(badge.valueText == "5")
        #expect(badge.systemImage == "text.bubble")
        #expect(badge.label == "Comments")
    }

    @Test("Initializes with custom valueText")
    func initializesWithCustomText() {
        let badge = MenuStatBadge(valueText: "Custom", systemImage: "star.fill")
        #expect(badge.valueText == "Custom")
        #expect(badge.systemImage == "star.fill")
        #expect(badge.label == nil)
    }

    @Test("Initializes without systemImage")
    func initializesWithoutIcon() {
        let badge = MenuStatBadge(label: "Count", value: 100)
        #expect(badge.valueText == "100")
        #expect(badge.systemImage == nil)
        #expect(badge.label == "Count")
    }

    @Test("Formats large values automatically")
    func formatsLargeValues() {
        let badge1 = MenuStatBadge(value: 1234, systemImage: "text.bubble")
        #expect(badge1.valueText == "1.2K")

        let badge2 = MenuStatBadge(value: 1_234_567, systemImage: "checkmark.bubble")
        #expect(badge2.valueText == "1.2M")
    }

    @Test("Common use cases for comment counts")
    func commentCountUseCases() {
        let zero = MenuStatBadge(value: 0, systemImage: "text.bubble")
        #expect(zero.valueText == "0")

        let few = MenuStatBadge(value: 5, systemImage: "text.bubble")
        #expect(few.valueText == "5")

        let many = MenuStatBadge(value: 42, systemImage: "text.bubble")
        #expect(many.valueText == "42")

        let lots = MenuStatBadge(value: 1500, systemImage: "text.bubble")
        #expect(lots.valueText == "1.5K")
    }

    @Test("Common use cases for review counts")
    func reviewCountUseCases() {
        let approved = MenuStatBadge(value: 3, systemImage: "checkmark.bubble")
        #expect(approved.valueText == "3")

        let changesRequested = MenuStatBadge(value: 2, systemImage: "exclamationmark.bubble")
        #expect(changesRequested.valueText == "2")
    }

    @Test("Star count badge example")
    func starCountBadge() {
        let badge = MenuStatBadge(label: "★", value: 5600, systemImage: "star.fill")
        #expect(badge.valueText == "5.6K")
        #expect(badge.label == "★")
    }

    @Test("Fork count badge example")
    func forkCountBadge() {
        let badge = MenuStatBadge(label: "Forks", value: 123)
        #expect(badge.valueText == "123")
        #expect(badge.label == "Forks")
        #expect(badge.systemImage == nil)
    }
}
