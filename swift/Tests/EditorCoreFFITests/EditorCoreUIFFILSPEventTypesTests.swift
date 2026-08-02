import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPEventTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testAuxiliaryResolveSlotsExposeTypedKinds() {
        XCTAssertEqual(EcuLspResultSlot(rawValue: "inlay_hint_resolve"), .inlayHintResolve)
        XCTAssertEqual(EcuLspResultSlot.inlayHintResolve.rawValue, "inlay_hint_resolve")
        XCTAssertEqual(EcuLspResultSlot(rawValue: "document_link_resolve"), .documentLinkResolve)
        XCTAssertEqual(EcuLspResultSlot.documentLinkResolve.rawValue, "document_link_resolve")
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
          "latest_sequence": 4,
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

    func testEditorUIStateEventsExposeTypedKindsAndNestedPayloads() throws {
        let snapshot = try decode(EcuEditorUIStateEventsSnapshot.self, """
        {
          "latest_sequence": 2,
          "events": [
            {
              "sequence": 1,
              "kind": "lsp_request",
              "family": "hover",
              "title": "LSP Hover: pending",
              "view_id": 3,
              "source_sequence": 10,
              "lsp_request": {
                "sequence": 10,
                "family": "hover",
                "title": "LSP Hover: pending",
                "slot": "hover",
                "method": "textDocument/hover",
                "view_id": 3,
                "request_id": 44,
                "phase": "started",
                "status": "pending"
              }
            },
            {
              "sequence": 2,
              "kind": "lsp_result",
              "family": "future_family",
              "title": "Future result",
              "view_id": 3,
              "source_sequence": 11,
              "lsp_result": {
                "sequence": 11,
                "family": "future_family",
                "title": "Future result",
                "slot": "future_slot",
                "method": "future/method",
                "view_id": 3,
                "request_id": 44,
                "status": "future_status",
                "has_result": false,
                "result_json_len": 0
              }
            }
          ]
        }
        """)

        XCTAssertEqual(snapshot.latestSequence, 2)
        XCTAssertEqual(snapshot.events[0].kindValue, .lspRequest)
        XCTAssertEqual(snapshot.events[0].familyKind, .hover)
        XCTAssertEqual(snapshot.events[0].sourceSequence, 10)
        XCTAssertEqual(snapshot.events[0].lspRequest?.slotKind, .hover)
        XCTAssertEqual(snapshot.events[0].lspRequest?.phaseKind, .started)
        XCTAssertNil(snapshot.events[0].lspResult)
        XCTAssertEqual(snapshot.events[1].kindValue, .lspResult)
        XCTAssertEqual(snapshot.events[1].familyKind, .unknown("future_family"))
        XCTAssertEqual(snapshot.events[1].lspResult?.slotKind, .unknown("future_slot"))
        XCTAssertEqual(snapshot.events[1].lspResult?.statusKind, .unknown("future_status"))
        XCTAssertNil(snapshot.events[1].lspRequest)
        XCTAssertEqual(EcuEditorUIStateEventKind.unknown("future").rawValue, "future")
    }

    func testEditorUIStateEventsDecodeDocumentPayloads() throws {
        let snapshot = try decode(EcuEditorUIStateEventsSnapshot.self, """
        {
          "latest_sequence": 4,
          "events": [
            {
              "sequence": 1,
              "kind": "dirty_changed",
              "family": "document",
              "title": "Dirty state changed",
              "view_id": 3,
              "source_sequence": 1,
              "dirty": {
                "is_modified": true
              }
            },
            {
              "sequence": 2,
              "kind": "selection_changed",
              "family": "document",
              "title": "Selection changed",
              "view_id": 3,
              "source_sequence": 2,
              "selection": {
                "view_version": 2,
                "primary": {
                  "line": 1,
                  "column": 2,
                  "offset": 7
                },
                "primary_selection_index": 0,
                "selection_count": 2,
                "has_selection": true,
                "selections": [
                  {
                    "start": 4,
                    "end": 7,
                    "anchor": 4,
                    "active": 7
                  },
                  {
                    "start": 9,
                    "end": 9,
                    "anchor": 9,
                    "active": 9
                  }
                ]
              }
            },
            {
              "sequence": 3,
              "kind": "text_changed",
              "family": "document",
              "title": "Text changed",
              "view_id": 3,
              "source_sequence": 1,
              "text": {
                "text_version": 1,
                "char_len": 5,
                "is_modified": true
              }
            },
            {
              "sequence": 4,
              "kind": "viewport_changed",
              "family": "document",
              "title": "Viewport changed",
              "view_id": 3,
              "source_sequence": 3,
              "viewport": {
                "view_version": 3,
                "width": 80,
                "height": 12,
                "scroll_top": 4,
                "sub_row_offset": 32768,
                "overscan_rows": 2,
                "visible_lines": {
                  "start": 4,
                  "end": 16
                },
                "prefetch_lines": {
                  "start": 2,
                  "end": 18
                },
                "total_visual_lines": 40
              }
            }
          ]
        }
        """)

        XCTAssertEqual(snapshot.latestSequence, 4)
        XCTAssertEqual(snapshot.events[0].kindValue, .dirtyChanged)
        XCTAssertEqual(snapshot.events[0].familyKind, .document)
        XCTAssertEqual(snapshot.events[0].dirty?.isModified, true)
        XCTAssertNil(snapshot.events[0].text)
        XCTAssertEqual(snapshot.events[1].kindValue, .selectionChanged)
        XCTAssertEqual(snapshot.events[1].familyKind, .document)
        XCTAssertEqual(snapshot.events[1].selection?.viewVersion, 2)
        XCTAssertEqual(snapshot.events[1].selection?.primary.line, 1)
        XCTAssertEqual(snapshot.events[1].selection?.primary.column, 2)
        XCTAssertEqual(snapshot.events[1].selection?.primary.offset, 7)
        XCTAssertEqual(snapshot.events[1].selection?.primarySelectionIndex, 0)
        XCTAssertEqual(snapshot.events[1].selection?.selectionCount, 2)
        XCTAssertEqual(snapshot.events[1].selection?.hasSelection, true)
        XCTAssertEqual(snapshot.events[1].selection?.selections.first?.start, 4)
        XCTAssertEqual(snapshot.events[1].selection?.selections.first?.end, 7)
        XCTAssertEqual(snapshot.events[1].selection?.selections.first?.anchor, 4)
        XCTAssertEqual(snapshot.events[1].selection?.selections.first?.active, 7)
        XCTAssertNil(snapshot.events[1].dirty)
        XCTAssertNil(snapshot.events[1].text)
        XCTAssertEqual(snapshot.events[2].kindValue, .textChanged)
        XCTAssertEqual(snapshot.events[2].familyKind, .document)
        XCTAssertEqual(snapshot.events[2].text?.textVersion, 1)
        XCTAssertEqual(snapshot.events[2].text?.charLen, 5)
        XCTAssertEqual(snapshot.events[2].text?.isModified, true)
        XCTAssertNil(snapshot.events[2].dirty)
        XCTAssertNil(snapshot.events[2].selection)
        XCTAssertEqual(snapshot.events[3].kindValue, .viewportChanged)
        XCTAssertEqual(snapshot.events[3].familyKind, .document)
        XCTAssertEqual(snapshot.events[3].viewport?.viewVersion, 3)
        XCTAssertEqual(snapshot.events[3].viewport?.width, 80)
        XCTAssertEqual(snapshot.events[3].viewport?.height, 12)
        XCTAssertEqual(snapshot.events[3].viewport?.scrollTop, 4)
        XCTAssertEqual(snapshot.events[3].viewport?.subRowOffset, 32768)
        XCTAssertEqual(snapshot.events[3].viewport?.overscanRows, 2)
        XCTAssertEqual(snapshot.events[3].viewport?.visibleLines.start, 4)
        XCTAssertEqual(snapshot.events[3].viewport?.visibleLines.end, 16)
        XCTAssertEqual(snapshot.events[3].viewport?.prefetchLines.start, 2)
        XCTAssertEqual(snapshot.events[3].viewport?.prefetchLines.end, 18)
        XCTAssertEqual(snapshot.events[3].viewport?.totalVisualLines, 40)
        XCTAssertNil(snapshot.events[3].text)
        XCTAssertNil(snapshot.events[3].selection)
        XCTAssertEqual(EcuEditorUIStateEventKind.textChanged.rawValue, "text_changed")
        XCTAssertEqual(EcuEditorUIStateEventKind.dirtyChanged.rawValue, "dirty_changed")
        XCTAssertEqual(EcuEditorUIStateEventKind.selectionChanged.rawValue, "selection_changed")
        XCTAssertEqual(EcuEditorUIStateEventKind.viewportChanged.rawValue, "viewport_changed")
        XCTAssertEqual(EcuLspEventFamily.document.rawValue, "document")
    }

    func testEditorUIStateEventsDecodeLayoutPayload() throws {
        let snapshot = try decode(EcuEditorUIStateEventsSnapshot.self, """
        {
          "latest_sequence": 1,
          "events": [
            {
              "sequence": 1,
              "kind": "layout_changed",
              "family": "document",
              "title": "Layout changed",
              "view_id": 3,
              "source_sequence": 1,
              "layout": {
                "width_px": 800,
                "height_px": 600,
                "scale": 2.0,
                "font_size": 14.0,
                "line_height_px": 20.0,
                "cell_width_px": 9.0,
                "padding_x_px": 3.0,
                "padding_y_px": 4.0,
                "gutter_width_cells": 5,
                "tab_width_cells": 2,
                "text_vertical_align": "bottom"
              }
            }
          ]
        }
        """)

        let event = try XCTUnwrap(snapshot.events.first)
        XCTAssertEqual(snapshot.latestSequence, 1)
        XCTAssertEqual(event.kindValue, .layoutChanged)
        XCTAssertEqual(event.familyKind, .document)
        XCTAssertEqual(event.layout?.widthPx, 800)
        XCTAssertEqual(event.layout?.heightPx, 600)
        XCTAssertEqual(event.layout?.scale, 2)
        XCTAssertEqual(event.layout?.fontSize, 14)
        XCTAssertEqual(event.layout?.lineHeightPx, 20)
        XCTAssertEqual(event.layout?.cellWidthPx, 9)
        XCTAssertEqual(event.layout?.paddingXPx, 3)
        XCTAssertEqual(event.layout?.paddingYPx, 4)
        XCTAssertEqual(event.layout?.gutterWidthCells, 5)
        XCTAssertEqual(event.layout?.tabWidthCells, 2)
        XCTAssertEqual(event.layout?.textVerticalAlign, "bottom")
        XCTAssertNil(event.viewport)
        XCTAssertEqual(EcuEditorUIStateEventKind.layoutChanged.rawValue, "layout_changed")
    }

    func testMultiDocumentStateEventsExposeTypedKindsAndNestedPayloads() throws {
        let snapshot = try decode(EcuMultiDocumentStateEventsSnapshot.self, """
        {
          "latest_sequence": 1,
          "events": [
            {
              "sequence": 1,
              "tab_id": 7,
              "view_index": 2,
              "view_id": 9,
              "source_sequence": 4,
              "kind": "lsp_request",
              "family": "actions",
              "title": "LSP Code Action: pending",
              "state_event": {
                "sequence": 4,
                "kind": "lsp_request",
                "family": "actions",
                "title": "LSP Code Action: pending",
                "view_id": 9,
                "source_sequence": 8,
                "lsp_request": {
                  "sequence": 8,
                  "family": "actions",
                  "title": "LSP Code Action: pending",
                  "slot": "code_action",
                  "method": "textDocument/codeAction",
                  "view_id": 9,
                  "request_id": 77,
                  "phase": "started",
                  "status": "pending"
                }
              }
            }
          ]
        }
        """)

        let event = try XCTUnwrap(snapshot.events.first)
        XCTAssertEqual(snapshot.latestSequence, 1)
        XCTAssertEqual(event.tabId, 7)
        XCTAssertEqual(event.viewIndex, 2)
        XCTAssertEqual(event.viewId, 9)
        XCTAssertEqual(event.kindValue, .lspRequest)
        XCTAssertEqual(event.familyKind, .actions)
        XCTAssertEqual(event.stateEvent.kindValue, .lspRequest)
        XCTAssertEqual(event.stateEvent.lspRequest?.slotKind, .codeAction)
        XCTAssertEqual(event.stateEvent.lspRequest?.requestId, 77)
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
