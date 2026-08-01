import XCTest
@testable import AttoEditor

final class AttoLspStatusFormatterTests: XCTestCase {
    func testFormatsReadyStatusWithServerName() {
        let display = AttoLspStatusFormatter.display(
            statusJSON: #"{"state":"ready","server":{"name":"rust-analyzer"}}"#,
            fallbackEnabled: true
        )

        XCTAssertEqual(display.text, "LSP rust-analyzer: Ready")
        XCTAssertNil(display.failureDetail)
    }

    func testFormatsIndexingActivityWithPercentage() {
        let display = AttoLspStatusFormatter.display(
            statusJSON: #"{"state":"indexing","activity":{"title":"Indexing crates","percentage":42}}"#,
            fallbackEnabled: true
        )

        XCTAssertEqual(display.text, "LSP: Indexing crates 42%")
        XCTAssertNil(display.failureDetail)
    }

    func testFormatsFailedStatusWithDetailForHud() {
        let display = AttoLspStatusFormatter.display(
            statusJSON: #"{"state":"failed","detail":"formatter exploded","server":{"command":"fake-lsp"}}"#,
            fallbackEnabled: true
        )

        XCTAssertEqual(display.text, "LSP fake-lsp: Failed")
        XCTAssertEqual(display.failureDetail, "formatter exploded")
    }

    func testInvalidStatusJSONFallsBackToEnabledText() {
        let display = AttoLspStatusFormatter.display(statusJSON: "not json", fallbackEnabled: true)

        XCTAssertEqual(display.text, "LSP: on")
        XCTAssertNil(display.failureDetail)
    }
}
