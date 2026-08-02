@testable import AttoEditor
import EditorCoreUIFFI
import XCTest

final class AttoLspLinkedEditingParserTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testLinkedEditingRangesParseUTF16PositionsAndDeduplicate() throws {
        let text = "\u{1F600}foo foo\n"
        let json = """
        {
          "ranges": [
            {
              "start": { "line": 0, "character": 2 },
              "end": { "line": 0, "character": 5 }
            },
            {
              "start": { "line": 0, "character": 6 },
              "end": { "line": 0, "character": 9 }
            },
            {
              "start": { "line": 0, "character": 6 },
              "end": { "line": 0, "character": 9 }
            }
          ],
          "wordPattern": "[A-Za-z]+"
        }
        """

        let result = try XCTUnwrap(AttoLspLinkedEditingParser.result(
            fromLinkedEditingRangeResultJSON: json,
            documentText: text
        ))

        XCTAssertEqual(
            result.ranges,
            [
                EcuSelectionRange(start: 1, end: 4),
                EcuSelectionRange(start: 5, end: 8),
            ]
        )
        XCTAssertEqual(result.wordPattern, "[A-Za-z]+")
        XCTAssertEqual(result.primaryIndex(containing: 6), 1)
        XCTAssertEqual(result.primaryIndex(containing: 20), 0)
    }

    func testTypedLinkedEditingRangesParseUTF16PositionsAndDeduplicate() throws {
        let text = "\u{1F600}foo foo\n"
        let dto = try decode(EcuLspLinkedEditingRangeResult.self, """
        {
          "ranges": [
            {
              "start": { "line": 0, "character": 2 },
              "end": { "line": 0, "character": 5 }
            },
            {
              "start": { "line": 0, "character": 6 },
              "end": { "line": 0, "character": 9 }
            },
            {
              "start": { "line": 0, "character": 6 },
              "end": { "line": 0, "character": 9 }
            }
          ],
          "wordPattern": "[A-Za-z]+"
        }
        """)

        let result = try XCTUnwrap(AttoLspLinkedEditingParser.result(from: dto, documentText: text))

        XCTAssertEqual(
            result.ranges,
            [
                EcuSelectionRange(start: 1, end: 4),
                EcuSelectionRange(start: 5, end: 8),
            ]
        )
        XCTAssertEqual(result.wordPattern, "[A-Za-z]+")
        XCTAssertEqual(result.primaryIndex(containing: 6), 1)
        XCTAssertEqual(result.primaryIndex(containing: 20), 0)
    }

    func testNullOrEmptyResultReturnsNil() {
        XCTAssertNil(AttoLspLinkedEditingParser.result(
            fromLinkedEditingRangeResultJSON: "null",
            documentText: "foo"
        ))
        XCTAssertNil(AttoLspLinkedEditingParser.result(
            fromLinkedEditingRangeResultJSON: #"{"ranges":[]}"#,
            documentText: "foo"
        ))
        XCTAssertNil(AttoLspLinkedEditingParser.result(
            fromLinkedEditingRangeResultJSON: "not-json",
            documentText: "foo"
        ))
    }

    func testTypedNullOrEmptyResultReturnsNil() throws {
        XCTAssertNil(AttoLspLinkedEditingParser.result(
            from: try decode(EcuLspLinkedEditingRangeResult.self, "null"),
            documentText: "foo"
        ))
        XCTAssertNil(AttoLspLinkedEditingParser.result(
            from: try decode(EcuLspLinkedEditingRangeResult.self, #"{"ranges":[]}"#),
            documentText: "foo"
        ))
    }

    func testResultRejectsRangesThatDoNotShareCurrentText() {
        XCTAssertNil(AttoLspLinkedEditingParser.result(
            fromLinkedEditingRangeResultJSON: """
            {
              "ranges": [
                {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 3 }
                },
                {
                  "start": { "line": 0, "character": 6 },
                  "end": { "line": 0, "character": 9 }
                }
              ]
            }
            """,
            documentText: "foo + bar"
        ))
    }

    func testResultRejectsRangesThatDoNotMatchWordPattern() {
        XCTAssertNil(AttoLspLinkedEditingParser.result(
            fromLinkedEditingRangeResultJSON: """
            {
              "ranges": [
                {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 3 }
                },
                {
                  "start": { "line": 0, "character": 6 },
                  "end": { "line": 0, "character": 9 }
                }
              ],
              "wordPattern": "[A-Za-z]+"
            }
            """,
            documentText: "123 + 123"
        ))
    }
}
