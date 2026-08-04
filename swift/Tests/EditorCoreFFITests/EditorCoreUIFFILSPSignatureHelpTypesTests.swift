import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPSignatureHelpTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testSignatureHelpPayloadDecodesTypedSignaturesAndParameters() throws {
        let result = try decode(EcuLspSignatureHelpResult.self, """
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
                {
                  "label": [5, 17],
                  "documentation": "Path to open."
                },
                {
                  "label": "mode: Mode"
                }
              ],
              "activeParameter": 1
            }
          ],
          "activeSignature": 1,
          "activeParameter": 0,
          "future": true
        }
        """)

        XCTAssertEqual(result.shape, .help)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.activeSignature, 1)
        XCTAssertEqual(result.activeParameter, 0)
        XCTAssertEqual(result.signatures.count, 2)
        if case let .object(raw)? = result.raw {
            XCTAssertEqual(raw["future"], .bool(true))
        } else {
            XCTFail("expected raw object payload")
        }

        let signature = result.signatures[1]
        XCTAssertEqual(signature.label, "open(path: String, mode: Mode)")
        XCTAssertEqual(signature.documentation, .markup(kind: "markdown", value: "Open a file."))
        XCTAssertEqual(signature.documentation?.text, "Open a file.")
        XCTAssertEqual(signature.activeParameter, 1)
        XCTAssertEqual(signature.parameters.count, 2)
        XCTAssertEqual(signature.parameters[0].label, .utf16Range(start: 5, end: 17))
        XCTAssertEqual(signature.parameters[0].documentation, .plain("Path to open."))
        XCTAssertEqual(signature.parameters[1].label, .string("mode: Mode"))
    }

    func testSignatureHelpNullAndUnknownParameterLabelsDecode() throws {
        let nullResult = try decode(EcuLspSignatureHelpResult.self, "null")
        XCTAssertEqual(nullResult.shape, .none)
        XCTAssertTrue(nullResult.isEmpty)
        XCTAssertEqual(nullResult.raw, .null)

        let result = try decode(EcuLspSignatureHelpResult.self, """
        {
          "signatures": [
            {
              "label": "future(value)",
              "parameters": [
                { "label": [4, 4] },
                { "label": { "future": 42 } }
              ]
            }
          ]
        }
        """)

        XCTAssertEqual(result.signatures[0].parameters[0].label, .unknown(.array([.number(4), .number(4)])))
        XCTAssertEqual(result.signatures[0].parameters[1].label, .unknown(.object(["future": .number(42)])))
    }

    func testSignatureHelpTypedTakeWrapperStartsEmpty() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        XCTAssertNil(try ui.lspTakeLastSignatureHelpResult())
    }
}
