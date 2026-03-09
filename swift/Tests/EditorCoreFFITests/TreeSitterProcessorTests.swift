import Foundation
import XCTest
@testable import EditorCoreFFI

final class TreeSitterProcessorTests: XCTestCase {
    func testTreeSitterHighlightsFoldsAndUpdateMode() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()

        let rust = """
        fn main() {
            let value = 1;
        }
        """

        let state = try EditorState(library: library, initialText: rust, viewportWidth: 80)

        let highlightsQuery = "(identifier) @id"
        let foldsQuery = """
        (function_item) @fold
        (impl_item) @fold
        (struct_item) @fold
        (enum_item) @fold
        (mod_item) @fold
        (block) @fold
        """
        let captureStylesJSON = #"{"id":777}"#

        // process_json API: compute edits without mutating state
        let processOnly = try TreeSitterProcessor(
            library: library,
            languageFn: library.treeSitterRustLanguageFn,
            highlightsQuery: highlightsQuery,
            foldsQuery: foldsQuery,
            captureStylesJSON: captureStylesJSON,
            styleLayer: 424242,
            preserveCollapsedFolds: true
        )

        let processed = try JSONTestHelpers.object(try processOnly.processJSON(state: state))
        let edits = (processed["edits"] as? [Any]) ?? []
        XCTAssertGreaterThanOrEqual(edits.count, 1)
        let ops = edits.compactMap { ($0 as? [String: Any])?["op"] as? String }
        XCTAssertTrue(ops.contains("replace_style_layer"))
        XCTAssertTrue(ops.contains("replace_folding_regions"))

        // apply API: actually mutates derived state inside editor
        let processor = try TreeSitterProcessor(
            library: library,
            languageFn: library.treeSitterRustLanguageFn,
            highlightsQuery: highlightsQuery,
            foldsQuery: foldsQuery,
            captureStylesJSON: captureStylesJSON,
            styleLayer: 424242,
            preserveCollapsedFolds: true
        )

        try processor.apply(state: state)

        let blob = try state.viewportBlob(startVisualRow: 0, rowCount: 50)
        XCTAssertTrue(blob.styleIds.contains(777))

        let full1 = try JSONTestHelpers.object(try state.fullStateJSON())
        let folding1 = (full1["folding"] as? [String: Any]) ?? [:]
        let regions1 = (folding1["regions"] as? [Any]) ?? []
        XCTAssertGreaterThan(regions1.count, 0)

        let mode1 = try processor.lastUpdateMode()
        XCTAssertEqual(mode1, "initial")

        // make a small edit; next update should not be "initial" or "skipped"
        try state.moveTo(line: 1, column: 0)
        try state.insertText("x")
        try processor.apply(state: state)
        let mode2 = try processor.lastUpdateMode()
        XCTAssertNotEqual(mode2, "initial")
        XCTAssertNotEqual(mode2, "skipped")
    }

    func testTreeSitterFoldPreserveCollapsedFlag() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let rust = """
        fn main() {
            let value = 1;
        }
        """
        let state = try EditorState(library: library, initialText: rust, viewportWidth: 80)

        let highlightsQuery = "(identifier) @id"
        let foldsQuery = "(function_item) @fold\n(block) @fold\n"
        let captureStylesJSON = #"{"id":1}"#

        let preserveProcessor = try TreeSitterProcessor(
            library: library,
            languageFn: library.treeSitterRustLanguageFn,
            highlightsQuery: highlightsQuery,
            foldsQuery: foldsQuery,
            captureStylesJSON: captureStylesJSON,
            styleLayer: 111,
            preserveCollapsedFolds: true
        )
        try preserveProcessor.apply(state: state)

        // manually collapse an expected region
        let collapse = """
        {
          "op": "replace_folding_regions",
          "regions": [
            { "start_line": 0, "end_line": 2, "is_collapsed": true, "placeholder": "[...]" }
          ],
          "preserve_collapsed": false
        }
        """
        try state.applyProcessingEditsJSON(collapse)

        try preserveProcessor.apply(state: state)
        let full1 = try JSONTestHelpers.object(try state.fullStateJSON())
        let folding1 = (full1["folding"] as? [String: Any]) ?? [:]
        let regions1 = (folding1["regions"] as? [Any]) ?? []
        XCTAssertTrue(regions1.contains { ($0 as? [String: Any])?["is_collapsed"] as? Bool == true })

        // new processor with preserve=false should reset collapsed back to false
        let resetProcessor = try TreeSitterProcessor(
            library: library,
            languageFn: library.treeSitterRustLanguageFn,
            highlightsQuery: highlightsQuery,
            foldsQuery: foldsQuery,
            captureStylesJSON: captureStylesJSON,
            styleLayer: 222,
            preserveCollapsedFolds: false
        )
        try resetProcessor.apply(state: state)
        let full2 = try JSONTestHelpers.object(try state.fullStateJSON())
        let folding2 = (full2["folding"] as? [String: Any]) ?? [:]
        let regions2 = (folding2["regions"] as? [Any]) ?? []
        XCTAssertFalse(regions2.contains { ($0 as? [String: Any])?["is_collapsed"] as? Bool == true })
    }
}
