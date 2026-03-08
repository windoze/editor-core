import AppKit
@testable import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewMultiViewTests: XCTestCase {
    func testClonedEditorCanBeEmbeddedInSecondSkiaView() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view1 = try EditorCoreSkiaView(library: lib, initialText: "abc\ndef\nghi\n", viewportWidthCells: 80)

        let cloned = try view1.editor.cloneView(viewportWidthCells: 80)
        let view2 = try EditorCoreSkiaView(editor: cloned)

        try view1.editor.insertText("X")
        XCTAssertEqual(try view2.editor.text(), "Xabc\ndef\nghi\n")
    }
}

