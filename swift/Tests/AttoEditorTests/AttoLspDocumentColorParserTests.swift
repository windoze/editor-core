@testable import AttoEditor
import EditorCoreUIFFI
import XCTest

final class AttoLspDocumentColorParserTests: XCTestCase {
    func testDocumentColorsParseRangesAndColors() throws {
        let text = "let icon = \"😀#0A1B2C\"\n"
        let json = """
        [
          {
            "range": {
              "start": { "line": 0, "character": 14 },
              "end": { "line": 0, "character": 21 }
            },
            "color": { "red": 0.04, "green": 0.105, "blue": 0.173, "alpha": 1.0 }
          }
        ]
        """

        let item = try XCTUnwrap(AttoLspDocumentColorParser.items(
            fromDocumentColorResultJSON: json,
            documentText: text
        ).first)

        XCTAssertEqual(item.range, EcuSelectionRange(start: 13, end: 20))
        XCTAssertEqual(item.startLine, 0)
        XCTAssertEqual(item.startUTF16Character, 14)
        XCTAssertEqual(AttoLspDocumentColorParser.hexString(for: item.color), "#0A1B2C")
        XCTAssertEqual(AttoLspDocumentColorParser.displayTitle(for: item), "#0A1B2C at 1:15")
        XCTAssertNotNil(AttoLspDocumentColorParser.colorJSON(for: item))
    }

    func testDocumentColorsParseTypedResult() throws {
        let text = "let icon = \"😀#0A1B2C\"\n"
        let result = try JSONDecoder().decode(EcuLspDocumentColorResult.self, from: Data("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 14 },
              "end": { "line": 0, "character": 21 }
            },
            "color": { "red": 0.04, "green": 0.105, "blue": 0.173, "alpha": 1.0 }
          }
        ]
        """.utf8))

        let item = try XCTUnwrap(AttoLspDocumentColorParser.items(
            fromDocumentColorResult: result,
            documentText: text
        ).first)

        XCTAssertEqual(item.range, EcuSelectionRange(start: 13, end: 20))
        XCTAssertEqual(item.startLine, 0)
        XCTAssertEqual(item.startUTF16Character, 14)
        XCTAssertEqual(AttoLspDocumentColorParser.hexString(for: item.color), "#0A1B2C")
    }

    func testColorPresentationsParseMainAndAdditionalEdits() throws {
        let text = "let color = \"#ff0000\"\n"
        let json = """
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
        """

        let presentations = AttoLspDocumentColorParser.presentations(
            fromColorPresentationResultJSON: json,
            documentText: text
        )

        XCTAssertEqual(presentations.count, 2)
        XCTAssertEqual(presentations[0].label, "rgb(255, 0, 0)")
        XCTAssertTrue(presentations[0].isApplicable)
        XCTAssertEqual(
            presentations[0].edits,
            [
                EcuTextEdit(start: 13, end: 20, text: "rgb(255, 0, 0)"),
                EcuTextEdit(start: 0, end: 0, text: "// converted\n"),
            ]
        )
        XCTAssertFalse(presentations[1].isApplicable)
        XCTAssertEqual(
            AttoLspDocumentColorParser.displayTitle(for: presentations[1]),
            "label only  [label only]"
        )
    }

    func testColorPresentationsParseTypedResult() throws {
        let text = "let color = \"#ff0000\"\n"
        let result = try JSONDecoder().decode(EcuLspColorPresentationResult.self, from: Data("""
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
        """.utf8))

        let presentations = AttoLspDocumentColorParser.presentations(
            fromColorPresentationResult: result,
            documentText: text
        )

        XCTAssertEqual(presentations.count, 2)
        XCTAssertEqual(presentations[0].label, "rgb(255, 0, 0)")
        XCTAssertEqual(
            presentations[0].edits,
            [
                EcuTextEdit(start: 13, end: 20, text: "rgb(255, 0, 0)"),
                EcuTextEdit(start: 0, end: 0, text: "// converted\n"),
            ]
        )
        XCTAssertEqual(presentations[1].label, "label only")
        XCTAssertFalse(presentations[1].isApplicable)
    }

    func testInvalidResultsReturnEmptyArrays() {
        XCTAssertEqual(
            AttoLspDocumentColorParser.items(fromDocumentColorResultJSON: "null", documentText: ""),
            []
        )
        XCTAssertEqual(
            AttoLspDocumentColorParser.presentations(fromColorPresentationResultJSON: "not-json", documentText: ""),
            []
        )
    }
}
