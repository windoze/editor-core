import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPDiagnosticTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testDocumentDiagnosticResultDecodesFullReportAndRelatedDocuments() throws {
        let result = try decode(EcuLspDocumentDiagnosticResult.self, """
        {
          "kind": "full",
          "resultId": "doc-1",
          "items": [
            {
              "range": {
                "start": { "line": 2, "character": 4 },
                "end": { "line": 2, "character": 9 }
              },
              "severity": 1,
              "code": 1001,
              "codeDescription": { "href": "https://example.test/1001" },
              "source": "swift",
              "message": "Cannot find value",
              "tags": [1],
              "relatedInformation": [
                {
                  "location": {
                    "uri": "file:///project/a.swift",
                    "range": {
                      "start": { "line": 0, "character": 0 },
                      "end": { "line": 0, "character": 1 }
                    }
                  },
                  "message": "Declared here"
                }
              ],
              "data": { "opaque": true }
            }
          ],
          "relatedDocuments": {
            "file:///project/b.swift": {
              "kind": "unchanged",
              "resultId": "b-1"
            }
          }
        }
        """)

        XCTAssertEqual(result.shape, .report)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.report?.kindKind, .full)
        XCTAssertEqual(result.report?.resultId, "doc-1")
        XCTAssertEqual(result.report?.diagnostics.first?.range.start.line, 2)
        XCTAssertEqual(result.report?.diagnostics.first?.severityKind, .error)
        XCTAssertEqual(result.report?.diagnostics.first?.severityLabel, "error")
        XCTAssertEqual(result.report?.diagnostics.first?.code, .number(1001))
        XCTAssertEqual(result.report?.diagnostics.first?.codeString, "1001")
        XCTAssertEqual(result.report?.diagnostics.first?.codeDescription?.href, "https://example.test/1001")
        XCTAssertEqual(result.report?.diagnostics.first?.source, "swift")
        XCTAssertEqual(result.report?.diagnostics.first?.message, "Cannot find value")
        XCTAssertEqual(result.report?.diagnostics.first?.tags, [1])
        XCTAssertEqual(result.report?.diagnostics.first?.relatedInformation.first?.message, "Declared here")
        XCTAssertEqual(result.report?.diagnostics.first?.data, .object(["opaque": .bool(true)]))
        XCTAssertEqual(result.report?.relatedDocuments["file:///project/b.swift"]?.kindKind, .unchanged)
        XCTAssertNotNil(result.rawJSONString)

        let none = try decode(EcuLspDocumentDiagnosticResult.self, "null")
        XCTAssertEqual(none.shape, .none)
        XCTAssertTrue(none.isEmpty)
    }

    func testWorkspaceDiagnosticResultDecodesItemsAndRelatedDocuments() throws {
        let result = try decode(EcuLspWorkspaceDiagnosticResult.self, """
        {
          "items": [
            {
              "uri": "file:///project/a.swift",
              "version": 3,
              "kind": "full",
              "resultId": "a-1",
              "items": [
                {
                  "range": {
                    "start": { "line": 1, "character": 2 },
                    "end": { "line": 1, "character": 5 }
                  },
                  "severity": 2,
                  "code": "unused",
                  "message": "Unused value"
                }
              ],
              "relatedDocuments": {
                "file:///project/b.swift": {
                  "kind": "full",
                  "resultId": "b-1",
                  "items": [
                    {
                      "range": {
                        "start": { "line": 0, "character": 1 },
                        "end": { "line": 0, "character": 3 }
                      },
                      "severity": 4,
                      "message": "Hint"
                    }
                  ]
                }
              }
            },
            {
              "uri": "file:///project/c.swift",
              "kind": "unchanged",
              "resultId": "c-1"
            }
          ]
        }
        """)

        XCTAssertEqual(result.shape, .report)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.items.count, 2)
        XCTAssertEqual(result.items[0].uri, "file:///project/a.swift")
        XCTAssertEqual(result.items[0].version, 3)
        XCTAssertEqual(result.items[0].kindKind, .full)
        XCTAssertEqual(result.items[0].diagnostics.first?.severityKind, .warning)
        XCTAssertEqual(result.items[0].diagnostics.first?.codeString, "unused")
        XCTAssertEqual(result.items[0].relatedDocuments["file:///project/b.swift"]?.diagnostics.first?.severityKind, .hint)
        XCTAssertEqual(result.items[1].kindKind, .unchanged)
        XCTAssertTrue(result.items[1].diagnostics.isEmpty)
        XCTAssertNotNil(result.rawJSONString)
    }

    func testDiagnosticTypedTakeWrappersStartEmpty() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        XCTAssertNil(try ui.lspTakeLastDocumentDiagnosticResult())
        XCTAssertNil(try ui.lspTakeLastWorkspaceDiagnosticResult())
    }
}
