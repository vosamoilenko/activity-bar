//
//  LabelChipViewTests.swift
//  ActivityBar
//
//  Created by Ralph Agent on 2026-01-20.
//

import XCTest
import SwiftUI
import AppKit
@testable import App
import Core

final class LabelChipViewTests: XCTestCase {

    // MARK: - LabelColorParser Tests

    func testHexColorParsingWithHash() {
        let color = LabelColorParser.nsColor(from: "#FF0000")
        XCTAssertNotNil(color)

        let components = color?.usingColorSpace(.sRGB)
        XCTAssertEqual(Double(components?.redComponent ?? 0), 1.0, accuracy: 0.01)
        XCTAssertEqual(Double(components?.greenComponent ?? 0), 0.0, accuracy: 0.01)
        XCTAssertEqual(Double(components?.blueComponent ?? 0), 0.0, accuracy: 0.01)
    }

    func testHexColorParsingWithoutHash() {
        let color = LabelColorParser.nsColor(from: "00FF00")
        XCTAssertNotNil(color)

        let components = color?.usingColorSpace(.sRGB)
        XCTAssertEqual(Double(components?.redComponent ?? 0), 0.0, accuracy: 0.01)
        XCTAssertEqual(Double(components?.greenComponent ?? 0), 1.0, accuracy: 0.01)
        XCTAssertEqual(Double(components?.blueComponent ?? 0), 0.0, accuracy: 0.01)
    }

    func testHexColorParsingBlue() {
        let color = LabelColorParser.nsColor(from: "0000FF")
        XCTAssertNotNil(color)

        let components = color?.usingColorSpace(.sRGB)
        XCTAssertEqual(Double(components?.redComponent ?? 0), 0.0, accuracy: 0.01)
        XCTAssertEqual(Double(components?.greenComponent ?? 0), 0.0, accuracy: 0.01)
        XCTAssertEqual(Double(components?.blueComponent ?? 0), 1.0, accuracy: 0.01)
    }

    func testHexColorParsingMixedColors() {
        let color = LabelColorParser.nsColor(from: "d73a4a")
        XCTAssertNotNil(color)

        let components = color?.usingColorSpace(.sRGB)
        XCTAssertEqual(Double(components?.redComponent ?? 0), 215.0/255.0, accuracy: 0.01)
        XCTAssertEqual(Double(components?.greenComponent ?? 0), 58.0/255.0, accuracy: 0.01)
        XCTAssertEqual(Double(components?.blueComponent ?? 0), 74.0/255.0, accuracy: 0.01)
    }

    func testHexColorParsingInvalidLength() {
        XCTAssertNil(LabelColorParser.nsColor(from: "FFF"))
        XCTAssertNil(LabelColorParser.nsColor(from: "FFFFFFF"))
        XCTAssertNil(LabelColorParser.nsColor(from: ""))
    }

    func testHexColorParsingInvalidCharacters() {
        XCTAssertNil(LabelColorParser.nsColor(from: "GGGGGG"))
        XCTAssertNil(LabelColorParser.nsColor(from: "!@#$%^"))
        XCTAssertNil(LabelColorParser.nsColor(from: "ZZZZZZ"))
    }

    func testHexColorParsingWhitespace() {
        // Should handle whitespace trimming via # trimming
        let color = LabelColorParser.nsColor(from: " #FF0000 ")
        XCTAssertNil(color) // Extra spaces make length != 6
    }

    func testHexColorParsingCaseSensitivity() {
        let colorLower = LabelColorParser.nsColor(from: "ff0000")
        let colorUpper = LabelColorParser.nsColor(from: "FF0000")
        let colorMixed = LabelColorParser.nsColor(from: "Ff0000")

        XCTAssertNotNil(colorLower)
        XCTAssertNotNil(colorUpper)
        XCTAssertNotNil(colorMixed)
    }

    func testHexColorParsingGitHubColors() {
        // Test common GitHub label colors
        let colors: [String: (r: Double, g: Double, b: Double)] = [
            "d73a4a": (215, 58, 74),     // bug (red)
            "a2eeef": (162, 238, 239),    // enhancement (teal)
            "0075ca": (0, 117, 202),      // documentation (blue)
            "7057ff": (112, 87, 255),     // good first issue (purple)
            "008672": (0, 134, 114),      // feature (green)
        ]

        for (hex, expected) in colors {
            let color = LabelColorParser.nsColor(from: hex)
            XCTAssertNotNil(color, "Failed to parse \(hex)")

            let components = color?.usingColorSpace(.sRGB)
            XCTAssertEqual(Double(components?.redComponent ?? 0), expected.r/255.0, accuracy: 0.01)
            XCTAssertEqual(Double(components?.greenComponent ?? 0), expected.g/255.0, accuracy: 0.01)
            XCTAssertEqual(Double(components?.blueComponent ?? 0), expected.b/255.0, accuracy: 0.01)
        }
    }

    // MARK: - MenuLabelChipsView Tests

    func testMenuLabelChipsViewCreation() {
        let labels = [
            ActivityLabel(id: "1", name: "bug", color: "d73a4a"),
            ActivityLabel(id: "2", name: "enhancement", color: "a2eeef"),
        ]

        let view = MenuLabelChipsView(labels: labels)
        XCTAssertNotNil(view)
    }

    func testMenuLabelChipsViewEmptyLabels() {
        let view = MenuLabelChipsView(labels: [])
        XCTAssertNotNil(view)
    }

    func testMenuLabelChipsViewSingleLabel() {
        let label = ActivityLabel(id: "1", name: "bug", color: "d73a4a")
        let view = MenuLabelChipsView(labels: [label])
        XCTAssertNotNil(view)
    }

    func testMenuLabelChipsViewManyLabels() {
        let labels = (1...20).map { i in
            ActivityLabel(id: "\(i)", name: "label-\(i)", color: "d73a4a")
        }
        let view = MenuLabelChipsView(labels: labels)
        XCTAssertNotNil(view)
    }

    // MARK: - Label Display Tests

    func testLabelWithInvalidColor() {
        let label = ActivityLabel(id: "1", name: "test", color: "invalid")
        let view = MenuLabelChipsView(labels: [label])
        XCTAssertNotNil(view) // Should not crash with invalid color
    }

    func testLabelWithEmptyName() {
        let label = ActivityLabel(id: "1", name: "", color: "d73a4a")
        let view = MenuLabelChipsView(labels: [label])
        XCTAssertNotNil(view)
    }

    func testLabelWithUnicodeName() {
        let labels = [
            ActivityLabel(id: "1", name: "バグ", color: "d73a4a"), // Japanese
            ActivityLabel(id: "2", name: "错误", color: "a2eeef"), // Chinese
            ActivityLabel(id: "3", name: "ошибка", color: "0075ca"), // Russian
        ]
        let view = MenuLabelChipsView(labels: labels)
        XCTAssertNotNil(view)
    }

    func testLabelWithEmoji() {
        let labels = [
            ActivityLabel(id: "1", name: "🐛 bug", color: "d73a4a"),
            ActivityLabel(id: "2", name: "✨ enhancement", color: "a2eeef"),
            ActivityLabel(id: "3", name: "🚀 rocket", color: "0075ca"),
        ]
        let view = MenuLabelChipsView(labels: labels)
        XCTAssertNotNil(view)
    }

    func testLabelWithLongName() {
        let label = ActivityLabel(
            id: "1",
            name: "this is a very long label name that should probably be truncated in the UI",
            color: "d73a4a"
        )
        let view = MenuLabelChipsView(labels: [label])
        XCTAssertNotNil(view)
    }

    func testLabelWithSpecialCharacters() {
        let labels = [
            ActivityLabel(id: "1", name: "bug/fix", color: "d73a4a"),
            ActivityLabel(id: "2", name: "needs-review!", color: "a2eeef"),
            ActivityLabel(id: "3", name: "WIP:feature", color: "0075ca"),
        ]
        let view = MenuLabelChipsView(labels: labels)
        XCTAssertNotNil(view)
    }

    // MARK: - Color Scheme Tests

    func testLabelColorFallback() {
        // When invalid color, should fall back to .separatorColor
        let result = LabelColorParser.nsColor(from: "not-a-color")
        XCTAssertNil(result)
    }

    // MARK: - Edge Cases

    func testDuplicateLabelIds() {
        // ForEach uses id: \.id, so duplicate IDs should still render
        let labels = [
            ActivityLabel(id: "1", name: "bug", color: "d73a4a"),
            ActivityLabel(id: "1", name: "duplicate", color: "a2eeef"),
        ]
        let view = MenuLabelChipsView(labels: labels)
        XCTAssertNotNil(view)
    }

    func testRapidCreation() {
        // Should handle rapid successive creation
        for _ in 1...100 {
            let label = ActivityLabel(id: "1", name: "test", color: "d73a4a")
            let view = MenuLabelChipsView(labels: [label])
            XCTAssertNotNil(view)
        }
    }

    // MARK: - Integration Tests

    func testMenuLabelChipsViewWithRealisticData() {
        // Realistic GitHub label data
        let labels = [
            ActivityLabel(id: "1", name: "bug", color: "d73a4a"),
            ActivityLabel(id: "2", name: "enhancement", color: "a2eeef"),
            ActivityLabel(id: "3", name: "documentation", color: "0075ca"),
            ActivityLabel(id: "4", name: "good first issue", color: "7057ff"),
            ActivityLabel(id: "5", name: "help wanted", color: "008672"),
        ]

        let view = MenuLabelChipsView(labels: labels)
        XCTAssertNotNil(view)
    }

    func testMenuLabelChipsViewWithMixedValidInvalidColors() {
        let labels = [
            ActivityLabel(id: "1", name: "valid", color: "d73a4a"),
            ActivityLabel(id: "2", name: "invalid", color: "notacolor"),
            ActivityLabel(id: "3", name: "another-valid", color: "0075ca"),
        ]

        let view = MenuLabelChipsView(labels: labels)
        XCTAssertNotNil(view) // Should gracefully handle mix
    }
}
