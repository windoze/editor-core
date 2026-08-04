@testable import AttoEditor
import EditorCoreUIFFI
import Foundation
import XCTest

final class AttoLspHierarchyParserTests: XCTestCase {
    func testPrepareCallItemsPreserveRequestJSONAndTargetSelectionRange() throws {
        let json = """
        [
          {
            "name": "render",
            "kind": 12,
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
        """

        let items = AttoLspHierarchyParser.prepareCallItems(fromResultJSON: json)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "render")
        XCTAssertEqual(items[0].detail, "View.swift")
        XCTAssertEqual(items[0].kindLabel, "function")
        XCTAssertEqual(items[0].target, AttoLspDefinitionParser.Target(
            uri: "file:///tmp/View.swift",
            line: 5,
            utf16Character: 7
        ))

        let request = try XCTUnwrap(jsonObject(items[0].requestJSON) as? [String: Any])
        XCTAssertEqual(request["name"] as? String, "render")
        XCTAssertNotNil(request["data"] as? [String: Any])
    }

    func testIncomingCallsNavigateToFirstCallSiteRange() {
        let json = """
        [
          {
            "from": {
              "name": "caller",
              "kind": 12,
              "detail": "Caller.swift",
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
              },
              {
                "start": { "line": 7, "character": 10 },
                "end": { "line": 7, "character": 16 }
              }
            ]
          }
        ]
        """

        let entries = AttoLspHierarchyParser.incomingCalls(fromResultJSON: json)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "caller")
        XCTAssertEqual(entries[0].kindLabel, "function")
        XCTAssertEqual(entries[0].relatedRangeCount, 2)
        XCTAssertEqual(entries[0].target, AttoLspDefinitionParser.Target(
            uri: "file:///tmp/Caller.swift",
            line: 6,
            utf16Character: 10
        ))
    }

    func testOutgoingCallsNavigateToCalleeSelectionRange() {
        let json = """
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
            "fromRanges": [
              {
                "start": { "line": 3, "character": 2 },
                "end": { "line": 3, "character": 8 }
              }
            ]
          }
        ]
        """

        let entries = AttoLspHierarchyParser.outgoingCalls(fromResultJSON: json)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "callee")
        XCTAssertEqual(entries[0].kindLabel, "method")
        XCTAssertEqual(entries[0].relatedRangeCount, 1)
        XCTAssertEqual(entries[0].target, AttoLspDefinitionParser.Target(
            uri: "file:///tmp/Callee.swift",
            line: 21,
            utf16Character: 9
        ))
    }

    func testTypeHierarchyEntriesParseItemsAndIgnoreInvalidShapes() {
        let json = """
        [
          {
            "name": "BaseView",
            "kind": 5,
            "detail": "UI",
            "uri": "file:///tmp/BaseView.swift",
            "selectionRange": {
              "start": { "line": 0, "character": 6 },
              "end": { "line": 0, "character": 14 }
            }
          },
          { "name": "Missing URI" },
          null
        ]
        """

        let entries = AttoLspHierarchyParser.typeHierarchyEntries(fromResultJSON: json)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "BaseView")
        XCTAssertEqual(entries[0].detail, "UI")
        XCTAssertEqual(entries[0].kindLabel, "class")
        XCTAssertEqual(entries[0].target, AttoLspDefinitionParser.Target(
            uri: "file:///tmp/BaseView.swift",
            line: 0,
            utf16Character: 6
        ))

        XCTAssertTrue(AttoLspHierarchyParser.prepareCallItems(fromResultJSON: "null").isEmpty)
        XCTAssertTrue(AttoLspHierarchyParser.incomingCalls(fromResultJSON: #"{"bad":true}"#).isEmpty)
    }

    func testTypedCallHierarchyPrepareAndIncomingCallsProjectToExistingModels() throws {
        let prepare = try decode(EcuLspCallHierarchyPrepareResult.self, """
        [
          {
            "name": "render",
            "kind": 12,
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

        let items = AttoLspHierarchyParser.prepareCallItems(from: prepare)

        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].name, "render")
        XCTAssertEqual(items[0].detail, "View.swift")
        XCTAssertEqual(items[0].kindLabel, "function")
        XCTAssertEqual(items[0].target, AttoLspDefinitionParser.Target(
            uri: "file:///tmp/View.swift",
            line: 5,
            utf16Character: 7
        ))
        XCTAssertNotNil(jsonObject(items[0].requestJSON) as? [String: Any])

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

        let entries = AttoLspHierarchyParser.incomingCalls(from: incoming)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "caller")
        XCTAssertEqual(entries[0].relatedRangeCount, 1)
        XCTAssertEqual(entries[0].target, AttoLspDefinitionParser.Target(
            uri: "file:///tmp/Caller.swift",
            line: 6,
            utf16Character: 10
        ))
    }

    func testTypedTypeHierarchyEntriesProjectToExistingModels() throws {
        let result = try decode(EcuLspTypeHierarchyItemsResult.self, """
        [
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
            }
          }
        ]
        """)

        let entries = AttoLspHierarchyParser.typeHierarchyEntries(from: result)

        XCTAssertEqual(entries.count, 1)
        XCTAssertEqual(entries[0].name, "BaseView")
        XCTAssertEqual(entries[0].detail, "UI")
        XCTAssertEqual(entries[0].kindLabel, "class")
        XCTAssertEqual(entries[0].target, AttoLspDefinitionParser.Target(
            uri: "file:///tmp/BaseView.swift",
            line: 0,
            utf16Character: 6
        ))
    }

    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    private func jsonObject(_ json: String) -> Any? {
        guard let data = json.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data, options: [])
    }
}
