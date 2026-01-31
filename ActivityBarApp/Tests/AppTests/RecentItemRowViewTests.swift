import XCTest
import SwiftUI
@testable import App

final class RecentItemRowViewTests: XCTestCase {

    // MARK: - Initialization Tests

    func testDefaultAlignment() {
        var openCalled = false
        let view = RecentItemRowView(onOpen: { openCalled = true }) {
            Text("Leading")
        } content: {
            Text("Content")
        }

        XCTAssertEqual(view.alignment, .top)
    }

    func testCustomAlignment() {
        var openCalled = false
        let view = RecentItemRowView(alignment: .center, onOpen: { openCalled = true }) {
            Text("Leading")
        } content: {
            Text("Content")
        }

        XCTAssertEqual(view.alignment, .center)
    }

    func testDefaultSpacing() {
        var openCalled = false
        let view = RecentItemRowView(onOpen: { openCalled = true }) {
            Text("Leading")
        } content: {
            Text("Content")
        }

        XCTAssertEqual(view.leadingSpacing, 8)
    }

    func testCustomLeadingSpacing() {
        var openCalled = false
        let view = RecentItemRowView(leadingSpacing: 12, onOpen: { openCalled = true }) {
            Text("Leading")
        } content: {
            Text("Content")
        }

        XCTAssertEqual(view.leadingSpacing, 12)
    }

    func testDefaultHorizontalPadding() {
        var openCalled = false
        let view = RecentItemRowView(onOpen: { openCalled = true }) {
            Text("Leading")
        } content: {
            Text("Content")
        }

        XCTAssertEqual(view.horizontalPadding, 10)
    }

    func testCustomHorizontalPadding() {
        var openCalled = false
        let view = RecentItemRowView(horizontalPadding: 15, onOpen: { openCalled = true }) {
            Text("Leading")
        } content: {
            Text("Content")
        }

        XCTAssertEqual(view.horizontalPadding, 15)
    }

    func testDefaultVerticalPadding() {
        var openCalled = false
        let view = RecentItemRowView(onOpen: { openCalled = true }) {
            Text("Leading")
        } content: {
            Text("Content")
        }

        XCTAssertEqual(view.verticalPadding, 6)
    }

    func testCustomVerticalPadding() {
        var openCalled = false
        let view = RecentItemRowView(verticalPadding: 8, onOpen: { openCalled = true }) {
            Text("Leading")
        } content: {
            Text("Content")
        }

        XCTAssertEqual(view.verticalPadding, 8)
    }

    // MARK: - Callback Tests

    func testOnOpenCallbackStored() {
        var callbackExecuted = false
        let view = RecentItemRowView(onOpen: { callbackExecuted = true }) {
            Text("Leading")
        } content: {
            Text("Content")
        }

        view.onOpen()
        XCTAssertTrue(callbackExecuted)
    }

    // MARK: - View Builder Tests

    func testLeadingViewBuilder() {
        var openCalled = false
        let view = RecentItemRowView(onOpen: { openCalled = true }) {
            Image(systemName: "person.circle")
        } content: {
            Text("Content")
        }

        // View is constructed without error - ViewBuilder works
        XCTAssertNotNil(view.leading)
    }

    func testContentViewBuilder() {
        var openCalled = false
        let view = RecentItemRowView(onOpen: { openCalled = true }) {
            Text("Leading")
        } content: {
            VStack {
                Text("Line 1")
                Text("Line 2")
            }
        }

        // View is constructed without error - ViewBuilder works
        XCTAssertNotNil(view.content)
    }

    // MARK: - Full Configuration Test

    func testFullConfiguration() {
        var openCalled = false
        let view = RecentItemRowView(
            alignment: .bottom,
            leadingSpacing: 10,
            horizontalPadding: 12,
            verticalPadding: 8,
            onOpen: { openCalled = true }
        ) {
            Image(systemName: "star")
        } content: {
            VStack {
                Text("Title")
                Text("Subtitle")
            }
        }

        XCTAssertEqual(view.alignment, .bottom)
        XCTAssertEqual(view.leadingSpacing, 10)
        XCTAssertEqual(view.horizontalPadding, 12)
        XCTAssertEqual(view.verticalPadding, 8)

        view.onOpen()
        XCTAssertTrue(openCalled)
    }

    // MARK: - Edge Cases

    func testZeroPadding() {
        var openCalled = false
        let view = RecentItemRowView(
            horizontalPadding: 0,
            verticalPadding: 0,
            onOpen: { openCalled = true }
        ) {
            Text("Leading")
        } content: {
            Text("Content")
        }

        XCTAssertEqual(view.horizontalPadding, 0)
        XCTAssertEqual(view.verticalPadding, 0)
    }

    func testZeroSpacing() {
        var openCalled = false
        let view = RecentItemRowView(
            leadingSpacing: 0,
            onOpen: { openCalled = true }
        ) {
            Text("Leading")
        } content: {
            Text("Content")
        }

        XCTAssertEqual(view.leadingSpacing, 0)
    }

    func testMultipleCallbackExecutions() {
        var callCount = 0
        let view = RecentItemRowView(onOpen: { callCount += 1 }) {
            Text("Leading")
        } content: {
            Text("Content")
        }

        view.onOpen()
        view.onOpen()
        view.onOpen()

        XCTAssertEqual(callCount, 3)
    }
}
