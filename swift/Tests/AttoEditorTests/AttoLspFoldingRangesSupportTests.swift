import EditorCoreUIFFI
@testable import AttoEditor
import XCTest

final class AttoLspFoldingRangesSupportTests: XCTestCase {
    func testAvailabilityUsesTypedFoldingRangeCapability() {
        XCTAssertEqual(
            AttoLspFoldingRangesSupport.availability(
                status: makeStatus(capabilities: EcuLspCapabilities(foldingRanges: true))
            ),
            .available
        )
        XCTAssertEqual(
            AttoLspFoldingRangesSupport.availability(
                status: makeStatus(capabilities: EcuLspCapabilities(foldingRanges: false))
            ),
            .unsupported
        )
    }

    func testAvailabilityIsUnknownWhenCapabilitiesAreMissing() {
        XCTAssertEqual(
            AttoLspFoldingRangesSupport.availability(status: makeStatus(capabilities: nil)),
            .unknown
        )
    }

    func testUnsupportedMessageNamesTheMissingLspCapability() {
        XCTAssertTrue(AttoLspFoldingRangesSupport.unsupportedMessage.contains("textDocument/foldingRange"))
    }

    private func makeStatus(capabilities: EcuLspCapabilities?) -> EcuLspStatusSnapshot {
        EcuLspStatusSnapshot(
            availability: .enabled,
            state: .ready,
            server: nil,
            activity: nil,
            detail: nil,
            capabilities: capabilities
        )
    }
}
