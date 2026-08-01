@testable import AttoEditor
import XCTest

final class AttoLspSelectionRangeParserTests: XCTestCase {
    func testCandidatesFlattenParentChainAndConvertUTF16Positions() {
        let text = "a\u{1F600}b(c)\n"
        let json = """
        [
          {
            "range": {
              "start": { "line": 0, "character": 5 },
              "end": { "line": 0, "character": 6 }
            },
            "parent": {
              "range": {
                "start": { "line": 0, "character": 3 },
                "end": { "line": 0, "character": 7 }
              },
              "parent": {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 7 }
                }
              }
            }
          }
        ]
        """

        XCTAssertEqual(
            AttoLspSelectionRangeParser.candidates(fromResultJSON: json, documentText: text),
            [
                .init(start: 4, end: 5),
                .init(start: 2, end: 6),
                .init(start: 0, end: 6),
            ]
        )
    }

    func testNextCandidateChoosesFirstStrictlyLargerContainingRange() {
        let candidates: [AttoLspSelectionRangeParser.Candidate] = [
            .init(start: 4, end: 5),
            .init(start: 2, end: 6),
            .init(start: 0, end: 6),
        ]

        XCTAssertEqual(
            AttoLspSelectionRangeParser.nextCandidate(
                from: candidates,
                currentStart: 4,
                currentEnd: 5
            ),
            .init(start: 2, end: 6)
        )
        XCTAssertEqual(
            AttoLspSelectionRangeParser.nextCandidate(
                from: candidates,
                currentStart: 5,
                currentEnd: 4
            ),
            .init(start: 2, end: 6)
        )
        XCTAssertEqual(
            AttoLspSelectionRangeParser.nextCandidate(
                from: candidates,
                currentStart: 2,
                currentEnd: 6
            ),
            .init(start: 0, end: 6)
        )
        XCTAssertNil(
            AttoLspSelectionRangeParser.nextCandidate(
                from: candidates,
                currentStart: 0,
                currentEnd: 6
            )
        )
    }

    func testInvalidOrNullResultReturnsNoCandidates() {
        XCTAssertEqual(
            AttoLspSelectionRangeParser.candidates(fromResultJSON: "null", documentText: "abc"),
            []
        )
        XCTAssertEqual(
            AttoLspSelectionRangeParser.candidates(fromResultJSON: "not-json", documentText: "abc"),
            []
        )
    }
}
