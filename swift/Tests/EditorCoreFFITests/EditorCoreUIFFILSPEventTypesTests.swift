import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPEventTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testEditorLSPResultEventsExposeTypedKinds() throws {
        let snapshot = try decode(EcuLspResultEventsSnapshot.self, """
        {
          "latest_sequence": 2,
          "events": [
            {
              "sequence": 1,
              "family": "diagnostics",
              "title": "LSP Publish Diagnostics: success",
              "slot": "publish_diagnostics",
              "method": "textDocument/publishDiagnostics",
              "view_id": 7,
              "request_id": 0,
              "status": "success",
              "has_result": true,
              "result_json_len": 32
            },
            {
              "sequence": 2,
              "family": "future_family",
              "title": "Future",
              "slot": "future_slot",
              "method": "future/method",
              "view_id": 7,
              "request_id": 99,
              "status": "future_status",
              "has_result": false,
              "result_json_len": 0
            }
          ]
        }
        """)

        XCTAssertEqual(snapshot.latestSequence, 2)
        XCTAssertEqual(snapshot.events[0].familyKind, .diagnostics)
        XCTAssertEqual(snapshot.events[0].slotKind, .publishDiagnostics)
        XCTAssertEqual(snapshot.events[0].statusKind, .success)
        XCTAssertEqual(snapshot.events[0].slotKind.rawValue, "publish_diagnostics")
        XCTAssertEqual(snapshot.events[1].familyKind, .unknown("future_family"))
        XCTAssertEqual(snapshot.events[1].slotKind, .unknown("future_slot"))
        XCTAssertEqual(snapshot.events[1].statusKind, .unknown("future_status"))
        XCTAssertEqual(snapshot.events[1].familyKind.rawValue, "future_family")
    }

    func testEditorLSPRequestEventsExposeTypedKinds() throws {
        let snapshot = try decode(EcuLspRequestEventsSnapshot.self, """
        {
          "latest_sequence": 3,
          "events": [
            {
              "sequence": 1,
              "family": "semantic_tokens",
              "title": "LSP Semantic Tokens Full: pending",
              "slot": "semantic_tokens_full",
              "method": "textDocument/semanticTokens/full",
              "view_id": 11,
              "request_id": 42,
              "phase": "started",
              "status": "pending"
            },
            {
              "sequence": 2,
              "family": "diagnostics",
              "title": "LSP Document Diagnostic: stale",
              "slot": "document_diagnostic",
              "method": "textDocument/diagnostic",
              "view_id": 11,
              "request_id": 43,
              "phase": "completed",
              "status": "stale",
              "result_sequence": 10
            },
            {
              "sequence": 3,
              "family": "future_family",
              "title": "Future",
              "slot": "future_slot",
              "method": "future/method",
              "view_id": 11,
              "request_id": 44,
              "phase": "future_phase",
              "status": "future_status"
            }
          ]
        }
        """)

        XCTAssertEqual(snapshot.events[0].familyKind, .semanticTokens)
        XCTAssertEqual(snapshot.events[0].slotKind, .semanticTokensFull)
        XCTAssertEqual(snapshot.events[0].phaseKind, .started)
        XCTAssertEqual(snapshot.events[0].statusKind, .pending)
        XCTAssertEqual(snapshot.events[1].familyKind, .diagnostics)
        XCTAssertEqual(snapshot.events[1].slotKind, .documentDiagnostic)
        XCTAssertEqual(snapshot.events[1].phaseKind, .completed)
        XCTAssertEqual(snapshot.events[1].statusKind, .stale)
        XCTAssertEqual(snapshot.events[1].resultSequence, 10)
        XCTAssertEqual(snapshot.events[2].phaseKind, .unknown("future_phase"))
        XCTAssertEqual(snapshot.events[2].statusKind.rawValue, "future_status")
    }

    func testWorkspaceDiagnosticsExposeTypedKinds() throws {
        let snapshot = try decode(EcuWorkspaceDiagnosticsSnapshot.self, """
        {
          "documents": [
            {
              "uri": "file:///project/a.swift",
              "kind": "full",
              "result_id": "a-1",
              "diagnostics": [
                {
                  "target": {
                    "uri": "file:///project/a.swift",
                    "line": 1,
                    "utf16_character": 2
                  },
                  "end_line": 1,
                  "end_utf16_character": 5,
                  "severity": 2,
                  "severity_label": "warning",
                  "message": "warn"
                }
              ]
            },
            {
              "uri": "file:///project/b.swift",
              "kind": "future_kind",
              "result_id": "b-1",
              "diagnostics": []
            }
          ],
          "diagnostics": [
            {
              "target": {
                "uri": "file:///project/a.swift",
                "line": 1,
                "utf16_character": 2
              },
              "end_line": 1,
              "end_utf16_character": 5,
              "severity": 2,
              "severity_label": "warning",
              "message": "warn"
            }
          ]
        }
        """)

        XCTAssertEqual(snapshot.documents[0].reportKind, .full)
        XCTAssertEqual(snapshot.documents[1].reportKind, .unknown("future_kind"))
        XCTAssertEqual(snapshot.diagnostics[0].severityKind, .warning)
        XCTAssertEqual(EcuDiagnosticSeverity.warning.lspSeverity, 2)

        let events = try decode(EcuWorkspaceDiagnosticsEventsSnapshot.self, """
        {
          "latest_sequence": 2,
          "events": [
            {
              "sequence": 1,
              "family": "workspace_diagnostics",
              "title": "Workspace Diagnostics: 1 problem",
              "operation": "apply",
              "document_count": 1,
              "diagnostic_count": 1,
              "marker_count": 1
            },
            {
              "sequence": 2,
              "family": "workspace_diagnostics",
              "title": "Workspace Diagnostics: cleared",
              "operation": "clear",
              "document_count": 0,
              "diagnostic_count": 0,
              "marker_count": 0
            }
          ]
        }
        """)
        XCTAssertEqual(events.events[0].familyKind, .workspaceDiagnostics)
        XCTAssertEqual(events.events[0].operationKind, .apply)
        XCTAssertEqual(events.events[1].operationKind, .clear)
    }

    func testMultiDocumentLSPEventsExposeTypedKinds() throws {
        let resultEvents = try decode(EcuMultiDocumentLSPResultEventsSnapshot.self, """
        {
          "latest_sequence": 1,
          "events": [
            {
              "sequence": 1,
              "tab_id": 100,
              "view_index": 0,
              "view_id": 7,
              "source_sequence": 3,
              "family": "colors",
              "title": "LSP Document Color: empty",
              "slot": "document_color",
              "method": "textDocument/documentColor",
              "request_id": 42,
              "status": "empty",
              "has_result": true,
              "result_json_len": 2
            }
          ]
        }
        """)
        XCTAssertEqual(resultEvents.events[0].familyKind, .colors)
        XCTAssertEqual(resultEvents.events[0].slotKind, .documentColor)
        XCTAssertEqual(resultEvents.events[0].statusKind, .empty)

        let requestEvents = try decode(EcuMultiDocumentLSPRequestEventsSnapshot.self, """
        {
          "latest_sequence": 1,
          "events": [
            {
              "sequence": 1,
              "tab_id": 100,
              "view_index": 0,
              "view_id": 7,
              "source_sequence": 8,
              "source_result_sequence": 3,
              "family": "formatting",
              "title": "LSP On-Type Formatting: timeout",
              "slot": "on_type_formatting",
              "method": "textDocument/onTypeFormatting",
              "request_id": 45,
              "phase": "completed",
              "status": "timeout"
            }
          ]
        }
        """)
        XCTAssertEqual(requestEvents.events[0].familyKind, .formatting)
        XCTAssertEqual(requestEvents.events[0].slotKind, .onTypeFormatting)
        XCTAssertEqual(requestEvents.events[0].phaseKind, .completed)
        XCTAssertEqual(requestEvents.events[0].statusKind, .timeout)
        XCTAssertEqual(requestEvents.events[0].sourceResultSequence, 3)
    }
}
