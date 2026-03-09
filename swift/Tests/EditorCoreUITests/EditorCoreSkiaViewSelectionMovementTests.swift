import AppKit
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewSelectionMovementTests: XCTestCase {
    func testMoveUpDownWithSelectionCollapsesToCaretAndMoves() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "aaa\nbbb\nccc", viewportWidthCells: 80)

        // Put the view in a real window so the view lifecycle matches the demo.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()

        // Select "bbb" (offset 4..7). This places the caret at the active end (offset 7).
        try view.editor.setSelections([EcuSelectionRange(start: 4, end: 7)], primaryIndex: 0)
        let s0 = try view.editor.selectionOffsets()
        XCTAssertEqual(s0.start, 4)
        XCTAssertEqual(s0.end, 7)

        // Up arrow (no shift): selection should collapse to the caret, then move up.
        view.doCommand(by: #selector(NSResponder.moveUp(_:)))
        let s1 = try view.editor.selectionOffsets()
        XCTAssertEqual(s1.start, 3)
        XCTAssertEqual(s1.end, 3)

        // Re-create selection and move down: should collapse and move to line 2 col 3 => offset 11.
        try view.editor.setSelections([EcuSelectionRange(start: 4, end: 7)], primaryIndex: 0)
        view.doCommand(by: #selector(NSResponder.moveDown(_:)))
        let s2 = try view.editor.selectionOffsets()
        XCTAssertEqual(s2.start, 11)
        XCTAssertEqual(s2.end, 11)
    }
}
