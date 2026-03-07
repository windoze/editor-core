import AppKit
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewExtraKeyBindingsTests: XCTestCase {
    func testInsertTabSelectorUsesCoreTabBehavior() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "abc", viewportWidthCells: 80)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()

        // Default is spaces mode, tab_width=4. Caret at end of "abc" => inserts 1 space.
        try view.editor.setSelections([EcuSelectionRange(start: 3, end: 3)], primaryIndex: 0)
        view.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(try view.editor.text(), "abc ")
    }

    func testInsertTabIndentsLineSelectionWithoutIndentingTrailingLine() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "a\nb\n", viewportWidthCells: 80)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()

        // Select the first line including its trailing newline (half-open: 0..<2).
        try view.editor.setSelections([EcuSelectionRange(start: 0, end: 2)], primaryIndex: 0)
        view.doCommand(by: #selector(NSResponder.insertTab(_:)))
        XCTAssertEqual(try view.editor.text(), "    a\nb\n")
    }

    func testLeftRightEndOfLineSelectorsAreHandled() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
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

        view.doCommand(by: #selector(NSResponder.moveToLeftEndOfLine(_:)))
        var s = try view.editor.selectionOffsets()
        XCTAssertEqual(s.start, 0)
        XCTAssertEqual(s.end, 0)

        try view.editor.setSelections([EcuSelectionRange(start: 2, end: 2)], primaryIndex: 0)
        view.doCommand(by: #selector(NSResponder.moveToRightEndOfLine(_:)))
        s = try view.editor.selectionOffsets()
        XCTAssertEqual(s.start, 3)
        XCTAssertEqual(s.end, 3)

        // Shift+Home variant (bidi-aware selector).
        try view.editor.setSelections([EcuSelectionRange(start: 2, end: 2)], primaryIndex: 0)
        view.doCommand(by: #selector(NSResponder.moveToLeftEndOfLineAndModifySelection(_:)))
        s = try view.editor.selectionOffsets()
        XCTAssertEqual(s.start, 0)
        XCTAssertEqual(s.end, 2)
    }

    func testScrollPageUpDownSelectorsAreHandled() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let text = (0..<80).map(String.init).joined(separator: "\n")
        let view = try EditorCoreSkiaView(library: lib, initialText: text, viewportWidthCells: 80)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 90),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()

        try view.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)
        view.doCommand(by: #selector(NSResponder.scrollPageDown(_:)))
        var s = try view.editor.selectionOffsets()
        XCTAssertGreaterThan(s.start, 0)
        XCTAssertEqual(s.start, s.end)

        view.doCommand(by: #selector(NSResponder.scrollPageUp(_:)))
        s = try view.editor.selectionOffsets()
        XCTAssertEqual(s.start, 0)
        XCTAssertEqual(s.end, 0)
    }

    func testScrollPageDownModifySelectionSelectorIsHandled() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let text = (0..<80).map(String.init).joined(separator: "\n")
        let view = try EditorCoreSkiaView(library: lib, initialText: text, viewportWidthCells: 80)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 90),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()

        try view.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)
        view.doCommand(by: Selector(("scrollPageDownAndModifySelection:")))
        let s = try view.editor.selectionOffsets()
        XCTAssertEqual(s.start, 0)
        XCTAssertGreaterThan(s.end, 0)
    }

    func testScrollToBeginEndOfDocumentSelectorsAreHandled() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
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

        try view.editor.setSelections([EcuSelectionRange(start: 2, end: 2)], primaryIndex: 0)

        view.doCommand(by: #selector(NSResponder.scrollToBeginningOfDocument(_:)))
        var s = try view.editor.selectionOffsets()
        XCTAssertEqual(s.start, 0)
        XCTAssertEqual(s.end, 0)

        view.doCommand(by: #selector(NSResponder.scrollToEndOfDocument(_:)))
        s = try view.editor.selectionOffsets()
        XCTAssertEqual(s.start, 7)
        XCTAssertEqual(s.end, 7)
    }

    func testScrollToDocumentModifySelectionSelectorsAreHandled() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
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

        try view.editor.setSelections([EcuSelectionRange(start: 2, end: 2)], primaryIndex: 0)

        view.doCommand(by: Selector(("scrollToBeginningOfDocumentAndModifySelection:")))
        var s = try view.editor.selectionOffsets()
        XCTAssertEqual(s.start, 0)
        XCTAssertEqual(s.end, 2)

        try view.editor.setSelections([EcuSelectionRange(start: 2, end: 2)], primaryIndex: 0)
        view.doCommand(by: Selector(("scrollToEndOfDocumentAndModifySelection:")))
        s = try view.editor.selectionOffsets()
        XCTAssertEqual(s.start, 2)
        XCTAssertEqual(s.end, 7)
    }
}
