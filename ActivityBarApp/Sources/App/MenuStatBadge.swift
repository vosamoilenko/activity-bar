import SwiftUI

/// Formatter for compact display of large numbers (1.2k, 5.3M)
enum StatValueFormatter {
    static func compact(_ value: Int) -> String {
        if value < 1000 { return "\(value)" }
        if value < 10000 {
            let short = self.oneDecimal(value, divisor: 1000)
            return "\(short)K"
        }
        if value < 1_000_000 {
            return "\(value / 1000)K"
        }
        if value < 10_000_000 {
            let short = self.oneDecimal(value, divisor: 1_000_000)
            return "\(short)M"
        }
        if value >= 1_000_000_000 {
            return "999M"
        }
        return "\(value / 1_000_000)M"
    }

    private static func oneDecimal(_ value: Int, divisor: Double) -> String {
        let scaled = Double(value) / divisor
        let formatted = String(format: "%.1f", scaled)
        if formatted.hasSuffix(".0") {
            return String(formatted.dropLast(2))
        }
        if formatted.hasPrefix("10") {
            return "10"
        }
        return formatted
    }
}

/// Badge showing an icon and count (e.g., comment count with text.bubble icon)
/// Uses MenuHighlighting environment for color adaptation on selection
struct MenuStatBadge: View {
    let label: String?
    let valueText: String
    let systemImage: String?
    @Environment(\.menuItemHighlighted) private var isHighlighted

    private static let iconWidth: CGFloat = 12

    init(label: String? = nil, value: Int, systemImage: String? = nil) {
        self.label = label
        self.valueText = StatValueFormatter.compact(value)
        self.systemImage = systemImage
    }

    init(label: String? = nil, valueText: String, systemImage: String? = nil) {
        self.label = label
        self.valueText = valueText
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.caption2)
                    .frame(width: Self.iconWidth, alignment: .center)
            }
            if let label {
                Text(label)
                    .font(.caption2)
            }
            Text(self.valueText)
                .font(.caption2)
                .monospacedDigit()
                .lineLimit(1)
        }
        .foregroundStyle(MenuHighlightStyle.secondary(self.isHighlighted))
    }
}

#Preview("MenuStatBadge Examples") {
    VStack(alignment: .leading, spacing: 12) {
        MenuStatBadge(value: 5, systemImage: "text.bubble")
        MenuStatBadge(label: "Comments", value: 42, systemImage: "text.bubble")
        MenuStatBadge(value: 1234, systemImage: "checkmark.bubble")
        MenuStatBadge(value: 5600, systemImage: "text.bubble")
        MenuStatBadge(value: 1_234_567, systemImage: "text.bubble")
        MenuStatBadge(valueText: "Custom", systemImage: "star.fill")
    }
    .padding()
}
