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
        XCTAssertNil(report.loadError)
    }

    func testRejectsOlderUIABI() throws {
        let report = AttoRuntimeCompatibility.evaluate(
            runtimeInfo: EditorCoreUIFFIRuntimeInfo(
                abiVersion: 0,
                version: "test",
                features: allRequiredFeatures()
            )
        )

        XCTAssertFalse(report.isCompatible)
        XCTAssertTrue(report.missingFeatures.isEmpty)
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
        XCTAssertTrue(report.missingFeatures.contains { $0.feature == .lspInteractiveRequests })
        XCTAssertTrue(report.missingFeatures.contains { $0.feature == .lspStatusSnapshot })
        XCTAssertTrue(report.missingFeatures.contains { $0.feature == .workspaceEditApplication })
        XCTAssertTrue(report.missingFeatures.contains { $0.feature == .multiDocumentUI })
        XCTAssertTrue(report.diagnosticMessage.contains("Missing UI FFI features"))
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
}
