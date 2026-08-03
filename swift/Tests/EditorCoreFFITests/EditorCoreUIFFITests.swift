import EditorCoreUIFFI
import Foundation
import XCTest

final class EditorCoreUIFFITests: XCTestCase {
    @discardableResult
    private func assertCommandSuccess(
        _ ui: EditorUI,
        _ commandJSON: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> [String: Any] {
        let result = try ui.executeCommandJSON(commandJSON)
        let data = try XCTUnwrap(result.data(using: .utf8), file: file, line: line)
        let obj = try XCTUnwrap(
            JSONSerialization.jsonObject(with: data, options: []) as? [String: Any],
            file: file,
            line: line
        )
        XCTAssertEqual(obj["kind"] as? String, "success", file: file, line: line)
        return obj
    }

    private func waitForAsyncProcessing(_ ui: EditorUI, timeoutSeconds: TimeInterval = 2.0) throws {
        let deadline = Date().addingTimeInterval(timeoutSeconds)
        while true {
            let r = try ui.pollProcessing()
            if r.pending == false {
                return
            }
            if Date() > deadline {
                XCTFail("timeout waiting for async processing")
                return
            }
            Thread.sleep(forTimeInterval: 0.001)
        }
    }

    private func setTestTreeSitterRegistry(_ ui: EditorUI) throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // EditorCoreUIFFITests.swift
            .deletingLastPathComponent() // EditorCoreFFITests
            .deletingLastPathComponent() // Tests
            .deletingLastPathComponent() // swift

        let root = repoRoot.appendingPathComponent(
            "crates/editor-core-treesitter/tests/fixtures/treesitter",
            isDirectory: true
        )

        let registry: [String: Any] = [
            "schema_version": 1,
            "root_dir": root.path,
            "extension_map": ["rs": "rust"],
            "languages": [
                "rust": [
                    "wasm": "rust/language.wasm",
                    "highlights": "rust/highlights.scm",
                    "folds": "rust/folds.scm",
                ],
            ],
        ]

        let data = try JSONSerialization.data(withJSONObject: registry, options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            XCTFail("failed to encode registry json")
            return
        }

        try ui.treeSitterSetRegistryJSON(json)
    }

    func testLoadsLibraryAndVersion() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        XCTAssertGreaterThan(lib.abiVersion, 0)
        XCTAssertFalse((try lib.versionString()).isEmpty)

        let info = try lib.runtimeInfo()
        XCTAssertEqual(info.abiVersion, lib.abiVersion)
        XCTAssertFalse(info.version.isEmpty)
        XCTAssertTrue(info.supports(.jsonCommandDispatch))
        XCTAssertTrue(info.supports(.typedDerivedSnapshots))
        XCTAssertTrue(info.supports(.lspInteractiveRequests))
        XCTAssertTrue(info.supports(.lspStatusSnapshot))
        XCTAssertTrue(info.supports(.workspaceEditApplication))
        XCTAssertTrue(info.supports(.multiDocumentUI))
        XCTAssertTrue(info.supports(.workspaceDiagnosticsStore))
        XCTAssertTrue(info.supports(.workspaceDiagnosticsEvents))
        XCTAssertTrue(info.supports(.lspResultEvents))
        XCTAssertTrue(info.supports(.multiDocumentLSPResultEvents))
        XCTAssertTrue(info.supports(.lspRequestEvents))
        XCTAssertTrue(info.supports(.multiDocumentLSPRequestEvents))
        XCTAssertTrue(info.supports(.lspRequestCancelTimeoutEvents))
        XCTAssertTrue(info.supports(.editorUIStateEvents))
        XCTAssertTrue(info.supports(.multiDocumentStateEvents))
        XCTAssertTrue(info.supports(.workspaceOutlineSnapshot))
        XCTAssertTrue(info.supports(.multiDocumentTabDocumentURI))
        XCTAssertTrue(info.supports(.multiDocumentWorkspaceEditTransaction))
        XCTAssertTrue(info.supports(.multiDocumentWorkspaceEditTransactionEvents))
        XCTAssertTrue(info.supports(.multiDocumentWorkspaceRoots))
        XCTAssertTrue(info.supports(.multiDocumentWorkspaceEditTransactionUndo))
        XCTAssertTrue(info.supports(.multiDocumentTabLanguageID))
        XCTAssertTrue(info.supports(.jsonCommandEnvelope))
        XCTAssertTrue(info.supports(.lspResultEnvelope))
        XCTAssertTrue(info.supports(.eventStreamEnvelope))
        XCTAssertTrue(info.supports(.multiDocumentSpecialEventStreamEnvelope))
        XCTAssertTrue(info.supports(.workspaceEditTransactionEnvelope))
        XCTAssertTrue(info.supports(.workspaceDiagnosticsEnvelope))
        XCTAssertTrue(info.supports(.workspaceOutlineSnapshotEnvelope))
        XCTAssertTrue(info.supports(.multiDocumentSnapshotEnvelope))
        XCTAssertTrue(info.supports(.multiDocumentSearchEnvelope))
        XCTAssertTrue(info.supports(.multiDocumentWorkspaceRootsChangeEnvelope))
        XCTAssertTrue(info.supports(.multiDocumentProjectLSPServersEnvelope))
        XCTAssertTrue(info.supports(.editorUIDerivedSnapshotEnvelope))
        XCTAssertTrue(info.supports(.lspStatusEnvelope))
        XCTAssertTrue(info.supports(.lspWorkspaceEditApplicationEnvelope))

        let runtimeJSON = try JSONTestHelpers.object(try lib.runtimeInfoJSON())
        XCTAssertEqual(runtimeJSON["kind"] as? String, "editor-core-ui-ffi")
        XCTAssertEqual((runtimeJSON["abi_version"] as? NSNumber)?.uint32Value, lib.abiVersion)
        XCTAssertEqual((runtimeJSON["feature_flags"] as? NSNumber)?.uint64Value, lib.featureFlags.rawValue)
        let features = try XCTUnwrap(runtimeJSON["features"] as? [[String: Any]])
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "json_command_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 25
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreUIFFIFeatures.jsonCommandEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "lsp_result_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 26
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreUIFFIFeatures.lspResultEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "event_stream_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 27
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreUIFFIFeatures.eventStreamEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_special_event_stream_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 28
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreUIFFIFeatures.multiDocumentSpecialEventStreamEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "workspace_edit_transaction_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 29
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreUIFFIFeatures.workspaceEditTransactionEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "workspace_diagnostics_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 30
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreUIFFIFeatures.workspaceDiagnosticsEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "workspace_outline_snapshot_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 31
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreUIFFIFeatures.workspaceOutlineSnapshotEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_snapshot_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 32
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreUIFFIFeatures.multiDocumentSnapshotEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_search_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 33
                && (feature["flag"] as? NSNumber)?.uint64Value == EditorCoreUIFFIFeatures.multiDocumentSearchEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_workspace_roots_change_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 34
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.multiDocumentWorkspaceRootsChangeEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_project_lsp_servers_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 35
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.multiDocumentProjectLSPServersEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "editor_ui_derived_snapshot_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 36
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.editorUIDerivedSnapshotEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "lsp_status_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 37
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.lspStatusEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "lsp_workspace_edit_application_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 38
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.lspWorkspaceEditApplicationEnvelope.rawValue
        })
    }

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

    func testMultiDocumentSnapshotEnvelopeReportsSuccess() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let tab = try multi.openTab(text: "alpha\n", viewportWidthCells: 80)
        try multi.setTabTitle("Alpha", tabId: tab)
        try multi.setTabDocumentURI("file:///project/Alpha.swift", tabId: tab)
        try multi.setTabLanguageId("swift", tabId: tab)

        let envelope = try multi.snapshotEnvelope()
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.version, lib.abiVersion)
        XCTAssertEqual(envelope.statusKind, .success)
        XCTAssertNil(envelope.error)
        guard case .object(let value)? = envelope.value,
              case .array(let tabs)? = value["tabs"],
              case .object(let firstTab)? = tabs.first
        else {
            XCTFail("expected multi-document snapshot object")
            return
        }
        XCTAssertEqual(value["active_tab_id"], .number(Double(tab)))
        XCTAssertEqual(value["workspace_roots"], .array([]))
        XCTAssertEqual(firstTab["id"], .number(Double(tab)))
        XCTAssertEqual(firstTab["title"], .string("Alpha"))
        XCTAssertEqual(firstTab["document_uri"], .string("file:///project/Alpha.swift"))
        XCTAssertEqual(firstTab["language_id"], .string("swift"))
        XCTAssertEqual(firstTab["is_active"], .bool(true))
        XCTAssertEqual(firstTab["is_modified"], .bool(false))
        XCTAssertEqual(firstTab["view_count"], .number(1))
    }

    func testMultiDocumentSnapshotEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "status": "future_status",
          "value": {
            "tabs": [],
            "future": true
          },
          "error": null,
          "version": 7,
          "futureTopLevel": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuMultiDocumentSnapshotEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future multi-document snapshot value")
            return
        }
        XCTAssertEqual(value["tabs"], .array([]))
        XCTAssertEqual(value["future"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 777777,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 8
        }
        """
        let failure = try JSONTestHelpers.decode(EcuMultiDocumentSnapshotEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testWorkspaceRootsChangeEnvelopeReportsSuccess() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        let envelope = try multi.setWorkspaceRootsReturningChangeEnvelope([
            "file:///project/Alpha",
            "file:///project/Beta",
        ])
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.version, lib.abiVersion)
        XCTAssertEqual(envelope.statusKind, .success)
        XCTAssertNil(envelope.error)
        guard case .object(let value)? = envelope.value,
              case .array(let added)? = value["added"],
              case .object(let firstAdded)? = added.first
        else {
            XCTFail("expected workspace roots change object")
            return
        }
        XCTAssertEqual(firstAdded["uri"], .string("file:///project/Alpha"))
        XCTAssertEqual(firstAdded["name"], .string("Alpha"))
        XCTAssertEqual(value["removed"], .array([]))

        let replacement = try multi.setWorkspaceRootsReturningChangeEnvelope(["file:///project/Beta"])
        guard case .object(let replacementValue)? = replacement.value,
              case .array(let removed)? = replacementValue["removed"],
              case .object(let firstRemoved)? = removed.first
        else {
            XCTFail("expected workspace roots replacement object")
            return
        }
        XCTAssertEqual(replacementValue["added"], .array([]))
        XCTAssertEqual(firstRemoved["uri"], .string("file:///project/Alpha"))
        XCTAssertEqual(firstRemoved["name"], .string("Alpha"))
    }

    func testWorkspaceRootsChangeEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "status": "future_status",
          "value": {
            "added": [],
            "removed": [],
            "future": true
          },
          "error": null,
          "version": 11,
          "futureTopLevel": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuWorkspaceRootsChangeEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future workspace roots change value")
            return
        }
        XCTAssertEqual(value["added"], .array([]))
        XCTAssertEqual(value["removed"], .array([]))
        XCTAssertEqual(value["future"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 1000001,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 12
        }
        """
        let failure = try JSONTestHelpers.decode(EcuWorkspaceRootsChangeEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testProjectLspServersEnvelopeReportsSuccess() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        try multi.setProjectLspServers([
            EcuProjectLspServerConfig(
                key: " Rust ",
                command: " /bin/rust-analyzer ",
                args: [" ", "--stdio "],
                languageId: " rust ",
                workspaceRoots: ["file:///workspace", " file:///workspace ", "file:///other"],
                autoStart: true
            ),
            EcuProjectLspServerConfig(
                key: "",
                command: "/bin/sourcekit-lsp",
                languageId: "swift",
                autoStart: false
            ),
        ])

        let envelope = try multi.projectLspServersEnvelope()
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.version, lib.abiVersion)
        XCTAssertEqual(envelope.statusKind, .success)
        XCTAssertNil(envelope.error)
        guard case .array(let servers)? = envelope.value,
              case .object(let first)? = servers.first,
              case .object(let second)? = servers.dropFirst().first
        else {
            XCTFail("expected project LSP server config array")
            return
        }
        XCTAssertEqual(first["key"], .string("rust"))
        XCTAssertEqual(first["command"], .string("/bin/rust-analyzer"))
        XCTAssertEqual(first["args"], .array([.string("--stdio")]))
        XCTAssertEqual(first["language_id"], .string("rust"))
        XCTAssertEqual(first["workspace_roots"], .array([.string("file:///other"), .string("file:///workspace")]))
        XCTAssertEqual(first["auto_start"], .bool(true))
        XCTAssertEqual(second["key"], .string("swift"))
        XCTAssertEqual(second["command"], .string("/bin/sourcekit-lsp"))
        XCTAssertEqual(second["args"], .array([]))
        XCTAssertEqual(second["language_id"], .string("swift"))
        XCTAssertEqual(second["workspace_roots"], .array([]))
        XCTAssertEqual(second["auto_start"], .bool(false))
    }

    func testProjectLspServersEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "status": "future_status",
          "value": [
            {
              "key": "future",
              "command": "future-lsp",
              "futureConfigField": true
            }
          ],
          "error": null,
          "version": 13,
          "futureTopLevel": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuProjectLspServersEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertNil(success.error)
        guard case .array(let value)? = success.value,
              case .object(let first)? = value.first
        else {
            XCTFail("expected future project LSP config array")
            return
        }
        XCTAssertEqual(first["key"], .string("future"))
        XCTAssertEqual(first["futureConfigField"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 1000002,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 14
        }
        """
        let failure = try JSONTestHelpers.decode(EcuProjectLspServersEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testMultiDocumentSearchEnvelopeReportsSuccess() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let alpha = try multi.openTab(text: "alpha world", viewportWidthCells: 80)
        let beta = try multi.openTab(text: "beta world", viewportWidthCells: 80)

        let envelope = try multi.searchAllTabsEnvelope(query: "world")
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.version, lib.abiVersion)
        XCTAssertEqual(envelope.statusKind, .success)
        XCTAssertNil(envelope.error)
        guard case .object(let value)? = envelope.value,
              case .array(let results)? = value["results"],
              case .object(let first)? = results.first,
              case .object(let second)? = results.dropFirst().first,
              case .array(let firstMatches)? = first["matches"],
              case .object(let firstMatch)? = firstMatches.first
        else {
            XCTFail("expected multi-document search result object")
            return
        }
        XCTAssertEqual(first["tab_id"], .number(Double(alpha)))
        XCTAssertEqual(firstMatch["start"], .number(6))
        XCTAssertEqual(firstMatch["end"], .number(11))
        XCTAssertEqual(second["tab_id"], .number(Double(beta)))
    }

    func testMultiDocumentSearchEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "status": "future_status",
          "value": {
            "results": [],
            "future": true
          },
          "error": null,
          "version": 9,
          "futureTopLevel": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuMultiDocumentSearchEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future multi-document search value")
            return
        }
        XCTAssertEqual(value["results"], .array([]))
        XCTAssertEqual(value["future"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 999999,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 10
        }
        """
        let failure = try JSONTestHelpers.decode(EcuMultiDocumentSearchEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testWorkspaceOutlineSnapshotEnvelopeReportsSuccess() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let tab = try multi.openTab(text: "struct Beta {}\n", viewportWidthCells: 80)
        try multi.setTabTitle("Beta", tabId: tab)
        try multi.setTabDocumentURI("file:///project/Beta.swift", tabId: tab)
        try multi.applyTabDocumentSymbolsJSON(tabId: tab, resultJSON: """
        [
          {
            "name": "Beta",
            "kind": 23,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 14 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 7 },
              "end": { "line": 0, "character": 11 }
            }
          }
        ]
        """)

        let envelope = try multi.workspaceOutlineSnapshotEnvelope()
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.version, lib.abiVersion)
        XCTAssertEqual(envelope.statusKind, .success)
        XCTAssertNil(envelope.error)
        guard case .object(let value)? = envelope.value,
              case .array(let documents)? = value["documents"],
              case .object(let document)? = documents.first,
              case .array(let symbols)? = document["symbols"],
              case .object(let symbol)? = symbols.first
        else {
            XCTFail("expected workspace outline snapshot object")
            return
        }
        XCTAssertEqual(document["tab_id"], .number(Double(tab)))
        XCTAssertEqual(document["title"], .string("Beta"))
        XCTAssertEqual(document["document_uri"], .string("file:///project/Beta.swift"))
        XCTAssertEqual(document["symbol_count"], .number(1))
        XCTAssertEqual(symbol["name"], .string("Beta"))
    }

    func testWorkspaceOutlineSnapshotEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "status": "future_status",
          "value": {
            "documents": [],
            "future": true
          },
          "error": null,
          "version": 7,
          "futureTopLevel": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuWorkspaceOutlineSnapshotEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future workspace outline value")
            return
        }
        XCTAssertEqual(value["documents"], .array([]))
        XCTAssertEqual(value["future"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 777777,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 8
        }
        """
        let failure = try JSONTestHelpers.decode(EcuWorkspaceOutlineSnapshotEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testWorkspaceEditTransactionEnvelopeReportsSuccessAndError() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let tab = try multi.openTab(text: "hello\n", viewportWidthCells: 80)
        try multi.setTabDocumentURI("file:///project/App.swift", tabId: tab)

        let workspaceEdit = """
        {
          "changes": {
            "file:///project/App.swift": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 5 }
                },
                "newText": "Hello"
              }
            ]
          }
        }
        """

        let preview = try multi.previewWorkspaceEditTransactionEnvelope(workspaceEdit)
        XCTAssertTrue(preview.ok)
        XCTAssertEqual(preview.version, lib.abiVersion)
        XCTAssertEqual(preview.operation, "preview")
        XCTAssertEqual(preview.operationKind, .preview)
        XCTAssertEqual(preview.statusKind, .success)
        XCTAssertNil(preview.error)
        guard case .object(let previewValue)? = preview.value else {
            XCTFail("expected WorkspaceEdit transaction result object")
            return
        }
        XCTAssertEqual(previewValue["mode"], .string("preview"))
        XCTAssertEqual(previewValue["applied"], .bool(false))

        let undo = try multi.undoLastWorkspaceEditTransactionEnvelope()
        XCTAssertTrue(undo.ok)
        XCTAssertEqual(undo.operationKind, .undo)
        guard case .object(let undoValue)? = undo.value else {
            XCTFail("expected WorkspaceEdit undo result object")
            return
        }
        XCTAssertEqual(undoValue["undone"], .bool(false))

        let failure = try multi.workspaceEditTransactionEnvelope(
            operationRawValue: "future_operation",
            workspaceEditJSON: workspaceEdit
        )
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.operationKind, .unknown("future_operation"))
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "invalid_argument")
        XCTAssertEqual(failure.error?.status, .invalidArgument)
        XCTAssertTrue(failure.error?.message.contains("unknown workspace edit transaction operation") ?? false)
    }

    func testWorkspaceEditTransactionEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "operation": "future_operation",
          "status": "future_status",
          "value": {
            "mode": "future_mode",
            "items": [1, "x"]
          },
          "error": null,
          "version": 7,
          "futureTopLevel": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuWorkspaceEditTransactionEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.operationKind, .unknown("future_operation"))
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future WorkspaceEdit transaction value")
            return
        }
        XCTAssertEqual(value["mode"], .string("future_mode"))
        XCTAssertEqual(value["items"], .array([.number(1), .string("x")]))

        let failureJSON = """
        {
          "ok": false,
          "operation": "apply",
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 777777,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 8
        }
        """
        let failure = try JSONTestHelpers.decode(EcuWorkspaceEditTransactionEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.operationKind, .apply)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testWorkspaceDiagnosticsEnvelopeReportsSuccessAndError() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        let diagnosticsJSON = """
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
        """

        let apply = try multi.applyWorkspaceDiagnosticsEnvelope(diagnosticsJSON)
        XCTAssertTrue(apply.ok)
        XCTAssertEqual(apply.version, lib.abiVersion)
        XCTAssertEqual(apply.operation, "apply")
        XCTAssertEqual(apply.operationKind, .apply)
        XCTAssertEqual(apply.statusKind, .success)
        XCTAssertNil(apply.error)
        guard case .object(let applyValue)? = apply.value,
              case .array(let diagnostics)? = applyValue["diagnostics"],
              case .object(let firstDiagnostic)? = diagnostics.first
        else {
            XCTFail("expected workspace diagnostics snapshot object")
            return
        }
        XCTAssertEqual(firstDiagnostic["message"], .string("first problem"))
        XCTAssertEqual(firstDiagnostic["severity_label"], .string("error"))

        let markers = try multi.workspaceDiagnosticMarkersEnvelope()
        XCTAssertTrue(markers.ok)
        XCTAssertEqual(markers.operationKind, .markers)
        guard case .object(let markersValue)? = markers.value,
              case .array(let markerItems)? = markersValue["markers"],
              case .object(let firstMarker)? = markerItems.first
        else {
            XCTFail("expected workspace diagnostic markers object")
            return
        }
        XCTAssertEqual(firstMarker["uri"], .string("file:///project/a.swift"))
        XCTAssertEqual(firstMarker["line"], .number(0))
        XCTAssertEqual(firstMarker["severity_label"], .string("error"))

        let previous = try multi.workspaceDiagnosticsPreviousResultIdsEnvelope()
        XCTAssertTrue(previous.ok)
        XCTAssertEqual(previous.operationKind, .previousResultIds)
        guard case .array(let previousItems)? = previous.value,
              case .object(let previousItem)? = previousItems.first
        else {
            XCTFail("expected workspace diagnostics previous-result-id array")
            return
        }
        XCTAssertEqual(previousItem["uri"], .string("file:///project/a.swift"))
        XCTAssertEqual(previousItem["value"], .string("a-1"))

        let snapshot = try multi.workspaceDiagnosticsSnapshotEnvelope()
        XCTAssertTrue(snapshot.ok)
        XCTAssertEqual(snapshot.operationKind, .snapshot)
        guard case .object(let snapshotValue)? = snapshot.value,
              case .array(let documents)? = snapshotValue["documents"],
              case .object(let firstDocument)? = documents.first
        else {
            XCTFail("expected workspace diagnostics snapshot documents")
            return
        }
        XCTAssertEqual(firstDocument["uri"], .string("file:///project/a.swift"))

        let failure = try multi.workspaceDiagnosticsEnvelope(operationRawValue: "future_operation")
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.operationKind, .unknown("future_operation"))
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "invalid_argument")
        XCTAssertEqual(failure.error?.status, .invalidArgument)
        XCTAssertTrue(failure.error?.message.contains("unknown workspace diagnostics operation") ?? false)
    }

    func testWorkspaceDiagnosticsEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "operation": "future_operation",
          "status": "future_status",
          "value": {
            "documents": [],
            "future": true
          },
          "error": null,
          "version": 7,
          "futureTopLevel": true
        }
        """
        let success = try JSONTestHelpers.decode(EcuWorkspaceDiagnosticsEnvelope.self, from: successJSON)
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.operationKind, .unknown("future_operation"))
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertNil(success.error)
        guard case .object(let value)? = success.value else {
            XCTFail("expected future workspace diagnostics value")
            return
        }
        XCTAssertEqual(value["documents"], .array([]))
        XCTAssertEqual(value["future"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "operation": "apply",
          "status": "error",
          "value": null,
          "error": {
            "code": "future_error",
            "status": 777777,
            "message": "future failure",
            "futureErrorMetadata": true
          },
          "version": 8
        }
        """
        let failure = try JSONTestHelpers.decode(EcuWorkspaceDiagnosticsEnvelope.self, from: failureJSON)
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.operationKind, .apply)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.value, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testEditorUILSPResultEventsWrapperStartsEmpty() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        XCTAssertEqual(try ui.lspResultEventsLatestSequence(), 0)
        let events = try ui.lspResultEvents()
        XCTAssertEqual(events.latestSequence, 0)
        XCTAssertTrue(events.events.isEmpty)

        XCTAssertEqual(try ui.lspRequestEventsLatestSequence(), 0)
        let requestEvents = try ui.lspRequestEvents()
        XCTAssertEqual(requestEvents.latestSequence, 0)
        XCTAssertTrue(requestEvents.events.isEmpty)
        XCTAssertFalse(try ui.lspCancelRequest(999))
        XCTAssertFalse(try ui.lspMarkRequestTimedOut(999))
        XCTAssertThrowsError(
            try ui.lspDidChangeWorkspaceFolders(
                added: [.init(uri: "file:///tmp/added", name: "added")],
                removed: []
            )
        )
        XCTAssertThrowsError(
            try ui.lspDidOpenDocument(
                uri: "file:///tmp/opened.rs",
                languageId: "rust",
                text: "fn opened() {}\n"
            )
        )
        XCTAssertThrowsError(try ui.lspDidChangeDocument(uri: "file:///tmp/opened.rs", text: "changed"))
        XCTAssertThrowsError(try ui.lspDidSaveDocument(uri: "file:///tmp/saved.rs", text: "saved"))
        XCTAssertThrowsError(try ui.lspDidCloseDocument(uri: "file:///tmp/saved.rs"))
        XCTAssertEqual(try ui.lspRequestEventsLatestSequence(), 0)

        XCTAssertEqual(try ui.stateEventsLatestSequence(), 0)
        let stateEvents = try ui.stateEvents()
        XCTAssertEqual(stateEvents.latestSequence, 0)
        XCTAssertTrue(stateEvents.events.isEmpty)
        XCTAssertFalse(try ui.lspShutdown())
        XCTAssertFalse(try ui.lspIsEnabled())
    }

    func testEditorUIStateEventsRecordTextAndDirtyChanges() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "", viewportWidthCells: 80)

        try ui.insertText("x")
        var snapshot = try ui.stateEvents()
        XCTAssertEqual(snapshot.latestSequence, 3)
        XCTAssertEqual(snapshot.events.map(\.kind), ["dirty_changed", "selection_changed", "text_changed"])
        XCTAssertEqual(snapshot.events[0].kindValue, .dirtyChanged)
        XCTAssertEqual(snapshot.events[0].familyKind, .document)
        XCTAssertEqual(snapshot.events[0].dirty?.isModified, true)
        XCTAssertEqual(snapshot.events[1].kindValue, .selectionChanged)
        XCTAssertEqual(snapshot.events[1].familyKind, .document)
        XCTAssertEqual(snapshot.events[1].selection?.primary.offset, 1)
        XCTAssertEqual(snapshot.events[1].selection?.selectionCount, 1)
        XCTAssertEqual(snapshot.events[1].selection?.hasSelection, false)
        XCTAssertEqual(snapshot.events[2].kindValue, .textChanged)
        XCTAssertEqual(snapshot.events[2].text?.textVersion, 1)
        XCTAssertEqual(snapshot.events[2].text?.charLen, 1)
        XCTAssertEqual(snapshot.events[2].text?.isModified, true)
        XCTAssertNil(snapshot.events[2].dirty)
        XCTAssertNil(snapshot.events[2].selection)

        try ui.markSaved()
        snapshot = try ui.stateEvents(after: snapshot.latestSequence)
        XCTAssertEqual(snapshot.latestSequence, 4)
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.events[0].kindValue, .dirtyChanged)
        XCTAssertEqual(snapshot.events[0].dirty?.isModified, false)
    }

    func testEditorUIStateEventsRecordSelectionChanges() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abcd", viewportWidthCells: 80)

        try ui.setSelections(
            [
                EcuSelectionRange(start: 1, end: 3),
                EcuSelectionRange(start: 4, end: 4),
            ],
            primaryIndex: 0
        )

        let snapshot = try ui.stateEvents()
        XCTAssertEqual(snapshot.latestSequence, 1)
        XCTAssertEqual(snapshot.events.count, 1)
        let event = try XCTUnwrap(snapshot.events.first)
        XCTAssertEqual(event.kindValue, .selectionChanged)
        XCTAssertEqual(event.familyKind, .document)
        XCTAssertEqual(event.selection?.primary.offset, 3)
        XCTAssertEqual(event.selection?.primarySelectionIndex, 0)
        XCTAssertEqual(event.selection?.selectionCount, 2)
        XCTAssertEqual(event.selection?.hasSelection, true)
        XCTAssertEqual(event.selection?.selections.first?.start, 1)
        XCTAssertEqual(event.selection?.selections.first?.end, 3)
        XCTAssertEqual(event.selection?.selections.first?.anchor, 1)
        XCTAssertEqual(event.selection?.selections.first?.active, 3)
        XCTAssertNil(event.text)
        XCTAssertNil(event.dirty)
    }

    func testEditorUIStateEventsRecordLayoutChanges() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        try ui.setRenderMetrics(fontSize: 14, lineHeightPx: 20, cellWidthPx: 9, paddingXPx: 3, paddingYPx: 4)
        var snapshot = try ui.stateEvents()
        XCTAssertEqual(snapshot.latestSequence, 1)
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.events[0].kindValue, .layoutChanged)
        XCTAssertEqual(snapshot.events[0].familyKind, .document)
        XCTAssertEqual(snapshot.events[0].layout?.widthPx, 800)
        XCTAssertEqual(snapshot.events[0].layout?.heightPx, 600)
        XCTAssertEqual(snapshot.events[0].layout?.fontSize, 14)
        XCTAssertEqual(snapshot.events[0].layout?.lineHeightPx, 20)
        XCTAssertEqual(snapshot.events[0].layout?.cellWidthPx, 9)
        XCTAssertEqual(snapshot.events[0].layout?.paddingXPx, 3)
        XCTAssertEqual(snapshot.events[0].layout?.paddingYPx, 4)
        XCTAssertEqual(snapshot.events[0].layout?.tabWidthCells, 4)
        XCTAssertEqual(snapshot.events[0].layout?.textVerticalAlign, "center")
        XCTAssertNil(snapshot.events[0].viewport)

        try ui.setTextVerticalAlign(.bottom)
        snapshot = try ui.stateEvents(after: snapshot.latestSequence)
        XCTAssertEqual(snapshot.latestSequence, 2)
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.events[0].kindValue, .layoutChanged)
        XCTAssertEqual(snapshot.events[0].layout?.textVerticalAlign, "bottom")

        try ui.setTabWidth(2)
        snapshot = try ui.stateEvents(after: snapshot.latestSequence)
        XCTAssertEqual(snapshot.latestSequence, 3)
        XCTAssertEqual(snapshot.events.count, 1)
        XCTAssertEqual(snapshot.events[0].kindValue, .layoutChanged)
        XCTAssertEqual(snapshot.events[0].layout?.tabWidthCells, 2)
    }

    func testEditorUIStateEventsRecordViewportChanges() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(
            library: lib,
            initialText: "one\ntwo\nthree\nfour\nfive",
            viewportWidthCells: 80
        )

        try ui.setRenderMetrics(fontSize: 10, lineHeightPx: 10, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        let baseline = try ui.stateEventsLatestSequence()
        try ui.setViewportPx(widthPx: 80, heightPx: 20, scale: 1)

        let resize = try ui.stateEvents(after: baseline)
        XCTAssertEqual(resize.events.map(\.kindValue), [.viewportChanged, .layoutChanged])
        let resizeEvent = try XCTUnwrap(resize.events.first { $0.kindValue == .viewportChanged })
        XCTAssertEqual(resizeEvent.familyKind, .document)
        XCTAssertEqual(resizeEvent.viewport?.width, 8)
        XCTAssertEqual(resizeEvent.viewport?.height, 2)
        XCTAssertEqual(resizeEvent.viewport?.scrollTop, 0)
        XCTAssertEqual(resizeEvent.viewport?.visibleLines.start, 0)
        XCTAssertEqual(resizeEvent.viewport?.visibleLines.end, 2)
        XCTAssertNil(resizeEvent.text)
        XCTAssertNil(resizeEvent.dirty)
        XCTAssertNil(resizeEvent.selection)

        ui.setSmoothScrollState(topVisualRow: 1, subRowOffset: 32768)
        let scrolled = try ui.stateEvents(after: resize.latestSequence)
        XCTAssertEqual(scrolled.events.count, 1)
        XCTAssertEqual(scrolled.events[0].kindValue, .viewportChanged)
        XCTAssertEqual(scrolled.events[0].viewport?.scrollTop, 1)
        XCTAssertEqual(scrolled.events[0].viewport?.subRowOffset, 32768)
        XCTAssertEqual(scrolled.events[0].viewport?.visibleLines.start, 1)
    }

    func testEditorUIStateEventsRecordDerivedStateChangesAndStale() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc\n", viewportWidthCells: 80)

        try ui.lspApplyDiagnosticsJSON("""
        {
          "uri": "file:///tmp/main.rs",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 0, "character": 1 },
                "end": { "line": 0, "character": 2 }
              },
              "severity": 1,
              "message": "unit"
            }
          ],
          "version": 1
        }
        """)

        let changed = try ui.stateEvents()
        XCTAssertEqual(changed.latestSequence, 1)
        XCTAssertEqual(changed.events.count, 1)
        XCTAssertEqual(changed.events[0].kindValue, .derivedStateChanged)
        XCTAssertEqual(changed.events[0].familyKind, .derivedState)
        XCTAssertEqual(changed.events[0].derivedState?.status, "changed")
        XCTAssertEqual(changed.events[0].derivedState?.reason, "processing_edits")
        XCTAssertEqual(changed.events[0].derivedState?.textVersion, 0)
        XCTAssertEqual(changed.events[0].derivedState?.editCount, 2)
        XCTAssertEqual(changed.events[0].derivedState?.families, ["style_intervals", "diagnostics"])
        XCTAssertNil(changed.events[0].text)
        XCTAssertNil(changed.events[0].dirty)

        try ui.insertText("z")
        let stale = try ui.stateEvents(after: changed.latestSequence)
        XCTAssertEqual(stale.events.map(\.kindValue), [
            .dirtyChanged,
            .selectionChanged,
            .textChanged,
            .derivedStateStale,
        ])
        let staleEvent = try XCTUnwrap(stale.events.last)
        XCTAssertEqual(staleEvent.familyKind, .derivedState)
        XCTAssertEqual(staleEvent.derivedState?.status, "stale")
        XCTAssertEqual(staleEvent.derivedState?.reason, "text_changed")
        XCTAssertEqual(staleEvent.derivedState?.textVersion, 1)
        XCTAssertEqual(staleEvent.derivedState?.editCount, 0)
        XCTAssertEqual(staleEvent.derivedState?.families.last, "document_symbols")
    }

    func testMultiDocumentEditorUIWrapperExposesTabsSplitsPreviewAndSearch() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        XCTAssertEqual(try multi.stateEventsLatestSequence(), 0)
        let stateEvents = try multi.stateEvents()
        XCTAssertEqual(stateEvents.latestSequence, 0)
        XCTAssertTrue(stateEvents.events.isEmpty)

        let alpha = try multi.openTab(text: "alpha world", viewportWidthCells: 80)
        let beta = try multi.openTab(text: "beta world", viewportWidthCells: 80)
        XCTAssertNotEqual(alpha, beta)

        try multi.setTabTitle("Beta", tabId: beta)
        try multi.setTabDocumentURI("file:///project/Beta.swift", tabId: beta)
        XCTAssertEqual(try multi.tabDocumentURI(tabId: beta), "file:///project/Beta.swift")
        try multi.setTabLanguageId(" swift ", tabId: beta)
        XCTAssertEqual(try multi.tabLanguageId(tabId: beta), "swift")
        try multi.setWorkspaceRoots([
            "file:///project",
            "file:///project",
            "file:///other",
        ])
        XCTAssertEqual(try multi.snapshot().workspaceRoots, ["file:///project", "file:///other"])
        let rootsChange = try multi.setWorkspaceRootsReturningChange([
            "file:///other",
            "file:///new",
            "file:///new",
        ])
        XCTAssertEqual(
            rootsChange.added,
            [EcuLspWorkspaceFolder(uri: "file:///new", name: "new")]
        )
        XCTAssertEqual(
            rootsChange.removed,
            [EcuLspWorkspaceFolder(uri: "file:///project", name: "project")]
        )
        XCTAssertEqual(try multi.snapshot().workspaceRoots, ["file:///other", "file:///new"])

        try multi.setProjectLspServers([
            EcuProjectLspServerConfig(
                key: " Rust ",
                command: " /bin/rust-analyzer ",
                args: [" ", "--stdio "],
                languageId: " rust ",
                workspaceRoots: ["file:///new", "file:///new", " file:///other "]
            ),
            EcuProjectLspServerConfig(
                key: "",
                command: "/bin/sourcekit-lsp",
                languageId: "swift",
                autoStart: false
            ),
        ])
        let lspServers = try multi.projectLspServers()
        XCTAssertEqual(lspServers.map(\.key), ["rust", "swift"])
        XCTAssertEqual(lspServers[0].command, "/bin/rust-analyzer")
        XCTAssertEqual(lspServers[0].args, ["--stdio"])
        XCTAssertEqual(lspServers[0].languageId, "rust")
        XCTAssertEqual(lspServers[0].workspaceRoots, ["file:///new", "file:///other"])
        XCTAssertFalse(lspServers[1].autoStart)
        XCTAssertEqual(try multi.snapshot().projectLspServers, lspServers)

        try multi.setActiveTab(beta)
        XCTAssertEqual(try multi.activeTabId(), beta)

        XCTAssertTrue(try multi.moveTab(fromIndex: 1, toIndex: 0))
        let movedSnapshot = try multi.snapshot()
        XCTAssertEqual(movedSnapshot.tabs.map(\.id), [beta, alpha])
        XCTAssertEqual(movedSnapshot.tabs.first?.documentURI, "file:///project/Beta.swift")
        XCTAssertEqual(movedSnapshot.tabs.first?.languageId, "swift")
        XCTAssertTrue(try multi.moveTab(fromIndex: 0, toIndex: 1))
        XCTAssertEqual(try multi.snapshot().tabs.map(\.id), [alpha, beta])

        XCTAssertEqual(try multi.splitTab(beta, viewportWidthCells: 80), 1)
        XCTAssertEqual(try multi.viewCount(tabId: beta), 2)
        XCTAssertTrue(try multi.closeView(tabId: beta, viewIndex: 1))
        XCTAssertEqual(try multi.viewCount(tabId: beta), 1)
        XCTAssertEqual(try multi.splitTab(beta, viewportWidthCells: 80), 1)
        XCTAssertEqual(try multi.splitTab(beta, viewportWidthCells: 80), 2)
        XCTAssertTrue(try multi.moveView(tabId: beta, fromIndex: 2, toIndex: 0))
        XCTAssertFalse(try multi.moveView(tabId: beta, fromIndex: 0, toIndex: 0))

        try multi.replaceTabText(tabId: beta, text: "beta mirror", markSaved: false)
        XCTAssertEqual(try multi.tabText(tabId: beta), "beta mirror")
        XCTAssertTrue(try multi.isTabModified(beta))
        try multi.markTabSaved(beta)
        XCTAssertFalse(try multi.isTabModified(beta))
        try multi.replaceTabText(tabId: beta, text: "beta saved mirror", markSaved: true)
        XCTAssertFalse(try multi.isTabModified(beta))

        let preview = try multi.openPreviewTab(text: "preview one", viewportWidthCells: 80)
        let reusedPreview = try multi.openPreviewTab(text: "preview two", viewportWidthCells: 80)
        XCTAssertEqual(reusedPreview, preview)
        XCTAssertTrue(try multi.isPreviewTab(preview))

        try multi.pinTab(preview)
        XCTAssertFalse(try multi.isPreviewTab(preview))

        let results = try multi.searchAllTabs(query: "mirror")
        XCTAssertEqual(results.map(\.tabId), [beta])
        XCTAssertEqual(results.flatMap(\.matches).count, 1)

        let workspaceEdit = """
        {
          "changes": {
            "file:///project/Beta.swift": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 4 }
                },
                "newText": "BETA"
              }
            ],
            "file:///project/Missing.swift": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "missing"
              }
            ]
          }
        }
        """
        let transactionPreview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertEqual(transactionPreview.mode, "preview")
        XCTAssertFalse(transactionPreview.applied)
        XCTAssertEqual(transactionPreview.skippedURIs, ["file:///project/Missing.swift"])
        XCTAssertTrue(transactionPreview.skippedDetails.contains {
            $0.uri == "file:///project/Missing.swift"
                && $0.operation == "text_edit"
                && $0.reason == "file_not_found"
        })
        let betaTransactionDocument = try XCTUnwrap(
            transactionPreview.documents.first { $0.uri == "file:///project/Beta.swift" }
        )
        XCTAssertTrue(betaTransactionDocument.isOpen)
        XCTAssertEqual(betaTransactionDocument.tabId, beta)

        let transactionApply = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertEqual(transactionApply.mode, "apply")
        XCTAssertTrue(transactionApply.applied)
        XCTAssertEqual(transactionApply.appliedURIs, ["file:///project/Beta.swift"])
        XCTAssertEqual(transactionApply.appliedEditCount, 1)
        XCTAssertEqual(transactionApply.appliedResourceOperationCount, 0)

        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 1)
        let transactionEvents = try multi.workspaceEditTransactionEvents()
        XCTAssertEqual(transactionEvents.latestSequence, 1)
        XCTAssertEqual(transactionEvents.events.map(\.operation), ["apply"])
        XCTAssertEqual(transactionEvents.events.first?.result.appliedURIs, ["file:///project/Beta.swift"])

        XCTAssertEqual(try multi.tabText(tabId: beta), "BETA saved mirror")
        try multi.markTabSaved(beta)

        try multi.applyTabDocumentSymbolsJSON(tabId: beta, resultJSON: """
        [
          {
            "name": "Beta",
            "kind": 23,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 16 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 5 },
              "end": { "line": 0, "character": 9 }
            }
          }
        ]
        """)
        let outline = try multi.workspaceOutlineSnapshot()
        XCTAssertEqual(outline.documents.count, 3)
        let betaOutline = try XCTUnwrap(outline.documents.first { $0.tabId == beta })
        XCTAssertEqual(betaOutline.title, "Beta")
        XCTAssertEqual(betaOutline.documentURI, "file:///project/Beta.swift")
        XCTAssertEqual(betaOutline.viewIndex, 0)
        XCTAssertEqual(betaOutline.symbolCount, 1)
        XCTAssertEqual(betaOutline.symbols.map(\.name), ["Beta"])

        let diagnostics = try multi.applyWorkspaceDiagnosticsJSON("""
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
        XCTAssertEqual(diagnostics.diagnostics.map(\.message), ["first problem"])
        XCTAssertEqual(diagnostics.diagnostics.first?.severityLabel, "error")
        XCTAssertEqual(
            try multi.workspaceDiagnosticMarkersSnapshot().markers,
            [
                EcuWorkspaceDiagnosticMarker(
                    uri: "file:///project/a.swift",
                    line: 0,
                    utf16Character: 1,
                    severity: 1,
                    severityLabel: "error"
                ),
            ]
        )

        let previousResultIds = try JSONSerialization.jsonObject(
            with: Data(try multi.workspaceDiagnosticsPreviousResultIdsJSON().utf8),
            options: []
        ) as? [[String: String]]
        XCTAssertEqual(previousResultIds, [["uri": "file:///project/a.swift", "value": "a-1"]])
        XCTAssertEqual(try multi.workspaceDiagnosticsLatestEventSequence(), 1)
        let diagnosticEvents = try multi.workspaceDiagnosticsEvents()
        XCTAssertEqual(diagnosticEvents.latestSequence, 1)
        XCTAssertEqual(diagnosticEvents.events.count, 1)
        XCTAssertEqual(diagnosticEvents.events[0].family, "workspace_diagnostics")
        XCTAssertEqual(diagnosticEvents.events[0].operation, "apply")
        XCTAssertEqual(diagnosticEvents.events[0].documentCount, 1)
        XCTAssertEqual(diagnosticEvents.events[0].diagnosticCount, 1)
        XCTAssertEqual(diagnosticEvents.events[0].markerCount, 1)

        try multi.clearWorkspaceDiagnostics()
        XCTAssertTrue(try multi.workspaceDiagnosticsSnapshot().diagnostics.isEmpty)
        let clearEvents = try multi.workspaceDiagnosticsEvents(after: 1)
        XCTAssertEqual(clearEvents.latestSequence, 2)
        XCTAssertEqual(clearEvents.events.map(\.operation), ["clear"])
        XCTAssertEqual(clearEvents.events[0].diagnosticCount, 0)

        XCTAssertEqual(try multi.lspResultEventsLatestSequence(), 0)
        let lspEvents = try multi.lspResultEvents()
        XCTAssertEqual(lspEvents.latestSequence, 0)
        XCTAssertTrue(lspEvents.events.isEmpty)

        XCTAssertEqual(try multi.lspRequestEventsLatestSequence(), 0)
        let lspRequestEvents = try multi.lspRequestEvents()
        XCTAssertEqual(lspRequestEvents.latestSequence, 0)
        XCTAssertTrue(lspRequestEvents.events.isEmpty)

        let finalSnapshot = try multi.snapshot()
        XCTAssertEqual(finalSnapshot.activeTabId, beta)
        XCTAssertEqual(finalSnapshot.tabs.count, 3)
        let finalBetaTab = try XCTUnwrap(finalSnapshot.tabs.first { $0.id == beta })
        XCTAssertEqual(finalBetaTab.title, "Beta")
        XCTAssertEqual(finalBetaTab.documentURI, "file:///project/Beta.swift")
        XCTAssertEqual(finalBetaTab.viewCount, 3)
        XCTAssertEqual(finalBetaTab.activeViewIndex, 0)
        XCTAssertFalse(finalBetaTab.isModified)
        XCTAssertTrue(finalSnapshot.tabs.contains { $0.id == preview && $0.isPreview == false })

        XCTAssertEqual(try multi.closeTabsToRight(of: beta), 1)
        XCTAssertEqual(try multi.closeOtherTabs(keeping: beta), 1)
        XCTAssertEqual(try multi.snapshot().tabs.map(\.id), [beta])

        XCTAssertTrue(try multi.closeTab(beta))
        XCTAssertNil(try multi.activeTabId())
    }

    func testMultiDocumentEditorUIAtomicWorkspaceEditPreflightSkipsWithoutMutating() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        let app = try multi.openTab(text: "alpha\n", viewportWidthCells: 80)
        let dirty = try multi.openTab(text: "dirty\n", viewportWidthCells: 80)
        try multi.setTabDocumentURI("file:///project/App.swift", tabId: app)
        try multi.setTabDocumentURI("file:///project/Dirty.swift", tabId: dirty)
        try multi.replaceTabText(tabId: dirty, text: "dirty changed\n", markSaved: false)

        let workspaceEdit = """
        {
          "applyMode": "atomic",
          "workspaceEdit": {
            "documentChanges": [
              {
                "textDocument": {
                  "uri": "file:///project/App.swift",
                  "version": null
                },
                "edits": [
                  {
                    "range": {
                      "start": { "line": 0, "character": 0 },
                      "end": { "line": 0, "character": 5 }
                    },
                    "newText": "App"
                  }
                ]
              },
              {
                "kind": "delete",
                "uri": "file:///project/Dirty.swift"
              }
            ]
          }
        }
        """

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertEqual(applied.mode, "apply")
        XCTAssertEqual(applied.applyMode, "atomic")
        XCTAssertFalse(applied.applied)
        XCTAssertEqual(applied.appliedEditCount, 0)
        XCTAssertEqual(applied.appliedResourceOperationCount, 0)
        XCTAssertTrue(applied.appliedURIs.isEmpty)
        XCTAssertTrue(applied.skippedDetails.contains {
            $0.uri == "file:///project/Dirty.swift"
                && $0.operation == "delete"
                && $0.reason == "resource_operation_dirty_target"
        })
        XCTAssertEqual(applied.dirtyDocumentURIs, ["file:///project/Dirty.swift"])
        let dirtyDocument = try XCTUnwrap(applied.documents.first {
            $0.uri == "file:///project/Dirty.swift"
        })
        XCTAssertTrue(dirtyDocument.isDirty)
        let dirtyConflict = try XCTUnwrap(applied.conflicts.first {
            $0.uri == "file:///project/Dirty.swift"
                && $0.operation == "delete"
                && $0.reason == "resource_operation_dirty_target"
        })
        XCTAssertEqual(dirtyConflict.kind, "dirty_document")
        XCTAssertEqual(dirtyConflict.message, "delete targets a modified open tab")
        XCTAssertEqual(try multi.tabText(tabId: app), "alpha\n")
        XCTAssertEqual(try multi.tabText(tabId: dirty), "dirty changed\n")
        XCTAssertTrue(try multi.isTabModified(dirty))
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 1)
        let events = try multi.workspaceEditTransactionEvents()
        XCTAssertEqual(events.events.first?.result.applyMode, "atomic")
        XCTAssertEqual(events.events.first?.result.applied, false)
        XCTAssertEqual(events.events.first?.result.dirtyDocumentURIs, ["file:///project/Dirty.swift"])
    }

    func testMultiDocumentEditorUIAtomicWorkspaceEditPreflightsRemovedTextEditDependency() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        let tab = try multi.openTab(text: "delete me\n", viewportWidthCells: 80)
        try multi.setTabDocumentURI("file:///project/Delete.swift", tabId: tab)

        let workspaceEdit = """
        {
          "applyMode": "atomic",
          "workspaceEdit": {
            "documentChanges": [
              {
                "kind": "delete",
                "uri": "file:///project/Delete.swift"
              },
              {
                "textDocument": {
                  "uri": "file:///project/Delete.swift",
                  "version": null
                },
                "edits": [
                  {
                    "range": {
                      "start": { "line": 0, "character": 0 },
                      "end": { "line": 0, "character": 0 }
                    },
                    "newText": "late "
                  }
                ]
              }
            ]
          }
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertEqual(preview.applyMode, "atomic")
        XCTAssertTrue(preview.skippedDetails.contains {
            $0.uri == "file:///project/Delete.swift"
                && $0.operation == "text_edit"
                && $0.reason == "resource_operation_dependency_removed"
        })

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertEqual(applied.mode, "apply")
        XCTAssertEqual(applied.applyMode, "atomic")
        XCTAssertFalse(applied.applied)
        XCTAssertEqual(applied.appliedEditCount, 0)
        XCTAssertEqual(applied.appliedResourceOperationCount, 0)
        XCTAssertTrue(applied.skippedDetails.contains {
            $0.uri == "file:///project/Delete.swift"
                && $0.operation == "text_edit"
                && $0.reason == "resource_operation_dependency_removed"
        })
        XCTAssertEqual(try multi.tabDocumentURI(tabId: tab), "file:///project/Delete.swift")
        XCTAssertEqual(try multi.tabText(tabId: tab), "delete me\n")
        XCTAssertTrue(try multi.snapshot().tabs.contains { $0.id == tab })
    }

    func testMultiDocumentEditorUIPreviewsOrderedUnsupportedWorkspaceEditDependency() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        let tab = try multi.openTab(text: "old\n", viewportWidthCells: 80)
        try multi.setTabDocumentURI("file:///project/Old.swift", tabId: tab)

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "create",
              "uri": "file:///project/Old.swift"
            },
            {
              "textDocument": {
                "uri": "file:///project/Old.swift",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "later "
                }
              ]
            }
          ]
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(preview.skippedDetails.contains {
            $0.uri == "file:///project/Old.swift"
                && $0.operation == "create"
                && $0.reason == "resource_operation_create_exists"
        })
        XCTAssertTrue(preview.skippedDetails.contains {
            $0.uri == "file:///project/Old.swift"
                && $0.operation == "text_edit"
                && $0.reason == "resource_operation_dependency_unsupported"
        })

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertFalse(applied.applied)
        XCTAssertEqual(applied.appliedEditCount, 0)
        XCTAssertEqual(applied.appliedResourceOperationCount, 0)
        XCTAssertTrue(applied.skippedDetails.contains {
            $0.uri == "file:///project/Old.swift"
                && $0.operation == "text_edit"
                && $0.reason == "resource_operation_dependency_skipped"
        })
        XCTAssertEqual(try multi.tabText(tabId: tab), "old\n")
    }

    func testMultiDocumentEditorUIAtomicWorkspaceEditRollsBackRuntimeTextFailure() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("EditorCoreUIFFITests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("First.swift")
        let badURL = tempDir.appendingPathComponent("Bad.swift")
        try Data([0xff]).write(to: badURL)

        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        let first = try multi.openTab(text: "alpha\n", viewportWidthCells: 80)
        try multi.setWorkspaceRoots([tempDir.absoluteString])
        try multi.setTabDocumentURI(firstURL.absoluteString, tabId: first)

        let workspaceEdit = """
        {
          "applyMode": "atomic",
          "workspaceEdit": {
            "documentChanges": [
              {
                "textDocument": {
                  "uri": "\(firstURL.absoluteString)",
                  "version": null
                },
                "edits": [
                  {
                    "range": {
                      "start": { "line": 0, "character": 0 },
                      "end": { "line": 0, "character": 5 }
                    },
                    "newText": "ALPHA"
                  }
                ]
              },
              {
                "textDocument": {
                  "uri": "\(badURL.absoluteString)",
                  "version": null
                },
                "edits": [
                  {
                    "range": {
                      "start": { "line": 0, "character": 0 },
                      "end": { "line": 0, "character": 0 }
                    },
                    "newText": "invalid"
                  }
                ]
              }
            ]
          }
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertEqual(preview.applyMode, "atomic")
        XCTAssertTrue(preview.skippedDetails.isEmpty)

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertEqual(applied.mode, "apply")
        XCTAssertEqual(applied.applyMode, "atomic")
        XCTAssertFalse(applied.applied)
        XCTAssertTrue(applied.appliedURIs.isEmpty)
        XCTAssertEqual(applied.appliedEditCount, 0)
        XCTAssertEqual(applied.appliedResourceOperationCount, 0)
        XCTAssertTrue(applied.skippedDetails.contains {
            $0.uri == badURL.absoluteString
                && $0.operation == "text_edit"
                && $0.reason == "file_text_edit_read_failed"
        })
        XCTAssertEqual(try multi.tabText(tabId: first), "alpha\n")
        XCTAssertEqual(try Data(contentsOf: badURL), Data([0xff]))
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 1)
        let events = try multi.workspaceEditTransactionEvents()
        XCTAssertEqual(events.events.first?.result.applyMode, "atomic")
        XCTAssertEqual(events.events.first?.result.applied, false)
        XCTAssertEqual(events.events.first?.result.appliedURIs, [])
    }

    func testMultiDocumentEditorUIAppliesOpenTabResourceOperations() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        let tab = try multi.openTab(text: "beta saved mirror", viewportWidthCells: 80)
        try multi.setTabDocumentURI("file:///project/Beta.swift", tabId: tab)

        let resourceEdit = """
        {
          "documentChanges": [
            {
              "kind": "rename",
              "oldUri": "file:///project/Beta.swift",
              "newUri": "file:///project/Renamed.swift"
            },
            {
              "textDocument": {
                "uri": "file:///project/Renamed.swift",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 4 }
                  },
                  "newText": "RENAMED"
                }
              ]
            }
          ]
        }
        """

        let resourceApply = try multi.applyWorkspaceEditTransaction(resourceEdit)
        XCTAssertTrue(resourceApply.applied)
        XCTAssertEqual(resourceApply.appliedEditCount, 1)
        XCTAssertEqual(resourceApply.appliedResourceOperationCount, 1)
        XCTAssertEqual(resourceApply.resourceOperations.count, 1)
        let operation = try XCTUnwrap(resourceApply.resourceOperations.first)
        XCTAssertEqual(operation.kind, "rename")
        XCTAssertNil(operation.uri)
        XCTAssertEqual(operation.oldURI, "file:///project/Beta.swift")
        XCTAssertEqual(operation.newURI, "file:///project/Renamed.swift")
        XCTAssertEqual(operation.affectedURIs, [
            "file:///project/Beta.swift",
            "file:///project/Renamed.swift",
        ])
        XCTAssertTrue(operation.supported)
        XCTAssertTrue(operation.applied)
        XCTAssertEqual(try multi.tabDocumentURI(tabId: tab), "file:///project/Renamed.swift")
        XCTAssertEqual(try multi.tabText(tabId: tab), "RENAMED saved mirror")
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 1)
    }

    func testMultiDocumentEditorUIAppliesOpenTabResourceOperationFilesystemSideEffects() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-open-tab-resource-fs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src", isDirectory: true), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let old = root.appendingPathComponent("src/Old.swift")
        let renamed = root.appendingPathComponent("src/Renamed.swift")
        let deleted = root.appendingPathComponent("src/Deleted.swift")
        let overwritten = root.appendingPathComponent("src/Overwrite.swift")
        try "old\n".write(to: old, atomically: true, encoding: .utf8)
        try "delete\n".write(to: deleted, atomically: true, encoding: .utf8)
        try "existing\n".write(to: overwritten, atomically: true, encoding: .utf8)
        try multi.setWorkspaceRoots([root.absoluteString])

        let oldTab = try multi.openTab(text: "old\n", viewportWidthCells: 80)
        let deleteTab = try multi.openTab(text: "delete\n", viewportWidthCells: 80)
        let overwriteTab = try multi.openTab(text: "existing\n", viewportWidthCells: 80)
        try multi.setTabDocumentURI(old.absoluteString, tabId: oldTab)
        try multi.setTabDocumentURI(deleted.absoluteString, tabId: deleteTab)
        try multi.setTabDocumentURI(overwritten.absoluteString, tabId: overwriteTab)

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "rename",
              "oldUri": "\(old.absoluteString)",
              "newUri": "\(renamed.absoluteString)"
            },
            {
              "textDocument": {
                "uri": "\(renamed.absoluteString)",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "renamed "
                }
              ]
            },
            {
              "kind": "delete",
              "uri": "\(deleted.absoluteString)"
            },
            {
              "kind": "create",
              "uri": "\(overwritten.absoluteString)",
              "options": { "overwrite": true }
            }
          ]
        }
        """

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(applied.applied)
        XCTAssertEqual(applied.appliedEditCount, 1)
        XCTAssertEqual(applied.appliedResourceOperationCount, 3)
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "old\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: deleted.path))
        XCTAssertEqual(try String(contentsOf: overwritten, encoding: .utf8), "")
        XCTAssertEqual(try multi.tabDocumentURI(tabId: oldTab), renamed.absoluteString)
        XCTAssertEqual(try multi.tabText(tabId: oldTab), "renamed old\n")
        XCTAssertFalse(try multi.snapshot().tabs.contains { $0.id == deleteTab })
        XCTAssertEqual(try multi.tabText(tabId: overwriteTab), "")
        XCTAssertFalse(try multi.isTabModified(overwriteTab))
    }

    func testMultiDocumentEditorUIUndoesLastWorkspaceEditTransaction() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-edit-undo-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src", isDirectory: true), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let openURL = root.appendingPathComponent("src/Open.swift")
        let unopenedURL = root.appendingPathComponent("src/Unopened.swift")
        try "unopened\n".write(to: unopenedURL, atomically: true, encoding: .utf8)
        try multi.setWorkspaceRoots([root.absoluteString])

        let tab = try multi.openTab(text: "open\n", viewportWidthCells: 80)
        try multi.setTabDocumentURI(openURL.absoluteString, tabId: tab)

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "textDocument": {
                "uri": "\(openURL.absoluteString)",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 4 }
                  },
                  "newText": "OPEN"
                }
              ]
            },
            {
              "textDocument": {
                "uri": "\(unopenedURL.absoluteString)",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 8 }
                  },
                  "newText": "UNOPENED"
                }
              ]
            }
          ]
        }
        """

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(applied.applied)
        XCTAssertEqual(applied.appliedEditCount, 2)
        XCTAssertEqual(try multi.tabText(tabId: tab), "OPEN\n")
        XCTAssertEqual(try String(contentsOf: unopenedURL, encoding: .utf8), "UNOPENED\n")

        let undone = try multi.undoLastWorkspaceEditTransaction()
        XCTAssertTrue(undone.undone)
        XCTAssertEqual(undone.restoredOpenTabCount, 1)
        XCTAssertGreaterThanOrEqual(undone.restoredFilesystemEntryCount, 1)
        XCTAssertEqual(undone.restoredURIs, [openURL.absoluteString, unopenedURL.absoluteString])
        XCTAssertEqual(try multi.tabText(tabId: tab), "open\n")
        XCTAssertFalse(try multi.isTabModified(tab))
        XCTAssertEqual(try String(contentsOf: unopenedURL, encoding: .utf8), "unopened\n")

        let unavailable = try multi.undoLastWorkspaceEditTransaction()
        XCTAssertFalse(unavailable.undone)
        XCTAssertTrue(unavailable.restoredURIs.isEmpty)
    }

    func testMultiDocumentEditorUIAppliesUnopenedWorkspaceFileTextEdits() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-edit-\(UUID().uuidString)", isDirectory: true)
        let outsideRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-edit-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outsideRoot)
        }

        let target = root.appendingPathComponent("Unopened.swift")
        let outside = outsideRoot.appendingPathComponent("Outside.swift")
        try "alpha\nbeta\n".write(to: target, atomically: true, encoding: .utf8)
        try "outside\n".write(to: outside, atomically: true, encoding: .utf8)

        let targetURI = target.absoluteString
        let outsideURI = outside.absoluteString
        try multi.setWorkspaceRoots([root.absoluteString])

        let workspaceEdit = """
        {
          "changes": {
            "\(targetURI)": [
              {
                "range": {
                  "start": { "line": 1, "character": 0 },
                  "end": { "line": 1, "character": 4 }
                },
                "newText": "BETA"
              }
            ],
            "\(outsideURI)": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "changed "
              }
            ]
          }
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertFalse(preview.applied)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "alpha\nbeta\n")
        let targetDocument = try XCTUnwrap(preview.documents.first { $0.uri == targetURI })
        XCTAssertFalse(targetDocument.isOpen)
        XCTAssertNil(targetDocument.tabId)
        XCTAssertEqual(targetDocument.editCount, 1)
        XCTAssertTrue(preview.skippedDetails.contains {
            $0.uri == outsideURI
                && $0.operation == "text_edit"
                && $0.reason == "document_outside_workspace"
        })

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(applied.applied)
        XCTAssertEqual(applied.appliedURIs, [targetURI])
        XCTAssertEqual(applied.appliedEditCount, 1)
        XCTAssertEqual(applied.appliedResourceOperationCount, 0)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "alpha\nBETA\n")
        XCTAssertEqual(try String(contentsOf: outside, encoding: .utf8), "outside\n")
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 1)
    }

    func testMultiDocumentEditorUIAppliesUnopenedWorkspaceFileResourceOperations() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-resource-\(UUID().uuidString)", isDirectory: true)
        let outsideRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-resource-outside-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outsideRoot, withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: outsideRoot)
        }

        let old = root.appendingPathComponent("src/Old.swift")
        let renamed = root.appendingPathComponent("src/Renamed.swift")
        let created = root.appendingPathComponent("generated/Created.swift")
        let deleted = root.appendingPathComponent("src/Deleted.swift")
        let outside = outsideRoot.appendingPathComponent("Outside.swift")
        try "old\n".write(to: old, atomically: true, encoding: .utf8)
        try "delete me\n".write(to: deleted, atomically: true, encoding: .utf8)

        let oldURI = old.absoluteString
        let renamedURI = renamed.absoluteString
        let createdURI = created.absoluteString
        let deletedURI = deleted.absoluteString
        let outsideURI = outside.absoluteString
        try multi.setWorkspaceRoots([root.absoluteString])

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "create",
              "uri": "\(createdURI)"
            },
            {
              "textDocument": {
                "uri": "\(createdURI)",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "created\\n"
                }
              ]
            },
            {
              "kind": "rename",
              "oldUri": "\(oldURI)",
              "newUri": "\(renamedURI)"
            },
            {
              "kind": "delete",
              "uri": "\(deletedURI)"
            },
            {
              "kind": "create",
              "uri": "\(outsideURI)"
            }
          ]
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertFalse(preview.applied)
        XCTAssertFalse(FileManager.default.fileExists(atPath: created.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: deleted.path))
        XCTAssertTrue(preview.skippedDetails.contains {
            $0.uri == outsideURI
                && $0.operation == "create"
                && $0.reason == "document_outside_workspace"
        })

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(applied.applied)
        XCTAssertEqual(applied.appliedEditCount, 1)
        XCTAssertEqual(applied.appliedResourceOperationCount, 3)
        XCTAssertTrue(applied.appliedURIs.contains(createdURI))
        XCTAssertTrue(applied.appliedURIs.contains(oldURI))
        XCTAssertTrue(applied.appliedURIs.contains(renamedURI))
        XCTAssertTrue(applied.appliedURIs.contains(deletedURI))
        XCTAssertTrue(applied.skippedURIs.contains(outsideURI))
        XCTAssertEqual(try String(contentsOf: created, encoding: .utf8), "created\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try String(contentsOf: renamed, encoding: .utf8), "old\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: deleted.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: outside.path))
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 1)
    }

    func testMultiDocumentEditorUIAppliesWorkspaceEditDocumentChangesInOrder() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-order-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src", isDirectory: true), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let draft = root.appendingPathComponent("src/Draft.swift")
        let finalFile = root.appendingPathComponent("src/Final.swift")
        let draftURI = draft.absoluteString
        let finalURI = finalFile.absoluteString
        try multi.setWorkspaceRoots([root.absoluteString])

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "create",
              "uri": "\(draftURI)"
            },
            {
              "textDocument": {
                "uri": "\(draftURI)",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "draft\\n"
                }
              ]
            },
            {
              "kind": "rename",
              "oldUri": "\(draftURI)",
              "newUri": "\(finalURI)"
            },
            {
              "textDocument": {
                "uri": "\(finalURI)",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "final "
                }
              ]
            }
          ]
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertFalse(preview.applied)
        XCTAssertTrue(preview.skippedURIs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: draft.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: finalFile.path))

        let applied = try multi.applyWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(applied.applied)
        XCTAssertEqual(applied.appliedEditCount, 2)
        XCTAssertEqual(applied.appliedResourceOperationCount, 2)
        XCTAssertTrue(applied.skippedURIs.isEmpty)
        XCTAssertTrue(applied.appliedURIs.contains(draftURI))
        XCTAssertTrue(applied.appliedURIs.contains(finalURI))
        XCTAssertFalse(FileManager.default.fileExists(atPath: draft.path))
        XCTAssertEqual(try String(contentsOf: finalFile, encoding: .utf8), "final draft\n")
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 1)
    }

    func testMultiDocumentEditorUIRollsBackUnopenedResourceOperationsAfterRuntimeFailure() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-rollback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src", isDirectory: true), withIntermediateDirectories: true)
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let old = root.appendingPathComponent("src/Old.swift")
        let target = root.appendingPathComponent("src/Target.swift")
        let created = root.appendingPathComponent("generated/Created.swift")
        let blocker = root.appendingPathComponent("blocker")
        let blockedChild = root.appendingPathComponent("blocker/Child.swift")
        try "old\n".write(to: old, atomically: true, encoding: .utf8)
        try "target\n".write(to: target, atomically: true, encoding: .utf8)
        try "blocker\n".write(to: blocker, atomically: true, encoding: .utf8)
        try multi.setWorkspaceRoots([root.absoluteString])

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "create",
              "uri": "\(created.absoluteString)"
            },
            {
              "kind": "rename",
              "oldUri": "\(old.absoluteString)",
              "newUri": "\(target.absoluteString)",
              "options": { "overwrite": true }
            },
            {
              "kind": "create",
              "uri": "\(blockedChild.absoluteString)"
            }
          ]
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(preview.skippedURIs.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: created.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "target\n")

        XCTAssertThrowsError(try multi.applyWorkspaceEditTransaction(workspaceEdit))
        XCTAssertFalse(FileManager.default.fileExists(atPath: created.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("generated").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try String(contentsOf: old, encoding: .utf8), "old\n")
        XCTAssertTrue(FileManager.default.fileExists(atPath: target.path))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "target\n")
        XCTAssertEqual(try String(contentsOf: blocker, encoding: .utf8), "blocker\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: blockedChild.path))
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 0)
    }

    func testMultiDocumentEditorUIRollsBackUnopenedTextEditsAfterRuntimeFailure() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-workspace-text-rollback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let target = root.appendingPathComponent("src/Target.swift")
        let blocker = root.appendingPathComponent("blocker")
        let blockedChild = root.appendingPathComponent("blocker/Child.swift")
        try "alpha\nbeta\n".write(to: target, atomically: true, encoding: .utf8)
        try "blocker\n".write(to: blocker, atomically: true, encoding: .utf8)
        try multi.setWorkspaceRoots([root.absoluteString])

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "textDocument": {
                "uri": "\(target.absoluteString)",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 1, "character": 0 },
                    "end": { "line": 1, "character": 4 }
                  },
                  "newText": "BETA"
                }
              ]
            },
            {
              "kind": "create",
              "uri": "\(blockedChild.absoluteString)"
            }
          ]
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(preview.skippedURIs.isEmpty)
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "alpha\nbeta\n")

        XCTAssertThrowsError(try multi.applyWorkspaceEditTransaction(workspaceEdit))
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "alpha\nbeta\n")
        XCTAssertEqual(try String(contentsOf: blocker, encoding: .utf8), "blocker\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: blockedChild.path))
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 0)
    }

    func testMultiDocumentEditorUIRollsBackOpenTabsAfterRuntimeFailure() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("editor-core-ui-swift-open-tab-rollback-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("src", isDirectory: true),
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: root)
        }

        let old = root.appendingPathComponent("src/Old.swift")
        let renamed = root.appendingPathComponent("src/Renamed.swift")
        let deleted = root.appendingPathComponent("src/Delete.swift")
        let overwritten = root.appendingPathComponent("src/Overwrite.swift")
        let blocker = root.appendingPathComponent("blocker")
        let blockedChild = root.appendingPathComponent("blocker/Child.swift")
        try "old\n".write(to: old, atomically: true, encoding: .utf8)
        try "delete\n".write(to: deleted, atomically: true, encoding: .utf8)
        try "existing\n".write(to: overwritten, atomically: true, encoding: .utf8)
        try "blocker\n".write(to: blocker, atomically: true, encoding: .utf8)
        try multi.setWorkspaceRoots([root.absoluteString])

        let oldTab = try multi.openTab(text: "old\n", viewportWidthCells: 80)
        let deleteTab = try multi.openTab(text: "delete\n", viewportWidthCells: 80)
        let overwriteTab = try multi.openTab(text: "existing\n", viewportWidthCells: 80)
        try multi.setTabDocumentURI(old.absoluteString, tabId: oldTab)
        try multi.setTabDocumentURI(deleted.absoluteString, tabId: deleteTab)
        try multi.setTabDocumentURI(overwritten.absoluteString, tabId: overwriteTab)
        try multi.setActiveTab(deleteTab)

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "textDocument": {
                "uri": "\(old.absoluteString)",
                "version": null
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "edited "
                }
              ]
            },
            {
              "kind": "rename",
              "oldUri": "\(old.absoluteString)",
              "newUri": "\(renamed.absoluteString)"
            },
            {
              "kind": "delete",
              "uri": "\(deleted.absoluteString)"
            },
            {
              "kind": "create",
              "uri": "\(overwritten.absoluteString)",
              "options": { "overwrite": true }
            },
            {
              "kind": "create",
              "uri": "\(blockedChild.absoluteString)"
            }
          ]
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(workspaceEdit)
        XCTAssertTrue(preview.skippedURIs.isEmpty)
        XCTAssertEqual(try multi.tabText(tabId: oldTab), "old\n")
        XCTAssertEqual(try multi.tabDocumentURI(tabId: oldTab), old.absoluteString)
        XCTAssertTrue(try multi.snapshot().tabs.contains { $0.id == deleteTab })

        XCTAssertThrowsError(try multi.applyWorkspaceEditTransaction(workspaceEdit)) { error in
            XCTAssertTrue(String(describing: error).contains("open tab state was rolled back"))
        }
        XCTAssertEqual(try multi.tabText(tabId: oldTab), "old\n")
        XCTAssertFalse(try multi.isTabModified(oldTab))
        XCTAssertEqual(try multi.tabDocumentURI(tabId: oldTab), old.absoluteString)
        XCTAssertTrue(try multi.snapshot().tabs.contains { $0.id == deleteTab })
        XCTAssertEqual(try multi.tabText(tabId: deleteTab), "delete\n")
        XCTAssertEqual(try multi.tabDocumentURI(tabId: deleteTab), deleted.absoluteString)
        XCTAssertTrue(try multi.snapshot().tabs.contains { $0.id == overwriteTab })
        XCTAssertEqual(try multi.tabText(tabId: overwriteTab), "existing\n")
        XCTAssertFalse(try multi.isTabModified(overwriteTab))
        XCTAssertEqual(try multi.tabDocumentURI(tabId: overwriteTab), overwritten.absoluteString)
        XCTAssertEqual(try multi.activeTabId(), deleteTab)
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: renamed.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: deleted.path))
        XCTAssertEqual(try String(contentsOf: overwritten, encoding: .utf8), "existing\n")
        XCTAssertEqual(try String(contentsOf: blocker, encoding: .utf8), "blocker\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: blockedChild.path))
        XCTAssertEqual(try multi.workspaceEditTransactionEventsLatestSequence(), 0)
    }

    func testMultiDocumentEditorUIReportsWorkspaceEditVersionMismatch() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let multi = try MultiDocumentEditorUI(library: lib)

        let tab = try multi.openTab(text: "versioned", viewportWidthCells: 80)
        try multi.setTabDocumentURI("file:///project/Versioned.swift", tabId: tab)

        let edit = """
        {
          "documentChanges": [
            {
              "textDocument": {
                "uri": "file:///project/Versioned.swift",
                "version": 1
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "stale "
                }
              ]
            }
          ]
        }
        """

        let preview = try multi.previewWorkspaceEditTransaction(edit)
        XCTAssertEqual(preview.skippedURIs, ["file:///project/Versioned.swift"])
        let document = try XCTUnwrap(preview.documents.first {
            $0.uri == "file:///project/Versioned.swift"
        })
        XCTAssertEqual(document.expectedVersion, 1)
        XCTAssertEqual(document.actualVersion, 0)
        XCTAssertTrue(document.versionMismatch)
        XCTAssertTrue(preview.skippedDetails.contains {
            $0.uri == "file:///project/Versioned.swift"
                && $0.operation == "text_edit"
                && $0.reason == "version_mismatch"
        })

        let applied = try multi.applyWorkspaceEditTransaction(edit)
        XCTAssertFalse(applied.applied)
        XCTAssertEqual(applied.appliedEditCount, 0)
        XCTAssertEqual(try multi.tabText(tabId: tab), "versioned")
    }

    func testParagraphSelectionAPIs() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "aa\nbb\n\ncc\ndd", viewportWidthCells: 80)

        try ui.selectParagraph(atCharOffset: 0)
        let p1 = try ui.selectionOffsets()
        XCTAssertEqual(p1.start, 0)
        XCTAssertEqual(p1.end, 6) // "aa\nbb\n"

        try ui.selectParagraph(atCharOffset: 6)
        let blank = try ui.selectionOffsets()
        XCTAssertEqual(blank.start, 6)
        XCTAssertEqual(blank.end, 7) // the blank line's newline

        try ui.selectParagraph(atCharOffset: 8)
        let p2 = try ui.selectionOffsets()
        XCTAssertEqual(p2.start, 7)
        XCTAssertEqual(p2.end, 12) // "cc\ndd"

        // Union selection: from first paragraph into second paragraph.
        try ui.setParagraphSelection(anchorOffset: 0, activeOffset: 8)
        let u = try ui.selectionOffsets()
        XCTAssertEqual(u.start, 0)
        XCTAssertEqual(u.end, 12)
    }

    func testLineSelectionOffsetsAPI() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "aa\nbb\n\ncc\ndd", viewportWidthCells: 80)

        // Anchor in line 0, drag into line 3 (inside "cc").
        try ui.setLineSelection(anchorOffset: 0, activeOffset: 8)
        let a = try ui.selectionOffsets()
        XCTAssertEqual(a.start, 0)
        XCTAssertEqual(a.end, 10) // "aa\nbb\n\ncc\n"

        // Reverse direction should produce the same range.
        try ui.setLineSelection(anchorOffset: 8, activeOffset: 0)
        let b = try ui.selectionOffsets()
        XCTAssertEqual(b.start, 0)
        XCTAssertEqual(b.end, 10)

        // Last line has no trailing newline.
        try ui.setLineSelection(anchorOffset: 10, activeOffset: 11)
        let last = try ui.selectionOffsets()
        XCTAssertEqual(last.start, 10)
        XCTAssertEqual(last.end, 12)
    }

    func testExpandSelectionByWordAPI() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "one two three", viewportWidthCells: 80)

        try ui.setSelections([EcuSelectionRange(start: 4, end: 4)], primaryIndex: 0)
        try ui.expandSelectionBy(unit: .word, count: 2, direction: .forward)
        let s1 = try ui.selectionOffsets()
        XCTAssertEqual(s1.start, 4)
        XCTAssertEqual(s1.end, 13)

        // Expand-only: changing direction extends the other end without shrinking.
        try ui.expandSelectionBy(unit: .word, count: 1, direction: .backward)
        let s2 = try ui.selectionOffsets()
        XCTAssertEqual(s2.start, 0)
        XCTAssertEqual(s2.end, 13)
    }

    func testWordBoundaryConfigAffectsSelectWord() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "foo-bar", viewportWidthCells: 80)

        try ui.setSelections([EcuSelectionRange(start: 1, end: 1)], primaryIndex: 0)
        try ui.selectWord()
        let s1 = try ui.selectionOffsets()
        XCTAssertEqual(s1.start, 0)
        XCTAssertEqual(s1.end, 3)

        // Make '-' a word char by not including it in the boundary set.
        try ui.setWordBoundaryAsciiBoundaryChars(".")
        try ui.setSelections([EcuSelectionRange(start: 1, end: 1)], primaryIndex: 0)
        try ui.selectWord()
        let s2 = try ui.selectionOffsets()
        XCTAssertEqual(s2.start, 0)
        XCTAssertEqual(s2.end, 7)

        // Reset defaults: '-' becomes a boundary again.
        try ui.resetWordBoundaryDefaults()
        try ui.setSelections([EcuSelectionRange(start: 1, end: 1)], primaryIndex: 0)
        try ui.selectWord()
        let s3 = try ui.selectionOffsets()
        XCTAssertEqual(s3.start, 0)
        XCTAssertEqual(s3.end, 3)
    }

    func testInsertTabDefaultSpacesModeInsertsToNextStop() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        // Caret at end of "abc" (col=3, tab_width=4) => inserts 1 space.
        try ui.setSelections([EcuSelectionRange(start: 3, end: 3)], primaryIndex: 0)
        try ui.insertTab()
        XCTAssertEqual(try ui.text(), "abc ")
    }

    func testInsertTabRespectsTabWidthSettingInSpacesMode() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "a", viewportWidthCells: 80)

        try ui.setTabWidth(2)
        try ui.setSelections([EcuSelectionRange(start: 1, end: 1)], primaryIndex: 0)
        try ui.insertTab()
        XCTAssertEqual(try ui.text(), "a ")
    }

    func testInsertTabRespectsTabKeyBehaviorTabMode() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "", viewportWidthCells: 80)

        try ui.setTabKeyBehavior(.tab)
        try ui.insertTab()
        XCTAssertEqual(try ui.text(), "\t")
    }

    func testExecuteCommandJSONExposesCoreLineCommands() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()

        do {
            let ui = try EditorUI(library: lib, initialText: "a\nb\n", viewportWidthCells: 80)
            try assertCommandSuccess(ui, #"{"kind":"cursor","op":"move_to","line":0,"column":0}"#)
            try assertCommandSuccess(ui, #"{"kind":"edit","op":"duplicate_lines"}"#)
            XCTAssertEqual(try ui.text(), "a\na\nb\n")

            try assertCommandSuccess(ui, #"{"kind":"cursor","op":"move_to","line":1,"column":0}"#)
            try assertCommandSuccess(ui, #"{"kind":"edit","op":"delete_lines"}"#)
            XCTAssertEqual(try ui.text(), "a\nb\n")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "a\nb\nc\n", viewportWidthCells: 80)
            try assertCommandSuccess(ui, #"{"kind":"cursor","op":"move_to","line":1,"column":0}"#)
            try assertCommandSuccess(ui, #"{"kind":"edit","op":"move_lines_up"}"#)
            XCTAssertEqual(try ui.text(), "b\na\nc\n")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "a\nb\nc\n", viewportWidthCells: 80)
            try assertCommandSuccess(ui, #"{"kind":"cursor","op":"move_to","line":1,"column":0}"#)
            try assertCommandSuccess(ui, #"{"kind":"edit","op":"move_lines_down"}"#)
            XCTAssertEqual(try ui.text(), "a\nc\nb\n")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "a\nb\n", viewportWidthCells: 80)
            try assertCommandSuccess(ui, #"{"kind":"cursor","op":"move_to","line":0,"column":0}"#)
            try assertCommandSuccess(ui, #"{"kind":"edit","op":"join_lines"}"#)
            XCTAssertEqual(try ui.text(), "a b\n")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "ab\n", viewportWidthCells: 80)
            try assertCommandSuccess(ui, #"{"kind":"cursor","op":"move_to","line":0,"column":1}"#)
            try assertCommandSuccess(ui, #"{"kind":"edit","op":"split_line"}"#)
            XCTAssertEqual(try ui.text(), "a\nb\n")
        }
    }

    func testExecuteCommandJSONExposesCommentTextEditAndUndoGroupingCommands() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "let a = 1\n", viewportWidthCells: 80)

        try assertCommandSuccess(ui, #"{"kind":"cursor","op":"move_to","line":0,"column":0}"#)
        try assertCommandSuccess(ui, #"{"kind":"edit","op":"toggle_comment","config":{"line":"//"}}"#)
        XCTAssertEqual(try ui.text(), "// let a = 1\n")

        try assertCommandSuccess(ui, #"{"kind":"edit","op":"toggle_comment","config":{"line":"//"}}"#)
        XCTAssertEqual(try ui.text(), "let a = 1\n")

        try assertCommandSuccess(
            ui,
            #"{"kind":"edit","op":"apply_text_edits","edits":[{"start":0,"end":3,"text":"var"},{"start":8,"end":9,"text":"2"}]}"#
        )
        XCTAssertEqual(try ui.text(), "var a = 2\n")

        try assertCommandSuccess(ui, #"{"kind":"edit","op":"end_undo_group"}"#)
        try ui.undo()
        XCTAssertEqual(try ui.text(), "let a = 1\n")
    }

    func testExecuteCommandJSONExposesWrapAndFoldCommands() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abcdef\nsecond\nthird\n", viewportWidthCells: 80)

        try assertCommandSuccess(ui, #"{"kind":"view","op":"set_viewport_width","width":4}"#)
        try assertCommandSuccess(ui, #"{"kind":"view","op":"set_wrap_mode","mode":"char"}"#)
        try assertCommandSuccess(ui, #"{"kind":"view","op":"set_wrap_indent","indent":{"kind":"fixed_cells","cells":2}}"#)

        let viewportJSON = try ui.executeCommandJSON(#"{"kind":"view","op":"get_viewport","start_row":0,"count":10}"#)
        let data = try XCTUnwrap(viewportJSON.data(using: .utf8))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data, options: []) as? [String: Any])
        XCTAssertEqual(obj["kind"] as? String, "viewport")
        let viewport = try XCTUnwrap(obj["viewport"] as? [String: Any])
        let lines = try XCTUnwrap(viewport["lines"] as? [[String: Any]])
        XCTAssertTrue(lines.contains { ($0["is_wrapped_part"] as? Bool) == true && ($0["segment_x_start_cells"] as? Int) == 2 })

        try assertCommandSuccess(ui, #"{"kind":"style","op":"fold","start_line":0,"end_line":2}"#)
        let foldedJSON = try ui.executeCommandJSON(#"{"kind":"view","op":"get_viewport","start_row":0,"count":10}"#)
        let foldedData = try XCTUnwrap(foldedJSON.data(using: .utf8))
        let foldedObj = try XCTUnwrap(JSONSerialization.jsonObject(with: foldedData, options: []) as? [String: Any])
        let foldedViewport = try XCTUnwrap(foldedObj["viewport"] as? [String: Any])
        let foldedLines = try XCTUnwrap(foldedViewport["lines"] as? [[String: Any]])
        XCTAssertTrue(foldedLines.contains { ($0["is_fold_placeholder_appended"] as? Bool) == true })

        try assertCommandSuccess(ui, #"{"kind":"style","op":"unfold_all"}"#)
        let unfoldedJSON = try ui.executeCommandJSON(#"{"kind":"view","op":"get_viewport","start_row":0,"count":10}"#)
        let unfoldedData = try XCTUnwrap(unfoldedJSON.data(using: .utf8))
        let unfoldedObj = try XCTUnwrap(JSONSerialization.jsonObject(with: unfoldedData, options: []) as? [String: Any])
        let unfoldedViewport = try XCTUnwrap(unfoldedObj["viewport"] as? [String: Any])
        let unfoldedLines = try XCTUnwrap(unfoldedViewport["lines"] as? [[String: Any]])
        XCTAssertFalse(unfoldedLines.contains { ($0["is_fold_placeholder_appended"] as? Bool) == true })
    }

    func testExecuteCommandJSONExposesSnippetAndAutoPairsCommands() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()

        do {
            let ui = try EditorUI(library: lib, initialText: "", viewportWidthCells: 80)
            try assertCommandSuccess(
                ui,
                #"{"kind":"view","op":"set_auto_pairs_config","config":{"enabled":true,"pairs":[{"open":"<","close":">"}],"wrap_selection":true,"skip_over_closing":true,"delete_pair":true}}"#
            )
            try assertCommandSuccess(ui, #"{"kind":"edit","op":"type_char","ch":"<"}"#)
            XCTAssertEqual(try ui.text(), "<>")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "", viewportWidthCells: 80)
            try assertCommandSuccess(
                ui,
                #"{"kind":"edit","op":"apply_snippet","start":0,"end":0,"snippet":"println!(${1:msg})$0","additional_edits":[]}"#
            )
            XCTAssertEqual(try ui.text(), "println!(msg)")
            XCTAssertTrue(try ui.hasActiveSnippetSession())

            try assertCommandSuccess(ui, #"{"kind":"cursor","op":"snippet_next_placeholder"}"#)
            XCTAssertFalse(try ui.hasActiveSnippetSession())
        }
    }

    func testTypedCommandConvenienceAPIsCoverCoreEditingCommands() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()

        do {
            let ui = try EditorUI(library: lib, initialText: "a\nb\n", viewportWidthCells: 80)
            try ui.moveTo(line: 0, column: 0)
            try ui.duplicateLines()
            XCTAssertEqual(try ui.text(), "a\na\nb\n")

            try ui.moveTo(line: 1, column: 0)
            try ui.deleteLines()
            XCTAssertEqual(try ui.text(), "a\nb\n")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "a\nb\nc\n", viewportWidthCells: 80)
            try ui.moveTo(line: 1, column: 0)
            try ui.moveLinesUp()
            XCTAssertEqual(try ui.text(), "b\na\nc\n")

            try ui.moveTo(line: 0, column: 0)
            try ui.moveLinesDown()
            XCTAssertEqual(try ui.text(), "a\nb\nc\n")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "a\nb\n", viewportWidthCells: 80)
            try ui.moveTo(line: 0, column: 0)
            try ui.joinLines()
            XCTAssertEqual(try ui.text(), "a b\n")

            try ui.moveTo(line: 0, column: 1)
            try ui.splitLine()
            XCTAssertEqual(try ui.text(), "a\n b\n")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "let a = 1\n", viewportWidthCells: 80)
            try ui.moveTo(line: 0, column: 0)
            try ui.toggleComment(EcuCommentConfig(line: "//"))
            XCTAssertEqual(try ui.text(), "// let a = 1\n")

            try ui.toggleComment(EcuCommentConfig(line: "//"))
            XCTAssertEqual(try ui.text(), "let a = 1\n")

            try ui.applyTextEdits(
                [
                    EcuTextEdit(start: 0, end: 3, text: "var"),
                    EcuTextEdit(start: 8, end: 9, text: "2"),
                ]
            )
            XCTAssertEqual(try ui.text(), "var a = 2\n")

            try ui.endUndoGroup()
            try ui.undo()
            XCTAssertEqual(try ui.text(), "let a = 1\n")
        }
    }

    func testTypedCommandConvenienceAPIsCoverConfigSnippetAndFoldCommands() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()

        do {
            let ui = try EditorUI(library: lib, initialText: "abcdef\nsecond\nthird\n", viewportWidthCells: 80)
            try ui.setViewportWidthCells(4)
            try ui.setWrapMode(.char)
            try ui.setWrapIndent(.fixedCells(2))

            let viewportJSON = try ui.viewportJSON(startRow: 0, count: 10)
            let data = try XCTUnwrap(viewportJSON.data(using: .utf8))
            let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data, options: []) as? [String: Any])
            XCTAssertEqual(obj["kind"] as? String, "viewport")
            let viewport = try XCTUnwrap(obj["viewport"] as? [String: Any])
            let lines = try XCTUnwrap(viewport["lines"] as? [[String: Any]])
            XCTAssertTrue(lines.contains { ($0["is_wrapped_part"] as? Bool) == true && ($0["segment_x_start_cells"] as? Int) == 2 })

            try ui.fold(startLine: 0, endLine: 2)
            let foldedJSON = try ui.viewportJSON(startRow: 0, count: 10)
            let foldedData = try XCTUnwrap(foldedJSON.data(using: .utf8))
            let foldedObj = try XCTUnwrap(JSONSerialization.jsonObject(with: foldedData, options: []) as? [String: Any])
            let foldedViewport = try XCTUnwrap(foldedObj["viewport"] as? [String: Any])
            let foldedLines = try XCTUnwrap(foldedViewport["lines"] as? [[String: Any]])
            XCTAssertTrue(foldedLines.contains { ($0["is_fold_placeholder_appended"] as? Bool) == true })

            try ui.unfoldAll()
            let unfoldedJSON = try ui.viewportJSON(startRow: 0, count: 10)
            let unfoldedData = try XCTUnwrap(unfoldedJSON.data(using: .utf8))
            let unfoldedObj = try XCTUnwrap(JSONSerialization.jsonObject(with: unfoldedData, options: []) as? [String: Any])
            let unfoldedViewport = try XCTUnwrap(unfoldedObj["viewport"] as? [String: Any])
            let unfoldedLines = try XCTUnwrap(unfoldedViewport["lines"] as? [[String: Any]])
            XCTAssertFalse(unfoldedLines.contains { ($0["is_fold_placeholder_appended"] as? Bool) == true })
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "{", viewportWidthCells: 80)
            try ui.setIndentationConfig(
                EcuIndentationConfig(
                    style: .spaces(width: 2),
                    indentTriggers: ["{"],
                    outdentTriggers: ["}"]
                )
            )
            try ui.moveTo(line: 0, column: 1)
            try ui.insertNewline(autoIndent: true)
            XCTAssertEqual(try ui.text(), "{\n  ")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "", viewportWidthCells: 80)
            try ui.setAutoPairsConfig(
                EcuAutoPairsConfig(
                    enabled: true,
                    pairs: [EcuAutoPair(open: "<", close: ">")],
                    wrapSelection: true,
                    skipOverClosing: true,
                    deletePair: true
                )
            )
            try ui.typeChar("<")
            XCTAssertEqual(try ui.text(), "<>")
        }

        do {
            let ui = try EditorUI(library: lib, initialText: "", viewportWidthCells: 80)
            try ui.applySnippet(start: 0, end: 0, snippet: "println!(${1:msg})$0")
            XCTAssertEqual(try ui.text(), "println!(msg)")
            XCTAssertTrue(try ui.hasActiveSnippetSession())

            try ui.snippetNextPlaceholder()
            XCTAssertFalse(try ui.hasActiveSnippetSession())
        }
    }

    func testCloneViewSharesTextAndHasIndependentScrollState() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui1 = try EditorUI(
            library: lib,
            initialText: "abc\ndef\nghi\njkl\nmno\npqr\nstu\nvwx\nyz\n",
            viewportWidthCells: 80
        )
        let ui2 = try ui1.cloneView(viewportWidthCells: 80)

        // View state is independent.
        try ui1.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)
        try ui2.setSelections([EcuSelectionRange(start: 4, end: 4)], primaryIndex: 0)
        XCTAssertEqual(try ui1.selectionOffsets().start, 0)
        XCTAssertEqual(try ui2.selectionOffsets().start, 4)

        // Text edits are shared.
        try ui1.insertText("X")
        XCTAssertEqual(try ui2.text(), "Xabc\ndef\nghi\njkl\nmno\npqr\nstu\nvwx\nyz\n")

        // Each view tracks its own selection, but receives the same text delta.
        let s2 = try ui2.selectionOffsets()
        XCTAssertEqual(s2.start, 5)
        XCTAssertEqual(s2.end, 5)

        // Scroll is view-local.
        try ui1.setRenderMetrics(fontSize: 10, lineHeightPx: 10, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui2.setRenderMetrics(fontSize: 10, lineHeightPx: 10, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui1.setViewportPx(widthPx: 80, heightPx: 20, scale: 1)
        try ui2.setViewportPx(widthPx: 80, heightPx: 20, scale: 1)

        ui1.setSmoothScrollState(topVisualRow: 1, subRowOffset: 0)
        ui2.setSmoothScrollState(topVisualRow: 3, subRowOffset: 0)

        XCTAssertEqual(try ui1.viewportState().scrollTop, 1)
        XCTAssertEqual(try ui2.viewportState().scrollTop, 3)
    }

    func testCreateInsertUndoRedoRenderAndQueries() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )

        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        // 多字体 fallback：确保主字体缺字时仍能显示 CJK/Emoji（渲染层按字符挑选可用字体）。
        try ui.setFontFamiliesCSV("Menlo, PingFang SC, Apple Color Emoji")
        // Font ligatures (visual-only): should not crash even if the selected font has no ligatures.
        try ui.setFontLigaturesEnabled(true)
        try ui.setViewportPx(widthPx: 80, heightPx: 40, scale: 1)

        var rgba: [UInt8] = []
        let n = try ui.renderRGBA(into: &rgba)
        XCTAssertEqual(n, 80 * 40 * 4)
        XCTAssertEqual(rgba.count, 80 * 40 * 4)

        // 背景色在空白区域必须是我们设置的值
        XCTAssertEqual(pixel(rgba, widthPx: 80, x: 70, y: 30), [10, 20, 30, 255])

        // 编辑 + undo/redo
        try ui.insertText("abc")
        XCTAssertEqual(try ui.text(), "abc")
        try ui.undo()
        XCTAssertEqual(try ui.text(), "")
        try ui.redo()
        XCTAssertEqual(try ui.text(), "abc")

        // IME marked text（Rust UI 层实现）
        try ui.setMarkedText("你")
        let marked1 = try ui.markedRange()
        XCTAssertTrue(marked1.hasMarked)
        XCTAssertEqual(marked1.len, 1)

        try ui.setMarkedText("你好")
        let marked2 = try ui.markedRange()
        XCTAssertTrue(marked2.hasMarked)
        XCTAssertEqual(marked2.len, 2)

        // Inline/preedit: caret inside marked text (after first char of "你好").
        try ui.setMarkedText("你好", selectedStart: 1, selectedLen: 0)
        let selIme = try ui.selectionOffsets()
        XCTAssertEqual(selIme.start, 4) // "abc" (3) + 1
        XCTAssertEqual(selIme.end, 4)

        try ui.commitText("你好!")
        let marked3 = try ui.markedRange()
        XCTAssertFalse(marked3.hasMarked)
        XCTAssertEqual(try ui.text(), "abc你好!")

        // selection offsets: no selection => start == end == caret
        let sel = try ui.selectionOffsets()
        XCTAssertEqual(sel.start, sel.end)

        // offset <-> view point mapping
        let p = try ui.charOffsetToViewPoint(offset: 0)
        XCTAssertEqual(p.xPx, 0)
        XCTAssertEqual(p.yPx, 0)
        XCTAssertEqual(p.lineHeightPx, 20)

        let hit = try ui.viewPointToCharOffset(xPx: 25, yPx: 10)
        XCTAssertEqual(hit, 2)
    }

    func testCharOffsetToLogicalPosition() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "ab\ncde\nf", viewportWidthCells: 80)

        let p = try ui.charOffsetToLogicalPosition(offset: 4) // 'd'
        XCTAssertEqual(p.line, 1)
        XCTAssertEqual(p.column, 1)
    }

    func testMinimapJSON() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "a\nb\nc", viewportWidthCells: 80)

        let minimap = try JSONTestHelpers.object(try ui.minimapJSON(startVisualRow: 0, rowCount: 20))
        XCTAssertNotNil(minimap["lines"])
        XCTAssertEqual(minimap["start_visual_row"] as? Int, 0)
        XCTAssertEqual(minimap["count"] as? Int, 20)
        XCTAssertEqual(minimap["actual_line_count"] as? Int, 3)
    }

    func testSmoothScrollByPixelsAffectsHitTestingAndViewPointMapping() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "a\nb\nc\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 10, lineHeightPx: 10, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 80, heightPx: 20, scale: 1)

        // Scroll down by half a row: content should move up by 5px.
        ui.scrollByPixels(5)

        // "b" starts at char offset 2 ("a\nb..."), its y should be (1*10 - 5) = 5.
        let pB = try ui.charOffsetToViewPoint(offset: 2)
        XCTAssertEqual(pB.yPx, 5)

        // Hit test must account for smooth scroll:
        // y < 5 => line 0 ("a"), y >= 5 => line 1 ("b")
        XCTAssertEqual(try ui.viewPointToCharOffset(xPx: 0, yPx: 4), 0)
        XCTAssertEqual(try ui.viewPointToCharOffset(xPx: 0, yPx: 5), 2)
        XCTAssertEqual(try ui.viewPointToCharOffset(xPx: 0, yPx: 9), 2)
    }

    func testViewportStateAndSetSmoothScrollState() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "0\n1\n2\n3\n4\n5\n6\n7", viewportWidthCells: 80)
        try ui.setRenderMetrics(fontSize: 10, lineHeightPx: 10, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 80, heightPx: 20, scale: 1)

        let vp0 = try ui.viewportState()
        XCTAssertEqual(vp0.totalVisualLines, 8)
        XCTAssertEqual(vp0.heightRows, 2)
        XCTAssertEqual(vp0.scrollTop, 0)
        XCTAssertEqual(vp0.subRowOffset, 0)

        ui.setSmoothScrollState(topVisualRow: 3, subRowOffset: 32768)
        let vp1 = try ui.viewportState()
        XCTAssertEqual(vp1.scrollTop, 3)
        XCTAssertEqual(vp1.subRowOffset, 32768)

        // Clamp to max scroll (total - height = 6).
        ui.setSmoothScrollState(topVisualRow: 999, subRowOffset: 65535)
        let vp2 = try ui.viewportState()
        XCTAssertEqual(vp2.scrollTop, 6)
        XCTAssertEqual(vp2.subRowOffset, 0)
    }

    func testRevealPrimaryCaretScrollsToShowCaret() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let text = (0..<100).map { _ in "x" }.joined(separator: "\n")
        let ui = try EditorUI(library: lib, initialText: text, viewportWidthCells: 80)

        try ui.setRenderMetrics(fontSize: 14, lineHeightPx: 10, cellWidthPx: 8, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 800, heightPx: 50, scale: 1)
        ui.setSmoothScrollState(topVisualRow: 0, subRowOffset: 0)

        // Line 50, col 0 in "x\nx\n..." => offset 50*(1+1) = 100.
        try ui.setSelections([EcuSelectionRange(start: 100, end: 100)], primaryIndex: 0)
        try ui.revealPrimaryCaret()

        let vp = try ui.viewportState()
        XCTAssertEqual(vp.heightRows, 5)
        XCTAssertEqual(vp.scrollTop, 46)
    }

    func testLspInteractiveRequestsThrowWhenLspDisabledAndTakeReturnsNil() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "hello", viewportWidthCells: 80)
        XCTAssertThrowsError(try ui.lspRequestHover(logicalLine: 0, logicalColumn: 0))
        XCTAssertThrowsError(try ui.lspRequestDefinition(logicalLine: 0, logicalColumn: 0))
        XCTAssertThrowsError(try ui.lspRequestDeclaration(logicalLine: 0, logicalColumn: 0))
        XCTAssertThrowsError(try ui.lspRequestTypeDefinition(logicalLine: 0, logicalColumn: 0))
        XCTAssertThrowsError(try ui.lspRequestImplementation(logicalLine: 0, logicalColumn: 0))
        XCTAssertThrowsError(try ui.lspRequestReferences(logicalLine: 0, logicalColumn: 0))
        XCTAssertThrowsError(try ui.lspRequestCompletion(logicalLine: 0, logicalColumn: 0))
        XCTAssertThrowsError(try ui.lspRequestCompletionItemResolve(itemJSON: #"{"label":"hello"}"#))
        XCTAssertThrowsError(try ui.lspRequestSignatureHelp(logicalLine: 0, logicalColumn: 0))
        XCTAssertThrowsError(try ui.lspRequestPrepareRename(logicalLine: 0, logicalColumn: 0))
        XCTAssertThrowsError(try ui.lspRequestRename(logicalLine: 0, logicalColumn: 0, newName: "world"))
        XCTAssertThrowsError(try ui.lspRequestCodeAction(startOffset: 0, endOffset: 0))
        XCTAssertThrowsError(try ui.lspRequestCodeActionResolve(actionJSON: #"{"title":"Fix"}"#))
        XCTAssertThrowsError(try ui.lspRequestExecuteCommand(commandJSON: #"{"command":"server.fix","arguments":[]}"#))
        XCTAssertThrowsError(try ui.lspRequestCodeLens())
        XCTAssertThrowsError(try ui.lspRequestCodeLensResolve(lensJSON: #"{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":1}}}"#))
        XCTAssertThrowsError(try ui.lspRequestInlayHints(startOffset: 0, endOffset: 1))
        XCTAssertThrowsError(try ui.lspRequestInlayHintResolve(hintJSON: #"{"position":{"line":0,"character":1},"label":"x"}"#))
        XCTAssertThrowsError(try ui.lspRequestDocumentLinks())
        XCTAssertThrowsError(try ui.lspRequestDocumentLinkResolve(linkJSON: #"{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":1}}}"#))
        XCTAssertThrowsError(try ui.lspRequestDocumentSymbols())
        XCTAssertThrowsError(try ui.lspRequestFoldingRanges())
        XCTAssertThrowsError(try ui.lspRequestSemanticTokensFull())
        XCTAssertThrowsError(try ui.lspRequestSemanticTokensDelta(previousResultId: "previous"))
        XCTAssertThrowsError(try ui.lspRequestSemanticTokensRange(startLine: 0, startColumn: 0, endLine: 0, endColumn: 1))
        XCTAssertThrowsError(try ui.lspRequestSelectionRange(positionsJSON: #"[{"line":0,"column":0}]"#))
        XCTAssertThrowsError(try ui.lspRequestLinkedEditingRange(logicalLine: 0, logicalColumn: 0))
        XCTAssertThrowsError(try ui.lspRequestDocumentDiagnostic())
        XCTAssertThrowsError(try ui.lspRequestWorkspaceDiagnostic())
        XCTAssertThrowsError(try ui.lspRequestDocumentColor())
        XCTAssertThrowsError(try ui.lspRequestColorPresentation(startOffset: 0, endOffset: 1, colorJSON: #"{"red":1,"green":0,"blue":0,"alpha":1}"#))
        XCTAssertThrowsError(try ui.lspRequestPrepareCallHierarchy(logicalLine: 0, logicalColumn: 0))
        XCTAssertThrowsError(try ui.lspRequestCallHierarchyIncomingCalls(itemJSON: #"{"name":"main"}"#))
        XCTAssertThrowsError(try ui.lspRequestCallHierarchyOutgoingCalls(itemJSON: #"{"name":"main"}"#))
        XCTAssertThrowsError(try ui.lspRequestPrepareTypeHierarchy(logicalLine: 0, logicalColumn: 0))
        XCTAssertThrowsError(try ui.lspRequestTypeHierarchySupertypes(itemJSON: #"{"name":"Type"}"#))
        XCTAssertThrowsError(try ui.lspRequestTypeHierarchySubtypes(itemJSON: #"{"name":"Type"}"#))
        XCTAssertThrowsError(try ui.lspRequestWorkspaceSymbols(query: "hello"))
        XCTAssertThrowsError(try ui.lspFormatDocument())
        XCTAssertThrowsError(try ui.lspFormatRange(startOffset: 0, endOffset: 1))
        XCTAssertThrowsError(try ui.lspFormatOnType(logicalLine: 0, logicalColumn: 1, trigger: "\n"))

        XCTAssertNil(try ui.lspTakeLastHoverResultJSON())
        XCTAssertNil(try ui.lspTakeLastDefinitionResultJSON())
        XCTAssertNil(try ui.lspTakeLastDeclarationResultJSON())
        XCTAssertNil(try ui.lspTakeLastTypeDefinitionResultJSON())
        XCTAssertNil(try ui.lspTakeLastImplementationResultJSON())
        XCTAssertNil(try ui.lspTakeLastReferencesResultJSON())
        XCTAssertNil(try ui.lspTakeLastCompletionResultJSON())
        XCTAssertNil(try ui.lspTakeLastCompletionItemResolveResultJSON())
        XCTAssertNil(try ui.lspTakeLastSignatureHelpResultJSON())
        XCTAssertNil(try ui.lspTakeLastSignatureHelpResult())
        XCTAssertNil(try ui.lspTakeLastPrepareRenameResultJSON())
        XCTAssertNil(try ui.lspTakeLastRenameResultJSON())
        XCTAssertNil(try ui.lspTakeLastCodeActionResultJSON())
        XCTAssertNil(try ui.lspTakeLastCodeActionResolveResultJSON())
        XCTAssertNil(try ui.lspTakeLastExecuteCommandResultJSON())
        XCTAssertNil(try ui.lspTakeLastCodeLensResultJSON())
        XCTAssertNil(try ui.lspTakeLastCodeLensResolveResultJSON())
        XCTAssertNil(try ui.lspTakeLastInlayHintsResultJSON())
        XCTAssertNil(try ui.lspTakeLastInlayHintResolveResultJSON())
        XCTAssertNil(try ui.lspTakeLastDocumentLinksResultJSON())
        XCTAssertNil(try ui.lspTakeLastDocumentLinkResolveResultJSON())
        XCTAssertNil(try ui.lspTakeLastDocumentSymbolsResultJSON())
        XCTAssertNil(try ui.lspTakeLastFoldingRangesResultJSON())
        XCTAssertNil(try ui.lspTakeLastSemanticTokensFullResultJSON())
        XCTAssertNil(try ui.lspTakeLastSemanticTokensDeltaResultJSON())
        XCTAssertNil(try ui.lspTakeLastSemanticTokensRangeResultJSON())
        XCTAssertNil(try ui.lspTakeLastSelectionRangeResultJSON())
        XCTAssertNil(try ui.lspTakeLastLinkedEditingRangeResultJSON())
        XCTAssertNil(try ui.lspTakeLastDocumentDiagnosticResultJSON())
        XCTAssertNil(try ui.lspTakeLastWorkspaceDiagnosticResultJSON())
        XCTAssertNil(try ui.lspTakeLastDocumentColorResultJSON())
        XCTAssertNil(try ui.lspTakeLastColorPresentationResultJSON())
        XCTAssertNil(try ui.lspTakeLastPrepareCallHierarchyResultJSON())
        XCTAssertNil(try ui.lspTakeLastCallHierarchyIncomingCallsResultJSON())
        XCTAssertNil(try ui.lspTakeLastCallHierarchyOutgoingCallsResultJSON())
        XCTAssertNil(try ui.lspTakeLastPrepareTypeHierarchyResultJSON())
        XCTAssertNil(try ui.lspTakeLastTypeHierarchySupertypesResultJSON())
        XCTAssertNil(try ui.lspTakeLastTypeHierarchySubtypesResultJSON())
        XCTAssertNil(try ui.lspTakeLastWorkspaceSymbolsResultJSON())
    }

    func testStyleColorsOverrideAffectsRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Use a space in the styled cell so glyph rasterization does not affect the pixel sample.
        let ui = try EditorUI(library: lib, initialText: "a c", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 80, heightPx: 40, scale: 1)

        // 给中间字符（一个空格）加一个 style id，然后下发该 style 的背景色覆盖。
        try ui.addStyle(start: 1, end: 2, styleId: 42)
        try ui.setStyleColors([EcuStyleColors(styleId: 42, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // Styled cell 对应 x in [10..20]，取中心像素。
        XCTAssertEqual(pixel(rgba, widthPx: 80, x: 15, y: 10), [1, 200, 2, 255])
    }

    func testRenderDrawsSomeTextPixels() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "M", viewportWidthCells: 80)

        // Make caret/selection invisible so only glyph pixels can differ from background.
        let bg = EcuRgba8(r: 10, g: 20, b: 30, a: 255)
        try ui.setTheme(
            EcuTheme(
                background: bg,
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: bg,
                caret: bg
            )
        )
        try ui.setRenderMetrics(fontSize: 20, lineHeightPx: 40, cellWidthPx: 20, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 80, heightPx: 40, scale: 1)

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        let bgPx: [UInt8] = [bg.r, bg.g, bg.b, bg.a]
        var hasNonBackground = false
        for i in stride(from: 0, to: rgba.count, by: 4) {
            if Array(rgba[i..<min(i + 4, rgba.count)]) != bgPx {
                hasNonBackground = true
                break
            }
        }
        XCTAssertTrue(hasNonBackground, "expected at least one non-background pixel from glyph rendering")
    }

    func testSublimeHighlightScopeMappingAndRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Put a space after '#' so we can sample a highlighted cell without glyph pixels.
        let ui = try EditorUI(library: lib, initialText: "a # \n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        let yaml = """
        %YAML 1.2
        ---
        name: Demo
        scope: source.demo
        contexts:
          main:
            - match: "#.*$"
              scope: comment.line.demo
        """
        try ui.sublimeSetSyntaxYAML(yaml)

        let styleId = try ui.sublimeStyleId(forScope: "comment.line.demo")
        XCTAssertEqual(try ui.sublimeScope(forStyleId: styleId), "comment.line.demo")

        try ui.setStyleColors([EcuStyleColors(styleId: styleId, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // "a # " => space at col=3 is highlighted => x in [30..40]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 35, y: 10), [1, 200, 2, 255])
    }

    func testTreeSitterHighlightCaptureMappingAndRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "// c\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        try setTestTreeSitterRegistry(ui)
        try ui.treeSitterEnableLanguage("rust")
        try waitForAsyncProcessing(ui)
        let styleId = try ui.treeSitterStyleId(forCapture: "comment")
        XCTAssertEqual(try ui.treeSitterCapture(forStyleId: styleId), "comment")

        try ui.setStyleColors([EcuStyleColors(styleId: styleId, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // Comment contains a space at col=2 => x in [20..30]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 25, y: 10), [1, 200, 2, 255])
    }

    func testLspDiagnosticsAffectRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Use a space in the highlighted range so glyph rasterization does not affect the pixel sample.
        let ui = try EditorUI(library: lib, initialText: "a c\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        // LSP diagnostics style id encoding: 0x0400_0100 | severity
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0400_0100 | 1, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        let params = """
        {
          "uri": "file:///test",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 0, "character": 1 },
                "end": { "line": 0, "character": 2 }
              },
              "severity": 1,
              "message": "unit"
            }
          ],
          "version": 1
        }
        """
        try ui.lspApplyDiagnosticsJSON(params)

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // Highlighted cell at col=1 => x in [10..20]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 10), [1, 200, 2, 255])
    }

    func testDerivedStateSnapshotsExposeLspAndFoldingState() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "fn main() {\n  value\n}\n", viewportWidthCells: 80)

        let diagnosticsParams = """
        {
          "uri": "file:///test.rs",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 1, "character": 2 },
                "end": { "line": 1, "character": 7 }
              },
              "severity": 2,
              "code": "unused",
              "source": "unit-test",
              "message": "value is unused"
            }
          ],
          "version": 1
        }
        """
        try ui.lspApplyDiagnosticsJSON(diagnosticsParams)

        let diagnostics = try JSONTestHelpers.object(try ui.diagnosticsJSON())
        let diagnosticList = try XCTUnwrap(diagnostics["diagnostics"] as? [[String: Any]])
        XCTAssertEqual(diagnosticList.count, 1)
        XCTAssertEqual(diagnosticList[0]["message"] as? String, "value is unused")
        XCTAssertEqual(diagnosticList[0]["severity"] as? String, "warning")
        let diagnosticsSnapshot = try ui.diagnosticsSnapshot()
        XCTAssertEqual(diagnosticsSnapshot.diagnostics.count, 1)
        XCTAssertEqual(diagnosticsSnapshot.diagnostics[0].message, "value is unused")
        XCTAssertEqual(diagnosticsSnapshot.diagnostics[0].severity, .warning)
        XCTAssertEqual(diagnosticsSnapshot.diagnostics[0].code, "unused")
        XCTAssertEqual(diagnosticsSnapshot.diagnostics[0].source, "unit-test")

        let inlayHints = """
        [
          {
            "position": { "line": 1, "character": 7 },
            "label": ": i32",
            "tooltip": "inferred type"
          }
        ]
        """
        try ui.lspApplyInlayHintsJSON(inlayHints)

        let decorations = try JSONTestHelpers.object(try ui.decorationsJSON())
        let decorationLayers = try XCTUnwrap(decorations["layers"] as? [[String: Any]])
        let inlayLayer = try XCTUnwrap(decorationLayers.first { ($0["layer"] as? Int) == 1 })
        let inlayDecorations = try XCTUnwrap(inlayLayer["decorations"] as? [[String: Any]])
        XCTAssertEqual(inlayDecorations.first?["text"] as? String, ": i32")
        let inlayKind = try XCTUnwrap(inlayDecorations.first?["kind"] as? [String: Any])
        XCTAssertEqual(inlayKind["kind"] as? String, "inlay_hint")
        let decorationsSnapshot = try ui.decorationsSnapshot()
        let typedInlayLayer = try XCTUnwrap(decorationsSnapshot.layers.first { $0.layer == 1 })
        let typedInlay = try XCTUnwrap(typedInlayLayer.decorations.first)
        XCTAssertEqual(typedInlay.text, ": i32")
        XCTAssertEqual(typedInlay.kind, .object(["kind": .string("inlay_hint")]))

        let documentSymbols = """
        [
          {
            "name": "main",
            "detail": "fn()",
            "kind": 12,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 2, "character": 1 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 3 },
              "end": { "line": 0, "character": 7 }
            },
            "children": []
          }
        ]
        """
        try ui.lspApplyDocumentSymbolsJSON(documentSymbols)

        let symbols = try JSONTestHelpers.object(try ui.documentSymbolsJSON())
        let symbolList = try XCTUnwrap(symbols["symbols"] as? [[String: Any]])
        XCTAssertEqual(symbolList.first?["name"] as? String, "main")
        let symbolKind = try XCTUnwrap(symbolList.first?["kind"] as? [String: Any])
        XCTAssertEqual(symbolKind["kind"] as? String, "function")
        let symbolsSnapshot = try ui.documentSymbolsSnapshot()
        let typedSymbol = try XCTUnwrap(symbolsSnapshot.symbols.first)
        XCTAssertEqual(typedSymbol.name, "main")
        XCTAssertEqual(typedSymbol.detail, "fn()")
        XCTAssertEqual(typedSymbol.kind, .object(["kind": .string("function")]))

        try ui.lspApplySemanticTokens([0, 3, 4, 7, 0])

        let styleIntervals = try JSONTestHelpers.object(try ui.styleIntervalsJSON(start: 0, end: 24))
        let styleLayers = try XCTUnwrap(styleIntervals["layers"] as? [[String: Any]])
        let semanticLayer = try XCTUnwrap(styleLayers.first { ($0["layer"] as? Int) == 1 })
        let semanticIntervals = try XCTUnwrap(semanticLayer["intervals"] as? [[String: Any]])
        XCTAssertEqual(semanticIntervals.first?["start"] as? Int, 3)
        XCTAssertEqual(semanticIntervals.first?["end"] as? Int, 7)
        XCTAssertEqual(semanticIntervals.first?["style_id"] as? Int, 0x0007_0000)
        let styleSnapshot = try ui.styleIntervalsSnapshot(start: 0, end: 24)
        let typedSemanticLayer = try XCTUnwrap(styleSnapshot.layers.first { $0.layer == 1 })
        let typedSemanticInterval = try XCTUnwrap(typedSemanticLayer.intervals.first)
        XCTAssertEqual(typedSemanticInterval.start, 3)
        XCTAssertEqual(typedSemanticInterval.end, 7)
        XCTAssertEqual(typedSemanticInterval.styleId, 0x0007_0000)

        let foldingRanges = """
        [
          {
            "startLine": 0,
            "endLine": 2,
            "kind": "region"
          }
        ]
        """
        try ui.lspApplyFoldingRangesJSON(foldingRanges)

        let lspFolding = try JSONTestHelpers.object(try ui.foldingRegionsJSON())
        let lspRegions = try XCTUnwrap(lspFolding["regions"] as? [[String: Any]])
        XCTAssertTrue(lspRegions.contains {
            ($0["start_line"] as? Int) == 0
                && ($0["end_line"] as? Int) == 2
                && ($0["is_collapsed"] as? Bool) == false
        })
        let lspFoldingSnapshot = try ui.foldingRegionsSnapshot()
        XCTAssertTrue(lspFoldingSnapshot.regions.contains {
            $0.startLine == 0 && $0.endLine == 2 && $0.isCollapsed == false
        })

        try ui.fold(startLine: 0, endLine: 2)

        let folding = try JSONTestHelpers.object(try ui.foldingRegionsJSON())
        let regions = try XCTUnwrap(folding["regions"] as? [[String: Any]])
        XCTAssertTrue(regions.contains {
            ($0["start_line"] as? Int) == 0
                && ($0["end_line"] as? Int) == 2
                && ($0["is_collapsed"] as? Bool) == true
        })
        let foldingSnapshot = try ui.foldingRegionsSnapshot()
        XCTAssertTrue(foldingSnapshot.regions.contains {
            $0.startLine == 0 && $0.endLine == 2 && $0.isCollapsed == true
        })
    }

    func testLspSemanticTokensAffectRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Use a space in the highlighted range so glyph rasterization does not affect the pixel sample.
        let ui = try EditorUI(library: lib, initialText: "a c\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        // encode_semantic_style_id(token_type=7, token_modifiers=0) => 0x0007_0000
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0007_0000, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        // Highlight cell at col=1 (line 0, utf16 start=1, len=1).
        try ui.lspApplySemanticTokens([0, 1, 1, 7, 0])

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 10), [1, 200, 2, 255])
    }

    func testLspApplyWorkspaceEditJSONAppliesCurrentDocumentAndReportsSkippedURIs() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc\n", viewportWidthCells: 80)

        let workspaceEdit = """
        {
          "changes": {
            "file:///test.rs": [
              {
                "range": {
                  "start": { "line": 0, "character": 1 },
                  "end": { "line": 0, "character": 2 }
                },
                "newText": "B"
              }
            ],
            "file:///other.rs": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "X"
              }
            ]
          }
        }
        """

        let result = try JSONTestHelpers.object(
            try ui.lspApplyWorkspaceEditJSON(workspaceEdit, documentURI: "file:///test.rs")
        )

        XCTAssertEqual(try ui.text(), "aBc\n")
        XCTAssertEqual(result["applied"] as? Bool, true)
        XCTAssertEqual(result["applied_uri"] as? String, "file:///test.rs")
        XCTAssertEqual(result["applied_edit_count"] as? Int, 1)
        XCTAssertEqual(result["skipped_uris"] as? [String], ["file:///other.rs"])

        let documents = try XCTUnwrap(result["documents"] as? [[String: Any]])
        XCTAssertEqual(documents.count, 2)
        XCTAssertTrue(documents.contains {
            ($0["uri"] as? String) == "file:///test.rs"
                && ($0["edit_count"] as? Int) == 1
                && ($0["has_overlapping_edits"] as? Bool) == false
        })
    }

    func testLspWorkspaceEditApplicationEnvelopeReportsSuccessAndError() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc\n", viewportWidthCells: 80)

        let workspaceEdit = """
        {
          "changes": {
            "file:///test.rs": [
              {
                "range": {
                  "start": { "line": 0, "character": 1 },
                  "end": { "line": 0, "character": 2 }
                },
                "newText": "B"
              }
            ],
            "file:///other.rs": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "X"
              }
            ]
          }
        }
        """

        let envelope = try ui.lspApplyWorkspaceEditEnvelope(workspaceEdit, documentURI: "file:///test.rs")
        XCTAssertTrue(envelope.ok)
        XCTAssertEqual(envelope.version, lib.abiVersion)
        XCTAssertEqual(envelope.statusKind, .success)
        XCTAssertEqual(envelope.documentURI, "file:///test.rs")
        XCTAssertEqual(envelope.value?.applied, true)
        XCTAssertEqual(envelope.value?.appliedURI, "file:///test.rs")
        XCTAssertEqual(envelope.value?.appliedEditCount, 1)
        XCTAssertEqual(envelope.value?.skippedURIs, ["file:///other.rs"])
        XCTAssertEqual(envelope.value?.documents.count, 2)
        XCTAssertNil(envelope.error)
        guard case .object(let rawValue)? = envelope.rawValue else {
            XCTFail("expected workspace edit application raw object")
            return
        }
        XCTAssertEqual(rawValue["applied_uri"], .string("file:///test.rs"))
        XCTAssertEqual(try ui.text(), "aBc\n")

        let failure = try ui.lspApplyWorkspaceEditEnvelope("{", documentURI: "file:///test.rs")
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.documentURI, "file:///test.rs")
        XCTAssertNil(failure.value)
        XCTAssertEqual(failure.rawValue, .null)
        XCTAssertEqual(failure.error?.code, "internal")
        XCTAssertTrue(failure.error?.message.contains("EOF while parsing") ?? false)
    }

    func testLspWorkspaceEditApplicationEnvelopeDecodesFutureFieldsAndUnknownStatus() throws {
        let successJSON = """
        {
          "ok": true,
          "status": "future_status",
          "document_uri": "file:///future.swift",
          "value": {
            "applied": true,
            "applied_uri": "file:///future.swift",
            "applied_edit_count": 2,
            "skipped_uris": ["file:///other.swift"],
            "documents": [
              {
                "uri": "file:///future.swift",
                "edit_count": 2,
                "has_overlapping_edits": false,
                "futureDocumentField": true
              }
            ],
            "future": true
          },
          "error": null,
          "version": 15,
          "futureTopLevel": true
        }
        """
        let success = try JSONDecoder().decode(
            EcuLspWorkspaceEditApplicationEnvelope.self,
            from: Data(successJSON.utf8)
        )
        XCTAssertTrue(success.ok)
        XCTAssertEqual(success.statusKind, .unknown("future_status"))
        XCTAssertEqual(success.documentURI, "file:///future.swift")
        XCTAssertEqual(success.value?.applied, true)
        XCTAssertEqual(success.value?.appliedURI, "file:///future.swift")
        XCTAssertEqual(success.value?.appliedEditCount, 2)
        XCTAssertEqual(success.value?.skippedURIs, ["file:///other.swift"])
        XCTAssertEqual(success.value?.documents.first?.uri, "file:///future.swift")
        XCTAssertNil(success.error)
        guard case .object(let rawValue)? = success.rawValue else {
            XCTFail("expected future workspace edit application raw object")
            return
        }
        XCTAssertEqual(rawValue["future"], .bool(true))

        let failureJSON = """
        {
          "ok": false,
          "status": "error",
          "document_uri": "file:///future.swift",
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
        let failure = try JSONDecoder().decode(
            EcuLspWorkspaceEditApplicationEnvelope.self,
            from: Data(failureJSON.utf8)
        )
        XCTAssertFalse(failure.ok)
        XCTAssertEqual(failure.statusKind, .error)
        XCTAssertEqual(failure.documentURI, "file:///future.swift")
        XCTAssertNil(failure.value)
        XCTAssertEqual(failure.rawValue, .null)
        XCTAssertEqual(failure.error?.code, "future_error")
        XCTAssertEqual(failure.error?.message, "future failure")
        XCTAssertNil(failure.error?.status)
    }

    func testLspInlayHintsAffectRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Use a space in the inlay hint label so glyph rasterization does not affect the pixel sample.
        let ui = try EditorUI(library: lib, initialText: "ab\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        // Built-in style id for LSP inlay hint virtual text: 0x0800_0001
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0800_0001, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        let result = """
        [
          {
            "position": { "line": 0, "character": 1 },
            "label": " "
          }
        ]
        """
        try ui.lspApplyInlayHintsJSON(result)

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // Inlay hint is inserted at offset=1 => between 'a' and 'b' => col=1 => x in [10..20]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 10), [1, 200, 2, 255])
    }

    func testLspInlayHintsAffectHitTestingAndCaretPoint() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "ab\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        let result = """
        [
          {
            "position": { "line": 0, "character": 1 },
            "label": " "
          }
        ]
        """
        try ui.lspApplyInlayHintsJSON(result)

        // With the inlay hint inserted between 'a' and 'b', the 'b' cell shifts right by 1.
        // So x=25 should hit 'b' (offset=1) instead of end-of-line (offset=2).
        XCTAssertEqual(try ui.viewPointToCharOffset(xPx: 25, yPx: 10), 1)

        let pt = try ui.charOffsetToViewPoint(offset: 2)
        XCTAssertEqual(pt.xPx, 30)
        XCTAssertEqual(pt.yPx, 0)
        XCTAssertEqual(pt.lineHeightPx, 20)
    }

    func testLspCodeLensAffectRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Use a space in the code lens title so glyph rasterization does not affect the pixel sample.
        let ui = try EditorUI(library: lib, initialText: "line1\nline2\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        // Built-in style id for LSP code lens virtual text: 0x0800_0002
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0800_0002, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        let result = """
        [
          {
            "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } },
            "command": { "title": " ", "command": "noop" }
          }
        ]
        """
        try ui.lspApplyCodeLensJSON(result)

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // Code lens is an above-line virtual line inserted at the very top => row=0, col=0.
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 5, y: 10), [1, 200, 2, 255])
    }

    func testCodeLensHitTestReturnsPayloadJSON() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "line1\nline2\n", viewportWidthCells: 80)

        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 400, heightPx: 80, scale: 1)

        let result = """
        [
          {
            "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } },
            "command": { "title": "Run tests", "command": "test.run", "arguments": [1] }
          }
        ]
        """
        try ui.lspApplyCodeLensJSON(result)

        let json = try ui.codeLensJSONAtViewPoint(xPx: 5, yPx: 10)
        XCTAssertNotNil(json)
        XCTAssertTrue(json?.contains(#""title":"Run tests""#) == true)
        XCTAssertTrue(json?.contains(#""command":"test.run""#) == true)

        XCTAssertNil(try ui.codeLensJSONAtViewPoint(xPx: 200, yPx: 10))
        XCTAssertNil(try ui.codeLensJSONAtViewPoint(xPx: 5, yPx: 30))
    }

    func testLspDocumentLinksAffectRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Use a space in the link range so glyph rasterization does not affect the pixel sample.
        let ui = try EditorUI(library: lib, initialText: "a c\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 10, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 20, scale: 1)

        // Built-in style id for LSP document links underline: 0x0800_0003
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0800_0003, foreground: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        let result = """
        [
          {
            "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 2 } },
            "target": "https://example.com"
          }
        ]
        """
        try ui.lspApplyDocumentLinksJSON(result)

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // Underline is drawn at y = line_height_px - 1 (scale=1), i.e. y=9.
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 9), [1, 200, 2, 255])
    }

    func testDocumentLinkHitTestReturnsPayloadJSON() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "a c\n", viewportWidthCells: 80)

        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 10, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 20, scale: 1)

        let result = """
        [
          {
            "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 2 } },
            "target": "https://example.com"
          }
        ]
        """
        try ui.lspApplyDocumentLinksJSON(result)

        let p = try ui.charOffsetToViewPoint(offset: 1)
        let json = try ui.documentLinkJSONAtViewPoint(xPx: p.xPx + 1, yPx: p.yPx + 1)
        XCTAssertNotNil(json)
        XCTAssertTrue(json?.contains("https://example.com") == true)

        let none = try ui.documentLinkJSONAtViewPoint(xPx: 1, yPx: 1)
        XCTAssertNil(none)
    }

    func testLspDocumentHighlightsAffectRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Use a space in the highlighted range so glyph rasterization does not affect the pixel sample.
        let ui = try EditorUI(library: lib, initialText: "a c\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        // Built-in style id for LSP document highlight text: 0x0400_0001
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0400_0001, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        let result = """
        [
          {
            "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 2 } },
            "kind": 1
          }
        ]
        """
        try ui.lspApplyDocumentHighlightsJSON(result)

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // Highlighted cell at col=1 => x in [10..20]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 10), [1, 200, 2, 255])
    }

    func testMatchHighlightsAffectRendering() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Use a space in the highlighted range so glyph rasterization does not affect the pixel sample.
        let ui = try EditorUI(library: lib, initialText: "a c\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        // Built-in style id for match highlights: 0x0800_0004
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0800_0004, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])
        try ui.setMatchHighlights([EcuSelectionRange(start: 1, end: 2)])

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 10), [1, 200, 2, 255])
    }

    func testSearchSetQuerySetsMatchHighlightsAndReturnsCount() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        // Use spaces as matches so glyph rasterization does not affect the pixel samples.
        let ui = try EditorUI(library: lib, initialText: "a c a\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 40, scale: 1)

        // Built-in style id for match highlights: 0x0800_0004
        try ui.setStyleColors([EcuStyleColors(styleId: 0x0800_0004, background: EcuRgba8(r: 1, g: 200, b: 2, a: 255))])

        let count = try ui.setSearchQuery(" ", options: EcuSearchOptions(caseSensitive: true, wholeWord: false, regex: false))
        XCTAssertEqual(count, 2)

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)

        // First space at col=1 => x in [10..20]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 15, y: 10), [1, 200, 2, 255])
        // Second space at col=3 => x in [30..40]
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 35, y: 10), [1, 200, 2, 255])
    }

    func testFindNextAndReplaceCurrentAndAll() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "foo foo foo\n", viewportWidthCells: 80)

        try ui.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        XCTAssertTrue(try ui.findNext("foo"))
        XCTAssertEqual(try ui.selectionOffsets().start, 0)
        XCTAssertEqual(try ui.selectionOffsets().end, 3)

        XCTAssertTrue(try ui.findNext("foo"))
        XCTAssertEqual(try ui.selectionOffsets().start, 4)
        XCTAssertEqual(try ui.selectionOffsets().end, 7)

        let replaced = try ui.replaceCurrent(query: "foo", replacement: "bar")
        XCTAssertEqual(replaced, 1)
        XCTAssertEqual(try ui.text(), "foo bar foo\n")

        let replacedAll = try ui.replaceAll(query: "foo", replacement: "baz")
        XCTAssertEqual(replacedAll, 2)
        XCTAssertEqual(try ui.text(), "baz bar baz\n")
    }

    func testMultiSelectionsSetGetAndInsertTextAppliesToAllCarets() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc\ndef\n", viewportWidthCells: 80)

        try ui.setSelections(
            [
                EcuSelectionRange(start: 0, end: 0),
                EcuSelectionRange(start: 4, end: 4),
            ],
            primaryIndex: 0
        )

        let sels = try ui.selections()
        XCTAssertEqual(sels.ranges.count, 2)
        XCTAssertEqual(sels.primaryIndex, 0)
        XCTAssertEqual(sels.ranges[0], EcuSelectionRange(start: 0, end: 0))
        XCTAssertEqual(sels.ranges[1], EcuSelectionRange(start: 4, end: 4))

        try ui.insertText("X")
        XCTAssertEqual(try ui.text(), "Xabc\nXdef\n")
    }

    func testRectSelectionReplacesEachLineRange() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc\ndef\nghi\n", viewportWidthCells: 80)

        try ui.setRectSelection(anchorOffset: 1, activeOffset: 10)
        try ui.insertText("X")
        XCTAssertEqual(try ui.text(), "aXc\ndXf\ngXi\n")
    }

    func testSelectWordAndAddAllOccurrences() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "foo foo foo\n", viewportWidthCells: 80)

        try ui.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)
        try ui.selectWord()
        try ui.addAllOccurrences()

        let sels = try ui.selections()
        XCTAssertEqual(sels.ranges.count, 3)

        try ui.insertText("X")
        XCTAssertEqual(try ui.text(), "X X X\n")
    }

    func testAddAllOccurrencesAcceptsSearchOptions() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "foo Foo foo\n", viewportWidthCells: 80)

        try ui.setSelections([EcuSelectionRange(start: 0, end: 3)], primaryIndex: 0)
        try ui.addAllOccurrences(options: EcuSearchOptions(caseSensitive: false))

        let sels = try ui.selections()
        XCTAssertEqual(sels.ranges.count, 3)
    }

    func testAddCursorAboveAndClearSecondarySelections() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "aa\naa\naa\n", viewportWidthCells: 80)

        // line 1 col 1 => offset 4
        try ui.setSelections([EcuSelectionRange(start: 4, end: 4)], primaryIndex: 0)
        try ui.addCursorAbove()

        let sels1 = try ui.selections()
        XCTAssertEqual(sels1.ranges.count, 2)

        try ui.insertText("X")
        XCTAssertEqual(try ui.text(), "aXa\naXa\naa\n")

        try ui.clearSecondarySelections()
        let sels2 = try ui.selections()
        XCTAssertEqual(sels2.ranges.count, 1)
    }

    func testMoveAndModifySelectionExtendsFromAnchor() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc\n", viewportWidthCells: 80)

        try ui.setSelections([EcuSelectionRange(start: 2, end: 2)], primaryIndex: 0)

        try ui.moveGraphemeLeftAndModifySelection()
        var sel = try ui.selectionOffsets()
        XCTAssertEqual(sel.start, 1)
        XCTAssertEqual(sel.end, 2)

        try ui.moveGraphemeLeftAndModifySelection()
        sel = try ui.selectionOffsets()
        XCTAssertEqual(sel.start, 0)
        XCTAssertEqual(sel.end, 2)

        try ui.moveGraphemeRightAndModifySelection()
        sel = try ui.selectionOffsets()
        XCTAssertEqual(sel.start, 1)
        XCTAssertEqual(sel.end, 2)
    }

    func testGutterRendersFoldMarkerAndClickTogglesFold() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "fn main() {\n  let x = 1;\n}\n", viewportWidthCells: 80)

        try ui.setTheme(
            EcuTheme(
                background: EcuRgba8(r: 10, g: 20, b: 30, a: 255),
                foreground: EcuRgba8(r: 250, g: 250, b: 250, a: 255),
                selectionBackground: EcuRgba8(r: 200, g: 0, b: 0, a: 255),
                caret: EcuRgba8(r: 0, g: 0, b: 200, a: 255)
            )
        )
        try ui.setRenderMetrics(fontSize: 12, lineHeightPx: 20, cellWidthPx: 10, paddingXPx: 0, paddingYPx: 0)
        try ui.setViewportPx(widthPx: 200, heightPx: 60, scale: 1)
        try setTestTreeSitterRegistry(ui)
        try ui.treeSitterEnableLanguage("rust")
        try waitForAsyncProcessing(ui)
        // Ensure there is space for both the fold-marker column (2 cells) and line numbers.
        try ui.setGutterWidthCells(4)
        // Use block style to keep pixel assertions deterministic (chevrons are anti-aliased).
        try ui.setFoldMarkerStyle(.block)

        // Reserved overlay style ids (see `editor-core-render-skia`).
        let gutterBg: UInt32 = 0x0600_0001
        let gutterFg: UInt32 = 0x0600_0002
        let foldCollapsed: UInt32 = 0x0600_0004
        let foldExpanded: UInt32 = 0x0600_0005

        try ui.setStyleColors([
            // Make gutter background visible; keep numbers "invisible" for deterministic pixel tests.
            EcuStyleColors(styleId: gutterBg, background: EcuRgba8(r: 1, g: 2, b: 3, a: 255)),
            EcuStyleColors(styleId: gutterFg, foreground: EcuRgba8(r: 1, g: 2, b: 3, a: 255)),
            EcuStyleColors(styleId: foldExpanded, background: EcuRgba8(r: 9, g: 9, b: 9, a: 255)),
            EcuStyleColors(styleId: foldCollapsed, background: EcuRgba8(r: 8, g: 8, b: 8, a: 255)),
        ])

        var rgba: [UInt8] = []
        _ = try ui.renderRGBA(into: &rgba)
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 5, y: 10), [9, 9, 9, 255])
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 25, y: 10), [1, 2, 3, 255])

        // Click in gutter to toggle fold.
        try ui.mouseDown(xPx: 5, yPx: 10)
        _ = try ui.renderRGBA(into: &rgba)
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 5, y: 10), [8, 8, 8, 255])

        try ui.mouseDown(xPx: 5, yPx: 10)
        _ = try ui.renderRGBA(into: &rgba)
        XCTAssertEqual(pixel(rgba, widthPx: 200, x: 5, y: 10), [9, 9, 9, 255])
    }

    private func pixel(_ buf: [UInt8], widthPx: UInt32, x: UInt32, y: UInt32) -> [UInt8] {
        let idx = Int((y * widthPx + x) * 4)
        return [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
    }
}
