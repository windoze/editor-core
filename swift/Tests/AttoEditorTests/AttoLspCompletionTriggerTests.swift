import XCTest
@testable import AttoEditor

final class AttoLspCompletionTriggerTests: XCTestCase {
    func testCompletionTriggerUsesServerDeclaredCharacters() throws {
        let json = """
        {
          "availability": "enabled",
          "state": "ready",
          "capabilities": {
            "completion": {
              "supported": true,
              "trigger_characters": [".", "/"],
              "all_commit_characters": [";"]
            }
          }
        }
        """

        XCTAssertTrue(AttoLspCompletionTrigger.shouldTrigger(committedText: ".", lspStatusJSON: json))
        XCTAssertTrue(AttoLspCompletionTrigger.shouldTrigger(committedText: "/", lspStatusJSON: json))
        XCTAssertFalse(AttoLspCompletionTrigger.shouldTrigger(committedText: "a", lspStatusJSON: json))
        XCTAssertFalse(AttoLspCompletionTrigger.shouldTrigger(committedText: "./", lspStatusJSON: json))
        XCTAssertFalse(AttoLspCompletionTrigger.shouldTrigger(committedText: ";", lspStatusJSON: json))
    }

    func testCompletionTriggerIgnoresMissingOrInvalidStatus() throws {
        XCTAssertFalse(AttoLspCompletionTrigger.shouldTrigger(committedText: ".", lspStatusJSON: "{}"))
        XCTAssertFalse(AttoLspCompletionTrigger.shouldTrigger(committedText: ".", lspStatusJSON: "not json"))
        XCTAssertFalse(
            AttoLspCompletionTrigger.shouldTrigger(
                committedText: ".",
                lspStatusJSON: #"{"capabilities":{"completion":{"supported":false,"trigger_characters":["."]}}}"#
            )
        )
    }
}
