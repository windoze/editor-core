import AppKit
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewClipboardTests: XCTestCase {
    func testCopyCutPasteUseInjectedPasteboard() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "one two three", viewportWidthCells: 80)

        // Use a private pasteboard to avoid touching the user's real clipboard.
        let pb = NSPasteboard(name: NSPasteboard.Name("EditorCoreSkiaViewClipboardTests-\(UUID().uuidString)"))
        pb.clearContents()
        view.pasteboard = pb

        // Put the view in a real window to match demo behavior.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()

        // Copy "one".
        try view.editor.setSelections([EcuSelectionRange(start: 0, end: 3)], primaryIndex: 0)
        view.copy(nil)
        XCTAssertEqual(pb.string(forType: .string), "one")

        // Cut "two".
        try view.editor.setSelections([EcuSelectionRange(start: 4, end: 7)], primaryIndex: 0)
        view.cut(nil)
        XCTAssertEqual(pb.string(forType: .string), "two")
        XCTAssertEqual(try view.editor.text(), "one  three")
        let selAfterCut = try view.editor.selectionOffsets()
        XCTAssertEqual(selAfterCut.start, 4)
        XCTAssertEqual(selAfterCut.end, 4)
        XCTAssertEqual(try view.editor.selectedText(), "")

        // Paste inserts at caret.
        pb.clearContents()
        pb.setString("XYZ", forType: .string)
        try view.editor.setSelections([EcuSelectionRange(start: 4, end: 4)], primaryIndex: 0)
        view.paste(nil)
        XCTAssertEqual(try view.editor.text(), "one XYZ three")
    }

    func testCutWithEmptySelectionIsNoOp() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "abc", viewportWidthCells: 80)

        let pb = NSPasteboard(name: NSPasteboard.Name("EditorCoreSkiaViewClipboardTests-\(UUID().uuidString)"))
        pb.clearContents()
        pb.setString("old", forType: .string)
        view.pasteboard = pb

        // Empty selection (caret): cut should do nothing.
        try view.editor.setSelections([EcuSelectionRange(start: 1, end: 1)], primaryIndex: 0)
        view.cut(nil)
        XCTAssertEqual(pb.string(forType: .string), "old")
        XCTAssertEqual(try view.editor.text(), "abc")
    }

    func testPasteScrollsToKeepCaretVisible() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "", viewportWidthCells: 80)

        let pb = NSPasteboard(name: NSPasteboard.Name("EditorCoreSkiaViewClipboardTests-\(UUID().uuidString)"))
        pb.clearContents()
        view.pasteboard = pb

        // Use a small window so the caret must leave the viewport after pasting many lines.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 90),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()

        let vp0 = try view.editor.viewportState()
        XCTAssertEqual(vp0.scrollTop, 0)

        let bigText = (0..<200).map(String.init).joined(separator: "\n")
        pb.setString(bigText, forType: .string)
        view.paste(nil)

        let vp1 = try view.editor.viewportState()
        XCTAssertGreaterThan(vp1.scrollTop, 0, "expected paste to scroll the viewport to keep caret visible")
    }
}
