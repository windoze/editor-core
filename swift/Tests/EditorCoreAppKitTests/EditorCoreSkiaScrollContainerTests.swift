import AppKit
@testable import EditorCoreAppKit
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaScrollContainerTests: XCTestCase {
    func testScrollContainerUpdatesScrollerAndAppliesScrollState() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
        let longText = "a\nb\nc\n" + String(repeating: "x\n", count: 300)
        let editorView = try EditorCoreSkiaView(library: lib, initialText: longText, viewportWidthCells: 80)
        let container = EditorCoreSkiaScrollContainer(editorView: editorView)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = container
        window.makeKeyAndOrderFront(nil)
        container.layoutSubtreeIfNeeded()

        container._updateScrollerForTesting()

        let scroller = container._verticalScrollerForTesting
        XCTAssertFalse(scroller.isHidden)
        XCTAssertLessThan(scroller.knobProportion, 1.0)
        XCTAssertEqual(scroller.doubleValue, 0.0, accuracy: 0.0001)

        // Drag the scroller to the middle and ensure the editor scroll position changes.
        container._applyScrollerProportionForTesting(0.5)
        container._updateScrollerForTesting()

        let vp = try editorView.editor.viewportState()
        XCTAssertGreaterThan(vp.scrollTop, 0)
        XCTAssertGreaterThan(container._verticalScrollerForTesting.doubleValue, 0.0)
    }
}

