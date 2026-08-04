import XCTest
@testable import EditorCoreUIFFI

final class EditorCoreUIFFIRuntimeCompatibilityTests: XCTestCase {
    func testCurrentRuntimeIsCompatible() throws {
        let library = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let report = EditorCoreUIFFIRuntimeCompatibility.evaluate(library: library)

        XCTAssertTrue(report.isCompatible, report.diagnosticMessage)
        XCTAssertEqual(report.minimumABIVersion, EditorCoreUIFFIRuntimeCompatibility.minimumABIVersion)
        XCTAssertTrue(report.missingRequiredFeatures.isEmpty)
        XCTAssertTrue(report.missingOptionalFeatures.isEmpty)
        XCTAssertNil(report.loadError)
        XCTAssertTrue(report.diagnosticMessage.contains("compatible"))
    }

    func testEvaluatesCapabilitySnapshot() throws {
        let library = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let snapshot = try library.runtimeCapabilitySnapshot()
        let report = EditorCoreUIFFIRuntimeCompatibility.evaluate(capabilitySnapshot: snapshot)

        XCTAssertTrue(report.isCompatible, report.diagnosticMessage)
        XCTAssertEqual(report.runtimeInfo, snapshot.runtimeInfo)
        XCTAssertTrue(report.missingRequiredFeatures.isEmpty)
        XCTAssertTrue(report.missingOptionalFeatures.isEmpty)
        XCTAssertNil(report.loadError)
    }

    func testCapabilitySnapshotReportsMissingFeatures() throws {
        let required = try feature(.jsonCommandEnvelope)
        let optional = try feature(.lspSemanticTokensApplicationEnvelope)
        let snapshot = EditorCoreUIFFIRuntimeCapabilitySnapshot(
            kind: "editor-core-ui-ffi",
            abiVersion: EditorCoreUIFFIRuntimeCompatibility.minimumABIVersion,
            version: "test-runtime",
            featureFlags: [.jsonCommandDispatch],
            features: [
                EditorCoreUIFFIRuntimeFeatureDescriptor(
                    bit: 0,
                    flag: EditorCoreUIFFIFeatures.jsonCommandDispatch.rawValue,
                    name: "json_command_dispatch",
                    description: "test descriptor"
                ),
            ]
        )

        let report = EditorCoreUIFFIRuntimeCompatibility.evaluate(
            capabilitySnapshot: snapshot,
            requiredFeatures: [required],
            optionalFeatures: [optional]
        )

        XCTAssertFalse(report.isCompatible)
        XCTAssertEqual(report.runtimeInfo, snapshot.runtimeInfo)
        XCTAssertEqual(report.missingRequiredFeatures, [required])
        XCTAssertEqual(report.missingOptionalFeatures, [optional])
        XCTAssertNil(report.loadError)
    }

    func testCapabilitySnapshotNegotiatesFeatureAvailabilityAndReasons() throws {
        let required = try feature(.jsonCommandDispatch)
        let optional = try feature(.lspSemanticTokensApplicationEnvelope)
        let snapshot = EditorCoreUIFFIRuntimeCapabilitySnapshot(
            kind: "editor-core-ui-ffi",
            abiVersion: EditorCoreUIFFIRuntimeCompatibility.minimumABIVersion,
            version: "test-runtime",
            featureFlags: [.jsonCommandDispatch],
            features: [
                EditorCoreUIFFIRuntimeFeatureDescriptor(
                    bit: 0,
                    flag: EditorCoreUIFFIFeatures.jsonCommandDispatch.rawValue,
                    name: "json_command_dispatch",
                    description: "test descriptor"
                ),
            ]
        )

        let report = EditorCoreUIFFIRuntimeCompatibility.evaluate(
            capabilitySnapshot: snapshot,
            requiredFeatures: [required],
            optionalFeatures: [optional]
        )

        let dispatch = try XCTUnwrap(
            report.negotiatedFeatures.first { $0.feature == .jsonCommandDispatch }
        )
        XCTAssertTrue(dispatch.isRequired)
        XCTAssertTrue(dispatch.isAvailable)
        XCTAssertEqual(dispatch.availability, .available)
        XCTAssertEqual(dispatch.featureFlag, EditorCoreUIFFIFeatures.jsonCommandDispatch.rawValue)
        XCTAssertEqual(dispatch.runtimeFeatureFlags, snapshot.featureFlags.rawValue)
        XCTAssertEqual(dispatch.runtimeABIVersion, snapshot.abiVersion)
        XCTAssertEqual(dispatch.runtimeVersion, snapshot.version)
        XCTAssertEqual(dispatch.descriptor?.name, "json_command_dispatch")
        XCTAssertNil(dispatch.unsupportedReason)

        let semanticTokens = try XCTUnwrap(
            report.negotiatedFeatures.first { $0.feature == .lspSemanticTokensApplicationEnvelope }
        )
        XCTAssertFalse(semanticTokens.isRequired)
        XCTAssertFalse(semanticTokens.isAvailable)
        XCTAssertEqual(semanticTokens.availability, .unsupported)
        XCTAssertEqual(
            semanticTokens.featureFlag,
            EditorCoreUIFFIFeatures.lspSemanticTokensApplicationEnvelope.rawValue
        )
        XCTAssertNil(semanticTokens.descriptor)
        XCTAssertTrue(semanticTokens.unsupportedReason?.contains(optional.reason) ?? false)
        XCTAssertTrue(
            semanticTokens.unsupportedReason?.contains(semanticTokens.featureFlagHexForTest) ?? false
        )
    }

    func testRejectsOlderABI() throws {
        let report = EditorCoreUIFFIRuntimeCompatibility.evaluate(
            runtimeInfo: EditorCoreUIFFIRuntimeInfo(
                abiVersion: 0,
                version: "test-runtime",
                features: allKnownFeatures()
            )
        )

        XCTAssertFalse(report.isCompatible)
        XCTAssertTrue(report.missingRequiredFeatures.isEmpty)
        XCTAssertTrue(report.missingOptionalFeatures.isEmpty)
        XCTAssertTrue(report.diagnosticMessage.contains("older than required ABI"))
    }

    func testNegotiatesVersionMismatchReason() throws {
        let required = try feature(.jsonCommandEnvelope)
        let runtimeInfo = EditorCoreUIFFIRuntimeInfo(
            abiVersion: 0,
            version: "old-runtime",
            features: allKnownFeatures()
        )

        let report = EditorCoreUIFFIRuntimeCompatibility.evaluate(
            runtimeInfo: runtimeInfo,
            requiredFeatures: [required]
        )

        let envelope = try XCTUnwrap(
            report.negotiatedFeatures.first { $0.feature == .jsonCommandEnvelope }
        )
        XCTAssertFalse(envelope.isAvailable)
        XCTAssertEqual(envelope.availability, .versionMismatch)
        XCTAssertEqual(envelope.runtimeABIVersion, 0)
        XCTAssertEqual(envelope.runtimeVersion, "old-runtime")
        XCTAssertEqual(envelope.runtimeFeatureFlags, runtimeInfo.features.rawValue)
        XCTAssertTrue(envelope.unsupportedReason?.contains("requires UI FFI ABI") ?? false)
    }

    func testReportsRuntimeInfoLoadFailure() {
        let required = EditorCoreUIFFIRuntimeFeature(
            feature: .jsonCommandEnvelope,
            name: "JSON command envelope",
            reason: "required by the test host"
        )
        let optional = EditorCoreUIFFIRuntimeFeature(
            feature: .lspSemanticTokensApplicationEnvelope,
            name: "LSP semantic tokens application envelope",
            reason: "optional by the test host"
        )
        let report = EditorCoreUIFFIRuntimeCompatibilityReport(
            runtimeInfo: nil,
            minimumABIVersion: EditorCoreUIFFIRuntimeCompatibility.minimumABIVersion,
            missingRequiredFeatures: [required],
            missingOptionalFeatures: [optional],
            loadError: "runtime_info_json returned null"
        )

        XCTAssertFalse(report.isCompatible)
        XCTAssertNil(report.runtimeInfo)
        XCTAssertEqual(report.loadError, "runtime_info_json returned null")
        XCTAssertEqual(report.missingRequiredFeatures, [required])
        XCTAssertEqual(report.missingOptionalFeatures, [optional])
        XCTAssertTrue(report.diagnosticMessage.contains("Failed to read UI FFI runtime information"))
        XCTAssertTrue(report.diagnosticMessage.contains("runtime_info_json returned null"))
        XCTAssertFalse(report.diagnosticMessage.contains("Missing UI FFI features"))
    }

    func testReportsMissingRequiredFeatures() throws {
        let report = EditorCoreUIFFIRuntimeCompatibility.evaluate(
            runtimeInfo: EditorCoreUIFFIRuntimeInfo(
                abiVersion: EditorCoreUIFFIRuntimeCompatibility.minimumABIVersion,
                version: "test-runtime",
                features: [.jsonCommandDispatch]
            )
        )

        XCTAssertFalse(report.isCompatible)
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .typedDerivedSnapshots })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .multiDocumentUI })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .multiDocumentSnapshotEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .jsonCommandEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .editorUIDerivedSnapshotEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .editorUIMinimapEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .editorUIViewPointPayloadEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .lspStatusEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .lspResultEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .eventStreamEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .multiDocumentSpecialEventStreamEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .workspaceEditTransactionEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .workspaceDiagnosticsEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .workspaceOutlineSnapshotEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .multiDocumentSearchEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .multiDocumentWorkspaceFileSearch })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .multiDocumentWorkspaceFileReplacement })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .multiDocumentRecentFiles })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .multiDocumentWorkspaceFileList })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .multiDocumentRecentProjects })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .multiDocumentProjectFileIndex })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .multiDocumentProjectFileIndexQuery })
        XCTAssertTrue(report.missingRequiredFeatures.contains {
            $0.feature == .multiDocumentWorkspaceFileOperationEnvelope
        })
        XCTAssertTrue(report.missingRequiredFeatures.contains {
            $0.feature == .multiDocumentWorkspaceFileScanOptions
        })
        XCTAssertTrue(report.missingRequiredFeatures.contains {
            $0.feature == .lspWorkspaceEditApplicationEnvelope
        })
        XCTAssertTrue(report.missingRequiredFeatures.contains {
            $0.feature == .lspDerivedStateApplicationEnvelope
        })
        XCTAssertTrue(report.missingRequiredFeatures.contains {
            $0.feature == .lspSemanticTokensApplicationEnvelope
        })
        XCTAssertTrue(report.missingRequiredFeatures.contains {
            $0.feature == .multiDocumentWorkspaceRootsChangeEnvelope
        })
        XCTAssertTrue(report.missingRequiredFeatures.contains {
            $0.feature == .multiDocumentProjectLSPServersEnvelope
        })
        XCTAssertTrue(report.missingRequiredFeatures.contains {
            $0.feature == .multiDocumentProjectLSPLifecycleEnvelope
        })
        XCTAssertTrue(report.diagnosticMessage.contains("Missing UI FFI features"))
    }

    func testReportsOlderABIAndFeatureMismatchesTogether() throws {
        let required = try feature(.jsonCommandEnvelope)
        let optional = try feature(.lspSemanticTokensApplicationEnvelope)
        let report = EditorCoreUIFFIRuntimeCompatibility.evaluate(
            runtimeInfo: EditorCoreUIFFIRuntimeInfo(
                abiVersion: 0,
                version: "test-runtime",
                features: []
            ),
            requiredFeatures: [required],
            optionalFeatures: [optional]
        )

        XCTAssertFalse(report.isCompatible)
        XCTAssertNil(report.loadError)
        XCTAssertEqual(report.missingRequiredFeatures, [required])
        XCTAssertEqual(report.missingOptionalFeatures, [optional])
        XCTAssertTrue(report.diagnosticMessage.contains("older than required ABI"))
        XCTAssertTrue(report.diagnosticMessage.contains("Missing UI FFI features: JSON command envelope"))
        XCTAssertTrue(report.diagnosticMessage.contains("Unavailable optional UI FFI features: LSP semantic tokens application envelope"))
    }

    func testMissingOptionalFeaturesDoNotBlockCompatibility() throws {
        let jsonCommand = try feature(.jsonCommandDispatch)
        let envelope = try feature(.jsonCommandEnvelope)
        let report = EditorCoreUIFFIRuntimeCompatibility.evaluate(
            runtimeInfo: EditorCoreUIFFIRuntimeInfo(
                abiVersion: EditorCoreUIFFIRuntimeCompatibility.minimumABIVersion,
                version: "test-runtime",
                features: [.jsonCommandDispatch]
            ),
            requiredFeatures: [jsonCommand],
            optionalFeatures: [envelope]
        )

        XCTAssertTrue(report.isCompatible, report.diagnosticMessage)
        XCTAssertTrue(report.missingRequiredFeatures.isEmpty)
        XCTAssertEqual(report.missingOptionalFeatures.map(\.feature.rawValue), [EditorCoreUIFFIFeatures.jsonCommandEnvelope.rawValue])
        XCTAssertTrue(report.diagnosticMessage.contains("Unavailable optional UI FFI features"))
    }

    func testUnknownFutureFeatureBitsArePreservedAndIgnored() throws {
        let future = EditorCoreUIFFIFeatures(rawValue: 1 << 62)
        let features = allKnownFeatures().union(future)
        let runtimeInfo = EditorCoreUIFFIRuntimeInfo(
            abiVersion: EditorCoreUIFFIRuntimeCompatibility.minimumABIVersion,
            version: "future-runtime",
            features: features
        )
        let report = EditorCoreUIFFIRuntimeCompatibility.evaluate(runtimeInfo: runtimeInfo)

        XCTAssertTrue(report.isCompatible, report.diagnosticMessage)
        XCTAssertTrue(report.runtimeInfo?.features.contains(future) ?? false)
        XCTAssertTrue(report.missingRequiredFeatures.isEmpty)
    }

    private func allKnownFeatures() -> EditorCoreUIFFIFeatures {
        EditorCoreUIFFIRuntimeCompatibility.knownFeatures.reduce([]) { acc, feature in
            acc.union(feature.feature)
        }
    }

    private func feature(_ value: EditorCoreUIFFIFeatures) throws -> EditorCoreUIFFIRuntimeFeature {
        try XCTUnwrap(EditorCoreUIFFIRuntimeCompatibility.knownFeatures.first { $0.feature == value })
    }
}

private extension EditorCoreUIFFIRuntimeFeatureNegotiation {
    var featureFlagHexForTest: String {
        "0x" + String(featureFlag, radix: 16, uppercase: false)
    }
}
