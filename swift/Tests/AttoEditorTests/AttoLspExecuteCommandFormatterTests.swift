@testable import AttoEditor
import XCTest

final class AttoLspExecuteCommandFormatterTests: XCTestCase {
    func testDisplayTextFormatsSuccessfulObjectResult() {
        let text = AttoLspExecuteCommandFormatter.displayText(
            forResultJSON: #"{"result":{"changed":true,"files":2}}"#,
            commandTitle: "Fix all"
        )

        XCTAssertTrue(text.contains("Command completed."))
        XCTAssertTrue(text.contains("Command: Fix all"))
        XCTAssertTrue(text.contains(#""changed" : true"#))
        XCTAssertTrue(text.contains(#""files" : 2"#))
    }

    func testDisplayTextFormatsNullResultAsCompleted() {
        XCTAssertEqual(
            AttoLspExecuteCommandFormatter.displayText(
                forResultJSON: #"{"result":null}"#,
                commandTitle: "Organize Imports"
            ),
            """
            Command completed.
            Command: Organize Imports
            """
        )
    }

    func testDisplayTextFormatsErrorEnvelope() {
        let text = AttoLspExecuteCommandFormatter.displayText(
            forResultJSON: #"{"error":{"code":-32603,"message":"failed","data":{"reason":"boom"}}}"#,
            commandTitle: "Fix"
        )

        XCTAssertTrue(text.contains("Command failed."))
        XCTAssertTrue(text.contains("Command: Fix"))
        XCTAssertTrue(text.contains("failed"))
        XCTAssertTrue(text.contains("Code: -32603"))
        XCTAssertTrue(text.contains(#""reason" : "boom""#))
    }

    func testDisplayTextAcceptsLegacyRawResultJSON() {
        XCTAssertEqual(
            AttoLspExecuteCommandFormatter.displayText(
                forResultJSON: #""done""#,
                commandTitle: nil
            ),
            """
            Command completed.

            done
            """
        )
    }

    func testTimeoutTextIncludesCommandTitle() {
        let text = AttoLspExecuteCommandFormatter.timeoutText(commandTitle: "Fix")

        XCTAssertTrue(text.contains("Command result was not returned."))
        XCTAssertTrue(text.contains("Command: Fix"))
    }
}
