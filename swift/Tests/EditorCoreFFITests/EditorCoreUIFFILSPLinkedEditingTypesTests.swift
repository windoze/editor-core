import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPLinkedEditingTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testLinkedEditingRangeResultDecodesRangesWordPatternAndNull() throws {
        let result = try decode(EcuLspLinkedEditingRangeResult.self, """
        {
          "ranges": [
            {
              "start": { "line": 0, "character": 2 },
              "end": { "line": 0, "character": 5 }
            },
            {
              "start": { "line": 0, "character": 6 },
              "end": { "line": 0, "character": 9 }
            }
          ],
          "wordPattern": "[A-Za-z]+"
        }
        """)

        XCTAssertEqual(result.shape, .linkedEditingRange)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.ranges.count, 2)
        XCTAssertEqual(result.ranges.first?.start.line, 0)
        XCTAssertEqual(result.ranges.first?.start.utf16Character, 2)
        XCTAssertEqual(result.ranges.first?.end.utf16Character, 5)
        XCTAssertEqual(result.wordPattern, "[A-Za-z]+")
        XCTAssertNotNil(result.value?.raw)
        XCTAssertNotNil(result.rawJSONString)

        let none = try decode(EcuLspLinkedEditingRangeResult.self, "null")
        XCTAssertEqual(none.shape, .none)
        XCTAssertTrue(none.isEmpty)
        XCTAssertNil(none.value)
        XCTAssertEqual(none.ranges, [])
    }

    func testLinkedEditingTypedTakeWrapperStartsEmpty() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        XCTAssertNil(try ui.lspTakeLastLinkedEditingRangeResult())
    }
}
