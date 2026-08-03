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
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .lspResultEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .eventStreamEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .multiDocumentSpecialEventStreamEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .workspaceEditTransactionEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .workspaceDiagnosticsEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .workspaceOutlineSnapshotEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains { $0.feature == .multiDocumentSearchEnvelope })
        XCTAssertTrue(report.missingRequiredFeatures.contains {
            $0.feature == .multiDocumentWorkspaceRootsChangeEnvelope
        })
        XCTAssertTrue(report.missingRequiredFeatures.contains {
            $0.feature == .multiDocumentProjectLSPServersEnvelope
        })
        XCTAssertTrue(report.diagnosticMessage.contains("Missing UI FFI features"))
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
        let future = EditorCoreUIFFIFeatures(rawValue: 1 << 40)
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
