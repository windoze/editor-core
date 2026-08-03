@testable import AttoEditor
import EditorCoreUIFFI
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
            { "kind": "create", "uri": "file:///project/new.swift", "options": { "overwrite": true } },
            {
              "kind": "rename",
              "oldUri": "file:///project/old.swift",
              "newUri": "file:///project/renamed.swift",
              "options": { "ignoreIfExists": true }
            },
            { "kind": "delete", "uri": "file:///project/remove.swift", "options": { "recursive": true } }
          ]
        }
        """

        let parsed = try XCTUnwrap(AttoWorkspaceEditParser.parse(edit))

        XCTAssertEqual(parsed.documents.map(\.uri), ["file:///project/a.swift", "file:///project/b.swift"])
        XCTAssertEqual(parsed.documents[0].edits.count, 1)
        XCTAssertEqual(parsed.documents[1].edits.count, 1)
        XCTAssertEqual(
            parsed.resourceOperations,
            [
                .create(.init(uri: "file:///project/new.swift", overwrite: true, ignoreIfExists: false)),
                .rename(.init(
                    oldURI: "file:///project/old.swift",
                    newURI: "file:///project/renamed.swift",
                    overwrite: false,
                    ignoreIfExists: true
                )),
                .delete(.init(uri: "file:///project/remove.swift", recursive: true, ignoreIfNotExists: false)),
            ]
        )
        XCTAssertEqual(parsed.unsupportedURIs, [])
    }

    func testParseKeepsUnknownResourceOperationURIsUnsupported() throws {
        let edit = """
        {
          "documentChanges": [
            { "kind": "unknown", "uri": "file:///project/a.swift", "newUri": "file:///project/b.swift" }
          ]
        }
        """

        let parsed = try XCTUnwrap(AttoWorkspaceEditParser.parse(edit))

        XCTAssertEqual(parsed.resourceOperations, [])
        XCTAssertEqual(
            parsed.unsupportedURIs,
            [
                "file:///project/a.swift",
                "file:///project/b.swift",
            ]
        )
    }

    func testParseUnwrapsWorkspaceEditTransactionEnvelope() throws {
        let edit = """
        {
          "applyMode": "atomic",
          "workspaceEdit": {
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
              { "kind": "delete", "uri": "file:///project/remove.swift" }
            ]
          }
        }
        """

        let parsed = try XCTUnwrap(AttoWorkspaceEditParser.parse(edit))

        XCTAssertEqual(parsed.documents.map(\.uri), ["file:///project/a.swift"])
        XCTAssertEqual(parsed.documents.first?.edits.first?.newText, "A")
        XCTAssertEqual(
            parsed.resourceOperations,
            [
                .delete(.init(uri: "file:///project/remove.swift", recursive: false, ignoreIfNotExists: false)),
            ]
        )
    }

    func testParseTypedWorkspaceEditMatchesJSONPath() throws {
        let edit = try JSONDecoder().decode(EcuLspWorkspaceEdit.self, from: Data("""
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
            { "kind": "create", "uri": "file:///project/new.swift", "options": { "overwrite": true } },
            {
              "kind": "rename",
              "oldUri": "file:///project/old.swift",
              "newUri": "file:///project/renamed.swift",
              "options": { "ignoreIfExists": true }
            },
            { "kind": "delete", "uri": "file:///project/remove.swift", "options": { "recursive": true } }
          ]
        }
        """.utf8))

        let parsed = AttoWorkspaceEditParser.parse(edit)

        XCTAssertEqual(parsed.documents.map(\.uri), ["file:///project/a.swift", "file:///project/b.swift"])
        XCTAssertEqual(parsed.documents[0].edits.first?.newText, "A")
        XCTAssertEqual(parsed.documents[1].edits.first?.range.start.line, 1)
        XCTAssertEqual(
            parsed.resourceOperations,
            [
                .create(.init(uri: "file:///project/new.swift", overwrite: true, ignoreIfExists: false)),
                .rename(.init(
                    oldURI: "file:///project/old.swift",
                    newURI: "file:///project/renamed.swift",
                    overwrite: false,
                    ignoreIfExists: true
                )),
                .delete(.init(uri: "file:///project/remove.swift", recursive: true, ignoreIfNotExists: false)),
            ]
        )
        XCTAssertEqual(parsed.unsupportedURIs, [])
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
