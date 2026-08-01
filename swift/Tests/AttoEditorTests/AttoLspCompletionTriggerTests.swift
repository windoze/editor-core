import XCTest
import EditorCoreUIFFI
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

    func testCompletionTriggerUsesTypedStatus() {
        let status = EcuLspStatusSnapshot(
            availability: .enabled,
            state: .ready,
            server: nil,
            activity: nil,
            detail: nil,
            capabilities: EcuLspCapabilities(
                completion: .init(supported: true, triggerCharacters: [".", "/"], allCommitCharacters: [";"])
            )
        )

        XCTAssertTrue(AttoLspCompletionTrigger.shouldTrigger(committedText: ".", lspStatus: status))
        XCTAssertTrue(AttoLspCompletionTrigger.shouldTrigger(committedText: "/", lspStatus: status))
        XCTAssertFalse(AttoLspCompletionTrigger.shouldTrigger(committedText: ";", lspStatus: status))
        XCTAssertFalse(AttoLspCompletionTrigger.shouldTrigger(committedText: "./", lspStatus: status))
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
