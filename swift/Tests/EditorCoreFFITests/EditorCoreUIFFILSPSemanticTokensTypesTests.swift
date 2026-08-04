import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPSemanticTokensTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testSemanticTokensResultDecodesFullDeltaAndNull() throws {
        let full = try decode(EcuLspSemanticTokensResult.self, """
        {
          "resultId": "full-1",
          "data": [0, 4, 5, 7, 0]
        }
        """)

        XCTAssertEqual(full.shape, .tokens)
        XCTAssertEqual(full.resultId, "full-1")
        XCTAssertEqual(full.data, [0, 4, 5, 7, 0])
        XCTAssertEqual(full.edits, [])
        XCTAssertFalse(full.isEmpty)
        XCTAssertNotNil(full.rawJSONString)
        XCTAssertEqual(try full.dataForApplying(), [0, 4, 5, 7, 0])

        let delta = try decode(EcuLspSemanticTokensResult.self, """
        {
          "resultId": "delta-1",
          "edits": [
            { "start": 2, "deleteCount": 2, "data": [3, 9] }
          ]
        }
        """)

        XCTAssertEqual(delta.shape, .delta)
        XCTAssertEqual(delta.resultId, "delta-1")
        XCTAssertEqual(delta.data, [])
        XCTAssertEqual(delta.edits.count, 1)
        XCTAssertEqual(try delta.dataForApplying(baseline: [0, 4, 5, 7, 0]), [0, 4, 3, 9, 0])

        let none = try decode(EcuLspSemanticTokensResult.self, "null")
        XCTAssertEqual(none.shape, .none)
        XCTAssertTrue(none.isEmpty)
        XCTAssertEqual(try none.dataForApplying(baseline: [1, 2, 3]), [])
    }

    func testSemanticTokensDeltaRejectsOutOfBoundsEdit() throws {
        let delta = try decode(EcuLspSemanticTokensResult.self, """
        {
          "edits": [
            { "start": 10, "deleteCount": 1, "data": [3] }
          ]
        }
        """)

        XCTAssertThrowsError(try delta.dataForApplying(baseline: [0, 1, 2])) { error in
            XCTAssertEqual(
                error as? EcuLspSemanticTokensDeltaError,
                .editOutOfBounds(start: 10, deleteCount: 1, count: 3)
            )
        }
    }

    func testTypedSemanticTokensApplyUpdatesStyleLayer() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(
            library: lib,
            initialText: "let value = 1\n",
            viewportWidthCells: 80
        )

        XCTAssertNil(try ui.lspTakeLastSemanticTokensFullResult())
        XCTAssertNil(try ui.lspTakeLastSemanticTokensDeltaResult())
        XCTAssertNil(try ui.lspTakeLastSemanticTokensRangeResult())

        let full = try decode(EcuLspSemanticTokensResult.self, """
        {
          "resultId": "full-1",
          "data": [0, 4, 5, 7, 0]
        }
        """)

        var baseline = try ui.lspApplySemanticTokens(full)
        XCTAssertEqual(baseline, [0, 4, 5, 7, 0])
        var snapshot = try ui.styleIntervalsSnapshot(start: 0, end: 14)
        var semanticLayer = try XCTUnwrap(snapshot.layers.first { $0.layer == 1 })
        var interval = try XCTUnwrap(semanticLayer.intervals.first)
        XCTAssertEqual(interval.start, 4)
        XCTAssertEqual(interval.end, 9)
        XCTAssertEqual(interval.styleId, 0x0007_0000)

        let delta = try decode(EcuLspSemanticTokensResult.self, """
        {
          "resultId": "delta-1",
          "edits": [
            { "start": 2, "deleteCount": 1, "data": [3] }
          ]
        }
        """)

        baseline = try ui.lspApplySemanticTokens(delta, baseline: baseline)
        XCTAssertEqual(baseline, [0, 4, 3, 7, 0])
        snapshot = try ui.styleIntervalsSnapshot(start: 0, end: 14)
        semanticLayer = try XCTUnwrap(snapshot.layers.first { $0.layer == 1 })
        interval = try XCTUnwrap(semanticLayer.intervals.first)
        XCTAssertEqual(interval.start, 4)
        XCTAssertEqual(interval.end, 7)
        XCTAssertEqual(interval.styleId, 0x0007_0000)
    }
}
