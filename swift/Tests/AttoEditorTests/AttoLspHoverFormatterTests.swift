import AppKit
@testable import AttoEditor
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoLspHoverFormatterTests: XCTestCase {
    func testHoverMarkupContentExtractsValue() {
        let json = #"{"contents":{"kind":"markdown","value":"`foo`: i32\n\nDocs here"}} "#
        XCTAssertEqual(
            AttoLspHoverFormatter.displayText(fromHoverResultJSON: json),
            "`foo`: i32\n\nDocs here"
        )
    }

    func testHoverArrayJoinsParts() {
        let json = #"{"contents":["a",{"kind":"plaintext","value":"b"}]}"#
        XCTAssertEqual(AttoLspHoverFormatter.displayText(fromHoverResultJSON: json), "a\n\nb")
    }

    func testHoverFormatterConsumesTypedResult() throws {
        let result = try JSONDecoder().decode(EcuLspHoverResult.self, from: Data("""
        {
          "contents": [
            "a",
            { "language": "swift", "value": "let b = 1" }
          ]
        }
        """.utf8))

        XCTAssertEqual(AttoLspHoverFormatter.displayText(fromHoverResult: result), "a\n\nlet b = 1")
    }

    func testLspRequestHoverThrowsWhenLspDisabled() throws {
        let lib = EditorCoreUIFFILibrary()
        let editor = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)
        XCTAssertThrowsError(try editor.lspRequestHover(logicalLine: 0, logicalColumn: 0))
        XCTAssertNil(try editor.lspTakeLastHoverResultJSON())
        XCTAssertNil(try editor.lspTakeLastHoverResult())
    }
}
