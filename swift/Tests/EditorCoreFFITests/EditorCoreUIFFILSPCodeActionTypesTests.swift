import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPCodeActionTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testCodeActionResultDecodesActionsCommandsAndNull() throws {
        let result = try decode(EcuLspCodeActionResult.self, """
        [
          {
            "title": "Fix import",
            "kind": "quickfix",
            "diagnostics": [
              {
                "range": {
                  "start": { "line": 1, "character": 2 },
                  "end": { "line": 1, "character": 9 }
                },
                "severity": 1,
                "code": "missing-import",
                "source": "swift",
                "message": "Missing import",
                "tags": [1],
                "data": { "id": 7 }
              }
            ],
            "isPreferred": true,
            "edit": {
              "changes": {
                "file:///tmp/a.swift": [
                  {
                    "range": {
                      "start": { "line": 0, "character": 0 },
                      "end": { "line": 0, "character": 0 }
                    },
                    "newText": "import Foundation\\n"
                  }
                ]
              }
            },
            "command": {
              "title": "Organize",
              "command": "source.organizeImports",
              "arguments": [1, "x"]
            },
            "data": { "token": "abc" }
          },
          {
            "title": "Run command",
            "command": "server.run",
            "arguments": ["arg"]
          }
        ]
        """)

        XCTAssertEqual(result.shape, .actionArray)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.items.count, 2)

        guard case let .codeAction(action) = result.items[0] else {
            return XCTFail("expected code action")
        }
        XCTAssertEqual(action.title, "Fix import")
        XCTAssertEqual(action.kind, "quickfix")
        XCTAssertEqual(action.diagnostics.first?.range.start.line, 1)
        XCTAssertEqual(action.diagnostics.first?.range.end.utf16Character, 9)
        XCTAssertEqual(action.diagnostics.first?.code, .string("missing-import"))
        XCTAssertEqual(action.diagnostics.first?.tags, [1])
        XCTAssertEqual(action.isPreferred, true)
        XCTAssertEqual(action.edit?.changes["file:///tmp/a.swift"]?.first?.newText, "import Foundation\n")
        XCTAssertEqual(action.command?.command, "source.organizeImports")
        XCTAssertEqual(action.command?.arguments, [.number(1), .string("x")])
        XCTAssertEqual(action.data, .object(["token": .string("abc")]))
        XCTAssertNotNil(action.rawJSONString)

        guard case let .command(command) = result.items[1] else {
            return XCTFail("expected legacy command")
        }
        XCTAssertEqual(command.title, "Run command")
        XCTAssertEqual(command.command, "server.run")
        XCTAssertEqual(command.arguments, [.string("arg")])

        let none = try decode(EcuLspCodeActionResult.self, "null")
        XCTAssertEqual(none.shape, .none)
        XCTAssertTrue(none.isEmpty)
    }

    func testCodeActionResolvePayloadDecodesDisabledAction() throws {
        let action = try decode(EcuLspCodeAction.self, """
        {
          "title": "Cannot fix",
          "kind": "quickfix",
          "disabled": { "reason": "not applicable" }
        }
        """)

        XCTAssertEqual(action.title, "Cannot fix")
        XCTAssertEqual(action.kind, "quickfix")
        XCTAssertEqual(action.disabled?.reason, "not applicable")
        XCTAssertNotNil(action.rawJSONString)
    }

    func testCodeActionTypedTakeWrappersStartEmpty() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        XCTAssertNil(try ui.lspTakeLastCodeActionResult())
        XCTAssertNil(try ui.lspTakeLastCodeActionResolveResult())
    }
}
