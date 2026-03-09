import Foundation
import XCTest
@testable import EditorCoreFFI

final class LSPBridgeTests: XCTestCase {
    func testUriAndUtf16Conversions() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let bridge = LSPBridge(library: library)

        let path = "/tmp/editor-core ffi.swift"
        let uri = try bridge.pathToFileURI(path)
        XCTAssertTrue(uri.hasPrefix("file://"))
        let roundTrip = try bridge.fileURIToPath(uri)
        XCTAssertEqual(roundTrip, path)

        let encoded = try bridge.percentEncodePath(path)
        XCTAssertTrue(encoded.contains("%20"))
        let decoded = try bridge.percentDecodePath(encoded)
        XCTAssertEqual(decoded, path)

        let text = "a🙂b"
        let utf16 = bridge.charOffsetToUTF16(lineText: text, charOffset: 2)
        XCTAssertEqual(utf16, 3)
        let scalarOffset = bridge.utf16OffsetToCharOffset(lineText: text, utf16Offset: utf16)
        XCTAssertEqual(scalarOffset, 2)
    }

    func testApplyTextEditsSemanticTokensAndCompletion() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let bridge = LSPBridge(library: library)
        let state = try EditorState(library: library, initialText: "abc\n", viewportWidth: 80)

        let editsJSON = """
        [
          {
            "range": {
              "start": { "line": 0, "character": 1 },
              "end": { "line": 0, "character": 2 }
            },
            "newText": "Z"
          }
        ]
        """
        let changed = try bridge.applyTextEditsJSON(state: state, editsJSON: editsJSON)
        XCTAssertEqual(changed.count, 1)
        XCTAssertEqual(try state.text(), "aZc\n")

        let expectedStyleId = bridge.encodeSemanticStyleId(tokenType: 1, tokenModifiers: 2)
        let intervals = try bridge.semanticTokensToIntervalsJSON(state: state, dataJSON: "[0,0,3,1,2]")
        XCTAssertEqual(intervals.count, 1)
        XCTAssertEqual(intervals[0].start, 0)
        XCTAssertEqual(intervals[0].end, 3)
        XCTAssertEqual(intervals[0].styleId, expectedStyleId)

        let decoded = try bridge.decodeSemanticStyleId(expectedStyleId)
        XCTAssertEqual(decoded.tokenType, 1)
        XCTAssertEqual(decoded.tokenModifiers, 2)

        // completion item -> edits
        let completionItem = """
        {
          "label": "bar",
          "textEdit": {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 3 }
            },
            "newText": "bar"
          }
        }
        """
        let editsOut = try bridge.completionItemToTextEditsJSON(state: state, completionItemJSON: completionItem, mode: "replace", fallback: nil)
        let obj = try JSONTestHelpers.object(editsOut)
        let edits = (obj["edits"] as? [Any]) ?? []
        XCTAssertEqual(edits.count, 1)

        // apply completion item (fallback path: insertText/label)
        try state.moveTo(line: 0, column: 3)
        try bridge.applyCompletionItemJSON(state: state, completionItemJSON: #"{"label":"XYZ"}"#, mode: "insert")
        XCTAssertTrue((try state.text()).contains("aZcXYZ"))
    }

    func testProcessingEditsFromLspPayloads() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let bridge = LSPBridge(library: library)
        let state = try EditorState(library: library, initialText: "abc\n", viewportWidth: 80)

        // document highlights -> style layer -> styled viewport blob changes
        let highlights = """
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 1 }
            },
            "kind": 3
          }
        ]
        """
        let highlightEdit = try bridge.documentHighlightsToProcessingEditJSON(state: state, resultJSON: highlights)
        try state.applyProcessingEditsJSON(highlightEdit)
        let blob = try state.viewportBlob(startVisualRow: 0, rowCount: 5)
        XCTAssertGreaterThan(blob.stylesForCell(at: 0).count, 0)
        XCTAssertEqual(blob.stylesForCell(at: 1).count, 0)

        // inlay hints -> composed viewport contains virtual cells
        let inlays = """
        [
          {
            "position": { "line": 0, "character": 1 },
            "label": ": i32",
            "paddingLeft": true
          }
        ]
        """
        let inlayEdit = try bridge.inlayHintsToProcessingEditJSON(state: state, resultJSON: inlays)
        try state.applyProcessingEditsJSON(inlayEdit)
        let composed = try JSONTestHelpers.object(try state.viewportComposedJSON(startVisualRow: 0, rowCount: 5))
        let lines = (composed["lines"] as? [Any]) ?? []
        var sawVirtual = false
        for line in lines {
            guard let lineObj = line as? [String: Any],
                  let cells = lineObj["cells"] as? [Any]
            else { continue }
            for cell in cells {
                guard let cellObj = cell as? [String: Any],
                      let source = cellObj["source"] as? [String: Any],
                      source["kind"] as? String == "virtual"
                else { continue }
                sawVirtual = true
                break
            }
            if sawVirtual { break }
        }
        XCTAssertTrue(sawVirtual)

        // document links -> decorations list contains document_link
        let links = """
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 3 }
            },
            "tooltip": "demo link"
          }
        ]
        """
        let linkEdit = try bridge.documentLinksToProcessingEditJSON(state: state, resultJSON: links)
        try state.applyProcessingEditsJSON(linkEdit)
        let decorations = try JSONTestHelpers.object(try state.decorationsJSON())
        let layers = (decorations["layers"] as? [Any]) ?? []
        XCTAssertGreaterThan(layers.count, 0)
        let hasDocumentLink = layers.contains { layer in
            guard let layerObj = layer as? [String: Any],
                  let items = layerObj["decorations"] as? [Any]
            else { return false }
            return items.contains { item in
                guard let deco = item as? [String: Any],
                      let kindObj = deco["kind"] as? [String: Any],
                      let kind = kindObj["kind"] as? String
                else { return false }
                return kind == "document_link"
            }
        }
        XCTAssertTrue(hasDocumentLink)

        // code lens -> above_line -> composed viewport includes virtual_above_line line kind
        let codeLens = """
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 1 }
            },
            "command": { "title": "Run", "command": "run" }
          }
        ]
        """
        let codeLensEdit = try bridge.codeLensToProcessingEditJSON(state: state, resultJSON: codeLens)
        try state.applyProcessingEditsJSON(codeLensEdit)
        let composed2 = try JSONTestHelpers.object(try state.viewportComposedJSON(startVisualRow: 0, rowCount: 10))
        let lines2 = (composed2["lines"] as? [Any]) ?? []
        let hasAboveLine = lines2.contains { line in
            guard let obj = line as? [String: Any],
                  let kind = obj["kind"] as? [String: Any],
                  let k = kind["kind"] as? String
            else { return false }
            return k == "virtual_above_line"
        }
        XCTAssertTrue(hasAboveLine)

        // document symbols -> apply -> state exposes symbols JSON
        let docSymbols = """
        [
          {
            "name": "main",
            "kind": 12,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 3 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 3 }
            },
            "children": []
          }
        ]
        """
        let symbolsEdit = try bridge.documentSymbolsToProcessingEditJSON(state: state, resultJSON: docSymbols)
        try state.applyProcessingEditsJSON(symbolsEdit)
        let symbolsState = try JSONTestHelpers.object(try state.documentSymbolsJSON())
        let symbolsArr = (symbolsState["symbols"] as? [Any]) ?? []
        XCTAssertEqual(symbolsArr.count, 1)
        let sym0 = (symbolsArr.first as? [String: Any]) ?? [:]
        XCTAssertEqual(sym0["name"] as? String, "main")

        // diagnostics -> edits[] -> apply -> state diagnostics list contains message
        let publish = """
        {
          "uri": "file:///demo.txt",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 1 }
              },
              "severity": 2,
              "message": "oops"
            }
          ]
        }
        """
        let diagEditsWrapped = try bridge.diagnosticsToProcessingEditsJSON(state: state, publishDiagnosticsParamsJSON: publish)
        let wrappedObj = try JSONTestHelpers.object(diagEditsWrapped)
        let editsArr = (wrappedObj["edits"] as? [Any]) ?? []
        let editsArrJSON = try JSONTestHelpers.stringify(editsArr)
        try state.applyProcessingEditsJSON(editsArrJSON)
        let diags = try JSONTestHelpers.object(try state.diagnosticsJSON())
        let diagItems = (diags["diagnostics"] as? [Any]) ?? []
        XCTAssertTrue(diagItems.contains { item in
            (item as? [String: Any])?["message"] as? String == "oops"
        })

        // workspace symbols + locations normalization smoke
        let workspaceSymbolsResult = """
        [
          {
            "name": "Foo",
            "kind": 5,
            "location": {
              "uri": "file:///demo.txt",
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 1 }
              }
            }
          }
        ]
        """
        let wsSymbols = try JSONTestHelpers.object(try bridge.workspaceSymbolsJSON(resultJSON: workspaceSymbolsResult))
        XCTAssertNotNil(wsSymbols["symbols"])

        let locationsResult = """
        {
          "uri": "file:///demo.txt",
          "range": {
            "start": { "line": 0, "character": 0 },
            "end": { "line": 0, "character": 1 }
          }
        }
        """
        let locations = try JSONTestHelpers.object(try bridge.locationsJSON(resultJSON: locationsResult))
        XCTAssertNotNil(locations["locations"])
    }
}
