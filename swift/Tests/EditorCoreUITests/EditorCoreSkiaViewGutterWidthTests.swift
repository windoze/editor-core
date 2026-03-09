import AppKit
@testable import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewGutterWidthTests: XCTestCase {
    func testRequiredGutterWidthAddsPaddingForFiveAndSevenDigitLineNumbers() {
        // 10_000 lines => last visible line number has 5 digits.
        XCTAssertEqual(EditorCoreSkiaView.requiredGutterWidthCells(lineCount: 10_000), 7)
        // 1_000_000 lines => 7 digits.
        XCTAssertEqual(EditorCoreSkiaView.requiredGutterWidthCells(lineCount: 1_000_000), 9)
    }

    func testGutterWidthExpandsForFourDigitLineNumbers() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let text = (0..<1000).map(String.init).joined(separator: "\n") // 1000 logical lines
        let view = try EditorCoreSkiaView(library: lib, initialText: text, viewportWidthCells: 80)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 400),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()

        let gutter = try view.editor.gutterWidthCells()
        XCTAssertEqual(gutter, 5, "expected gutter to be 1(fold) + 4(digits) cells for 1000 lines")
    }

    func testGutterWidthExpandsForFiveDigitLineNumbers() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        // 10_000 logical lines (avoid heavy strings; content is irrelevant for gutter sizing).
        let text = String(repeating: "\n", count: 9_999)
        let view = try EditorCoreSkiaView(library: lib, initialText: text, viewportWidthCells: 80)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(try view.editor.gutterWidthCells(), 7)
    }

    func testGutterWidthUpdatesWhenLineCountCrossesThreshold() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let text = (0..<999).map(String.init).joined(separator: "\n") // 999 logical lines
        let view = try EditorCoreSkiaView(library: lib, initialText: text, viewportWidthCells: 80)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 200),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()

        XCTAssertEqual(try view.editor.gutterWidthCells(), 4)

        // Add a trailing newline => 1000 lines => gutter should expand to 5 cells.
        try view.editor.moveToDocumentEnd()
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(try view.editor.gutterWidthCells(), 5)
    }
}
