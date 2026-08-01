import AppKit
@testable import AttoEditor
import XCTest

@MainActor
final class AttoLspDefinitionParserTests: XCTestCase {
    func testLocationParsesTarget() {
        let json = """
        {
          "uri": "file:///tmp/a.rs",
          "range": {
            "start": { "line": 12, "character": 34 },
            "end": { "line": 12, "character": 35 }
          }
        }
        """

        XCTAssertEqual(
            AttoLspDefinitionParser.firstTarget(fromDefinitionResultJSON: json),
            .init(uri: "file:///tmp/a.rs", line: 12, utf16Character: 34)
        )
    }

    func testLocationLinkUsesTargetSelectionRange() {
        let json = """
        {
          "targetUri": "file:///tmp/b.rs",
          "targetRange": {
            "start": { "line": 1, "character": 1 },
            "end": { "line": 1, "character": 9 }
          },
          "targetSelectionRange": {
            "start": { "line": 2, "character": 3 },
            "end": { "line": 2, "character": 4 }
          }
        }
        """

        XCTAssertEqual(
            AttoLspDefinitionParser.firstTarget(fromDefinitionResultJSON: json),
            .init(uri: "file:///tmp/b.rs", line: 2, utf16Character: 3)
        )
    }

    func testArraySelectsFirstValidTarget() {
        let json = """
        [
          { "not": "a location" },
          { "uri": "file:///tmp/c.rs", "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 1 } } }
        ]
        """

        XCTAssertEqual(
            AttoLspDefinitionParser.firstTarget(fromDefinitionResultJSON: json),
            .init(uri: "file:///tmp/c.rs", line: 0, utf16Character: 0)
        )
    }

    func testTargetsReturnsAllValidLocations() {
        let json = """
        [
          { "not": "a location" },
          { "uri": "file:///tmp/a.rs", "range": { "start": { "line": 1, "character": 2 }, "end": { "line": 1, "character": 3 } } },
          { "targetUri": "file:///tmp/b.rs", "targetSelectionRange": { "start": { "line": 4, "character": 5 }, "end": { "line": 4, "character": 6 } } }
        ]
        """

        XCTAssertEqual(
            AttoLspDefinitionParser.targets(fromLocationResultJSON: json),
            [
                .init(uri: "file:///tmp/a.rs", line: 1, utf16Character: 2),
                .init(uri: "file:///tmp/b.rs", line: 4, utf16Character: 5),
            ]
        )
    }

    func testNullReturnsNil() {
        XCTAssertNil(AttoLspDefinitionParser.firstTarget(fromDefinitionResultJSON: "null"))
        XCTAssertEqual(AttoLspDefinitionParser.targets(fromLocationResultJSON: "null"), [])
    }

    func testCharOffsetConversionHandlesUTF16Emoji() {
        // "😀" is non-BMP => 2 UTF-16 code units.
        let text = "a😀b\nccc\n"

        // LSP position line 0, character 3 points to "b" (a=1, 😀=2, so b starts at 3).
        XCTAssertEqual(
            AttoLspDefinitionParser.charOffsetForLspPosition(inText: text, line: 0, utf16Character: 3),
            2
        )

        // Line 1 starts after "a😀b\n" => 4 scalars; col 2 => offset 6.
        XCTAssertEqual(
            AttoLspDefinitionParser.charOffsetForLspPosition(inText: text, line: 1, utf16Character: 2),
            6
        )
    }
}
