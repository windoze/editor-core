import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPFoldingRangeTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testFoldingRangeResultDecodesRangesAndNull() throws {
        let result = try decode(EcuLspFoldingRangeResult.self, """
        [
          {
            "startLine": 0,
            "startCharacter": 1,
            "endLine": 2,
            "endCharacter": 3,
            "kind": "region",
            "collapsedText": "..."
          }
        ]
        """)

        XCTAssertEqual(result.shape, .foldingRangeArray)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.ranges.count, 1)
        XCTAssertEqual(result.ranges.first?.startLine, 0)
        XCTAssertEqual(result.ranges.first?.startCharacter, 1)
        XCTAssertEqual(result.ranges.first?.endLine, 2)
        XCTAssertEqual(result.ranges.first?.endCharacter, 3)
        XCTAssertEqual(result.ranges.first?.kind, "region")
        XCTAssertEqual(result.ranges.first?.collapsedText, "...")
        XCTAssertNotNil(result.ranges.first?.raw)
        XCTAssertNotNil(result.rawJSONString)

        let none = try decode(EcuLspFoldingRangeResult.self, "null")
        XCTAssertEqual(none.shape, .none)
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(none.ranges, [])
    }

    func testFoldingRangesTypedTakeWrapperStartsEmptyAndTypedApplyUpdatesSnapshot() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(
            library: lib,
            initialText: "import A\nimport B\nlet value = 1\n",
            viewportWidthCells: 80
        )

        XCTAssertNil(try ui.lspTakeLastFoldingRangesResult())

        let result = try decode(EcuLspFoldingRangeResult.self, """
        [
          {
            "startLine": 0,
            "endLine": 1,
            "kind": "imports"
          }
        ]
        """)

        try ui.lspApplyFoldingRanges(result)

        let snapshot = try ui.foldingRegionsSnapshot()
        XCTAssertEqual(snapshot.regions.count, 1)
        XCTAssertEqual(snapshot.regions.first?.startLine, 0)
        XCTAssertEqual(snapshot.regions.first?.endLine, 1)
        XCTAssertFalse(snapshot.regions.first?.isCollapsed ?? true)
        XCTAssertEqual(snapshot.regions.first?.placeholder, "use ...")
    }
}
