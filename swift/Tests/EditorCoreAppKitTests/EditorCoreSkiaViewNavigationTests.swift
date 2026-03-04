import AppKit
import EditorCoreAppKit
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewNavigationTests: XCTestCase {
    func testLineAndDocumentNavigationCommands() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "abc\ndef", viewportWidthCells: 80)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()

        // Start at "ab|c" (offset 2).
        try view.editor.setSelections([EcuSelectionRange(start: 2, end: 2)], primaryIndex: 0)

        view.doCommand(by: #selector(NSResponder.moveToBeginningOfLine(_:)))
        var s = try view.editor.selectionOffsets()
        XCTAssertEqual(s.start, 0)
        XCTAssertEqual(s.end, 0)

        view.doCommand(by: #selector(NSResponder.moveToEndOfLine(_:)))
        s = try view.editor.selectionOffsets()
        XCTAssertEqual(s.start, 3)
        XCTAssertEqual(s.end, 3)

        view.doCommand(by: #selector(NSResponder.moveToEndOfDocument(_:)))
        s = try view.editor.selectionOffsets()
        XCTAssertEqual(s.start, 7)
        XCTAssertEqual(s.end, 7)

        // Shift+Home (extend selection to start of line).
        try view.editor.setSelections([EcuSelectionRange(start: 2, end: 2)], primaryIndex: 0)
        view.doCommand(by: #selector(NSResponder.moveToBeginningOfLineAndModifySelection(_:)))
        s = try view.editor.selectionOffsets()
        XCTAssertEqual(s.start, 0)
        XCTAssertEqual(s.end, 2)
    }
}

