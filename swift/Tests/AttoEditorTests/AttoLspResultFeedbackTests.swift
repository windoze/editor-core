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
