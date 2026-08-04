import EditorCoreUIFFI
import Foundation
import XCTest

extension EditorCoreUIFFITests {
    func testExecuteCommandEnvelopeJSONReportsSuccessAndError() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        let success = try ui.executeCommandEnvelope(#"{"kind":"edit","op":"type_char","ch":"!"}"#)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.version, lib.abiVersion)
        XCTAssertNil(success.error)
        if case .object(let value)? = success.value {
            XCTAssertEqual(value["kind"], .string("success"))
        } else {
            XCTFail("expected object command result")
        }

        let failure = try ui.executeCommandEnvelope(#"{"kind":"edit","op":"type_char","ch":"too long"}"#)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.version, lib.abiVersion)
        XCTAssertNil(failure.value)
        XCTAssertEqual(failure.error?.code, "internal")
        XCTAssertEqual(failure.error?.status, .internal)
        XCTAssertTrue(failure.error?.message.contains("ch must be exactly one character") ?? false)
    }

    func testExecuteCommandEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "value": {
            "kind": "future_result",
            "futurePayload": {
              "enabled": true,
              "items": [1, "x"]
            }
          },
          "error": null,
          "version": 2,
          "futureTopLevel": "ignored"
        }
        """
        let success = try JSONTestHelpers.decode(EcuJSONCommandEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.version, 2)
        XCTAssertNil(success.error)
        guard case .object(let successValue)? = success.value else {
            XCTFail("expected future result object")
            return
        }
        XCTAssertEqual(successValue["kind"], .string("future_result"))
        XCTAssertEqual(
            successValue["futurePayload"],
            .object([
                "enabled": .bool(true),
                "items": .array([.number(1), .string("x")]),
            ])
        )

        let failureJSON = """
        {
          "ok": false,
          "value": null,
          "error": {
            "code": "future_error",
            "status": 999,
            "message": "future failure",
            "futureErrorMetadata": { "retryable": false }
          },
          "version": 2,
          "futureTopLevel": true
        }
        """
        let failure = try JSONTestHelpers.decode(EcuJSONCommandEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertNil(failure.value)
        XCTAssertEqual(failure.version, 2)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertNil(failure.error?.status)
        XCTAssertEqual(failure.error?.message, "future failure")
    }

    func testEditorUIDerivedSnapshotEnvelopeReportsSuccessAndError() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "fn main() {}\n", viewportWidthCells: 80)

        let diagnostics = try ui.derivedSnapshotEnvelope(snapshot: .diagnostics)
        XCTAssertTrue(diagnostics.ok)
        XCTAssertEqual(diagnostics.version, lib.abiVersion)
        XCTAssertEqual(diagnostics.snapshot, EcuDerivedSnapshotName.diagnostics.rawValue)
        XCTAssertEqual(diagnostics.statusKind, .success)
        XCTAssertEqual(diagnostics.range, EcuDerivedSnapshotEnvelopeRange(start: 0, end: 0))
        XCTAssertNotNil(diagnostics.value)
        XCTAssertNil(diagnostics.error)

        let styles = try ui.derivedSnapshotEnvelope(snapshot: .styleIntervals, start: 0, end: 4)
        XCTAssertTrue(styles.ok)
        XCTAssertEqual(styles.snapshot, EcuDerivedSnapshotName.styleIntervals.rawValue)
        XCTAssertEqual(styles.statusKind, .success)
        XCTAssertEqual(styles.range, EcuDerivedSnapshotEnvelopeRange(start: 0, end: 4))
        XCTAssertNotNil(styles.value)

        let unknown = try ui.derivedSnapshotEnvelope(snapshotRawValue: "future_snapshot", start: 1, end: 2)
        XCTAssertFalse(unknown.ok)
        XCTAssertEqual(unknown.version, lib.abiVersion)
        XCTAssertEqual(unknown.snapshot, "future_snapshot")
        XCTAssertEqual(unknown.statusKind, .error)
        XCTAssertEqual(unknown.range, EcuDerivedSnapshotEnvelopeRange(start: 1, end: 2))
        XCTAssertEqual(unknown.value, .null)
        XCTAssertEqual(unknown.error?.code, "invalid_argument")
        XCTAssertEqual(unknown.error?.status, .invalidArgument)
        XCTAssertEqual(unknown.error?.message, #"unknown derived snapshot "future_snapshot""#)
    }

    func testEditorUIDerivedSnapshotEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "snapshot": "future_snapshot",
          "range": { "start": 3, "end": 7, "futureRangeField": true },
          "status": "future_status",
          "value": {
            "items": [],
            "future": true
          },
          "error": null,
          "version": 9,
          "futureTopLevel": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuDerivedSnapshotEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.snapshot, "future_snapshot")
        XCTAssertEqual(success.range, EcuDerivedSnapshotEnvelopeRange(start: 3, end: 7))
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future derived snapshot value")
            return
        }
        XCTAssertEqual(value["items"], .array([]))
        XCTAssertEqual(value["future"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "snapshot": "future_snapshot",
          "range": { "start": 0, "end": 0 },
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 654321,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 10
        }
        """
        let failure = try JSONTestHelpers.decode(EcuDerivedSnapshotEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.snapshot, "future_snapshot")
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testLSPStatusEnvelopeReportsSuccess() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        let envelope = try ui.lspStatusEnvelope()
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.version, lib.abiVersion)
        XCTAssertEqual(envelope.statusKind, .success)
        XCTAssertEqual(envelope.value?.availability, .disabled)
        XCTAssertEqual(envelope.value?.state, .disabled)
        XCTAssertNil(envelope.error)
        guard case .object(let rawValue)? = envelope.rawValue else {
            XCTFail("expected raw LSP status object")
            return
        }
        XCTAssertEqual(rawValue["availability"], .string("disabled"))
        XCTAssertEqual(rawValue["state"], .string("disabled"))
    }

    func testLSPStatusEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "status": "future_status",
          "value": {
            "availability": "future_availability",
            "state": "future_state",
            "workspace_folders": [],
            "future": true
          },
          "error": null,
          "version": 13,
          "futureTopLevel": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuLspStatusEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertEqual(success.value?.availability, .unknown("future_availability"))
        XCTAssertEqual(success.value?.state, .unknown("future_state"))
        XCTAssertNil(success.error)
        guard case .object(let rawValue)? = success.rawValue else {
            XCTFail("expected raw future status object")
            return
        }
        XCTAssertEqual(rawValue["future"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 246810,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 14
        }
        """
        let failure = try JSONTestHelpers.decode(EcuLspStatusEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertNil(failure.value)
        XCTAssertEqual(failure.rawValue, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testLSPTakeLastResultEnvelopeReportsEmptyAndError() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        let empty = try ui.lspTakeLastResultEnvelope(slot: .hover)
        XCTAssertTrue(empty.ok)
        XCTAssertEqual(empty.version, lib.abiVersion)
        XCTAssertEqual(empty.slot, "hover")
        XCTAssertEqual(empty.slotKind, .hover)
        XCTAssertEqual(empty.status, "empty")
        XCTAssertEqual(empty.statusKind, .empty)
        XCTAssertFalse(empty.hasResult)
        XCTAssertEqual(empty.value, .null)
        XCTAssertNil(empty.error)

        let failure = try ui.lspTakeLastResultEnvelope(slotRawValue: "future_slot")
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.version, lib.abiVersion)
        XCTAssertEqual(failure.slot, "future_slot")
        XCTAssertEqual(failure.slotKind, .unknown("future_slot"))
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertFalse(failure.hasResult)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "invalid_argument")
        XCTAssertEqual(failure.error?.status, .invalidArgument)
        XCTAssertTrue(failure.error?.message.contains("unknown lsp result slot") ?? false)
    }

    func testLSPTakeLastResultEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "slot": "future_slot",
          "status": "future_status",
          "has_result": true,
          "value": {
            "kind": "future_payload",
            "items": [1, "x"]
          },
          "error": null,
          "version": 3,
          "futureTopLevel": "ignored"
        }
        """
        let success = try JSONTestHelpers.decode(EcuLspResultEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.slotKind, .unknown("future_slot"))
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertTrue(success.hasResult)
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future payload object")
            return
        }
        XCTAssertEqual(value["kind"], .string("future_payload"))
        XCTAssertEqual(value["items"], .array([.number(1), .string("x")]))

        let failureJSON = """
        {
          "ok": false,
          "slot": "hover",
          "status": "error",
          "has_result": false,
          "value": null,
          "error": {
            "code": "future_error",
            "status": 123456,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 4
        }
        """
        let failure = try JSONTestHelpers.decode(EcuLspResultEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.slotKind, .hover)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testEventStreamEnvelopeReportsSnapshotsAndErrors() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        let state = try ui.eventStreamEnvelope(stream: .stateEvents)
        XCTAssertTrue(state.ok)
        XCTAssertEqual(state.version, lib.abiVersion)
        XCTAssertEqual(state.owner, "editor_ui")
        XCTAssertEqual(state.ownerKind, .editorUI)
        XCTAssertEqual(state.stream, "state_events")
        XCTAssertEqual(state.streamKind, .stateEvents)
        XCTAssertEqual(state.statusKind, .success)
        XCTAssertEqual(state.afterSequence, 0)
        XCTAssertNil(state.error)
        guard case .object(let stateValue)? = state.value else {
            XCTFail("expected state event snapshot object")
            return
        }
        XCTAssertEqual(stateValue["latest_sequence"], .number(0))
        XCTAssertEqual(stateValue["events"], .array([]))

        let failure = try ui.eventStreamEnvelope(streamRawValue: "future_events", after: 7)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.version, lib.abiVersion)
        XCTAssertEqual(failure.ownerKind, .editorUI)
        XCTAssertEqual(failure.streamKind, .unknown("future_events"))
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.afterSequence, 7)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "invalid_argument")
        XCTAssertEqual(failure.error?.status, .invalidArgument)
        XCTAssertTrue(failure.error?.message.contains("unknown editor_ui event stream") ?? false)

        let multi = try MultiDocumentEditorUI(library: lib)
        let requestEvents = try multi.eventStreamEnvelope(stream: .lspRequestEvents)
        XCTAssertTrue(requestEvents.ok)
        XCTAssertEqual(requestEvents.version, lib.abiVersion)
        XCTAssertEqual(requestEvents.ownerKind, .multiDocument)
        XCTAssertEqual(requestEvents.streamKind, .lspRequestEvents)
        XCTAssertEqual(requestEvents.statusKind, .success)
        guard case .object(let requestValue)? = requestEvents.value else {
            XCTFail("expected multi-document request event snapshot object")
            return
        }
        XCTAssertEqual(requestValue["latest_sequence"], .number(0))
        XCTAssertEqual(requestValue["events"], .array([]))

        let diagnosticsEvents = try multi.eventStreamEnvelope(stream: .workspaceDiagnosticsEvents)
        XCTAssertTrue(diagnosticsEvents.ok)
        XCTAssertEqual(diagnosticsEvents.ownerKind, .multiDocument)
        XCTAssertEqual(diagnosticsEvents.streamKind, .workspaceDiagnosticsEvents)
        guard case .object(let diagnosticsValue)? = diagnosticsEvents.value else {
            XCTFail("expected workspace diagnostics event snapshot object")
            return
        }
        XCTAssertEqual(diagnosticsValue["latest_sequence"], .number(0))
        XCTAssertEqual(diagnosticsValue["events"], .array([]))

        let workspaceEditEvents = try multi.eventStreamEnvelope(stream: .workspaceEditTransactionEvents)
        XCTAssertTrue(workspaceEditEvents.ok)
        XCTAssertEqual(workspaceEditEvents.ownerKind, .multiDocument)
        XCTAssertEqual(workspaceEditEvents.streamKind, .workspaceEditTransactionEvents)
        guard case .object(let workspaceEditValue)? = workspaceEditEvents.value else {
            XCTFail("expected workspace edit transaction event snapshot object")
            return
        }
        XCTAssertEqual(workspaceEditValue["latest_sequence"], .number(0))
        XCTAssertEqual(workspaceEditValue["events"], .array([]))
    }

    func testEventStreamEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "owner": "future_owner",
          "stream": "future_stream",
          "status": "future_status",
          "after_sequence": 42,
          "value": {
            "latest_sequence": 99,
            "events": [
              { "kind": "future_event", "metadata": true }
            ]
          },
          "error": null,
          "version": 5,
          "futureTopLevel": "ignored"
        }
        """
        let success = try JSONTestHelpers.decode(EcuJSONEventStreamEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.ownerKind, .unknown("future_owner"))
        XCTAssertEqual(success.streamKind, .unknown("future_stream"))
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertEqual(success.afterSequence, 42)
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future event stream value object")
            return
        }
        XCTAssertEqual(value["latest_sequence"], .number(99))

        let failureJSON = """
        {
          "ok": false,
          "owner": "editor_ui",
          "stream": "state_events",
          "status": "error",
          "afterSequence": 8,
          "value": null,
          "error": {
            "code": "future_error",
            "status": 456789,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 6
        }
        """
        let failure = try JSONTestHelpers.decode(EcuJSONEventStreamEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.ownerKind, .editorUI)
        XCTAssertEqual(failure.streamKind, .stateEvents)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.afterSequence, 8)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testMinimapEnvelopeReportsSuccess() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "a\nb\nc", viewportWidthCells: 80)

        let envelope = try ui.minimapEnvelope(startVisualRow: 0, rowCount: 20)
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.statusKind, .success)
        XCTAssertEqual(envelope.startVisualRow, 0)
        XCTAssertEqual(envelope.count, 20)
        XCTAssertEqual(envelope.version, lib.abiVersion)
        XCTAssertNil(envelope.error)
        guard case .object(let value)? = envelope.value else {
            XCTFail("expected minimap value object")
            return
        }
        XCTAssertEqual(value["start_visual_row"], .number(0))
        XCTAssertEqual(value["count"], .number(20))
        XCTAssertEqual(value["actual_line_count"], .number(3))
        guard case .array(let lines)? = value["lines"] else {
            XCTFail("expected minimap lines array")
            return
        }
        XCTAssertFalse(lines.isEmpty)
    }

    func testMinimapEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "status": "future_status",
          "start_visual_row": 3,
          "count": 7,
          "value": {
            "start_visual_row": 3,
            "count": 7,
            "actual_line_count": 1,
            "lines": [],
            "future": true
          },
          "error": null,
          "version": 15,
          "futureTopLevel": true
        }
        """
        let success = try JSONDecoder().decode(EcuMinimapEnvelope.self, from: Data(successJSON.utf8))
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertEqual(success.startVisualRow, 3)
        XCTAssertEqual(success.count, 7)
        XCTAssertEqual(success.version, 15)
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future minimap value object")
            return
        }
        XCTAssertEqual(value["future"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "status": "error",
          "start_visual_row": 4,
          "count": 8,
          "value": null,
          "error": {
            "code": "future_error",
            "status": 135790,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 16
        }
        """
        let failure = try JSONDecoder().decode(EcuMinimapEnvelope.self, from: Data(failureJSON.utf8))
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.startVisualRow, 4)
        XCTAssertEqual(failure.count, 8)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testViewPointPayloadEnvelopeReportsSuccessEmptyAndErrors() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "ab cd\nline2\n", viewportWidthCells: 80)

        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 400, heightPx: 100, scale: 1)

        try ui.lspApplyCodeLensJSON(
            """
            [
              {
                "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } },
                "command": { "title": "Run tests", "command": "test.run", "arguments": [1] }
              }
            ]
            """
        )
        try ui.lspApplyInlayHintsJSON(
            """
            [
              {
                "position": { "line": 0, "character": 1 },
                "label": ": Int",
                "data": { "id": 42 }
              }
            ]
            """
        )
        try ui.lspApplyDocumentLinksJSON(
            """
            [
              {
                "range": { "start": { "line": 0, "character": 3 }, "end": { "line": 0, "character": 4 } },
                "target": "https://example.com"
              }
            ]
            """
        )

        let codeLens = try ui.viewPointPayloadEnvelope(kind: .codeLens, xPx: 5, yPx: 10)
        XCTAssertTrue(codeLens.ok)
        XCTAssertEqual(codeLens.kindValue, EcuViewPointPayloadKind.codeLens)
        XCTAssertEqual(codeLens.statusKind, .success)
        XCTAssertEqual(codeLens.version, lib.abiVersion)
        XCTAssertNil(codeLens.error)
        guard case .object(let codeLensValue)? = codeLens.value,
              case .object(let command)? = codeLensValue["command"]
        else {
            XCTFail("expected code lens payload object")
            return
        }
        XCTAssertEqual(command["title"], .string("Run tests"))
        XCTAssertEqual(command["command"], .string("test.run"))

        let empty = try ui.viewPointPayloadEnvelope(kind: .codeLens, xPx: 300, yPx: 10)
        XCTAssertTrue(empty.ok)
        XCTAssertEqual(empty.kindValue, EcuViewPointPayloadKind.codeLens)
        XCTAssertEqual(empty.statusKind, .empty)
        XCTAssertEqual(empty.value, .null)
        XCTAssertNil(empty.error)

        let inlayPoint = try ui.charOffsetToViewPoint(offset: 1)
        let inlay = try ui.viewPointPayloadEnvelope(kind: .inlayHint, xPx: inlayPoint.xPx + 1, yPx: inlayPoint.yPx + 1)
        XCTAssertTrue(inlay.ok)
        XCTAssertEqual(inlay.kindValue, EcuViewPointPayloadKind.inlayHint)
        XCTAssertEqual(inlay.statusKind, .success)
        guard case .object(let inlayValue)? = inlay.value,
              case .object(let inlayData)? = inlayValue["data"]
        else {
            XCTFail("expected inlay hint payload object")
            return
        }
        XCTAssertEqual(inlayValue["label"], .string(": Int"))
        XCTAssertEqual(inlayData["id"], .number(42))

        let linkPoint = try ui.charOffsetToViewPoint(offset: 3)
        let link = try ui.viewPointPayloadEnvelope(kind: .documentLink, xPx: linkPoint.xPx + 1, yPx: linkPoint.yPx + 1)
        XCTAssertTrue(link.ok)
        XCTAssertEqual(link.kindValue, EcuViewPointPayloadKind.documentLink)
        XCTAssertEqual(link.statusKind, .success)
        guard case .object(let linkValue)? = link.value else {
            XCTFail("expected document link payload object")
            return
        }
        XCTAssertEqual(linkValue["target"], .string("https://example.com"))

        let invalid = try ui.viewPointPayloadEnvelope(kindRawValue: "hover", xPx: 1, yPx: 2)
        XCTAssertFalse(invalid.ok)
        XCTAssertEqual(invalid.kind, "hover")
        XCTAssertNil(invalid.kindValue)
        XCTAssertEqual(invalid.statusKind, .error)
        XCTAssertEqual(invalid.value, .null)
        XCTAssertEqual(invalid.error?.code, "invalid_argument")
        XCTAssertEqual(invalid.error?.status, .invalidArgument)
        XCTAssertEqual(invalid.error?.message, #"unknown view point payload kind "hover""#)
    }

    func testViewPointPayloadEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "kind": "future_payload",
          "status": "future_status",
          "x_px": 1.5,
          "y_px": 2.5,
          "value": { "future": true },
          "error": null,
          "version": 17,
          "futureTopLevel": true
        }
        """
        let success = try JSONDecoder().decode(EcuViewPointPayloadEnvelope.self, from: Data(successJSON.utf8))
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.kind, "future_payload")
        XCTAssertNil(success.kindValue)
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertEqual(success.xPx, 1.5, accuracy: 0.001)
        XCTAssertEqual(success.yPx, 2.5, accuracy: 0.001)
        XCTAssertEqual(success.version, 17)
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future value object")
            return
        }
        XCTAssertEqual(value["future"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "kind": null,
          "status": "error",
          "x_px": 3.5,
          "y_px": 4.5,
          "value": null,
          "error": {
            "code": "future_error",
            "status": 135790,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 18
        }
        """
        let failure = try JSONDecoder().decode(EcuViewPointPayloadEnvelope.self, from: Data(failureJSON.utf8))
        XCTAssertFalse(failure.ok)
        XCTAssertNil(failure.kind)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.xPx, 3.5, accuracy: 0.001)
        XCTAssertEqual(failure.yPx, 4.5, accuracy: 0.001)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertNil(failure.error?.status)
        XCTAssertEqual(failure.error?.message, "future failure")
    }
}
