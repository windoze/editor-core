@testable import AttoEditor
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
}
