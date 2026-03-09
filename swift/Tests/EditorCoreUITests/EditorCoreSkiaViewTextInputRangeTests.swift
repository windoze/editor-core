import AppKit
import EditorCoreUI
import EditorCoreUIFFI
import Foundation
import XCTest

@MainActor
final class EditorCoreSkiaViewTextInputRangeTests: XCTestCase {
    func testSelectedRangeUTF16CountsEmojiCorrectly() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "a😀b", viewportWidthCells: 80)

        // Scalar offsets: "a"(1) + "😀"(1) + "b"(1)
        // Put caret after emoji => scalar offset 2.
        try view.editor.setSelections([EcuSelectionRange(start: 2, end: 2)], primaryIndex: 0)

        // UTF-16 offsets: "a"(1) + "😀"(2) => 3
        let r1 = view.selectedRange()
        XCTAssertEqual(r1.location, 3)
        XCTAssertEqual(r1.length, 0)

        // Second call should hit view-side cache but return identical results.
        let r2 = view.selectedRange()
        XCTAssertEqual(r2.location, 3)
        XCTAssertEqual(r2.length, 0)
    }

    func testMarkedRangeUTF16CountsEmojiCorrectly() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "", viewportWidthCells: 80)

        // Marked text includes an emoji (surrogate pair in UTF-16).
        view.setMarkedText(
            "a😀b",
            selectedRange: NSRange(location: 4, length: 0), // caret at end of marked text (UTF-16)
            replacementRange: NSRange(location: NSNotFound, length: 0)
        )

        let marked = view.markedRange()
        XCTAssertEqual(marked.location, 0)
        XCTAssertEqual(marked.length, 4) // a(1) + 😀(2) + b(1)

        // Second call should hit cache but stay correct.
        let marked2 = view.markedRange()
        XCTAssertEqual(marked2.location, 0)
        XCTAssertEqual(marked2.length, 4)
    }
}

