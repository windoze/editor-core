import AppKit
@testable import EditorCoreAppKit
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaMinimapTests: XCTestCase {
    func testMinimapContainerShowHideTogglesWidth() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
        let editorView = try EditorCoreSkiaView(library: lib, initialText: "a\nb\nc\n", viewportWidthCells: 80)
        let container = EditorCoreSkiaMinimapContainer(editorView: editorView, showsMinimap: true, minimapWidth: 100)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        container.layoutSubtreeIfNeeded()

        XCTAssertFalse(container.minimapView.isHidden)
        XCTAssertGreaterThan(container._minimapWidthConstraintForTesting.constant, 0)

        container.showsMinimap = false
        container.layoutSubtreeIfNeeded()

        XCTAssertTrue(container.minimapView.isHidden)
        XCTAssertEqual(container._minimapWidthConstraintForTesting.constant, 0)
    }

    func testMinimapViewRefreshLoadsGrid() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
        let editorView = try EditorCoreSkiaView(library: lib, initialText: "a\nb\nc", viewportWidthCells: 80)
        let container = EditorCoreSkiaMinimapContainer(editorView: editorView, showsMinimap: true, minimapWidth: 120)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        window.makeFirstResponder(editorView)
        container.layoutSubtreeIfNeeded()

        container.minimapView._refreshNowForTesting()
        let grid = try XCTUnwrap(container.minimapView._cachedGridForTesting)
        XCTAssertEqual(grid.actualLineCount, 3)
    }
}

