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
        XCTAssertTrue(report.diagnosticMessage.contains("Missing core FFI features"))
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
