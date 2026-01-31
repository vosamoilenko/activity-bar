//
//  LabelChipView.swift
//  ActivityBar
//
//  Created by Ralph Agent on 2026-01-20.
//

import SwiftUI
import AppKit
import Core

/// Displays issue/PR labels as colored chips in a flow layout
struct MenuLabelChipsView: View {
    let labels: [ActivityLabel]
    @Environment(\.menuItemHighlighted) private var isHighlighted

    var body: some View {
        FlowLayout(itemSpacing: 6, lineSpacing: 4) {
            ForEach(labels, id: \.id) { label in
                LabelChipView(label: label, isHighlighted: isHighlighted)
            }
        }
    }
}

/// Individual label chip with colored dot and text
private struct LabelChipView: View {
    let label: ActivityLabel
    let isHighlighted: Bool
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let base = LabelColorParser.nsColor(from: label.color) ?? .separatorColor
        let baseColor = Color(nsColor: base)

        // Consistent opacity across light/dark mode
        let fillOpacity: CGFloat = 0.16
        let strokeOpacity: CGFloat = colorScheme == .dark ? 0.45 : 0.85

        // Adaptive colors based on highlight state
        let fill = isHighlighted ? .white.opacity(0.16) : baseColor.opacity(fillOpacity)
        let stroke = isHighlighted ? .white.opacity(0.30) : baseColor.opacity(strokeOpacity)
        let dot = isHighlighted ? .white.opacity(0.85) : baseColor
        let text = isHighlighted ? Color.white.opacity(0.95) : Color(nsColor: .labelColor)

        HStack(spacing: 5) {
            Circle()
                .fill(dot)
                .frame(width: 6, height: 6)
            Text(label.name)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(text)
                .lineLimit(1)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 2)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(fill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(stroke, lineWidth: 1)
        )
    }
}

/// Parses hex color strings to NSColor
enum LabelColorParser {
    /// Parses hex color string (with or without # prefix) to NSColor
    /// - Parameter hex: Hex color string (e.g., "#FF0000" or "FF0000")
    /// - Returns: NSColor if parsing succeeds, nil otherwise
    static func nsColor(from hex: String) -> NSColor? {
        let cleaned = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        guard cleaned.count == 6, let value = Int(cleaned, radix: 16) else { return nil }
        let r = CGFloat((value >> 16) & 0xFF) / 255.0
        let g = CGFloat((value >> 8) & 0xFF) / 255.0
        let b = CGFloat(value & 0xFF) / 255.0
        return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
    }
}

// MARK: - Previews

#Preview("Label Chips - Light Mode") {
    let labels = [
        ActivityLabel(id: "1", name: "bug", color: "d73a4a"),
        ActivityLabel(id: "2", name: "enhancement", color: "a2eeef"),
        ActivityLabel(id: "3", name: "documentation", color: "0075ca"),
        ActivityLabel(id: "4", name: "good first issue", color: "7057ff"),
    ]

    return VStack(spacing: 16) {
        MenuLabelChipsView(labels: labels)
            .environment(\.menuItemHighlighted, false)
            .padding()

        MenuLabelChipsView(labels: labels)
            .environment(\.menuItemHighlighted, true)
            .padding()
            .background(Color.accentColor)
    }
    .frame(width: 300)
}

#Preview("Label Chips - Dark Mode") {
    let labels = [
        ActivityLabel(id: "1", name: "bug", color: "d73a4a"),
        ActivityLabel(id: "2", name: "enhancement", color: "a2eeef"),
        ActivityLabel(id: "3", name: "documentation", color: "0075ca"),
        ActivityLabel(id: "4", name: "good first issue", color: "7057ff"),
    ]

    return VStack(spacing: 16) {
        MenuLabelChipsView(labels: labels)
            .environment(\.menuItemHighlighted, false)
            .padding()

        MenuLabelChipsView(labels: labels)
            .environment(\.menuItemHighlighted, true)
            .padding()
            .background(Color.accentColor)
    }
    .frame(width: 300)
    .preferredColorScheme(.dark)
}

#Preview("Edge Cases") {
    let labels = [
        ActivityLabel(id: "1", name: "very long label name that should truncate", color: "d73a4a"),
        ActivityLabel(id: "2", name: "短", color: "a2eeef"),
        ActivityLabel(id: "3", name: "🚀 rocket", color: "0075ca"),
    ]

    return MenuLabelChipsView(labels: labels)
        .environment(\.menuItemHighlighted, false)
        .padding()
        .frame(width: 250)
}
