import Foundation
import XCTest
@testable import EditorCoreFFI

final class EditorStateCoreTests: XCTestCase {
    func testTypedEditingSelectionUndoRedoAndDeltas() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let state = try EditorState(library: library, initialText: "hello\nworld\n", viewportWidth: 80)

        try state.moveTo(line: 0, column: 5)
        try state.insertText("!")

        let deltaBeforeTake = try JSONTestHelpers.object(try state.lastTextDeltaJSON())
        XCTAssertNotNil(deltaBeforeTake["delta"])

        let taken = try JSONTestHelpers.object(try state.takeLastTextDeltaJSON())
        XCTAssertNotNil(taken["delta"])

        let deltaAfterTake = try JSONTestHelpers.object(try state.lastTextDeltaJSON())
        XCTAssertTrue(deltaAfterTake["delta"] is NSNull)

        try state.setSelection(startLine: 0, startColumn: 0, endLine: 0, endColumn: 5, direction: 0)
        try state.insertText("hi")
        XCTAssertTrue((try state.text()).hasPrefix("hi"))

        try state.undo()
        XCTAssertTrue((try state.text()).hasPrefix("hello"))

        try state.redo()
        XCTAssertTrue((try state.text()).hasPrefix("hi"))

        try state.clearSelection()
        try state.moveTo(line: 1, column: 0)
        try state.moveBy(deltaLine: 0, deltaColumn: 2)

        // line ending round-trip
        try state.setLineEnding("crlf")
        let le = try JSONTestHelpers.object(try state.lineEndingJSON())
        XCTAssertEqual(le["line_ending"] as? String, "crlf")

        let saving = try JSONTestHelpers.object(try state.textForSavingJSON())
        XCTAssertEqual(saving["line_ending"] as? String, "crlf")
        let savingText = saving["text"] as? String
        XCTAssertNotNil(savingText)
        XCTAssertTrue(savingText?.contains("\r\n") ?? false)

        // JSON viewport APIs are reachable
        let styled = try JSONTestHelpers.object(try state.viewportStyledJSON(startVisualRow: 0, rowCount: 20))
        XCTAssertNotNil(styled["lines"])
        let composed = try JSONTestHelpers.object(try state.viewportComposedJSON(startVisualRow: 0, rowCount: 20))
        XCTAssertNotNil(composed["lines"])
        let minimap = try JSONTestHelpers.object(try state.minimapJSON(startVisualRow: 0, rowCount: 20))
        XCTAssertNotNil(minimap["lines"])
    }

    func testApplyProcessingEditsAffectsStylesFoldsDecorationsDiagnostics() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let state = try EditorState(library: library, initialText: "let value = 1\nsecond line\n", viewportWidth: 80)

        let editsJSON = """
        [
          {
            "op": "replace_style_layer",
            "layer": 131072,
            "intervals": [
              { "start": 0, "end": 3, "style_id": 9 }
            ]
          },
          {
            "op": "replace_folding_regions",
            "regions": [
              {
                "start_line": 0,
                "end_line": 1,
                "is_collapsed": false,
                "placeholder": "[...]"
              }
            ],
            "preserve_collapsed": false
          },
          {
            "op": "replace_decorations",
            "layer": 1,
            "decorations": [
              {
                "range": { "start": 3, "end": 3 },
                "placement": "after",
                "kind": { "kind": "inlay_hint" },
                "text": ": i32",
                "styles": [42]
              }
            ]
          },
          {
            "op": "replace_diagnostics",
            "diagnostics": [
              {
                "range": { "start": 4, "end": 9 },
                "severity": "warning",
                "message": "demo warning"
              }
            ]
          }
        ]
        """

        try state.applyProcessingEditsJSON(editsJSON)

        let blob = try state.viewportBlob(startVisualRow: 0, rowCount: 40)
        XCTAssertGreaterThan(blob.styleIds.count, 0)

        // 样式应该至少落在第 0 个 cell 上
        XCTAssertGreaterThan(blob.stylesForCell(at: 0).count, 0)

        let full = try JSONTestHelpers.object(try state.fullStateJSON())
        let diagnostics = (full["diagnostics"] as? [String: Any]) ?? [:]
        XCTAssertEqual(diagnostics["diagnostics_count"] as? Int, 1)

        let folding = (full["folding"] as? [String: Any]) ?? [:]
        let regions = (folding["regions"] as? [Any]) ?? []
        XCTAssertEqual(regions.count, 1)

        let diagList = try JSONTestHelpers.object(try state.diagnosticsJSON())
        let diagItems = (diagList["diagnostics"] as? [Any]) ?? []
        XCTAssertEqual(diagItems.count, 1)
        let diag0 = (diagItems.first as? [String: Any]) ?? [:]
        XCTAssertEqual(diag0["message"] as? String, "demo warning")

        let decorations = try JSONTestHelpers.object(try state.decorationsJSON())
        let layers = (decorations["layers"] as? [Any]) ?? []
        XCTAssertGreaterThan(layers.count, 0)

        // composed viewport: should contain virtual cells from inlay hint text
        let composed = try JSONTestHelpers.object(try state.viewportComposedJSON(startVisualRow: 0, rowCount: 20))
        let lines = (composed["lines"] as? [Any]) ?? []
        XCTAssertGreaterThan(lines.count, 0)

        var foundVirtualCell = false
        for line in lines {
            guard let lineObj = line as? [String: Any],
                  let cells = lineObj["cells"] as? [Any]
            else { continue }
            for cell in cells {
                guard let cellObj = cell as? [String: Any],
                      let source = cellObj["source"] as? [String: Any],
                      let kind = source["kind"] as? String
                else { continue }
                if kind == "virtual" {
                    foundVirtualCell = true
                    break
                }
            }
            if foundVirtualCell { break }
        }
        XCTAssertTrue(foundVirtualCell)
    }
}

