import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPHoverTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testHoverMarkupContentDecodesRangeAndRawPayload() throws {
        let result = try decode(EcuLspHoverResult.self, """
        {
          "contents": {
            "kind": "markdown",
            "value": "`foo`: i32\\n\\nDocs here"
          },
          "range": {
            "start": { "line": 1, "character": 2 },
            "end": { "line": 1, "character": 5 }
          },
          "future": true
        }
        """)

        XCTAssertEqual(result.shape, .hover)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.contents, [.markup(kind: "markdown", value: "`foo`: i32\n\nDocs here")])
        XCTAssertEqual(result.displayText, "`foo`: i32\n\nDocs here")
        XCTAssertEqual(result.range?.start.line, 1)
        XCTAssertEqual(result.range?.start.utf16Character, 2)
        XCTAssertEqual(result.range?.end.utf16Character, 5)
        XCTAssertEqual(result.raw, .object([
            "contents": .object([
                "kind": .string("markdown"),
                "value": .string("`foo`: i32\n\nDocs here"),
            ]),
            "range": .object([
                "start": .object(["line": .number(1), "character": .number(2)]),
                "end": .object(["line": .number(1), "character": .number(5)]),
            ]),
            "future": .bool(true),
        ]))
    }

    func testHoverMarkedStringArrayDecodesAndJoinsDisplayText() throws {
        let result = try decode(EcuLspHoverResult.self, """
        {
          "contents": [
            "plain docs",
            {
              "language": "swift",
              "value": "let value: Int"
            }
          ]
        }
        """)

        XCTAssertEqual(result.shape, .hover)
        XCTAssertEqual(result.contents, [
            .plain("plain docs"),
            .markedString(language: "swift", value: "let value: Int"),
        ])
        XCTAssertEqual(result.displayText, "plain docs\n\nlet value: Int")
    }

    func testHoverNullAndUnknownPayloadsDecode() throws {
        let nullResult = try decode(EcuLspHoverResult.self, "null")
        XCTAssertEqual(nullResult.shape, .none)
        XCTAssertTrue(nullResult.isEmpty)
        XCTAssertEqual(nullResult.raw, .null)

        let unknownResult = try decode(EcuLspHoverResult.self, """
        {
          "contents": { "future": 42 }
        }
        """)

        XCTAssertEqual(unknownResult.shape, .hover)
        XCTAssertTrue(unknownResult.isEmpty)
        XCTAssertEqual(unknownResult.contents, [.unknown(.object(["future": .number(42)]))])
    }

    func testHoverTypedTakeWrapperStartsEmpty() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        XCTAssertNil(try ui.lspTakeLastHoverResult())
    }
}
