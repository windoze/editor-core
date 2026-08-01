@testable import AttoEditor
import XCTest

final class AttoLspSymbolRequestFeedbackTests: XCTestCase {
    func testUnavailableMessagesNameSymbolScopeAndLsp() {
        XCTAssertEqual(
            AttoLspSymbolRequestFeedback.unavailableMessage(kind: .document),
            "Document symbols are unavailable.\nLSP is not enabled for this document."
        )
        XCTAssertEqual(
            AttoLspSymbolRequestFeedback.unavailableMessage(kind: .workspace),
            "Workspace symbols are unavailable.\nLSP is not enabled for this document."
        )
    }

    func testFailureAndTimeoutMessagesNameSymbolScope() {
        XCTAssertEqual(
            AttoLspSymbolRequestFeedback.requestFailedMessage(kind: .document, errorDescription: "server busy"),
            "Document symbols request failed.\nserver busy"
        )
        XCTAssertEqual(
            AttoLspSymbolRequestFeedback.failedMessage(kind: .workspace, errorDescription: "decode failed"),
            "Workspace symbols failed.\ndecode failed"
        )
        XCTAssertEqual(
            AttoLspSymbolRequestFeedback.timeoutMessage(kind: .workspace),
            "Workspace symbols request timed out."
        )
    }

    func testEmptyMessagesUseWorkspaceQueryWhenPresent() {
        XCTAssertEqual(
            AttoLspSymbolRequestFeedback.emptyMessage(kind: .document),
            "No document symbols are available for this document."
        )
        XCTAssertEqual(
            AttoLspSymbolRequestFeedback.emptyMessage(kind: .workspace),
            "No workspace symbols are available."
        )
        XCTAssertEqual(
            AttoLspSymbolRequestFeedback.emptyMessage(kind: .workspace, query: "  App  "),
            "No workspace symbols match \"App\"."
        )
    }
}
