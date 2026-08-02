import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPHierarchyTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testCallHierarchyPrepareResultDecodesItemsAndNull() throws {
        let result = try decode(EcuLspCallHierarchyPrepareResult.self, """
        [
          {
            "name": "render",
            "kind": 12,
            "tags": [1],
            "detail": "View.swift",
            "uri": "file:///tmp/View.swift",
            "range": {
              "start": { "line": 4, "character": 0 },
              "end": { "line": 8, "character": 1 }
            },
            "selectionRange": {
              "start": { "line": 5, "character": 7 },
              "end": { "line": 5, "character": 13 }
            },
            "data": { "server": "opaque" }
          }
        ]
        """)

        XCTAssertEqual(result.shape, .itemArray)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.items.first?.name, "render")
        XCTAssertEqual(result.items.first?.kind, 12)
        XCTAssertEqual(result.items.first?.tags, [1])
        XCTAssertEqual(result.items.first?.detail, "View.swift")
        XCTAssertEqual(result.items.first?.target.uri, "file:///tmp/View.swift")
        XCTAssertEqual(result.items.first?.target.selectionRange.start.line, 5)
        XCTAssertEqual(result.items.first?.target.selectionRange.start.utf16Character, 7)
        XCTAssertEqual(result.items.first?.data, .object(["server": .string("opaque")]))
        XCTAssertNotNil(result.items.first?.rawJSONString)
        XCTAssertNotNil(result.rawJSONString)

        let none = try decode(EcuLspCallHierarchyPrepareResult.self, "null")
        XCTAssertEqual(none.shape, .none)
        XCTAssertTrue(none.isEmpty)
    }

    func testCallHierarchyIncomingAndOutgoingResultsDecodeCallRanges() throws {
        let incoming = try decode(EcuLspCallHierarchyIncomingCallsResult.self, """
        [
          {
            "from": {
              "name": "caller",
              "kind": 12,
              "uri": "file:///tmp/Caller.swift",
              "range": {
                "start": { "line": 1, "character": 0 },
                "end": { "line": 8, "character": 0 }
              },
              "selectionRange": {
                "start": { "line": 2, "character": 5 },
                "end": { "line": 2, "character": 11 }
              }
            },
            "fromRanges": [
              {
                "start": { "line": 6, "character": 10 },
                "end": { "line": 6, "character": 16 }
              }
            ]
          }
        ]
        """)

        XCTAssertEqual(incoming.shape, .incomingCallArray)
        XCTAssertEqual(incoming.calls.first?.from.name, "caller")
        XCTAssertEqual(incoming.calls.first?.fromRanges.first?.start.line, 6)
        XCTAssertEqual(incoming.calls.first?.fromRanges.first?.start.utf16Character, 10)

        let outgoing = try decode(EcuLspCallHierarchyOutgoingCallsResult.self, """
        [
          {
            "to": {
              "name": "callee",
              "kind": 6,
              "uri": "file:///tmp/Callee.swift",
              "range": {
                "start": { "line": 20, "character": 0 },
                "end": { "line": 26, "character": 0 }
              },
              "selectionRange": {
                "start": { "line": 21, "character": 9 },
                "end": { "line": 21, "character": 15 }
              }
            },
            "fromRanges": []
          }
        ]
        """)

        XCTAssertEqual(outgoing.shape, .outgoingCallArray)
        XCTAssertEqual(outgoing.calls.first?.to.name, "callee")
        XCTAssertTrue(outgoing.calls.first?.fromRanges.isEmpty == true)
    }

    func testTypeHierarchyPrepareAndItemsResultsDecodeItemsAndNull() throws {
        let prepare = try decode(EcuLspTypeHierarchyPrepareResult.self, """
        {
          "name": "BaseView",
          "kind": 5,
          "detail": "UI",
          "uri": "file:///tmp/BaseView.swift",
          "range": {
            "start": { "line": 0, "character": 0 },
            "end": { "line": 4, "character": 1 }
          },
          "selectionRange": {
            "start": { "line": 0, "character": 6 },
            "end": { "line": 0, "character": 14 }
          },
          "data": { "id": 1 }
        }
        """)

        XCTAssertEqual(prepare.shape, .item)
        XCTAssertEqual(prepare.items.first?.name, "BaseView")
        XCTAssertEqual(prepare.items.first?.target.selectionRange.start.utf16Character, 6)
        XCTAssertEqual(prepare.items.first?.data, .object(["id": .number(1)]))
        XCTAssertNotNil(prepare.items.first?.rawJSONString)

        let items = try decode(EcuLspTypeHierarchyItemsResult.self, """
        [
          {
            "name": "DerivedView",
            "kind": 5,
            "uri": "file:///tmp/DerivedView.swift",
            "range": {
              "start": { "line": 10, "character": 0 },
              "end": { "line": 18, "character": 1 }
            },
            "selectionRange": {
              "start": { "line": 10, "character": 6 },
              "end": { "line": 10, "character": 17 }
            }
          }
        ]
        """)

        XCTAssertEqual(items.shape, .itemArray)
        XCTAssertFalse(items.isEmpty)
        XCTAssertEqual(items.items.first?.target.uri, "file:///tmp/DerivedView.swift")
        XCTAssertEqual(items.items.first?.target.selectionRange.start.line, 10)

        let none = try decode(EcuLspTypeHierarchyItemsResult.self, "null")
        XCTAssertEqual(none.shape, .none)
        XCTAssertTrue(none.isEmpty)
    }

    func testHierarchyTypedTakeWrappersStartEmpty() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        XCTAssertNil(try ui.lspTakeLastPrepareCallHierarchyResult())
        XCTAssertNil(try ui.lspTakeLastCallHierarchyIncomingCallsResult())
        XCTAssertNil(try ui.lspTakeLastCallHierarchyOutgoingCallsResult())
        XCTAssertNil(try ui.lspTakeLastPrepareTypeHierarchyResult())
        XCTAssertNil(try ui.lspTakeLastTypeHierarchySupertypesResult())
        XCTAssertNil(try ui.lspTakeLastTypeHierarchySubtypesResult())
    }
}
