import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class EditorCoreSkiaViewFormattingTests: XCTestCase {
    func testLspFormattingResultReportsUnavailableWhenLspDisabled() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "abc\n", viewportWidthCells: 80)

        let unavailable = EditorCoreLSPFormattingResult.unavailable("LSP is not enabled for this document.")
        XCTAssertEqual(view.formatDocumentWithLSPResult(timeoutMs: 50), unavailable)
        XCTAssertEqual(view.formatRangeWithLSPResult(startOffset: 0, endOffset: 3, timeoutMs: 50), unavailable)
        XCTAssertEqual(
            view.formatOnTypeWithLSPResult(logicalLine: 0, logicalColumn: 3, trigger: "\n", timeoutMs: 50),
            unavailable
        )
    }

    func testLegacyLspFormattingBoolAPIRemainsFalseWhenUnavailable() throws {
        let lib = try EditorCoreUITestSupport.shared.loadLibrary()
        let view = try EditorCoreSkiaView(library: lib, initialText: "abc\n", viewportWidthCells: 80)

        XCTAssertFalse(view.formatDocumentWithLSP(timeoutMs: 50))
        XCTAssertFalse(view.formatRangeWithLSP(startOffset: 0, endOffset: 3, timeoutMs: 50))
        XCTAssertFalse(view.formatOnTypeWithLSP(logicalLine: 0, logicalColumn: 3, trigger: "\n", timeoutMs: 50))
    }
}
