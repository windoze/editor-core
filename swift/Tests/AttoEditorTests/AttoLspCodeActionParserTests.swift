@testable import AttoEditor
import EditorCoreUIFFI
import XCTest

final class AttoLspCodeActionParserTests: XCTestCase {
    func testParsesCodeActionsAndLegacyCommands() throws {
        let json = """
        [
          {
            "title": "Fix import",
            "kind": "quickfix",
            "isPreferred": true,
            "edit": { "changes": { "file:///a.swift": [] } },
            "command": { "title": "Organize", "command": "source.organizeImports", "arguments": [1] }
          },
          {
            "title": "Run command",
            "command": "server.run",
            "arguments": ["x"]
          }
        ]
        """

        let items = AttoLspCodeActionParser.items(fromCodeActionResultJSON: json)
        XCTAssertEqual(items.count, 2)

        XCTAssertEqual(items[0].title, "Fix import")
        XCTAssertEqual(items[0].kind, "quickfix")
        XCTAssertTrue(items[0].isPreferred)
        XCTAssertNotNil(items[0].edit)
        XCTAssertEqual(items[0].command?.command, "source.organizeImports")
        XCTAssertFalse(items[0].isLegacyCommand)
        XCTAssertEqual(AttoLspCodeActionParser.displayTitle(for: items[0]), "Fix import  [quickfix, preferred]")

        XCTAssertEqual(items[1].title, "Run command")
        XCTAssertNil(items[1].edit)
        XCTAssertEqual(items[1].command?.command, "server.run")
        XCTAssertTrue(items[1].isLegacyCommand)
        XCTAssertEqual(AttoLspCodeActionParser.displayTitle(for: items[1]), "Run command  [command]")
    }

    func testParsesResolvedSingleCodeActionAndSerializesPayloads() throws {
        let json = """
        {
          "title": "Resolve me",
          "kind": "quickfix",
          "data": { "id": 1 },
          "edit": { "changes": { "file:///a.swift": [] } }
        }
        """

        let item = try XCTUnwrap(AttoLspCodeActionParser.item(fromCodeActionJSON: json))
        XCTAssertEqual(item.title, "Resolve me")
        XCTAssertNotNil(AttoLspCodeActionParser.rawJSON(for: item))
        XCTAssertNotNil(AttoLspCodeActionParser.editJSON(for: item))
    }

    func testParsesTypedCodeActionResultAndSerializesPayloads() throws {
        let result = try JSONDecoder().decode(EcuLspCodeActionResult.self, from: Data("""
        [
          {
            "title": "Fix typed",
            "kind": "quickfix",
            "isPreferred": true,
            "edit": {
              "changes": {
                "file:///a.swift": [
                  {
                    "range": {
                      "start": { "line": 0, "character": 0 },
                      "end": { "line": 0, "character": 0 }
                    },
                    "newText": "let a = 1\\n"
                  }
                ]
              }
            },
            "command": {
              "title": "After fix",
              "command": "server.afterFix",
              "arguments": [{ "id": 1 }]
            },
            "data": { "resolve": true }
          },
          {
            "title": "Run typed command",
            "command": "server.run",
            "arguments": ["x"]
          }
        ]
        """.utf8))

        let items = AttoLspCodeActionParser.items(fromCodeActionResult: result)
        XCTAssertEqual(items.count, 2)

        XCTAssertEqual(items[0].title, "Fix typed")
        XCTAssertEqual(items[0].kind, "quickfix")
        XCTAssertTrue(items[0].isPreferred)
        XCTAssertFalse(items[0].isLegacyCommand)
        XCTAssertEqual(AttoLspCodeActionParser.workspaceEdit(for: items[0])?.documentEditCount, 1)
        XCTAssertNotNil(AttoLspCodeActionParser.editJSON(for: items[0]))
        XCTAssertNotNil(AttoLspCodeActionParser.rawJSON(for: items[0]))
        XCTAssertEqual(items[0].command?.command, "server.afterFix")
        XCTAssertNotNil(items[0].command.flatMap(AttoLspCodeActionParser.commandJSON(for:)))

        XCTAssertEqual(items[1].title, "Run typed command")
        XCTAssertTrue(items[1].isLegacyCommand)
        XCTAssertEqual(items[1].command?.command, "server.run")
        XCTAssertNotNil(items[1].command.flatMap(AttoLspCodeActionParser.commandJSON(for:)))
    }

    func testParsesTypedResolvedSingleCodeAction() throws {
        let action = try JSONDecoder().decode(EcuLspCodeAction.self, from: Data("""
        {
          "title": "Resolved typed",
          "kind": "quickfix",
          "disabled": { "reason": "later" },
          "edit": { "changes": { "file:///a.swift": [] } }
        }
        """.utf8))

        let item = try XCTUnwrap(AttoLspCodeActionParser.item(fromCodeAction: action))
        XCTAssertEqual(item.title, "Resolved typed")
        XCTAssertEqual(item.disabledReason, "later")
        XCTAssertEqual(
            AttoLspCodeActionParser.displayTitle(for: item),
            "Resolved typed  [quickfix, disabled: later]"
        )
        XCTAssertNotNil(AttoLspCodeActionParser.workspaceEdit(for: item))
        XCTAssertNotNil(AttoLspCodeActionParser.rawJSON(for: item))
    }

    func testDisabledCodeActionCarriesReason() throws {
        let json = """
        [
          {
            "title": "Cannot fix",
            "kind": "quickfix",
            "disabled": { "reason": "not applicable" }
          }
        ]
        """

        let item = try XCTUnwrap(AttoLspCodeActionParser.items(fromCodeActionResultJSON: json).first)
        XCTAssertEqual(item.disabledReason, "not applicable")
        XCTAssertEqual(
            AttoLspCodeActionParser.displayTitle(for: item),
            "Cannot fix  [quickfix, disabled: not applicable]"
        )
    }

    func testFilteredItemsMatchKindPrefixes() throws {
        let json = """
        [
          { "title": "Quick fix", "kind": "quickfix" },
          { "title": "Extract", "kind": "refactor.extract" },
          { "title": "Organize", "kind": "source.organizeImports" },
          { "title": "Legacy", "command": "server.run" }
        ]
        """

        let items = AttoLspCodeActionParser.items(fromCodeActionResultJSON: json)
        XCTAssertEqual(
            AttoLspCodeActionParser.filteredItems(items, onlyKinds: ["refactor"]).map(\.title),
            ["Extract"]
        )
        XCTAssertEqual(
            AttoLspCodeActionParser.filteredItems(items, onlyKinds: ["source.organizeImports"]).map(\.title),
            ["Organize"]
        )
        XCTAssertEqual(
            AttoLspCodeActionParser.filteredItems(items, onlyKinds: ["quickfix", "source"]).map(\.title),
            ["Quick fix", "Organize"]
        )
        XCTAssertEqual(AttoLspCodeActionParser.filteredItems(items, onlyKinds: []).count, 4)
    }
}
