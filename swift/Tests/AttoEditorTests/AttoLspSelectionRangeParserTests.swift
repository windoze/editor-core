@testable import AttoEditor
import EditorCoreUIFFI
import XCTest

final class AttoLspSelectionRangeParserTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

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

    func testTypedCandidatesFlattenParentChainAndConvertUTF16Positions() throws {
        let text = "a\u{1F600}b(c)\n"
        let result = try decode(EcuLspSelectionRangeResult.self, """
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
        """)

        XCTAssertEqual(
            AttoLspSelectionRangeParser.candidates(from: result, documentText: text),
            [
                .init(start: 4, end: 5),
                .init(start: 2, end: 6),
                .init(start: 0, end: 6),
            ]
        )
    }

    func testCandidateChainsPreservePerPositionResultOrder() {
        let text = "alpha\nbeta\n"
        let json = """
        [
          {
            "range": {
              "start": { "line": 0, "character": 1 },
              "end": { "line": 0, "character": 3 }
            },
            "parent": {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 5 }
              }
            }
          },
          {
            "range": {
              "start": { "line": 1, "character": 1 },
              "end": { "line": 1, "character": 3 }
            },
            "parent": {
              "range": {
                "start": { "line": 1, "character": 0 },
                "end": { "line": 1, "character": 4 }
              }
            }
          }
        ]
        """

        XCTAssertEqual(
            AttoLspSelectionRangeParser.candidateChains(fromResultJSON: json, documentText: text),
            [
                [.init(start: 1, end: 3), .init(start: 0, end: 5)],
                [.init(start: 7, end: 9), .init(start: 6, end: 10)],
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
