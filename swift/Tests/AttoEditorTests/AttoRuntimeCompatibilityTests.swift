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
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .workspaceEditApplication })
        XCTAssertTrue(report.missingOptionalFeatures.contains { $0.feature == .workspaceDiagnosticsStore })
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
                EditorCoreUIFFIFeatures.workspaceEditApplication.rawValue,
                EditorCoreUIFFIFeatures.workspaceDiagnosticsStore.rawValue,
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
