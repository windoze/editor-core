import EditorCoreUIFFI
import Foundation
import XCTest

extension EditorCoreUIFFITests {
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
        XCTAssertTrue(info.supports(.multiDocumentWorkspaceEditTransactionRedo))
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
        XCTAssertTrue(info.supports(.editorUIMinimapEnvelope))
        XCTAssertTrue(info.supports(.editorUIViewPointPayloadEnvelope))
        XCTAssertTrue(info.supports(.multiDocumentProjectLSPStartPlan))
        XCTAssertTrue(info.supports(.multiDocumentProjectLSPLifecycleEvents))
        XCTAssertTrue(info.supports(.multiDocumentProjectLSPStopPlan))
        XCTAssertTrue(info.supports(.multiDocumentProjectLSPRestartPlan))
        XCTAssertTrue(info.supports(.multiDocumentProjectLSPLifecycleEnvelope))
        XCTAssertTrue(info.supports(.lspDerivedStateApplicationEnvelope))
        XCTAssertTrue(info.supports(.lspSemanticTokensApplicationEnvelope))
        XCTAssertTrue(info.supports(.multiDocumentWorkspaceFileSearch))
        XCTAssertTrue(info.supports(.multiDocumentWorkspaceFileReplacement))
        XCTAssertTrue(info.supports(.multiDocumentRecentFiles))
        XCTAssertTrue(info.supports(.multiDocumentWorkspaceFileList))
        XCTAssertTrue(info.supports(.multiDocumentRecentProjects))
        XCTAssertTrue(info.supports(.multiDocumentProjectFileIndex))
        XCTAssertTrue(info.supports(.multiDocumentProjectFileIndexQuery))
        XCTAssertTrue(info.supports(.multiDocumentWorkspaceFileOperationEnvelope))

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
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "editor_ui_minimap_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 39
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.editorUIMinimapEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_workspace_edit_transaction_redo"
                && (feature["bit"] as? NSNumber)?.uint8Value == 40
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.multiDocumentWorkspaceEditTransactionRedo.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "editor_ui_view_point_payload_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 41
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.editorUIViewPointPayloadEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_project_lsp_start_plan"
                && (feature["bit"] as? NSNumber)?.uint8Value == 42
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.multiDocumentProjectLSPStartPlan.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_project_lsp_lifecycle_events"
                && (feature["bit"] as? NSNumber)?.uint8Value == 43
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.multiDocumentProjectLSPLifecycleEvents.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_project_lsp_stop_plan"
                && (feature["bit"] as? NSNumber)?.uint8Value == 44
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.multiDocumentProjectLSPStopPlan.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_project_lsp_restart_plan"
                && (feature["bit"] as? NSNumber)?.uint8Value == 45
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.multiDocumentProjectLSPRestartPlan.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_project_lsp_lifecycle_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 46
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.multiDocumentProjectLSPLifecycleEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "lsp_derived_state_application_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 47
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.lspDerivedStateApplicationEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "lsp_semantic_tokens_application_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 48
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.lspSemanticTokensApplicationEnvelope.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_workspace_file_search"
                && (feature["bit"] as? NSNumber)?.uint8Value == 49
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.multiDocumentWorkspaceFileSearch.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_workspace_file_replacement"
                && (feature["bit"] as? NSNumber)?.uint8Value == 50
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.multiDocumentWorkspaceFileReplacement.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_recent_files"
                && (feature["bit"] as? NSNumber)?.uint8Value == 51
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.multiDocumentRecentFiles.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_workspace_file_list"
                && (feature["bit"] as? NSNumber)?.uint8Value == 52
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.multiDocumentWorkspaceFileList.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_recent_projects"
                && (feature["bit"] as? NSNumber)?.uint8Value == 53
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.multiDocumentRecentProjects.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_project_file_index"
                && (feature["bit"] as? NSNumber)?.uint8Value == 54
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.multiDocumentProjectFileIndex.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_project_file_index_query"
                && (feature["bit"] as? NSNumber)?.uint8Value == 55
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.multiDocumentProjectFileIndexQuery.rawValue
        })
        XCTAssertTrue(features.contains { feature in
            feature["name"] as? String == "multi_document_workspace_file_operation_envelope"
                && (feature["bit"] as? NSNumber)?.uint8Value == 56
                && (feature["flag"] as? NSNumber)?.uint64Value
                    == EditorCoreUIFFIFeatures.multiDocumentWorkspaceFileOperationEnvelope.rawValue
        })
    }

    func testRuntimeInfoJSONDescriptorsCoverKnownFeatures() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let runtimeJSON = try JSONTestHelpers.object(try lib.runtimeInfoJSON())
        let features = try XCTUnwrap(runtimeJSON["features"] as? [[String: Any]])

        for knownFeature in EditorCoreUIFFIRuntimeCompatibility.knownFeatures {
            let flag = knownFeature.feature.rawValue
            let descriptor = try XCTUnwrap(
                features.first { feature in
                    (feature["flag"] as? NSNumber)?.uint64Value == flag
                },
                "missing runtime descriptor for \(knownFeature.name)"
            )
            XCTAssertEqual(
                (descriptor["bit"] as? NSNumber)?.intValue,
                flag.trailingZeroBitCount,
                "wrong runtime descriptor bit for \(knownFeature.name)"
            )
            XCTAssertFalse((descriptor["name"] as? String ?? "").isEmpty)
            XCTAssertFalse((descriptor["description"] as? String ?? "").isEmpty)
        }
    }

    func testRuntimeCapabilitySnapshotDecodesFeatureDescriptors() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let snapshot = try lib.runtimeCapabilitySnapshot()

        XCTAssertEqual(snapshot.kind, "editor-core-ui-ffi")
        XCTAssertEqual(snapshot.abiVersion, lib.abiVersion)
        XCTAssertEqual(snapshot.featureFlags, lib.featureFlags)
        XCTAssertEqual(snapshot.runtimeInfo, try lib.runtimeInfo())
        XCTAssertTrue(snapshot.supports(.lspSemanticTokensApplicationEnvelope))

        let descriptor = try XCTUnwrap(
            snapshot.features.first { $0.feature == .lspSemanticTokensApplicationEnvelope }
        )
        XCTAssertEqual(descriptor.bit, 48)
        XCTAssertEqual(descriptor.flag, EditorCoreUIFFIFeatures.lspSemanticTokensApplicationEnvelope.rawValue)
        XCTAssertEqual(descriptor.name, "lsp_semantic_tokens_application_envelope")
        XCTAssertFalse(descriptor.description.isEmpty)
    }
}
