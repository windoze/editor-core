@testable import AttoEditor
import XCTest

final class AttoLspWorkspaceDiagnosticsParserTests: XCTestCase {
    func testParseWorkspaceDiagnosticReportFlattensDocumentsAndRelatedDocuments() throws {
        let parsed = AttoLspWorkspaceDiagnosticsParser.parse("""
        {
          "items": [
            {
              "uri": "file:///project/a.swift",
              "kind": "full",
              "resultId": "a-1",
              "items": [
                {
                  "range": {
                    "start": { "line": 2, "character": 4 },
                    "end": { "line": 2, "character": 9 }
                  },
                  "severity": 1,
                  "code": 1001,
                  "source": "swift",
                  "message": "Cannot find value"
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
                      "severity": 2,
                      "code": "unused",
                      "message": "Unused import"
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

        XCTAssertEqual(parsed.documents.count, 3)
        XCTAssertEqual(parsed.documents.map(\.uri), [
            "file:///project/a.swift",
            "file:///project/b.swift",
            "file:///project/c.swift",
        ])
        XCTAssertEqual(parsed.documents.map(\.resultId), ["a-1", "b-1", "c-1"])
        XCTAssertEqual(parsed.diagnostics.count, 2)

        XCTAssertEqual(parsed.diagnostics[0].target.uri, "file:///project/a.swift")
        XCTAssertEqual(parsed.diagnostics[0].target.line, 2)
        XCTAssertEqual(parsed.diagnostics[0].target.utf16Character, 4)
        XCTAssertEqual(parsed.diagnostics[0].endLine, 2)
        XCTAssertEqual(parsed.diagnostics[0].endUTF16Character, 9)
        XCTAssertEqual(parsed.diagnostics[0].severity, 1)
        XCTAssertEqual(parsed.diagnostics[0].severityLabel, "error")
        XCTAssertEqual(parsed.diagnostics[0].code, "1001")
        XCTAssertEqual(parsed.diagnostics[0].source, "swift")
        XCTAssertEqual(parsed.diagnostics[0].message, "Cannot find value")
        XCTAssertEqual(parsed.diagnostics[0].resultId, "a-1")

        XCTAssertEqual(parsed.diagnostics[1].target.uri, "file:///project/b.swift")
        XCTAssertEqual(parsed.diagnostics[1].severityLabel, "warning")
        XCTAssertEqual(parsed.diagnostics[1].code, "unused")
        XCTAssertEqual(parsed.diagnostics[1].message, "Unused import")

        XCTAssertEqual(
            parsed.previousResultIdsJSON(),
            #"[{"uri":"file:\/\/\/project\/a.swift","value":"a-1"},{"uri":"file:\/\/\/project\/b.swift","value":"b-1"},{"uri":"file:\/\/\/project\/c.swift","value":"c-1"}]"#
        )
    }

    func testParseIgnoresInvalidDiagnosticsAndInvalidJSON() throws {
        XCTAssertTrue(AttoLspWorkspaceDiagnosticsParser.parse("not json").diagnostics.isEmpty)

        let parsed = AttoLspWorkspaceDiagnosticsParser.parse("""
        {
          "items": [
            {
              "uri": "file:///project/a.swift",
              "kind": "full",
              "items": [
                { "message": "missing range" },
                {
                  "range": {
                    "start": { "line": 1, "character": 0 },
                    "end": { "line": 1, "character": 1 }
                  },
                  "message": "valid"
                }
              ]
            }
          ]
        }
        """)

        XCTAssertEqual(parsed.documents.count, 1)
        XCTAssertEqual(parsed.diagnostics.count, 1)
        XCTAssertEqual(parsed.diagnostics[0].message, "valid")
        XCTAssertNil(parsed.diagnostics[0].severityLabel)
        XCTAssertEqual(parsed.previousResultIdsJSON(), "[]")
    }
}
