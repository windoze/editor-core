@testable import AttoEditor
import XCTest

final class AttoWorkspaceEditParserTests: XCTestCase {
    func testParseCollectsChangesDocumentChangesAndResourceOperationURIs() throws {
        let edit = """
        {
          "changes": {
            "file:///project/a.swift": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 1 }
                },
                "newText": "A"
              }
            ]
          },
          "documentChanges": [
            {
              "textDocument": { "uri": "file:///project/b.swift", "version": 1 },
              "edits": [
                {
                  "range": {
                    "start": { "line": 1, "character": 2 },
                    "end": { "line": 1, "character": 3 }
                  },
                  "newText": "B"
                }
              ]
            },
            { "kind": "create", "uri": "file:///project/new.swift" },
            { "kind": "rename", "oldUri": "file:///project/old.swift", "newUri": "file:///project/renamed.swift" }
          ]
        }
        """

        let parsed = try XCTUnwrap(AttoWorkspaceEditParser.parse(edit))

        XCTAssertEqual(parsed.documents.map(\.uri), ["file:///project/a.swift", "file:///project/b.swift"])
        XCTAssertEqual(parsed.documents[0].edits.count, 1)
        XCTAssertEqual(parsed.documents[1].edits.count, 1)
        XCTAssertEqual(
            parsed.unsupportedURIs,
            [
                "file:///project/new.swift",
                "file:///project/old.swift",
                "file:///project/renamed.swift",
            ]
        )
    }

    func testApplyUsesLspUTF16PositionsAgainstUnicodeScalarOffsets() throws {
        let edit = """
        {
          "changes": {
            "file:///project/emoji.swift": [
              {
                "range": {
                  "start": { "line": 0, "character": 4 },
                  "end": { "line": 0, "character": 5 }
                },
                "newText": "VALUE"
              }
            ]
          }
        }
        """

        let parsed = try XCTUnwrap(AttoWorkspaceEditParser.parse(edit))
        let document = try XCTUnwrap(parsed.documents.first)
        let result = try XCTUnwrap(AttoWorkspaceEditParser.apply(document, to: "ab😀cd\n"))

        XCTAssertEqual(result.text, "ab😀VALUEd\n")
        XCTAssertEqual(result.editCount, 1)
        XCTAssertFalse(result.hasOverlappingEdits)
    }

    func testApplyRefusesOverlappingRanges() throws {
        let edit = """
        {
          "changes": {
            "file:///project/a.swift": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 2 }
                },
                "newText": "A"
              },
              {
                "range": {
                  "start": { "line": 0, "character": 1 },
                  "end": { "line": 0, "character": 3 }
                },
                "newText": "B"
              }
            ]
          }
        }
        """

        let parsed = try XCTUnwrap(AttoWorkspaceEditParser.parse(edit))
        let document = try XCTUnwrap(parsed.documents.first)
        let result = try XCTUnwrap(AttoWorkspaceEditParser.apply(document, to: "abcd\n"))

        XCTAssertEqual(result.text, "abcd\n")
        XCTAssertEqual(result.editCount, 0)
        XCTAssertTrue(result.hasOverlappingEdits)
    }
}
