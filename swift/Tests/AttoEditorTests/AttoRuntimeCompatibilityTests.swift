import EditorCoreUIFFI
import XCTest
@testable import AttoEditor

@MainActor
final class AttoRuntimeCompatibilityTests: XCTestCase {
    func testCurrentUIFFIRuntimeIsCompatible() throws {
        let report = AttoRuntimeCompatibility.evaluate(library: EditorCoreUIFFILibrary())

        XCTAssertTrue(report.isCompatible, report.diagnosticMessage)
        XCTAssertEqual(report.minimumABIVersion, AttoRuntimeCompatibility.minimumUIABIVersion)
        XCTAssertTrue(report.missingFeatures.isEmpty)
        XCTAssertTrue(report.missingOptionalFeatures.isEmpty)
        XCTAssertNil(report.loadError)
    }

    func testRejectsOlderUIABI() throws {
        let report = AttoRuntimeCompatibility.evaluate(
            runtimeInfo: EditorCoreUIFFIRuntimeInfo(
                abiVersion: 0,
                version: "test",
                features: allKnownFeatures()
            )
        )

        XCTAssertFalse(report.isCompatible)
        XCTAssertTrue(report.missingFeatures.isEmpty)
        XCTAssertTrue(report.missingOptionalFeatures.isEmpty)
        XCTAssertTrue(report.diagnosticMessage.contains("older than required ABI"))
    }

    func testReportsMissingRequiredFeatures() throws {
        let report = AttoRuntimeCompatibility.evaluate(
            runtimeInfo: EditorCoreUIFFIRuntimeInfo(
                abiVersion: AttoRuntimeCompatibility.minimumUIABIVersion,
                version: "test",
                features: [.jsonCommandDispatch]
            )
        )

        XCTAssertFalse(report.isCompatible)
        XCTAssertTrue(report.missingFeatures.contains { $0.feature == .typedDerivedSnapshots })
        XCTAssertTrue(report.missingFeatures.contains { $0.feature == .multiDocumentUI })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .lspInteractiveRequests })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .lspStatusSnapshot })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .lspStatusEnvelope })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .workspaceEditApplication })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .lspWorkspaceEditApplicationEnvelope })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .workspaceDiagnosticsStore })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .lspResultEvents })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .multiDocumentLSPResultEvents })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .lspRequestEvents })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .multiDocumentLSPRequestEvents })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .lspRequestCancelTimeoutEvents })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .lspSemanticTokensRequests })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .editorUIDerivedSnapshotEnvelope })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .editorUIMinimapEnvelope })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .editorUIStateEvents })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .multiDocumentStateEvents })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .multiDocumentSnapshotEnvelope })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .eventStreamEnvelope })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .multiDocumentSpecialEventStreamEnvelope })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .workspaceEditTransactionEnvelope })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .workspaceDiagnosticsEnvelope })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .workspaceOutlineSnapshotEnvelope })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .multiDocumentSearchEnvelope })
        XCTAssertTrue(report.missingOptionalFeatures.contains {
            $0.feature == .multiDocumentWorkspaceRootsChangeEnvelope
        })
        XCTAssertTrue(report.missingOptionalFeatures.contains {
            $0.feature == .multiDocumentProjectLSPServersEnvelope
        })
        XCTAssertTrue(report.diagnosticMessage.contains("Missing UI FFI features"))
    }

    func testMissingOptionalFeaturesDoNotBlockLaunchCompatibility() throws {
        let report = AttoRuntimeCompatibility.evaluate(
            runtimeInfo: EditorCoreUIFFIRuntimeInfo(
                abiVersion: AttoRuntimeCompatibility.minimumUIABIVersion,
                version: "test",
                features: allRequiredFeatures()
            )
        )

        XCTAssertTrue(report.isCompatible, report.diagnosticMessage)
        XCTAssertTrue(report.missingFeatures.isEmpty)
        XCTAssertEqual(
            Set(report.missingOptionalFeatures.map(\.feature.rawValue)),
            Set([
                EditorCoreUIFFIFeatures.lspInteractiveRequests.rawValue,
                EditorCoreUIFFIFeatures.lspStatusSnapshot.rawValue,
                EditorCoreUIFFIFeatures.lspStatusEnvelope.rawValue,
                EditorCoreUIFFIFeatures.workspaceEditApplication.rawValue,
                EditorCoreUIFFIFeatures.lspWorkspaceEditApplicationEnvelope.rawValue,
                EditorCoreUIFFIFeatures.workspaceDiagnosticsStore.rawValue,
                EditorCoreUIFFIFeatures.workspaceDiagnosticsEvents.rawValue,
                EditorCoreUIFFIFeatures.lspResultEvents.rawValue,
                EditorCoreUIFFIFeatures.multiDocumentLSPResultEvents.rawValue,
                EditorCoreUIFFIFeatures.lspRequestEvents.rawValue,
                EditorCoreUIFFIFeatures.multiDocumentLSPRequestEvents.rawValue,
                EditorCoreUIFFIFeatures.lspRequestCancelTimeoutEvents.rawValue,
                EditorCoreUIFFIFeatures.lspSemanticTokensRequests.rawValue,
                EditorCoreUIFFIFeatures.editorUIDerivedSnapshotEnvelope.rawValue,
                EditorCoreUIFFIFeatures.editorUIMinimapEnvelope.rawValue,
                EditorCoreUIFFIFeatures.editorUIStateEvents.rawValue,
                EditorCoreUIFFIFeatures.multiDocumentStateEvents.rawValue,
                EditorCoreUIFFIFeatures.multiDocumentSnapshotEnvelope.rawValue,
                EditorCoreUIFFIFeatures.eventStreamEnvelope.rawValue,
                EditorCoreUIFFIFeatures.multiDocumentSpecialEventStreamEnvelope.rawValue,
                EditorCoreUIFFIFeatures.workspaceEditTransactionEnvelope.rawValue,
                EditorCoreUIFFIFeatures.workspaceDiagnosticsEnvelope.rawValue,
                EditorCoreUIFFIFeatures.workspaceOutlineSnapshotEnvelope.rawValue,
                EditorCoreUIFFIFeatures.multiDocumentSearchEnvelope.rawValue,
                EditorCoreUIFFIFeatures.multiDocumentWorkspaceRootsChangeEnvelope.rawValue,
                EditorCoreUIFFIFeatures.multiDocumentProjectLSPServersEnvelope.rawValue,
                EditorCoreUIFFIFeatures.workspaceOutlineSnapshot.rawValue,
                EditorCoreUIFFIFeatures.multiDocumentTabDocumentURI.rawValue,
                EditorCoreUIFFIFeatures.multiDocumentTabLanguageID.rawValue,
                EditorCoreUIFFIFeatures.multiDocumentWorkspaceEditTransaction.rawValue,
                EditorCoreUIFFIFeatures.multiDocumentWorkspaceEditTransactionEvents.rawValue,
                EditorCoreUIFFIFeatures.multiDocumentWorkspaceRoots.rawValue,
                EditorCoreUIFFIFeatures.multiDocumentWorkspaceEditTransactionUndo.rawValue,
            ])
        )
        XCTAssertTrue(report.diagnosticMessage.contains("Unavailable optional UI FFI features"))
    }

    func testAppDelegateRecordsRuntimeCompatibilityReport() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])

        XCTAssertTrue(delegate._validateRuntimeCompatibilityForTesting())

        let report = try XCTUnwrap(delegate._runtimeCompatibilityReportForTesting())
        XCTAssertTrue(report.isCompatible, report.diagnosticMessage)
    }

    func testCapabilitySnapshotSummarizesRuntimeAndLspCapabilities() throws {
        let runtimeInfo = EditorCoreUIFFIRuntimeInfo(
            abiVersion: AttoRuntimeCompatibility.minimumUIABIVersion,
            version: "test-runtime",
            features: [.jsonCommandDispatch, .multiDocumentUI, .lspStatusSnapshot]
        )
        let report = AttoRuntimeCompatibility.evaluate(runtimeInfo: runtimeInfo)
        let lspCapabilities = EcuLspCapabilities(
            semanticTokens: true,
            semanticTokensDelta: false,
            completionItemResolve: true,
            completion: EcuLspCompletionCapability(
                supported: true,
                triggerCharacters: [".", ":"],
                allCommitCharacters: [";", ")"]
            ),
            foldingRanges: true,
            onTypeFormatting: true,
            signatureHelp: EcuLspSignatureHelpCapability(
                supported: true,
                triggerCharacters: ["("],
                retriggerCharacters: [","]
            )
        )

        let snapshot = AttoCapabilitySnapshot(
            runtimeReport: report,
            lspCapabilities: lspCapabilities,
            platform: AttoPlatformCapabilitySnapshot(
                operatingSystem: "macOS",
                operatingSystemVersion: "14.0.0",
                architecture: "arm64",
                supportsAppKit: true,
                supportsNativeFileDialogs: true,
                supportsChildWindows: true
            ),
            app: AttoAppCapabilitySnapshot(
                supportsCommandPalette: true,
                supportsMenuCommandValidation: true,
                supportsUserDefaultsPersistence: true,
                supportsWorkspaceSessions: true,
                supportsMultipleWindows: true
            )
        )

        XCTAssertEqual(snapshot.schemaVersion, AttoCapabilitySnapshot.currentSchemaVersion)
        XCTAssertEqual(snapshot.uiRuntime?.abiVersion, AttoRuntimeCompatibility.minimumUIABIVersion)
        XCTAssertEqual(snapshot.uiRuntime?.version, "test-runtime")
        XCTAssertEqual(snapshot.uiRuntime?.rawFeatureFlags, runtimeInfo.features.rawValue)
        XCTAssertEqual(
            snapshot.uiRuntime?.knownFeatureNames,
            ["JSON command dispatch", "multi-document UI", "LSP status snapshot"]
        )
        XCTAssertTrue(snapshot.requiredUIFeatures.contains { $0.name == "typed derived snapshots" })
        XCTAssertTrue(snapshot.missingRequiredUIFeatures.contains("typed derived snapshots"))
        XCTAssertFalse(snapshot.missingOptionalUIFeatures.contains("LSP status snapshot"))
        XCTAssertEqual(snapshot.lsp?.semanticTokens, true)
        XCTAssertEqual(snapshot.lsp?.completionTriggerCharacters, [".", ":"])
        XCTAssertEqual(snapshot.lsp?.completionCommitCharacters, [";", ")"])
        XCTAssertEqual(snapshot.lsp?.signatureHelpTriggerCharacters, ["("])
        XCTAssertEqual(snapshot.platform.operatingSystemVersion, "14.0.0")
        XCTAssertTrue(snapshot.app.supportsWorkspaceSessions)

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(snapshot)
        let json = try XCTUnwrap(String(data: data, encoding: .utf8))
        XCTAssertTrue(json.contains(#""ui_runtime""#))
        XCTAssertTrue(json.contains(#""completion_trigger_characters":[".",":"]"#))

        let decoded = try JSONDecoder().decode(AttoCapabilitySnapshot.self, from: data)
        XCTAssertEqual(decoded, snapshot)
    }

    func testCapabilitySnapshotIgnoresUnknownFutureFields() throws {
        let json = """
        {
          "schema_version": 1,
          "ui_runtime": {
            "abi_version": 1,
            "version": "test",
            "raw_feature_flags": 3,
            "known_feature_names": ["JSON command dispatch"],
            "future_runtime_field": true
          },
          "required_ui_features": [],
          "optional_ui_features": [],
          "missing_required_ui_features": [],
          "missing_optional_ui_features": [],
          "lsp": {
            "semantic_tokens": true,
            "semantic_tokens_delta": false,
            "completion_supported": true,
            "completion_item_resolve": false,
            "completion_trigger_characters": ["."],
            "completion_commit_characters": [],
            "folding_ranges": true,
            "on_type_formatting": false,
            "signature_help_supported": false,
            "signature_help_trigger_characters": [],
            "signature_help_retrigger_characters": [],
            "future_lsp_field": "ignored"
          },
          "platform": {
            "operating_system": "macOS",
            "operating_system_version": "14.0.0",
            "architecture": "arm64",
            "supports_app_kit": true,
            "supports_native_file_dialogs": true,
            "supports_child_windows": true,
            "future_platform_field": "ignored"
          },
          "app": {
            "supports_command_palette": true,
            "supports_menu_command_validation": true,
            "supports_user_defaults_persistence": true,
            "supports_workspace_sessions": true,
            "supports_multiple_windows": true,
            "future_app_field": "ignored"
          },
          "load_error": null,
          "future_top_level": "ignored"
        }
        """

        let data = try XCTUnwrap(json.data(using: .utf8))
        let snapshot = try JSONDecoder().decode(AttoCapabilitySnapshot.self, from: data)

        XCTAssertEqual(snapshot.uiRuntime?.version, "test")
        XCTAssertEqual(snapshot.lsp?.semanticTokens, true)
        XCTAssertEqual(snapshot.lsp?.completionTriggerCharacters, ["."])
        XCTAssertEqual(snapshot.platform.architecture, "arm64")
        XCTAssertTrue(snapshot.app.supportsCommandPalette)
    }

    private func allRequiredFeatures() -> EditorCoreUIFFIFeatures {
        AttoRuntimeCompatibility.requiredFeatures.reduce([]) { acc, required in
            acc.union(required.feature)
        }
    }

    private func allKnownFeatures() -> EditorCoreUIFFIFeatures {
        AttoRuntimeCompatibility.optionalFeatures.reduce(allRequiredFeatures()) { acc, optional in
            acc.union(optional.feature)
        }
    }
}
