import XCTest
@testable import EditorCoreFFI

final class EditorCoreFFIRuntimeCompatibilityTests: XCTestCase {
    func testCurrentRuntimeIsCompatible() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let report = EditorCoreFFIRuntimeCompatibility.evaluate(library: library)

        XCTAssertTrue(report.isCompatible, report.diagnosticMessage)
        XCTAssertEqual(report.minimumABIVersion, EditorCoreFFIRuntimeCompatibility.minimumABIVersion)
        XCTAssertTrue(report.missingRequiredFeatures.isEmpty)
        XCTAssertTrue(report.missingOptionalFeatures.isEmpty)
        XCTAssertNil(report.loadError)
        XCTAssertTrue(report.diagnosticMessage.contains("compatible"))
    }

    func testEvaluatesCapabilitySnapshot() throws {
        let library = try EditorCoreFFITestSupport.shared.loadLibrary()
        let snapshot = try library.runtimeCapabilitySnapshot()
        let report = EditorCoreFFIRuntimeCompatibility.evaluate(capabilitySnapshot: snapshot)

        XCTAssertTrue(report.isCompatible, report.diagnosticMessage)
        XCTAssertEqual(report.runtimeInfo, snapshot.runtimeInfo)
        XCTAssertTrue(report.missingRequiredFeatures.isEmpty)
        XCTAssertTrue(report.missingOptionalFeatures.isEmpty)
        XCTAssertNil(report.loadError)
    }

    func testCapabilitySnapshotReportsMissingFeatures() throws {
        let required = try feature(.jsonCommandEnvelope)
        let optional = try feature(.processorResultEnvelope)
        let snapshot = EditorCoreFFIRuntimeCapabilitySnapshot(
            kind: "editor-core-ffi",
            abiVersion: EditorCoreFFIRuntimeCompatibility.minimumABIVersion,
            version: "test-runtime",
            featureFlags: [.jsonCommandDispatch],
            features: [
                EditorCoreFFIRuntimeFeatureDescriptor(
                    bit: 0,
                    flag: EditorCoreFFIFeatures.jsonCommandDispatch.rawValue,
                    name: "json_command_dispatch",
                    description: "test descriptor"
                ),
            ]
        )

        let report = EditorCoreFFIRuntimeCompatibility.evaluate(
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

    func testRejectsOlderABI() throws {
        let report = EditorCoreFFIRuntimeCompatibility.evaluate(
            runtimeInfo: EditorCoreFFIRuntimeInfo(
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

    func testReportsRuntimeInfoLoadFailure() {
        let required = EditorCoreFFIRuntimeFeature(
            feature: .jsonCommandEnvelope,
            name: "JSON command envelope",
            reason: "required by the test host"
        )
        let optional = EditorCoreFFIRuntimeFeature(
            feature: .processorResultEnvelope,
            name: "processor result envelope",
            reason: "optional by the test host"
        )
        let report = EditorCoreFFIRuntimeCompatibilityReport(
            runtimeInfo: nil,
            minimumABIVersion: EditorCoreFFIRuntimeCompatibility.minimumABIVersion,
            missingRequiredFeatures: [required],
            missingOptionalFeatures: [optional],
            loadError: "runtime_info_json returned null"
        )

        XCTAssertFalse(report.isCompatible)
        XCTAssertNil(report.runtimeInfo)
        XCTAssertEqual(report.loadError, "runtime_info_json returned null")
        XCTAssertEqual(report.missingRequiredFeatures, [required])
        XCTAssertEqual(report.missingOptionalFeatures, [optional])
        XCTAssertTrue(report.diagnosticMessage.contains("Failed to read core runtime information"))
        XCTAssertTrue(report.diagnosticMessage.contains("runtime_info_json returned null"))
        XCTAssertFalse(report.diagnosticMessage.contains("Missing core FFI features"))
    }

    func testReportsMissingRequiredFeatures() throws {
        let report = EditorCoreFFIRuntimeCompatibility.evaluate(
            runtimeInfo: EditorCoreFFIRuntimeInfo(
                abiVersion: EditorCoreFFIRuntimeCompatibility.minimumABIVersion,
                version: "test-runtime",
                features: [.jsonCommandDispatch]
            )
        )

        XCTAssertFalse(report.isCompatible)
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .typedHotPath })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .workspaceTypedAPI })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .jsonCommandEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .renderingSnapshotEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .editorStateDerivedSnapshotEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .workspaceResultEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .workspaceQueryEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .workspaceLifecycleEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .editorStateQueryEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .lspHelperEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .lspEditHelperEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .processorResultEnvelope })
        XCTAssertTrue(report.diagnosticMessage.contains("Missing core FFI features"))
    }

    func testReportsOlderABIAndFeatureMismatchesTogether() throws {
        let required = try feature(.jsonCommandEnvelope)
        let optional = try feature(.processorResultEnvelope)
        let report = EditorCoreFFIRuntimeCompatibility.evaluate(
            runtimeInfo: EditorCoreFFIRuntimeInfo(
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
        XCTAssertTrue(report.diagnosticMessage.contains("Missing core FFI features: JSON command envelope"))
        XCTAssertTrue(report.diagnosticMessage.contains("Unavailable optional core FFI features: processor result envelope"))
    }

    func testMissingOptionalFeaturesDoNotBlockCompatibility() throws {
        let jsonCommand = try feature(.jsonCommandDispatch)
        let envelope = try feature(.jsonCommandEnvelope)
        let report = EditorCoreFFIRuntimeCompatibility.evaluate(
            runtimeInfo: EditorCoreFFIRuntimeInfo(
                abiVersion: EditorCoreFFIRuntimeCompatibility.minimumABIVersion,
                version: "test-runtime",
                features: [.jsonCommandDispatch]
            ),
            requiredFeatures: [jsonCommand],
            optionalFeatures: [envelope]
        )

        XCTAssertTrue(report.isCompatible, report.diagnosticMessage)
        XCTAssertTrue(report.missingRequiredFeatures.isEmpty)
        XCTAssertEqual(report.missingOptionalFeatures.map(\.feature.rawValue), [EditorCoreFFIFeatures.jsonCommandEnvelope.rawValue])
        XCTAssertTrue(report.diagnosticMessage.contains("Unavailable optional core FFI features"))
    }

    func testUnknownFutureFeatureBitsArePreservedAndIgnored() throws {
        let future = EditorCoreFFIFeatures(rawValue: 1 << 40)
        let features = allKnownFeatures().union(future)
        let runtimeInfo = EditorCoreFFIRuntimeInfo(
            abiVersion: EditorCoreFFIRuntimeCompatibility.minimumABIVersion,
            version: "future-runtime",
            features: features
        )
        let report = EditorCoreFFIRuntimeCompatibility.evaluate(runtimeInfo: runtimeInfo)

        XCTAssertTrue(report.isCompatible, report.diagnosticMessage)
        XCTAssertTrue(report.runtimeInfo?.features.contains(future) ?? false)
        XCTAssertTrue(report.missingRequiredFeatures.isEmpty)
    }

    private func allKnownFeatures() -> EditorCoreFFIFeatures {
        EditorCoreFFIRuntimeCompatibility.knownFeatures.reduce([]) { acc, feature in
            acc.union(feature.feature)
        }
    }

    private func feature(_ value: EditorCoreFFIFeatures) throws -> EditorCoreFFIRuntimeFeature {
        try XCTUnwrap(EditorCoreFFIRuntimeCompatibility.knownFeatures.first { $0.feature == value })
    }
}
