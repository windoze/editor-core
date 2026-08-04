import EditorCoreUIFFI
import XCTest

final class EditorCoreUIFFILSPRenameTypesTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    func testPrepareRenamePayloadsDecode() throws {
        let rangeOnly = try decode(EcuLspPrepareRenameResult.self, """
        {
          "start": { "line": 1, "character": 2 },
          "end": { "line": 1, "character": 7 }
        }
        """)
        XCTAssertEqual(rangeOnly.shape, .range)
        XCTAssertEqual(rangeOnly.range?.start.line, 1)
        XCTAssertEqual(rangeOnly.range?.start.utf16Character, 2)
        XCTAssertNil(rangeOnly.placeholder)

        let placeholder = try decode(EcuLspPrepareRenameResult.self, """
        {
          "range": {
            "start": { "line": 2, "character": 3 },
            "end": { "line": 2, "character": 8 }
          },
          "placeholder": "serverName"
        }
        """)
        XCTAssertEqual(placeholder.shape, .rangePlaceholder)
        XCTAssertEqual(placeholder.range?.end.utf16Character, 8)
        XCTAssertEqual(placeholder.placeholder, "serverName")

        let defaultBehavior = try decode(EcuLspPrepareRenameResult.self, #"{"defaultBehavior":true}"#)
        XCTAssertEqual(defaultBehavior.shape, .defaultBehavior)
        XCTAssertEqual(defaultBehavior.defaultBehavior, true)

        let none = try decode(EcuLspPrepareRenameResult.self, "null")
        XCTAssertEqual(none.shape, .none)
        XCTAssertNil(none.range)
    }

    func testWorkspaceEditPayloadDecodesChangesDocumentChangesAndResources() throws {
        let edit = try decode(EcuLspWorkspaceEdit.self, """
        {
          "changes": {
            "file:///tmp/a.swift": [
              {
                "range": {
                  "start": { "line": 0, "character": 1 },
                  "end": { "line": 0, "character": 2 }
                },
                "newText": "A"
              }
            ]
          },
          "documentChanges": [
            {
              "textDocument": { "uri": "file:///tmp/b.swift", "version": null },
              "edits": [
                {
                  "range": {
                    "start": { "line": 1, "character": 0 },
                    "end": { "line": 1, "character": 3 }
                  },
                  "newText": "Bee"
                }
              ]
            },
            {
              "kind": "create",
              "uri": "file:///tmp/new.swift",
              "options": { "overwrite": true, "ignoreIfExists": false }
            },
            {
              "kind": "rename",
              "oldUri": "file:///tmp/old.swift",
              "newUri": "file:///tmp/renamed.swift",
              "options": { "overwrite": false, "ignoreIfExists": true }
            },
            {
              "kind": "delete",
              "uri": "file:///tmp/delete.swift",
              "options": { "recursive": true, "ignoreIfNotExists": true }
            }
          ],
          "changeAnnotations": {
            "label-1": { "label": "Rename" }
          }
        }
        """)

        XCTAssertEqual(edit.changes["file:///tmp/a.swift"]?.first?.newText, "A")
        XCTAssertEqual(edit.documentChanges.count, 4)
        XCTAssertEqual(edit.documentEditCount, 2)
        XCTAssertEqual(edit.resourceOperationCount, 3)
        XCTAssertEqual(edit.changeAnnotations["label-1"], .object(["label": .string("Rename")]))
        XCTAssertNotNil(edit.rawJSONString)

        guard case let .textDocumentEdit(textDocumentEdit) = edit.documentChanges[0] else {
            return XCTFail("expected text document edit")
        }
        XCTAssertEqual(textDocumentEdit.textDocument.uri, "file:///tmp/b.swift")
        XCTAssertNil(textDocumentEdit.textDocument.version)

        guard case let .createFile(create) = edit.documentChanges[1] else {
            return XCTFail("expected create file")
        }
        XCTAssertEqual(create.options?.overwrite, true)

        guard case let .renameFile(rename) = edit.documentChanges[2] else {
            return XCTFail("expected rename file")
        }
        XCTAssertEqual(rename.oldUri, "file:///tmp/old.swift")
        XCTAssertEqual(rename.options?.ignoreIfExists, true)

        guard case let .deleteFile(delete) = edit.documentChanges[3] else {
            return XCTFail("expected delete file")
        }
        XCTAssertEqual(delete.options?.recursive, true)
        XCTAssertEqual(delete.options?.ignoreIfNotExists, true)
    }

    func testRenameTypedTakeWrappersStartEmpty() throws {
        let lib = try EditorCoreUIFFITestSupport.shared.loadLibrary()
        let ui = try EditorUI(library: lib, initialText: "abc", viewportWidthCells: 80)

        XCTAssertNil(try ui.lspTakeLastPrepareRenameResult())
        XCTAssertNil(try ui.lspTakeLastRenameResult())
    }
}
