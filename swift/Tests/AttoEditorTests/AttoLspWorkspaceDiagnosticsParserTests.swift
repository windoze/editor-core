import EditorCoreUIFFI
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

    func testParseTypedWorkspaceDiagnosticReportFlattensDocumentsAndRelatedDocuments() throws {
        let result = try decode(EcuLspWorkspaceDiagnosticResult.self, """
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

        let parsed = AttoLspWorkspaceDiagnosticsParser.parse(result)

        XCTAssertEqual(parsed.documents.count, 3)
        XCTAssertEqual(parsed.documents.map(\.uri), [
            "file:///project/a.swift",
            "file:///project/b.swift",
            "file:///project/c.swift",
        ])
        XCTAssertEqual(parsed.documents.map(\.kind), ["full", "full", "unchanged"])
        XCTAssertEqual(parsed.documents.map(\.resultId), ["a-1", "b-1", "c-1"])
        XCTAssertEqual(parsed.diagnostics.count, 2)
        XCTAssertEqual(parsed.diagnostics[0].target.uri, "file:///project/a.swift")
        XCTAssertEqual(parsed.diagnostics[0].target.line, 2)
        XCTAssertEqual(parsed.diagnostics[0].target.utf16Character, 4)
        XCTAssertEqual(parsed.diagnostics[0].severityLabel, "error")
        XCTAssertEqual(parsed.diagnostics[0].code, "1001")
        XCTAssertEqual(parsed.diagnostics[0].source, "swift")
        XCTAssertEqual(parsed.diagnostics[0].message, "Cannot find value")
        XCTAssertEqual(parsed.diagnostics[1].target.uri, "file:///project/b.swift")
        XCTAssertEqual(parsed.diagnostics[1].severityLabel, "warning")
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

    func testWorkspaceProblemsStoreMergesUnchangedReportsAndClearsFullReports() throws {
        let store = AttoWorkspaceProblemsStore()
        let full = AttoLspWorkspaceDiagnosticsParser.parse("""
        {
          "items": [
            {
              "uri": "file:///project/a.swift",
              "kind": "full",
              "resultId": "a-1",
              "items": [
                {
                  "range": {
                    "start": { "line": 0, "character": 1 },
                    "end": { "line": 0, "character": 3 }
                  },
                  "severity": 1,
                  "message": "first problem"
                }
              ]
            }
          ]
        }
        """)
        var snapshot = store.apply(full)
        XCTAssertEqual(snapshot.diagnostics.map(\.message), ["first problem"])
        XCTAssertEqual(snapshot.previousResultIdsJSON(), #"[{"uri":"file:\/\/\/project\/a.swift","value":"a-1"}]"#)

        let unchanged = AttoLspWorkspaceDiagnosticsParser.parse("""
        {
          "items": [
            {
              "uri": "file:///project/a.swift",
              "kind": "unchanged",
              "resultId": "a-2"
            }
          ]
        }
        """)
        snapshot = store.apply(unchanged)
        XCTAssertEqual(snapshot.diagnostics.map(\.message), ["first problem"])
        XCTAssertEqual(snapshot.documents.map(\.resultId), ["a-2"])

        let cleared = AttoLspWorkspaceDiagnosticsParser.parse("""
        {
          "items": [
            {
              "uri": "file:///project/a.swift",
              "kind": "full",
              "resultId": "a-3",
              "items": []
            }
          ]
        }
        """)
        snapshot = store.apply(cleared)
        XCTAssertTrue(snapshot.diagnostics.isEmpty)
        XCTAssertEqual(snapshot.previousResultIdsJSON(), #"[{"uri":"file:\/\/\/project\/a.swift","value":"a-3"}]"#)
    }

    func testWorkspaceProblemsStoreCanApplyTypedResult() throws {
        let store = AttoWorkspaceProblemsStore()
        let typed = try decode(EcuLspWorkspaceDiagnosticResult.self, """
        {
          "items": [
            {
              "uri": "file:///project/a.swift",
              "kind": "full",
              "resultId": "a-1",
              "items": [
                {
                  "range": {
                    "start": { "line": 0, "character": 1 },
                    "end": { "line": 0, "character": 3 }
                  },
                  "severity": 1,
                  "message": "first problem"
                }
              ]
            }
          ]
        }
        """)

        let snapshot = store.apply(result: typed)

        XCTAssertEqual(snapshot.diagnostics.map(\.message), ["first problem"])
        XCTAssertEqual(snapshot.previousResultIdsJSON(), #"[{"uri":"file:\/\/\/project\/a.swift","value":"a-1"}]"#)
    }

    func testWorkspaceProblemsStoreCanUseCoreOwnedSnapshot() throws {
        let coreDocuments = try MultiDocumentEditorUI(library: EditorCoreUIFFILibrary())
        let store = AttoWorkspaceProblemsStore(coreDocuments: coreDocuments)

        var snapshot = store.apply(resultJSON: """
        {
          "items": [
            {
              "uri": "file:///project/a.swift",
              "kind": "full",
              "resultId": "a-1",
              "items": [
                {
                  "range": {
                    "start": { "line": 0, "character": 1 },
                    "end": { "line": 0, "character": 3 }
                  },
                  "severity": 1,
                  "message": "first problem"
                }
              ]
            }
          ]
        }
        """)
        XCTAssertEqual(snapshot.diagnostics.map(\.message), ["first problem"])
        XCTAssertEqual(snapshot.diagnostics.first?.severityLabel, "error")
        let initialMarkerRefreshCount = store.coreMarkerRefreshCount
        XCTAssertEqual(
            store.diagnosticMarkerProjections(),
            [
                AttoWorkspaceDiagnosticMarkerProjection(
                    uri: "file:///project/a.swift",
                    line: 0,
                    utf16Character: 1,
                    severity: .error
                ),
            ]
        )
        XCTAssertEqual(store.coreMarkerRefreshCount, initialMarkerRefreshCount + 1)

        let markerRefreshCountAfterInitialRead = store.coreMarkerRefreshCount
        _ = store.diagnosticMarkerProjections()
        XCTAssertEqual(store.coreMarkerRefreshCount, markerRefreshCountAfterInitialRead)

        let previous = try XCTUnwrap(
            JSONSerialization.jsonObject(
                with: Data(store.previousResultIdsJSON().utf8),
                options: []
            ) as? [[String: String]]
        )
        XCTAssertEqual(previous, [["uri": "file:///project/a.swift", "value": "a-1"]])

        snapshot = store.apply(resultJSON: """
        {
          "items": [
            {
              "uri": "file:///project/a.swift",
              "kind": "unchanged",
              "resultId": "a-2"
            }
          ]
        }
        """)
        XCTAssertEqual(snapshot.diagnostics.map(\.message), ["first problem"])
        XCTAssertEqual(snapshot.documents.map(\.resultId), ["a-2"])

        let refreshCountBeforeCoreEvent = store.coreSnapshotRefreshCount
        _ = try coreDocuments.applyWorkspaceDiagnosticsJSON("""
        {
          "items": [
            {
              "uri": "file:///project/a.swift",
              "kind": "full",
              "resultId": "a-3",
              "items": [
                {
                  "range": {
                    "start": { "line": 1, "character": 0 },
                    "end": { "line": 1, "character": 4 }
                  },
                  "severity": 2,
                  "message": "event refreshed problem"
                }
              ]
            }
          ]
        }
        """)

        snapshot = store.snapshot
        XCTAssertEqual(snapshot.diagnostics.map(\.message), ["event refreshed problem"])
        XCTAssertEqual(store.lastWorkspaceDiagnosticsEvents.map(\.operationKind), [.apply])
        XCTAssertEqual(store.coreSnapshotRefreshCount, refreshCountBeforeCoreEvent + 1)

        let refreshCountAfterEventDrain = store.coreSnapshotRefreshCount
        let markerRefreshCountBeforeEventDrain = store.coreMarkerRefreshCount
        XCTAssertEqual(
            store.diagnosticMarkerProjections(),
            [
                AttoWorkspaceDiagnosticMarkerProjection(
                    uri: "file:///project/a.swift",
                    line: 1,
                    utf16Character: 0,
                    severity: .warning
                ),
            ]
        )
        XCTAssertEqual(store.coreMarkerRefreshCount, markerRefreshCountBeforeEventDrain + 1)

        let markerRefreshCountAfterEventDrain = store.coreMarkerRefreshCount
        _ = store.diagnosticMarkerProjections()
        XCTAssertEqual(store.coreMarkerRefreshCount, markerRefreshCountAfterEventDrain)

        _ = store.snapshot
        XCTAssertTrue(store.lastWorkspaceDiagnosticsEvents.isEmpty)
        XCTAssertEqual(store.coreSnapshotRefreshCount, refreshCountAfterEventDrain)

        store.clear()
        XCTAssertTrue(store.snapshot.diagnostics.isEmpty)
        XCTAssertEqual(store.previousResultIdsJSON(), "[]")
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }
}
