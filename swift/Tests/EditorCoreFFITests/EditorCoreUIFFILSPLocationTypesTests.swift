import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPLocationTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testSingleLocationPayloadDecodesTarget() throws {
        let result = try decode(EcuLspLocationResult.self, """
        {
          "uri": "file:///tmp/main.swift",
          "range": {
            "start": { "line": 2, "character": 4 },
            "end": { "line": 2, "character": 9 }
          }
        }
        """)

        XCTAssertEqual(result.shape, .location)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.locations.count, 1)
        XCTAssertEqual(result.locationLinks.count, 0)
        XCTAssertEqual(result.targets.first?.uri, "file:///tmp/main.swift")
        XCTAssertEqual(result.targets.first?.selectionRange.start.line, 2)
        XCTAssertEqual(result.targets.first?.selectionRange.start.utf16Character, 4)
        XCTAssertEqual(result.targets.first?.sourceKind, .location)
        XCTAssertEqual(result.raw, .object([
            "uri": .string("file:///tmp/main.swift"),
            "range": .object([
                "start": .object(["line": .number(2), "character": .number(4)]),
                "end": .object(["line": .number(2), "character": .number(9)]),
            ]),
        ]))
    }

    func testLocationLinkArrayPayloadDecodesSelectionTargets() throws {
        let result = try decode(EcuLspLocationResult.self, """
        [
          {
            "originSelectionRange": {
              "start": { "line": 0, "character": 1 },
              "end": { "line": 0, "character": 3 }
            },
            "targetUri": "file:///tmp/lib.swift",
            "targetRange": {
              "start": { "line": 9, "character": 0 },
              "end": { "line": 12, "character": 0 }
            },
            "targetSelectionRange": {
              "start": { "line": 10, "character": 5 },
              "end": { "line": 10, "character": 12 }
            }
          }
        ]
        """)

        XCTAssertEqual(result.shape, .locationLinkArray)
        XCTAssertEqual(result.locations.count, 0)
        XCTAssertEqual(result.locationLinks.count, 1)
        XCTAssertEqual(result.locationLinks.first?.originSelectionRange?.start.utf16Character, 1)
        XCTAssertEqual(result.locationLinks.first?.targetRange.start.line, 9)
        let target = try XCTUnwrap(result.targets.first)
        XCTAssertEqual(target.uri, "file:///tmp/lib.swift")
        XCTAssertEqual(target.range.start.line, 9)
        XCTAssertEqual(target.range.end.line, 12)
        XCTAssertEqual(target.selectionRange.start.line, 10)
        XCTAssertEqual(target.selectionRange.start.utf16Character, 5)
        XCTAssertEqual(target.selectionRange.end.utf16Character, 12)
        XCTAssertEqual(target.sourceKind, .locationLink)
    }

    func testLocationArrayAndNullPayloadsDecode() throws {
        let arrayResult = try decode(EcuLspLocationResult.self, """
        [
          {
            "uri": "file:///tmp/a.swift",
            "range": {
              "start": { "line": 1, "character": 2 },
              "end": { "line": 1, "character": 3 }
            }
          },
          {
            "uri": "file:///tmp/b.swift",
            "range": {
              "start": { "line": 4, "character": 5 },
              "end": { "line": 4, "character": 6 }
            }
          }
        ]
        """)

        XCTAssertEqual(arrayResult.shape, .locationArray)
        XCTAssertEqual(arrayResult.targets.map(\.uri), ["file:///tmp/a.swift", "file:///tmp/b.swift"])

        let nullResult = try decode(EcuLspLocationResult.self, "null")
        XCTAssertEqual(nullResult.shape, .none)
        XCTAssertTrue(nullResult.isEmpty)
        XCTAssertEqual(nullResult.targets, [])
    }

    func testMixedArrayPreservesTargetOrder() throws {
        let result = try decode(EcuLspLocationResult.self, """
        [
          {
            "targetUri": "file:///tmp/link.swift",
            "targetRange": {
              "start": { "line": 8, "character": 0 },
              "end": { "line": 9, "character": 0 }
            },
            "targetSelectionRange": {
              "start": { "line": 8, "character": 2 },
              "end": { "line": 8, "character": 4 }
            }
          },
          {
            "uri": "file:///tmp/location.swift",
            "range": {
              "start": { "line": 1, "character": 2 },
              "end": { "line": 1, "character": 3 }
            }
          }
        ]
        """)

        XCTAssertEqual(result.shape, .mixedArray)
        XCTAssertEqual(result.targets.map(\.uri), ["file:///tmp/link.swift", "file:///tmp/location.swift"])
        XCTAssertEqual(result.targets.map(\.sourceKind), [.locationLink, .location])
    }

    func testLocationTypedTakeWrappersStartEmpty() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        XCTAssertNil(try ui.lspTakeLastDefinitionResult())
        XCTAssertNil(try ui.lspTakeLastDeclarationResult())
        XCTAssertNil(try ui.lspTakeLastTypeDefinitionResult())
        XCTAssertNil(try ui.lspTakeLastImplementationResult())
        XCTAssertNil(try ui.lspTakeLastReferencesResult())
    }
}
