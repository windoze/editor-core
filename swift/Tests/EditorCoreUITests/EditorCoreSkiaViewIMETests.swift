import AppKit
import EditorCoreUI
import EditorCoreUIFFI
import Foundation
import XCTest

@MainActor
final class EditorCoreSkiaViewIMETests: XCTestCase {
    func testSetMarkedTextConvertsUTF16SelectionToScalarOffsetsWithEmoji() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "abc", viewportWidthCells: 80)

        // Put caret at end of "abc" (char offsets use Unicode scalar count).
        try view.editor.setSelections([EcuSelectionRange(start: 3, end: 3)], primaryIndex: 0)

        // Marked text contains an emoji (surrogate pair in UTF-16).
        // UTF-16 offsets for "a😀b": a(1) + 😀(2) + b(1) => total 4
        // selectedRange.location=3 means caret after "a😀".
        view.setMarkedText(
            "a😀b",
            selectedRange: NSRange(location: 3, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        XCTAssertEqual(try view.editor.text(), "abca😀b")
        let sel = try view.editor.selectionOffsets()
        XCTAssertEqual(sel.start, 5) // "abc"(3) + ("a😀" = 2 scalars)
        XCTAssertEqual(sel.end, 5)
    }

    func testSetMarkedTextHonorsReplacementRangeUTF16WhenDocumentContainsEmoji() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "a😀b", viewportWidthCells: 80)

        // Replace the emoji (UTF-16: location 1, length 2) with marked text "你".
        view.setMarkedText(
            "你",
            selectedRange: NSRange(location: 1, length: 0), // caret at end of marked text
            replacementRange: NSRange(location: 1, length: 2)
        )

        XCTAssertEqual(try view.editor.text(), "a你b")
        let sel = try view.editor.selectionOffsets()
        XCTAssertEqual(sel.start, 2)
        XCTAssertEqual(sel.end, 2)
    }

    func testCancelOperationRestoresOriginalReplacedSelection() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "abcXYZdef", viewportWidthCells: 80)

        // Select "XYZ" (char offsets).
        try view.editor.setSelections([EcuSelectionRange(start: 3, end: 6)], primaryIndex: 0)

        // Start composition without explicit replacementRange (Rust should use the current selection).
        view.setMarkedText(
            "你",
            selectedRange: NSRange(location: 1, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        XCTAssertEqual(try view.editor.text(), "abc你def")

        // Escape: cancel composition => restore original text + selection.
        view.doCommand(by: #selector(NSResponder.cancelOperation(_:)))
        XCTAssertEqual(try view.editor.text(), "abcXYZdef")
        let sel = try view.editor.selectionOffsets()
        XCTAssertEqual(sel.start, 3)
        XCTAssertEqual(sel.end, 6)
    }

    func testFirstRectUsesCaretDuringMarkedTextSoCandidateWindowDoesNotJump() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()

        // Put the view into a window so `firstRect(forCharacterRange:)` can return screen coords.
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 200),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )

        let view = try EditorCoreSkiaView(library: lib, initialText: "", viewportWidthCells: 80)
        view.frame = NSRect(x: 0, y: 0, width: 400, height: 200)
        window.contentView = view
        view.layoutSubtreeIfNeeded()

        // Start a marked text session and place the caret at the end of the marked string.
        view.setMarkedText(
            "hanzi",
            selectedRange: NSRange(location: 5, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )
        let marked = view.markedRange()
        XCTAssertNotEqual(marked.location, NSNotFound)

        let rectEnd = view.firstRect(forCharacterRange: marked, actualRange: nil)
        XCTAssertNotEqual(rectEnd, .zero)

        // Update the same marked string but move the caret to the start.
        view.setMarkedText(
            "hanzi",
            selectedRange: NSRange(location: 0, length: 0),
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        let rectStart = view.firstRect(forCharacterRange: marked, actualRange: nil)
        XCTAssertNotEqual(rectStart, .zero)

        // If `firstRect` follows the caret (selectedRange), the X position should change.
        XCTAssertGreaterThan(rectEnd.minX, rectStart.minX + 0.5)
    }
}

final class EditorCoreUITestSupport: @unchecked Sendable {
    static let shared = EditorCoreUITestSupport()

    func loadLibrary() throws -> EditorCoreUIFFILibrary {
        // SwiftPM 通过 Rust `staticlib` 静态链接进来；这里不需要额外加载 dylib。
        return EditorCoreUIFFILibrary()
    }
}
