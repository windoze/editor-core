import AppKit
@testable import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewGutterWidthTests: XCTestCase {
    func testRequiredGutterWidthAddsPaddingForFiveAndSevenDigitLineNumbers() {
        // 10_000 lines => last visible line number has 5 digits.
        XCTAssertEqual(EditorCoreSkiaView.requiredGutterWidthCells(lineCount: 10_000), 8)
        // 1_000_000 lines => 7 digits.
        XCTAssertEqual(EditorCoreSkiaView.requiredGutterWidthCells(lineCount: 1_000_000), 10)
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
        XCTAssertEqual(gutter, 6, "expected gutter to be 2(fold) + 4(digits) cells for 1000 lines")
    }

    func testGutterDiagnosticMarkersMapCharOffsetsToRects() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "a\nb\nc\n", viewportWidthCells: 80)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 600, height: 300),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentView = view
        window.makeKeyAndOrderFront(nil)
        view.layoutSubtreeIfNeeded()

        let markers = [
            EditorCoreSkiaGutterDiagnosticMarker(logicalLine: 0, charOffset: 0, kind: .error),
            EditorCoreSkiaGutterDiagnosticMarker(logicalLine: 2, charOffset: 4, kind: .warning),
        ]
        view.gutterDiagnosticMarkers = markers

        XCTAssertEqual(view._gutterDiagnosticMarkersForTesting, markers)
        let rects = view._gutterDiagnosticMarkerRectsForTesting()
        XCTAssertEqual(rects.count, 2)
        XCTAssertLessThan(rects[0].minY, rects[1].minY)
        XCTAssertGreaterThan(rects[0].width, 0)
        XCTAssertGreaterThan(rects[0].height, 0)
        XCTAssertGreaterThanOrEqual(rects[0].minX, 0)
        XCTAssertLessThan(rects[0].maxX, view.bounds.width)
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

        XCTAssertEqual(try view.editor.gutterWidthCells(), 8)
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

        XCTAssertEqual(try view.editor.gutterWidthCells(), 5)

        // Add a trailing newline => 1000 lines => gutter should expand to 6 cells.
        try view.editor.moveToDocumentEnd()
        view.doCommand(by: #selector(NSResponder.insertNewline(_:)))

        XCTAssertEqual(try view.editor.gutterWidthCells(), 6)
    }
}
