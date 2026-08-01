import Foundation
@testable import AttoEditor
import EditorCoreUIFFI
import XCTest

final class AttoLspSymbolParserTests: XCTestCase {
    func testDocumentSymbolsParseNestedDocumentSymbolResult() throws {
        let json = """
        [
          {
            "name": "App",
            "kind": 5,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 10, "character": 1 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 6 },
              "end": { "line": 0, "character": 9 }
            },
            "children": [
              {
                "name": "run",
                "detail": "fn()",
                "kind": 12,
                "range": {
                  "start": { "line": 2, "character": 2 },
                  "end": { "line": 4, "character": 3 }
                },
                "selectionRange": {
                  "start": { "line": 2, "character": 5 },
                  "end": { "line": 2, "character": 8 }
                }
              }
            ]
          }
        ]
        """

        let symbols = AttoLspSymbolParser.documentSymbols(
            fromResultJSON: json,
            documentURI: "file:///tmp/app.rs"
        )

        XCTAssertEqual(symbols.count, 2)
        XCTAssertEqual(symbols[0].name, "App")
        XCTAssertEqual(symbols[0].kindLabel, "class")
        XCTAssertEqual(symbols[0].target, .init(uri: "file:///tmp/app.rs", line: 0, utf16Character: 6))
        XCTAssertEqual(symbols[0].depth, 0)

        XCTAssertEqual(symbols[1].name, "run")
        XCTAssertEqual(symbols[1].detail, "fn()")
        XCTAssertEqual(symbols[1].kindLabel, "function")
        XCTAssertEqual(symbols[1].target, .init(uri: "file:///tmp/app.rs", line: 2, utf16Character: 5))
        XCTAssertEqual(symbols[1].depth, 1)
    }

    func testDocumentSymbolsParseFlatSymbolInformationResult() throws {
        let json = """
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
        """

        let symbols = AttoLspSymbolParser.documentSymbols(
            fromResultJSON: json,
            documentURI: "file:///tmp/main.rs"
        )

        XCTAssertEqual(symbols.count, 1)
        XCTAssertEqual(symbols[0].name, "main")
        XCTAssertEqual(symbols[0].containerName, "crate")
        XCTAssertEqual(symbols[0].target, .init(uri: "file:///tmp/main.rs", line: 4, utf16Character: 3))
    }

    func testDocumentSymbolsBuildFromTypedSnapshot() throws {
        let text = "let 😀app\nrun()\n"
        let snapshot = EcuDocumentSymbolsSnapshot(symbols: [
            EcuDocumentSymbol(
                name: "App",
                detail: nil,
                kind: .number(5),
                range: EcuOffsetRange(start: 0, end: 8),
                selectionRange: EcuOffsetRange(start: 5, end: 8),
                children: [
                    EcuDocumentSymbol(
                        name: "run",
                        detail: "fn()",
                        kind: .object(["value": .number(12)]),
                        range: EcuOffsetRange(start: 9, end: 14),
                        selectionRange: EcuOffsetRange(start: 9, end: 12),
                        children: [],
                        dataJSON: nil
                    ),
                ],
                dataJSON: nil
            ),
        ])

        let symbols = AttoLspSymbolParser.documentSymbols(
            snapshot: snapshot,
            documentURI: "file:///tmp/app.rs",
            documentText: text
        )

        XCTAssertEqual(symbols.count, 2)
        XCTAssertEqual(symbols[0].name, "App")
        XCTAssertEqual(symbols[0].kindLabel, "class")
        XCTAssertEqual(symbols[0].target, .init(uri: "file:///tmp/app.rs", line: 0, utf16Character: 6))
        XCTAssertEqual(symbols[0].depth, 0)

        XCTAssertEqual(symbols[1].name, "run")
        XCTAssertEqual(symbols[1].detail, "fn()")
        XCTAssertEqual(symbols[1].kindLabel, "function")
        XCTAssertEqual(symbols[1].target, .init(uri: "file:///tmp/app.rs", line: 1, utf16Character: 0))
        XCTAssertEqual(symbols[1].depth, 1)
    }

    func testWorkspaceSymbolsParseLocationAndUriOnlyShapes() throws {
        let json = """
        [
          {
            "name": "open_project",
            "kind": 12,
            "detail": "fn",
            "location": {
              "uri": "file:///tmp/project.rs",
              "range": {
                "start": { "line": 7, "character": 2 },
                "end": { "line": 7, "character": 14 }
              }
            }
          },
          {
            "name": "Project",
            "kind": 23,
            "location": { "uri": "file:///tmp/project.rs" }
          }
        ]
        """

        let symbols = AttoLspSymbolParser.workspaceSymbols(fromResultJSON: json)

        XCTAssertEqual(symbols.count, 2)
        XCTAssertEqual(symbols[0].name, "open_project")
        XCTAssertEqual(symbols[0].detail, "fn")
        XCTAssertEqual(symbols[0].kindLabel, "function")
        XCTAssertEqual(symbols[0].target, .init(uri: "file:///tmp/project.rs", line: 7, utf16Character: 2))
        XCTAssertEqual(symbols[1].name, "Project")
        XCTAssertEqual(symbols[1].kindLabel, "struct")
        XCTAssertEqual(symbols[1].target, .init(uri: "file:///tmp/project.rs", line: 0, utf16Character: 0))
    }
}
