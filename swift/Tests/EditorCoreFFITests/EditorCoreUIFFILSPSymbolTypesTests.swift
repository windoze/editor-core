import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPSymbolTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testDocumentSymbolResultDecodesNestedDocumentSymbolsAndNull() throws {
        let result = try decode(EcuLspDocumentSymbolResult.self, """
        [
          {
            "name": "App",
            "detail": "struct",
            "kind": 23,
            "tags": [1],
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 5, "character": 1 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 7 },
              "end": { "line": 0, "character": 10 }
            },
            "children": [
              {
                "name": "run",
                "kind": 12,
                "range": {
                  "start": { "line": 2, "character": 2 },
                  "end": { "line": 4, "character": 3 }
                },
                "selectionRange": {
                  "start": { "line": 2, "character": 7 },
                  "end": { "line": 2, "character": 10 }
                }
              }
            ]
          }
        ]
        """)

        XCTAssertEqual(result.shape, .documentSymbolArray)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.documentSymbols.first?.name, "App")
        XCTAssertEqual(result.documentSymbols.first?.detail, "struct")
        XCTAssertEqual(result.documentSymbols.first?.kind, 23)
        XCTAssertEqual(result.documentSymbols.first?.tags, [1])
        XCTAssertEqual(result.documentSymbols.first?.selectionRange.start.utf16Character, 7)
        XCTAssertEqual(result.documentSymbols.first?.children.first?.name, "run")
        XCTAssertNotNil(result.rawJSONString)

        let none = try decode(EcuLspDocumentSymbolResult.self, "null")
        XCTAssertEqual(none.shape, .none)
        XCTAssertTrue(none.isEmpty)
    }

    func testDocumentSymbolResultDecodesSymbolInformation() throws {
        let result = try decode(EcuLspDocumentSymbolResult.self, """
        [
          {
            "name": "main",
            "kind": 12,
            "containerName": "crate",
            "location": {
              "uri": "file:///tmp/main.rs",
              "range": {
                "start": { "line": 4, "character": 3 },
                "end": { "line": 4, "character": 7 }
              }
            }
          }
        ]
        """)

        XCTAssertEqual(result.shape, .symbolInformationArray)
        XCTAssertEqual(result.symbolInformation.first?.name, "main")
        XCTAssertEqual(result.symbolInformation.first?.location.uri, "file:///tmp/main.rs")
        XCTAssertEqual(result.symbolInformation.first?.location.range.start.line, 4)
        XCTAssertEqual(result.symbolInformation.first?.containerName, "crate")
    }

    func testWorkspaceSymbolResultDecodesFullLocationAndUriOnlyLocation() throws {
        let result = try decode(EcuLspWorkspaceSymbolResult.self, """
        [
          {
            "name": "openProject",
            "detail": "fn",
            "kind": 12,
            "containerName": "Project",
            "location": {
              "uri": "file:///tmp/project.swift",
              "range": {
                "start": { "line": 7, "character": 2 },
                "end": { "line": 7, "character": 14 }
              }
            },
            "data": { "id": 1 }
          },
          {
            "name": "Project",
            "kind": 23,
            "location": { "uri": "file:///tmp/project.swift" }
          }
        ]
        """)

        XCTAssertEqual(result.shape, .workspaceSymbolArray)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.symbols.count, 2)
        XCTAssertEqual(result.symbols[0].detail, "fn")
        XCTAssertEqual(result.symbols[0].containerName, "Project")
        XCTAssertEqual(result.symbols[0].data, .object(["id": .number(1)]))
        XCTAssertEqual(result.symbols[0].location?.target?.selectionRange.start.line, 7)
        XCTAssertEqual(result.symbols[1].location?.target?.uri, "file:///tmp/project.swift")
        XCTAssertEqual(result.symbols[1].location?.target?.selectionRange.start.line, 0)
        XCTAssertNotNil(result.rawJSONString)
    }

    func testSymbolTypedTakeWrappersStartEmpty() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        XCTAssertNil(try ui.lspTakeLastDocumentSymbolsResult())
        XCTAssertNil(try ui.lspTakeLastWorkspaceSymbolsResult())
    }
}
