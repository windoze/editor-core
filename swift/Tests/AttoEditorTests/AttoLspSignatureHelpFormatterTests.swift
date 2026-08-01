import Foundation
@testable import AttoEditor
import XCTest

final class AttoLspSignatureHelpFormatterTests: XCTestCase {
    func testSignatureHelpFormatsActiveSignatureAndParameter() throws {
        let json = """
        {
          "signatures": [
            {
              "label": "ignored()"
            },
            {
              "label": "open(path: String, mode: Mode)",
              "documentation": {
                "kind": "markdown",
                "value": "Open a file."
              },
              "parameters": [
                { "label": [5, 17] },
                { "label": "mode: Mode" }
              ]
            }
          ],
          "activeSignature": 1,
          "activeParameter": 0
        }
        """

        let text = try XCTUnwrap(AttoLspSignatureHelpFormatter.displayText(fromSignatureHelpResultJSON: json))
        XCTAssertTrue(text.contains("open(path: String, mode: Mode)"))
        XCTAssertTrue(text.contains("parameter: path: String"))
        XCTAssertTrue(text.contains("Open a file."))
    }

    func testSignatureHelpUsesSignatureActiveParameterOverride() throws {
        let json = """
        {
          "signatures": [
            {
              "label": "sum(a: Int, b: Int)",
              "activeParameter": 1,
              "parameters": [
                { "label": "a: Int" },
                { "label": "b: Int" }
              ]
            }
          ],
          "activeParameter": 0
        }
        """

        let text = try XCTUnwrap(AttoLspSignatureHelpFormatter.displayText(fromSignatureHelpResultJSON: json))
        XCTAssertTrue(text.contains("parameter: b: Int"))
    }

    func testSignatureHelpReturnsNilForNullOrEmptyResult() throws {
        XCTAssertNil(AttoLspSignatureHelpFormatter.displayText(fromSignatureHelpResultJSON: "null"))
        XCTAssertNil(AttoLspSignatureHelpFormatter.displayText(fromSignatureHelpResultJSON: #"{"signatures":[]}"#))
    }

    func testSignatureHelpTriggerUsesServerDeclaredCharacters() throws {
        let json = """
        {
          "availability": "enabled",
          "state": "ready",
          "capabilities": {
            "signature_help": {
              "supported": true,
              "trigger_characters": ["("],
              "retrigger_characters": [","]
            }
          }
        }
        """

        XCTAssertTrue(AttoLspSignatureHelpTrigger.shouldTrigger(committedText: "(", lspStatusJSON: json))
        XCTAssertTrue(AttoLspSignatureHelpTrigger.shouldTrigger(committedText: ",", lspStatusJSON: json))
        XCTAssertFalse(AttoLspSignatureHelpTrigger.shouldTrigger(committedText: "a", lspStatusJSON: json))
        XCTAssertFalse(AttoLspSignatureHelpTrigger.shouldTrigger(committedText: "(),", lspStatusJSON: json))
    }

    func testSignatureHelpTriggerIgnoresMissingOrInvalidStatus() throws {
        XCTAssertFalse(AttoLspSignatureHelpTrigger.shouldTrigger(committedText: "(", lspStatusJSON: "{}"))
        XCTAssertFalse(AttoLspSignatureHelpTrigger.shouldTrigger(committedText: "(", lspStatusJSON: "not json"))
        XCTAssertFalse(
            AttoLspSignatureHelpTrigger.shouldTrigger(
                committedText: "(",
                lspStatusJSON: #"{"capabilities":{"signature_help":{"supported":false,"trigger_characters":["("]}}}"#
            )
        )
    }
}
