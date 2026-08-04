import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPCodeLensTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testCodeLensResultDecodesLensArrayNullAndError() throws {
        let result = try decode(EcuLspCodeLensResult.self, """
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 0 }
            },
            "command": {
              "title": "Run Test",
              "command": "test.run",
              "arguments": ["caseA"]
            },
            "data": { "id": 1 }
          }
        ]
        """)

        XCTAssertEqual(result.shape, .lensArray)
        XCTAssertEqual(result.items.count, 1)
        XCTAssertEqual(result.items.first?.range.start.line, 0)
        XCTAssertEqual(result.items.first?.command?.title, "Run Test")
        XCTAssertEqual(result.items.first?.command?.command, "test.run")
        XCTAssertEqual(result.items.first?.command?.arguments, [.string("caseA")])
        XCTAssertNotNil(result.items.first?.data)
        XCTAssertNotNil(result.rawJSONString)

        let none = try decode(EcuLspCodeLensResult.self, "null")
        XCTAssertEqual(none.shape, .none)
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(none.items, [])

        let error = try decode(EcuLspCodeLensResult.self, """
        {
          "error": {
            "code": -32603,
            "message": "code lens failed",
            "data": { "retry": false }
          }
        }
        """)

        XCTAssertEqual(error.shape, .error)
        XCTAssertEqual(error.items, [])
        XCTAssertEqual(error.error?.code, -32603)
        XCTAssertEqual(error.error?.message, "code lens failed")
        XCTAssertNotNil(error.error?.data)
    }

    func testCodeLensResolveDecodesSingleLens() throws {
        let lens = try decode(EcuLspCodeLens.self, """
        {
          "range": {
            "start": { "line": 1, "character": 0 },
            "end": { "line": 1, "character": 0 }
          },
          "command": {
            "title": "Apply Fix",
            "command": "fix.apply"
          }
        }
        """)

        XCTAssertEqual(lens.range.start.line, 1)
        XCTAssertEqual(lens.command?.title, "Apply Fix")
        XCTAssertEqual(lens.command?.command, "fix.apply")
        XCTAssertNotNil(lens.rawJSONString)
    }

    func testCodeLensTypedTakeWrappersStartEmpty() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        XCTAssertNil(try ui.lspTakeLastCodeLensResult())
        XCTAssertNil(try ui.lspTakeLastCodeLensResolveResult())
    }
}
