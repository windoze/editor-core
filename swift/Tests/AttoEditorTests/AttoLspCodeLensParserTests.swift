@testable import AttoEditor
import EditorCoreUIFFI
import XCTest

final class AttoLspCodeLensParserTests: XCTestCase {
    func testItemsParseCodeLensDecorationsAndCommandPayload() throws {
        let lensJSON = """
        {
          "range": {
            "start": { "line": 0, "character": 0 },
            "end": { "line": 0, "character": 0 }
          },
          "command": {
            "title": "Run Test",
            "command": "test.run",
            "arguments": ["caseA"]
          },
          "data": { "opaque": true }
        }
        """
        let snapshot = EcuDecorationsSnapshot(layers: [
            EcuDecorationLayerSnapshot(layer: 2, decorations: [
                EcuDecoration(
                    range: EcuOffsetRange(start: 5, end: 5),
                    placement: .aboveLine,
                    kind: .object(["kind": .string("code_lens")]),
                    text: "Run Test",
                    styles: [0x0800_0002],
                    tooltip: nil,
                    dataJSON: lensJSON
                ),
                EcuDecoration(
                    range: EcuOffsetRange(start: 6, end: 6),
                    placement: .after,
                    kind: .object(["kind": .string("inlay_hint")]),
                    text: ": Int",
                    styles: [],
                    tooltip: nil,
                    dataJSON: nil
                ),
            ]),
        ])

        let items = AttoLspCodeLensParser.items(fromDecorationsSnapshot: snapshot)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].title, "Run Test")
        XCTAssertEqual(items[0].range, EcuOffsetRange(start: 5, end: 5))
        XCTAssertEqual(items[0].command?.title, "Run Test")
        XCTAssertEqual(items[0].command?.command, "test.run")
        XCTAssertTrue(items[0].command?.commandJSON.contains("\"arguments\"") == true)
    }

    func testResolvedCodeLensParsesCommandAndFallbackTitle() throws {
        let unresolvedJSON = """
        {
          "range": {
            "start": { "line": 1, "character": 0 },
            "end": { "line": 1, "character": 0 }
          },
          "data": { "id": 1 }
        }
        """

        let unresolved = AttoLspCodeLensParser.item(
            fromCodeLensJSON: unresolvedJSON,
            fallbackTitle: "Resolve me",
            fallbackRange: EcuOffsetRange(start: 10, end: 10)
        )
        XCTAssertEqual(unresolved?.title, "Resolve me")
        XCTAssertNil(unresolved?.command)

        let resolvedJSON = """
        {
          "range": {
            "start": { "line": 1, "character": 0 },
            "end": { "line": 1, "character": 0 }
          },
          "command": {
            "title": "Apply Fix",
            "command": "fix.apply"
          }
        }
        """

        let resolved = AttoLspCodeLensParser.item(
            fromCodeLensJSON: resolvedJSON,
            fallbackTitle: unresolved?.title,
            fallbackRange: unresolved?.range ?? EcuOffsetRange(start: 0, end: 0)
        )

        XCTAssertEqual(resolved?.title, "Apply Fix")
        XCTAssertEqual(resolved?.range, EcuOffsetRange(start: 10, end: 10))
        XCTAssertEqual(resolved?.command?.command, "fix.apply")
        XCTAssertEqual(
            AttoLspCodeLensParser.displayTitle(for: try XCTUnwrap(resolved), location: "file.swift:2:1"),
            "Apply Fix — file.swift:2:1"
        )
    }

    func testInvalidDecorationsAreIgnored() {
        let snapshot = EcuDecorationsSnapshot(layers: [
            EcuDecorationLayerSnapshot(layer: 2, decorations: [
                EcuDecoration(
                    range: EcuOffsetRange(start: 0, end: 0),
                    placement: .aboveLine,
                    kind: .object(["kind": .string("code_lens")]),
                    text: nil,
                    styles: [],
                    tooltip: nil,
                    dataJSON: "{"
                ),
                EcuDecoration(
                    range: EcuOffsetRange(start: 0, end: 0),
                    placement: .aboveLine,
                    kind: .object(["kind": .string("custom")]),
                    text: "not code lens",
                    styles: [],
                    tooltip: nil,
                    dataJSON: "{}"
                ),
            ]),
        ])

        XCTAssertTrue(AttoLspCodeLensParser.items(fromDecorationsSnapshot: snapshot).isEmpty)
        XCTAssertNil(AttoLspCodeLensParser.item(fromCodeLensJSON: "{"))
    }
}
