import AppKit
@testable import EditorCoreAppKit
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewMouseDragCaretTests: XCTestCase {
    func testMouseDragSelectionThenArrowMovesFromActiveEnd() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "aaaa\nbbbb\ncccc", viewportWidthCells: 80)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()

        let p0 = try view.editor.charOffsetToViewPoint(offset: 0)
        let p3 = try view.editor.charOffsetToViewPoint(offset: 3)

        // Simulate a plain drag selection from col 0 to col 3 on the first line.
        try view.editor.mouseDown(xPx: p0.xPx + 1, yPx: p0.yPx + 1)
        try view.editor.mouseDragged(xPx: p3.xPx + 1, yPx: p3.yPx + 1)
        view.editor.mouseUp()

        let s0 = try view.editor.selectionOffsets()
        XCTAssertEqual(s0.start, 0)
        XCTAssertEqual(s0.end, 3)

        // Down arrow should collapse to the active end (col 3), then move down to line 1 col 3.
        view.doCommand(by: #selector(NSResponder.moveDown(_:)))
        let s1 = try view.editor.selectionOffsets()
        XCTAssertEqual(s1.start, 8)
        XCTAssertEqual(s1.end, 8)
    }
}

