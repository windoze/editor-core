@testable import AttoEditor
import EditorCoreUIFFI
import XCTest

final class AttoLspInlayHintResolverTests: XCTestCase {
    func testDisplayTextPrefersTooltipAndLabelPartTooltips() throws {
        let hint = try decodeHint("""
        {
          "position": { "line": 0, "character": 1 },
          "label": [
            {
              "value": ": Int",
              "tooltip": { "kind": "markdown", "value": "Type information" }
            }
          ],
          "tooltip": "Resolved hint"
        }
        """)

        XCTAssertEqual(
            AttoLspInlayHintResolver.displayText(for: hint),
            "Resolved hint\n\n: Int\nType information"
        )
    }

    func testWorkspaceEditJSONWrapsResolvedTextEditsForCurrentDocument() throws {
        let hint = try decodeHint("""
        {
          "position": { "line": 0, "character": 1 },
          "label": ": Int",
          "textEdits": [
            {
              "range": {
                "start": { "line": 0, "character": 1 },
                "end": { "line": 0, "character": 1 }
              },
              "newText": ": Int"
            }
          ]
        }
        """)

        let json = try XCTUnwrap(AttoLspInlayHintResolver.workspaceEditJSON(
            for: hint,
            documentURI: "file:///tmp/main.swift"
        ))
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
        let changes = try XCTUnwrap(root["changes"] as? [String: Any])
        let edits = try XCTUnwrap(changes["file:///tmp/main.swift"] as? [[String: Any]])
        XCTAssertEqual(edits.first?["newText"] as? String, ": Int")
    }

    func testCommandJSONUsesFirstLabelPartCommand() throws {
        let hint = try decodeHint("""
        {
          "position": { "line": 0, "character": 1 },
          "label": [
            {
              "value": "run",
              "command": {
                "title": "Run hint command",
                "command": "hint.run",
                "arguments": [{ "id": 1 }]
              }
            }
          ]
        }
        """)

        let command = try XCTUnwrap(AttoLspInlayHintResolver.command(for: hint))
        XCTAssertEqual(command.title, "Run hint command")
        let root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(command.commandJSON.utf8)) as? [String: Any])
        XCTAssertEqual(root["command"] as? String, "hint.run")
        let arguments = try XCTUnwrap(root["arguments"] as? [[String: Any]])
        XCTAssertEqual(arguments.first?["id"] as? Int, 1)
    }

    func testParserProjectsInlayHintDecorations() throws {
        let hintJSON = """
        {
          "position": { "line": 0, "character": 4 },
          "label": ": Int",
          "kind": 1
        }
        """
        let snapshot = EcuDecorationsSnapshot(layers: [
            EcuDecorationLayerSnapshot(layer: 1, decorations: [
                EcuDecoration(
                    range: EcuOffsetRange(start: 4, end: 4),
                    placement: .after,
                    kind: .object(["kind": .string("inlay_hint")]),
                    text: ": Int",
                    styles: [],
                    tooltip: nil,
                    dataJSON: hintJSON
                ),
                EcuDecoration(
                    range: EcuOffsetRange(start: 0, end: 0),
                    placement: .after,
                    kind: .object(["kind": .string("code_lens")]),
                    text: "Run",
                    styles: [],
                    tooltip: nil,
                    dataJSON: "{}"
                ),
            ]),
        ])

        let items = AttoLspInlayHintParser.items(fromDecorationsSnapshot: snapshot)
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, ": Int")
        XCTAssertEqual(items[0].kindLabel, "Type")
        XCTAssertEqual(items[0].range, EcuOffsetRange(start: 4, end: 4))
        XCTAssertEqual(items[0].hintJSON, hintJSON)
    }

    private func decodeHint(_ json: String) throws -> EcuLspInlayHint {
        try JSONDecoder().decode(EcuLspInlayHint.self, from: Data(json.utf8))
    }
}
