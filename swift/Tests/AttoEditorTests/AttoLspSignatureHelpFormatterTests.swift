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

        let display = try XCTUnwrap(AttoLspSignatureHelpFormatter.display(fromSignatureHelpResultJSON: json))
        let text = display.text
        XCTAssertTrue(text.contains("open(path: String, mode: Mode)"))
        XCTAssertTrue(text.contains("parameter: path: String"))
        XCTAssertTrue(text.contains("Open a file."))
        XCTAssertTrue(display.activeParameterRanges.contains(NSRange(location: 5, length: 12)))
        XCTAssertTrue(highlightedSubstrings(in: display).contains("path: String"))
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

        let display = try XCTUnwrap(AttoLspSignatureHelpFormatter.display(fromSignatureHelpResultJSON: json))
        XCTAssertTrue(display.text.contains("parameter: b: Int"))
        XCTAssertTrue(display.activeParameterRanges.contains(NSRange(location: 12, length: 6)))
        XCTAssertTrue(highlightedSubstrings(in: display).contains("b: Int"))
    }

    func testSignatureHelpHighlightRangeUsesUTF16Offsets() throws {
        let json = """
        {
          "signatures": [
            {
              "label": "mix(😀: Int, b: Int)",
              "parameters": [
                { "label": [4, 11] },
                { "label": "b: Int" }
              ]
            }
          ],
          "activeParameter": 0
        }
        """

        let display = try XCTUnwrap(AttoLspSignatureHelpFormatter.display(fromSignatureHelpResultJSON: json))
        XCTAssertTrue(display.activeParameterRanges.contains(NSRange(location: 4, length: 7)))
        XCTAssertTrue(highlightedSubstrings(in: display).contains("😀: Int"))
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

    private func highlightedSubstrings(in display: AttoLspSignatureHelpFormatter.Display) -> [String] {
        let nsText = display.text as NSString
        return display.activeParameterRanges.map { nsText.substring(with: $0) }
    }
}
