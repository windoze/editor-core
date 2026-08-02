import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPAuxiliaryTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testInlayHintResultDecodesStringAndPartLabels() throws {
        let result = try decode(EcuLspInlayHintResult.self, """
        [
          {
            "position": { "line": 0, "character": 7 },
            "label": ": i32",
            "kind": 1,
            "tooltip": { "kind": "markdown", "value": "**type**" },
            "paddingLeft": true,
            "data": { "id": "hint-a" }
          },
          {
            "position": { "line": 1, "character": 4 },
            "label": [
              {
                "value": "name",
                "tooltip": "parameter",
                "command": { "title": "Apply", "command": "hint.apply" }
              },
              { "value": ": " },
              { "value": "String" }
            ],
            "kind": 2,
            "textEdits": [
              {
                "range": {
                  "start": { "line": 1, "character": 4 },
                  "end": { "line": 1, "character": 4 }
                },
                "newText": "name"
              }
            ]
          }
        ]
        """)

        XCTAssertEqual(result.shape, .hintArray)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.hints.count, 2)
        XCTAssertEqual(result.hints[0].position.line, 0)
        XCTAssertEqual(result.hints[0].position.utf16Character, 7)
        XCTAssertEqual(result.hints[0].label.plainText, ": i32")
        XCTAssertEqual(result.hints[0].kind, .type)
        guard case let .markup(tooltip)? = result.hints[0].tooltip else {
            return XCTFail("expected markup tooltip")
        }
        XCTAssertEqual(tooltip.kind, "markdown")
        XCTAssertEqual(tooltip.value, "**type**")
        XCTAssertEqual(result.hints[0].paddingLeft, true)
        XCTAssertNotNil(result.hints[0].data)
        XCTAssertEqual(result.hints[1].label.plainText, "name: String")
        XCTAssertEqual(result.hints[1].kind, .parameter)
        XCTAssertEqual(result.hints[1].textEdits.first?.newText, "name")
        XCTAssertEqual(result.hints[1].textEdits.first?.range.start.line, 1)
        XCTAssertEqual(result.hints[1].rawJSONString?.contains(#""label""#), true)
        XCTAssertNotNil(result.rawJSONString)
    }

    func testInlayHintResultDecodesNullUnknownKindAndError() throws {
        let none = try decode(EcuLspInlayHintResult.self, "null")
        XCTAssertEqual(none.shape, .none)
        XCTAssertTrue(none.isEmpty)

        let unknown = try decode(EcuLspInlayHint.self, """
        {
          "position": { "line": 2, "character": 3 },
          "label": "x",
          "kind": 99,
          "tooltip": ["custom"]
        }
        """)
        XCTAssertEqual(unknown.kind, .unknown(99))
        XCTAssertEqual(unknown.tooltip, .raw(.array([.string("custom")])))

        let error = try decode(EcuLspInlayHintResult.self, """
        {
          "error": {
            "code": -32603,
            "message": "inlay failed",
            "data": { "retry": true }
          }
        }
        """)
        XCTAssertEqual(error.shape, .error)
        XCTAssertEqual(error.hints, [])
        XCTAssertEqual(error.error?.message, "inlay failed")
        XCTAssertNotNil(error.error?.data)
    }

    func testDocumentLinkResultDecodesLinksNullAndError() throws {
        let result = try decode(EcuLspDocumentLinkResult.self, """
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 12 }
            },
            "target": "https://example.com",
            "tooltip": "Open docs",
            "data": { "source": "server" }
          },
          {
            "range": {
              "start": { "line": 1, "character": 0 },
              "end": { "line": 1, "character": 4 }
            },
            "data": { "needsResolve": true }
          }
        ]
        """)

        XCTAssertEqual(result.shape, .linkArray)
        XCTAssertEqual(result.links.count, 2)
        XCTAssertEqual(result.links[0].range.start.line, 0)
        XCTAssertEqual(result.links[0].range.end.utf16Character, 12)
        XCTAssertEqual(result.links[0].target, "https://example.com")
        XCTAssertEqual(result.links[0].tooltip, "Open docs")
        XCTAssertNotNil(result.links[0].data)
        XCTAssertNil(result.links[1].target)
        XCTAssertNotNil(result.links[1].rawJSONString)
        XCTAssertNotNil(result.rawJSONString)

        let none = try decode(EcuLspDocumentLinkResult.self, "null")
        XCTAssertEqual(none.shape, .none)
        XCTAssertTrue(none.isEmpty)

        let error = try decode(EcuLspDocumentLinkResult.self, """
        {
          "error": {
            "code": -32603,
            "message": "links failed"
          }
        }
        """)
        XCTAssertEqual(error.shape, .error)
        XCTAssertEqual(error.links, [])
        XCTAssertEqual(error.error?.message, "links failed")
    }

    func testAuxiliaryTypedTakeWrappersStartEmpty() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        XCTAssertTrue(lib.featureFlags.contains(.lspAuxiliaryRequests))
        XCTAssertNil(try ui.lspTakeLastInlayHintsResult())
        XCTAssertNil(try ui.lspTakeLastDocumentLinksResult())
    }
}
