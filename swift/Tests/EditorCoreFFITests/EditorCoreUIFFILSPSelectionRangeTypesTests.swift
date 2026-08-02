import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPSelectionRangeTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testSelectionRangeResultDecodesParentChainsAndNull() throws {
        let result = try decode(EcuLspSelectionRangeResult.self, """
        [
          {
            "range": {
              "start": { "line": 0, "character": 4 },
              "end": { "line": 0, "character": 7 }
            },
            "parent": {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 8 }
              }
            }
          }
        ]
        """)

        XCTAssertEqual(result.shape, .selectionRangeArray)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.roots.count, 1)
        XCTAssertEqual(result.roots.first?.range.start.line, 0)
        XCTAssertEqual(result.roots.first?.range.start.utf16Character, 4)
        XCTAssertEqual(result.roots.first?.range.end.utf16Character, 7)
        XCTAssertEqual(result.roots.first?.parent?.range.start.utf16Character, 0)
        XCTAssertEqual(result.roots.first?.parent?.range.end.utf16Character, 8)
        XCTAssertNotNil(result.rawJSONString)

        let none = try decode(EcuLspSelectionRangeResult.self, "null")
        XCTAssertEqual(none.shape, .none)
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(none.roots, [])
    }

    func testSelectionRangeTypedTakeWrapperStartsEmpty() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        XCTAssertNil(try ui.lspTakeLastSelectionRangeResult())
    }
}
