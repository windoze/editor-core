import EditorCoreAppKit
import EditorCoreUIFFI
import Foundation
import XCTest

@MainActor
final class EditorCoreSkiaViewAsyncProcessingTests: XCTestCase {
    func testAsyncProcessingPollTimerAppliesEdits() throws {
        let lib = try EditorCoreAppKitTestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(
            library: lib,
            initialText: "fn main() {\n  let x = 1;\n}\n",
            viewportWidthCells: 80
        )

        try view.editor.treeSitterRustEnableDefault()

        let applied = expectation(description: "applied async processing")
        view.onDidApplyAsyncProcessing = {
            applied.fulfill()
        }

        // Trigger a text mutation so the view starts its polling timer.
        view.insertText(" ", replacementRange: NSRange(location: NSNotFound, length: 0))

        wait(for: [applied], timeout: 2.0)
    }
}
