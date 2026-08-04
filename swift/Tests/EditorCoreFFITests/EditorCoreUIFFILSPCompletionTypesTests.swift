import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPCompletionTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testCompletionListPayloadDecodesTypedItems() throws {
        let result = try decode(EcuLspCompletionResult.self, """
        {
          "isIncomplete": true,
          "itemDefaults": {
            "commitCharacters": ["."]
          },
          "items": [
            {
              "label": "print",
              "labelDetails": {
                "detail": "(value)",
                "description": "Swift"
              },
              "kind": 3,
              "tags": [1],
              "detail": "(value: Any)",
              "documentation": {
                "kind": "markdown",
                "value": "Writes a value."
              },
              "preselect": true,
              "sortText": "0001",
              "filterText": "print",
              "insertText": "print(${1:value})",
              "insertTextFormat": 2,
              "insertTextMode": 2,
              "textEdit": {
                "range": {
                  "start": { "line": 1, "character": 2 },
                  "end": { "line": 1, "character": 5 }
                },
                "newText": "print()"
              },
              "additionalTextEdits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "import Swift\\n"
                }
              ],
              "commitCharacters": ["(", "."],
              "command": {
                "title": "After completion",
                "command": "completion.after",
                "arguments": [1, "x"]
              },
              "data": { "id": 7 }
            }
          ]
        }
        """)

        XCTAssertEqual(result.shape, .list)
        XCTAssertTrue(result.isIncomplete)
        XCTAssertFalse(result.isEmpty)
        XCTAssertEqual(result.itemDefaults, .object(["commitCharacters": .array([.string(".")])]))

        let item = try XCTUnwrap(result.items.first)
        XCTAssertEqual(item.label, "print")
        XCTAssertEqual(item.labelDetails?.detail, "(value)")
        XCTAssertEqual(item.labelDetails?.description, "Swift")
        XCTAssertEqual(item.kindKind, .function)
        XCTAssertEqual(item.kindKind?.rawValue, 3)
        XCTAssertEqual(item.tagKinds, [.deprecated])
        XCTAssertEqual(item.detail, "(value: Any)")
        XCTAssertEqual(item.documentation, .markup(kind: "markdown", value: "Writes a value."))
        XCTAssertEqual(item.documentation?.text, "Writes a value.")
        XCTAssertEqual(item.preselect, true)
        XCTAssertEqual(item.sortText, "0001")
        XCTAssertEqual(item.filterText, "print")
        XCTAssertEqual(item.insertText, "print(${1:value})")
        XCTAssertEqual(item.insertTextFormatKind, .snippet)
        XCTAssertEqual(item.insertTextModeKind, .adjustIndentation)
        XCTAssertEqual(item.textEdit?.newText, "print()")
        XCTAssertEqual(item.additionalTextEdits.first?.newText, "import Swift\n")
        XCTAssertEqual(item.additionalTextEdits.first?.range.start.line, 0)
        XCTAssertEqual(item.commitCharacters, ["(", "."])
        XCTAssertEqual(item.command?.title, "After completion")
        XCTAssertEqual(item.command?.command, "completion.after")
        XCTAssertEqual(item.command?.arguments, [.number(1), .string("x")])
        XCTAssertEqual(item.data, .object(["id": .number(7)]))
        XCTAssertEqual(item.raw, .object([
            "label": .string("print"),
            "labelDetails": .object([
                "detail": .string("(value)"),
                "description": .string("Swift"),
            ]),
            "kind": .number(3),
            "tags": .array([.number(1)]),
            "detail": .string("(value: Any)"),
            "documentation": .object([
                "kind": .string("markdown"),
                "value": .string("Writes a value."),
            ]),
            "preselect": .bool(true),
            "sortText": .string("0001"),
            "filterText": .string("print"),
            "insertText": .string("print(${1:value})"),
            "insertTextFormat": .number(2),
            "insertTextMode": .number(2),
            "textEdit": .object([
                "range": .object([
                    "start": .object(["line": .number(1), "character": .number(2)]),
                    "end": .object(["line": .number(1), "character": .number(5)]),
                ]),
                "newText": .string("print()"),
            ]),
            "additionalTextEdits": .array([
                .object([
                    "range": .object([
                        "start": .object(["line": .number(0), "character": .number(0)]),
                        "end": .object(["line": .number(0), "character": .number(0)]),
                    ]),
                    "newText": .string("import Swift\n"),
                ]),
            ]),
            "commitCharacters": .array([.string("("), .string(".")]),
            "command": .object([
                "title": .string("After completion"),
                "command": .string("completion.after"),
                "arguments": .array([.number(1), .string("x")]),
            ]),
            "data": .object(["id": .number(7)]),
        ]))
    }

    func testCompletionArrayAndNullPayloadsDecode() throws {
        let arrayResult = try decode(EcuLspCompletionResult.self, """
        [
          {
            "label": "map",
            "kind": 2,
            "documentation": "Transform values"
          }
        ]
        """)

        XCTAssertEqual(arrayResult.shape, .itemArray)
        XCTAssertFalse(arrayResult.isIncomplete)
        XCTAssertEqual(arrayResult.items.first?.label, "map")
        XCTAssertEqual(arrayResult.items.first?.kindKind, .method)
        XCTAssertEqual(arrayResult.items.first?.documentation, .plain("Transform values"))

        let nullResult = try decode(EcuLspCompletionResult.self, "null")
        XCTAssertEqual(nullResult.shape, .none)
        XCTAssertTrue(nullResult.isEmpty)
    }

    func testCompletionItemResolvePayloadDecodesInsertReplaceEditAndUnknowns() throws {
        let item = try decode(EcuLspCompletionItem.self, """
        {
          "label": "future",
          "kind": 99,
          "tags": [1, 9],
          "insertTextFormat": 42,
          "insertTextMode": 43,
          "textEdit": {
            "insert": {
              "start": { "line": 0, "character": 1 },
              "end": { "line": 0, "character": 2 }
            },
            "replace": {
              "start": { "line": 0, "character": 1 },
              "end": { "line": 0, "character": 5 }
            },
            "newText": "future()"
          }
        }
        """)

        XCTAssertEqual(item.kindKind, .unknown(99))
        XCTAssertEqual(item.kindKind?.rawValue, 99)
        XCTAssertEqual(item.tagKinds, [.deprecated, .unknown(9)])
        XCTAssertEqual(item.insertTextFormatKind, .unknown(42))
        XCTAssertEqual(item.insertTextModeKind, .unknown(43))
        XCTAssertEqual(item.textEdit?.newText, "future()")
        guard case let .insertReplace(edit) = item.textEdit else {
            return XCTFail("expected insert-replace edit")
        }
        XCTAssertEqual(edit.insert.start.utf16Character, 1)
        XCTAssertEqual(edit.replace.end.utf16Character, 5)
    }

    func testCompletionTypedTakeWrappersStartEmpty() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        XCTAssertNil(try ui.lspTakeLastCompletionResult())
        XCTAssertNil(try ui.lspTakeLastCompletionItemResolveResult())
    }
}
