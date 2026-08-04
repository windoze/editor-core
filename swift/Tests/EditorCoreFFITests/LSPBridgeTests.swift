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

    func testLSPHelperEnvelopes() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let bridge = LSPBridge(library: library)

        let path = "/tmp/editor-core ffi.swift"
        let uriEnvelope = try bridge.pathToFileURIEnvelope(path)
        XCTAssertTrue(uriEnvelope.ok)
        XCTAssertEqual(uriEnvelope.statusKind, .success)
        XCTAssertEqual(uriEnvelope.operation, "path_to_file_uri")
        let uriValue = try requireObject(uriEnvelope.value)
        let uri = try requireString(uriValue["uri"])
        XCTAssertTrue(uri.hasPrefix("file://"))

        let pathEnvelope = try bridge.fileURIToPathEnvelope(uri)
        XCTAssertTrue(pathEnvelope.ok)
        XCTAssertEqual(pathEnvelope.operation, "file_uri_to_path")
        let pathValue = try requireObject(pathEnvelope.value)
        XCTAssertEqual(try requireString(pathValue["path"]), path)

        let encodedEnvelope = try bridge.percentEncodePathEnvelope("editor-core ffi.swift")
        XCTAssertTrue(encodedEnvelope.ok)
        XCTAssertEqual(encodedEnvelope.operation, "percent_encode_path")
        let encodedValue = try requireObject(encodedEnvelope.value)
        let encoded = try requireString(encodedValue["encoded"])
        XCTAssertTrue(encoded.contains("%20"))

        let decodedEnvelope = try bridge.percentDecodePathEnvelope(encoded)
        XCTAssertTrue(decodedEnvelope.ok)
        XCTAssertEqual(decodedEnvelope.operation, "percent_decode_path")
        let decodedValue = try requireObject(decodedEnvelope.value)
        XCTAssertEqual(try requireString(decodedValue["decoded"]), "editor-core ffi.swift")

        let formatting = try bridge.formattingOptionsEnvelope(tabSize: 4, insertSpaces: true)
        XCTAssertTrue(formatting.ok)
        XCTAssertEqual(formatting.operation, "formatting_options")
        let formattingValue = try requireObject(formatting.value)
        let formattingOptions = try requireObject(formattingValue["options"])
        XCTAssertEqual(formattingOptions["tabSize"], .number(4))
        XCTAssertEqual(formattingOptions["insertSpaces"], .bool(true))

        let indentation = try bridge.formattingOptionsForIndentationConfigEnvelope(
            indentationConfigJSON: #"{"style":{"kind":"spaces","width":2}}"#,
            tabWidth: 4
        )
        XCTAssertTrue(indentation.ok)
        XCTAssertEqual(indentation.operation, "formatting_options_for_indentation_config")
        let indentationValue = try requireObject(indentation.value)
        let indentationOptions = try requireObject(indentationValue["options"])
        XCTAssertEqual(indentationOptions["tabSize"], .number(2))
        XCTAssertEqual(indentationOptions["insertSpaces"], .bool(true))

        let style = try bridge.decodeSemanticStyleIdEnvelope(0)
        XCTAssertTrue(style.ok)
        XCTAssertEqual(style.operation, "decode_semantic_style_id")
        let styleValue = try requireObject(style.value)
        XCTAssertEqual(styleValue["token_type"], .number(0))
        XCTAssertEqual(styleValue["token_modifiers"], .number(0))

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
        let workspaceSymbols = try bridge.workspaceSymbolsEnvelope(resultJSON: workspaceSymbolsResult)
        XCTAssertTrue(workspaceSymbols.ok)
        XCTAssertEqual(workspaceSymbols.operation, "workspace_symbols")
        let workspaceSymbolsValue = try requireObject(workspaceSymbols.value)
        let symbols = try requireArray(workspaceSymbolsValue["symbols"])
        XCTAssertEqual(symbols.count, 1)

        let locationsResult = """
        {
          "uri": "file:///demo.txt",
          "range": {
            "start": { "line": 0, "character": 0 },
            "end": { "line": 0, "character": 1 }
          }
        }
        """
        let locations = try bridge.locationsEnvelope(resultJSON: locationsResult)
        XCTAssertTrue(locations.ok)
        XCTAssertEqual(locations.operation, "locations")
        let locationsValue = try requireObject(locations.value)
        let normalizedLocations = try requireArray(locationsValue["locations"])
        XCTAssertEqual(normalizedLocations.count, 1)

        let invalidURI = try bridge.fileURIToPathEnvelope("not-a-file-uri")
        XCTAssertFalse(invalidURI.ok)
        XCTAssertEqual(invalidURI.statusKind, .error)
        XCTAssertEqual(invalidURI.operation, "file_uri_to_path")
        XCTAssertEqual(invalidURI.error?.code, "invalid_argument")
        XCTAssertEqual(invalidURI.error?.status, .invalidArgument)
        XCTAssertEqual(invalidURI.value, .null)

        let invalidSymbols = try bridge.workspaceSymbolsEnvelope(resultJSON: "{not json")
        XCTAssertFalse(invalidSymbols.ok)
        XCTAssertEqual(invalidSymbols.operation, "workspace_symbols")
        XCTAssertEqual(invalidSymbols.error?.code, "parse")
        XCTAssertEqual(invalidSymbols.error?.status, .parse)
        XCTAssertEqual(invalidSymbols.value, .null)
    }

    func testLSPEditHelperEnvelopes() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let bridge = LSPBridge(library: library)
        let state = try EditorState(library: library, initialText: "abc\n", viewportWidth: 80)

        let onType = try bridge.onTypeFormattingParamsEnvelope(
            state: state,
            uri: "file:///demo.rs",
            ch: "}",
            optionsJSON: #"{"tabSize":4,"insertSpaces":true}"#
        )
        XCTAssertTrue(onType.ok)
        XCTAssertEqual(onType.operation, "on_type_formatting_params")
        let onTypeValue = try requireObject(onType.value)
        let params = try requireObject(onTypeValue["params"])
        XCTAssertEqual(try requireString(try requireObject(params["textDocument"])["uri"]), "file:///demo.rs")
        XCTAssertEqual(try requireString(params["ch"]), "}")

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
        let apply = try bridge.applyTextEditsEnvelope(state: state, editsJSON: editsJSON)
        XCTAssertTrue(apply.ok)
        XCTAssertEqual(apply.operation, "apply_text_edits")
        let applyValue = try requireObject(apply.value)
        XCTAssertEqual(try requireArray(applyValue["changed_ranges"]).count, 1)

        let semantic = try bridge.semanticTokensToIntervalsEnvelope(state: state, dataJSON: "[0,0,3,1,2]")
        XCTAssertTrue(semantic.ok)
        XCTAssertEqual(semantic.operation, "semantic_tokens_to_intervals")
        let semanticValue = try requireObject(semantic.value)
        XCTAssertEqual(try requireArray(semanticValue["intervals"]).count, 1)

        let highlights = try bridge.documentHighlightsToProcessingEditEnvelope(
            state: state,
            resultJSON: """
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
        )
        XCTAssertTrue(highlights.ok)
        XCTAssertEqual(highlights.operation, "document_highlights_to_processing_edit")
        XCTAssertNotNil(highlights.value)

        let diagnostics = try bridge.diagnosticsToProcessingEditsEnvelope(
            state: state,
            publishDiagnosticsParamsJSON: """
            {
              "uri": "file:///demo.rs",
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
        )
        XCTAssertTrue(diagnostics.ok)
        XCTAssertEqual(diagnostics.operation, "diagnostics_to_processing_edits")
        let diagnosticsValue = try requireObject(diagnostics.value)
        XCTAssertFalse(try requireArray(diagnosticsValue["edits"]).isEmpty)

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
        let completion = try bridge.completionItemToTextEditsEnvelope(
            state: state,
            completionItemJSON: completionItem,
            mode: "replace",
            fallback: nil
        )
        XCTAssertTrue(completion.ok)
        XCTAssertEqual(completion.operation, "completion_item_to_text_edits")
        let completionValue = try requireObject(completion.value)
        XCTAssertEqual(try requireArray(completionValue["edits"]).count, 1)

        let appliedCompletion = try bridge.applyCompletionItemEnvelope(
            state: state,
            completionItemJSON: #"{"label":"XYZ"}"#,
            mode: "insert"
        )
        XCTAssertTrue(appliedCompletion.ok)
        XCTAssertEqual(appliedCompletion.operation, "apply_completion_item")
        let appliedValue = try requireObject(appliedCompletion.value)
        XCTAssertEqual(appliedValue["applied"], .bool(true))

        let invalidMode = try bridge.completionItemToTextEditsEnvelope(
            state: state,
            completionItemJSON: completionItem,
            mode: "future",
            fallback: nil
        )
        XCTAssertFalse(invalidMode.ok)
        XCTAssertEqual(invalidMode.operation, "completion_item_to_text_edits")
        XCTAssertEqual(invalidMode.error?.code, "invalid_argument")
        XCTAssertEqual(invalidMode.error?.status, .invalidArgument)
        XCTAssertEqual(invalidMode.value, .null)
    }

    func testLSPHelperEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let success = try JSONTestHelpers.decode(EcfLSPHelperEnvelope.self, from: """
        {
          "ok": true,
          "status": "future_success",
          "operation": "future_helper",
          "value": { "uri": "file:///future.swift" },
          "error": null,
          "version": 1,
          "futureTopLevel": { "ignored": true }
        }
        """)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.statusKind, .unknown("future_success"))
        XCTAssertEqual(success.operation, "future_helper")
        let value = try requireObject(success.value)
        XCTAssertEqual(try requireString(value["uri"]), "file:///future.swift")

        let failure = try JSONTestHelpers.decode(EcfLSPHelperEnvelope.self, from: """
        {
          "ok": false,
          "status": "future_error",
          "operation": "future_helper",
          "value": null,
          "error": {
            "code": "future_code",
            "status": 777,
            "message": "future failure",
            "details": { "ignored": true }
          },
          "version": 1
        }
        """)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .unknown("future_error"))
        XCTAssertEqual(failure.error?.code, "future_code")
        XCTAssertNil(failure.error?.status)
        XCTAssertEqual(failure.error?.message, "future failure")
    }

    private func requireObject(
        _ value: EcfJSONValue?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: EcfJSONValue] {
        guard case let .object(object)? = value else {
            XCTFail("expected JSON object", file: file, line: line)
            return [:]
        }
        return object
    }

    private func requireArray(
        _ value: EcfJSONValue?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [EcfJSONValue] {
        guard case let .array(array)? = value else {
            XCTFail("expected JSON array", file: file, line: line)
            return []
        }
        return array
    }

    private func requireString(
        _ value: EcfJSONValue?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> String {
        guard case let .string(string)? = value else {
            XCTFail("expected JSON string", file: file, line: line)
            return ""
        }
        return string
    }
}
