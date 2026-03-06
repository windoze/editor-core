import AppKit
@testable import EditorCoreAppKit
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewGutterWidthTests: XCTestCase {
    func testGutterWidthExpandsForFourDigitLineNumbers() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
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

    func testGutterWidthUpdatesWhenLineCountCrossesThreshold() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
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

