@testable import AttoEditor
import EditorCoreUIFFI
import XCTest

final class AttoLspLinkedEditingParserTests: XCTestCase {
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
}
