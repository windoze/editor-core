import AppKit
import EditorCoreAppKit
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewWordMovementTests: XCTestCase {
    func testWordMovementAndWordDeletionCommands() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "one two", viewportWidthCells: 80)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()

        // Word-right: 0 -> 3 -> 4.
        try view.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)
        view.doCommand(by: #selector(NSResponder.moveWordRight(_:)))
        var s = try view.editor.selectionOffsets()
        XCTAssertEqual(s.start, 3)
        XCTAssertEqual(s.end, 3)
        view.doCommand(by: #selector(NSResponder.moveWordRight(_:)))
        s = try view.editor.selectionOffsets()
        XCTAssertEqual(s.start, 4)
        XCTAssertEqual(s.end, 4)

        // Shift+Option right: extend selection.
        try view.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)
        view.doCommand(by: #selector(NSResponder.moveWordRightAndModifySelection(_:)))
        s = try view.editor.selectionOffsets()
        XCTAssertEqual(s.start, 0)
        XCTAssertEqual(s.end, 3)

        // Delete word back from end.
        try view.editor.setSelections([EcuSelectionRange(start: 7, end: 7)], primaryIndex: 0)
        view.doCommand(by: #selector(NSResponder.deleteWordBackward(_:)))
        XCTAssertEqual(try view.editor.text(), "one ")
    }
}
