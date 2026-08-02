@testable import AttoEditor
import XCTest

final class AttoLspResultFeedbackTests: XCTestCase {
    func testUnavailableMessageUsesShortStatusAndDetailedPopoverText() {
        XCTAssertEqual(
            AttoLspResultFeedback.unavailable(.foldingRanges),
            AttoLspResultFeedback.Message(
                statusText: "Folding ranges: unavailable",
                detailText: "Folding ranges are unavailable.\nLSP is not enabled for this document."
            )
        )
    }

    func testFailureTimeoutAndEmptyMessagesAreConsistentAcrossFamilies() {
        XCTAssertEqual(
            AttoLspResultFeedback.requestFailed(.linkedEditing, errorDescription: "server busy"),
            AttoLspResultFeedback.Message(
                statusText: "Linked editing: request failed",
                detailText: "Linked editing request failed.\nserver busy"
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.failed(.selectionRange, errorDescription: "decode failed"),
            AttoLspResultFeedback.Message(
                statusText: "Selection range: failed",
                detailText: "Selection range failed.\ndecode failed"
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.timeout(.codeLensRefresh),
            AttoLspResultFeedback.Message(
                statusText: "Code lens: timed out",
                detailText: "Code lens refresh request timed out."
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.empty(.workspaceDiagnostics),
            AttoLspResultFeedback.Message(
                statusText: "Workspace diagnostics: no results",
                detailText: "No workspace diagnostics are available."
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.empty(.signatureHelp),
            AttoLspResultFeedback.Message(
                statusText: "Signature help: no results",
                detailText: "No signature help is available here."
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.empty(.definition),
            AttoLspResultFeedback.Message(
                statusText: "Definition: no results",
                detailText: "No definitions are available here."
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.requestFailed(.references, errorDescription: "server busy"),
            AttoLspResultFeedback.Message(
                statusText: "References: request failed",
                detailText: "References request failed.\nserver busy"
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.requestFailed(.documentSymbols, errorDescription: "server busy"),
            AttoLspResultFeedback.Message(
                statusText: "Document symbols: request failed",
                detailText: "Document symbols request failed.\nserver busy"
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.failed(.workspaceSymbols, errorDescription: "decode failed"),
            AttoLspResultFeedback.Message(
                statusText: "Workspace symbols: failed",
                detailText: "Workspace symbols failed.\ndecode failed"
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.timeout(.workspaceSymbols),
            AttoLspResultFeedback.Message(
                statusText: "Workspace symbols: timed out",
                detailText: "Workspace symbols request timed out."
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.empty(.documentSymbols),
            AttoLspResultFeedback.Message(
                statusText: "Document symbols: no results",
                detailText: "No document symbols are available for this document."
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.empty(.workspaceSymbols, detailText: "No workspace symbols match \"App\"."),
            AttoLspResultFeedback.Message(
                statusText: "Workspace symbols: no results",
                detailText: "No workspace symbols match \"App\"."
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.requestFailed(.completion, errorDescription: "server busy"),
            AttoLspResultFeedback.Message(
                statusText: "Completion: request failed",
                detailText: "Completion request failed.\nserver busy"
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.timeout(.completion),
            AttoLspResultFeedback.Message(
                statusText: "Completion: timed out",
                detailText: "Completion request timed out."
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.empty(.completion),
            AttoLspResultFeedback.Message(
                statusText: "Completion: no results",
                detailText: "No completions are available here."
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.requestFailed(.documentColors, errorDescription: "server busy"),
            AttoLspResultFeedback.Message(
                statusText: "Document colors: request failed",
                detailText: "Document colors request failed.\nserver busy"
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.failed(.colorPresentations, errorDescription: "decode failed"),
            AttoLspResultFeedback.Message(
                statusText: "Color presentations: failed",
                detailText: "Color presentations failed.\ndecode failed"
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.empty(.documentColors),
            AttoLspResultFeedback.Message(
                statusText: "Document colors: no results",
                detailText: "No document colors are available."
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.empty(.colorPresentations),
            AttoLspResultFeedback.Message(
                statusText: "Color presentations: no results",
                detailText: "No color presentations are available."
            )
        )
    }

    func testRefreshSummaryFormatsSingularAndPluralCounts() {
        XCTAssertEqual(
            AttoLspResultFeedback.refreshed(.codeLensRefresh, count: 1, singular: "action", plural: "actions"),
            AttoLspResultFeedback.Message(
                statusText: "Code lens: 1",
                detailText: "Code lens refreshed.\n1 action is available."
            )
        )
        XCTAssertEqual(
            AttoLspResultFeedback.refreshed(.codeLensRefresh, count: 3, singular: "action", plural: "actions"),
            AttoLspResultFeedback.Message(
                statusText: "Code lens: 3",
                detailText: "Code lens refreshed.\n3 actions are available."
            )
        )
    }
}
