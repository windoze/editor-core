import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPColorTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testDocumentColorResultDecodesColorsAndNull() throws {
        let result = try decode(EcuLspDocumentColorResult.self, """
        [
          {
            "range": {
              "start": { "line": 1, "character": 2 },
              "end": { "line": 1, "character": 9 }
            },
            "color": { "red": 0.1, "green": 0.2, "blue": 0.3, "alpha": 0.4 }
          }
        ]
        """)

        XCTAssertEqual(result.shape, .colorInformationArray)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.items.first?.range.start.line, 1)
        XCTAssertEqual(result.items.first?.range.end.utf16Character, 9)
        XCTAssertEqual(result.items.first?.color.red, 0.1)
        XCTAssertEqual(result.items.first?.color.green, 0.2)
        XCTAssertEqual(result.items.first?.color.blue, 0.3)
        XCTAssertEqual(result.items.first?.color.alpha, 0.4)

        let none = try decode(EcuLspDocumentColorResult.self, "null")
        XCTAssertEqual(none.shape, .none)
        XCTAssertTrue(none.isEmpty)
    }

    func testColorPresentationResultDecodesMainAndAdditionalEdits() throws {
        let result = try decode(EcuLspColorPresentationResult.self, """
        [
          {
            "label": "rgb(255, 0, 0)",
            "textEdit": {
              "range": {
                "start": { "line": 0, "character": 13 },
                "end": { "line": 0, "character": 20 }
              },
              "newText": "rgb(255, 0, 0)"
            },
            "additionalTextEdits": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "// converted\\n"
              }
            ]
          },
          { "label": "label only" }
        ]
        """)

        XCTAssertEqual(result.shape, .colorPresentationArray)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.presentations.count, 2)
        XCTAssertEqual(result.presentations[0].label, "rgb(255, 0, 0)")
        XCTAssertEqual(result.presentations[0].textEdit?.newText, "rgb(255, 0, 0)")
        XCTAssertEqual(result.presentations[0].additionalTextEdits.first?.newText, "// converted\n")
        XCTAssertEqual(result.presentations[1].label, "label only")
        XCTAssertNil(result.presentations[1].textEdit)
    }

    func testColorTypedTakeWrappersStartEmpty() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        XCTAssertNil(try ui.lspTakeLastDocumentColorResult())
        XCTAssertNil(try ui.lspTakeLastColorPresentationResult())
    }
}
