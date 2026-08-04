import AppKit
@testable import AttoEditor
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testSublimeKeymapParserAcceptsCommentsTrailingCommasAndSublimeKeymapExtension() throws {
        try withTemporaryKeymap(named: "Default (OSX).sublime-keymap", contents: """
        [
          // Line comments are common in hand-edited Sublime keymap files.
          {
            "keys": ["super+shift+l"],
            "command": "editor.duplicate_lines",
            "args": { "note": "https://example.com/a//b" },
          },
          /*
            Block comments should be ignored without touching string values.
          */
          {
            "keys": ["ctrl+k", "ctrl+g"],
            "command": "go.line",
            "args": { "line": 2, "column": 1 },
          },
        ]
        """) { env in
            let resolution = AttoKeymap.resolvedKeymap(env: env)
            XCTAssertEqual(resolution.bindings["editor.duplicate_lines"], AttoKeymap.parseBinding("super+shift+l"))
            XCTAssertEqual(resolution.arguments["editor.duplicate_lines"], [
                "note": .string("https://example.com/a//b"),
            ])
            XCTAssertEqual(
                resolution.sequences["go.line"],
                AttoKeySequence(bindings: [
                    try XCTUnwrap(AttoKeymap.parseBinding("ctrl+k")),
                    try XCTUnwrap(AttoKeymap.parseBinding("ctrl+g")),
                ])
            )
            XCTAssertEqual(resolution.arguments["go.line"], ["line": .integer(2), "column": .integer(1)])
        }
    }

    func testSublimeKeymapSelectorContextUsesScopeContainment() throws {
        try withTemporaryKeymap(contents: """
        [
          {
            "key": "cmd+1",
            "command": "editor.duplicate_lines",
            "context": [
              { "key": "selector", "operand": "source.swift" }
            ]
          },
          {
            "key": "cmd+2",
            "command": "editor.delete_lines",
            "context": [
              { "key": "selector", "operator": "not_equal", "operand": "text.plain" }
            ]
          },
          {
            "key": "cmd+3",
            "command": "editor.join_lines",
            "context": [
              { "key": "selector", "operand": "source" }
            ]
          },
          {
            "key": "cmd+4",
            "command": "editor.split_line",
            "context": [
              { "key": "selector", "operand": "source.python" }
            ]
          },
          {
            "key": "cmd+5",
            "command": "editor.outdent",
            "context": [
              { "key": "selector", "operator": "not_equal", "operand": "source.swift" }
            ]
          }
        ]
        """) { env in
            let context = AttoKeymapContext(values: [
                "selector": .string("source.swift meta.function"),
            ])
            let resolution = AttoKeymap.resolvedKeymap(env: env, context: context)

            XCTAssertEqual(resolution.bindings["editor.duplicate_lines"], AttoKeymap.parseBinding("cmd+1"))
            XCTAssertEqual(resolution.bindings["editor.delete_lines"], AttoKeymap.parseBinding("cmd+2"))
            XCTAssertEqual(resolution.bindings["editor.join_lines"], AttoKeymap.parseBinding("cmd+3"))
            XCTAssertNil(resolution.bindings["editor.split_line"])
            XCTAssertNil(resolution.bindings["editor.outdent"])
        }
    }

    func testSublimeKeymapFallbackKeepsDefaultsForMalformedFilesAndInvalidEntries() throws {
        try withTemporaryKeymap(contents: #"[{ "key": "cmd+1", "#) { env in
            let resolution = AttoKeymap.resolvedKeymap(env: env)
            XCTAssertEqual(resolution.bindings["file.save"], AttoKeymap.defaultBindings["file.save"])
            XCTAssertEqual(resolution.bindings["editor.join_lines"], AttoKeymap.defaultBindings["editor.join_lines"])
            XCTAssertTrue(resolution.conflicts.isEmpty)
            XCTAssertTrue(resolution.sequenceConflicts.isEmpty)
        }

        try withTemporaryKeymap(contents: """
        [
          { "key": "cmd+1", "command": "editor.duplicate_lines" },
          { "keys": [], "command": "editor.delete_lines" },
          { "keys": ["cmd+2", "cmd+bad+extra"], "command": "editor.join_lines" },
          { "key": "", "command": "file.save" }
        ]
        """) { env in
            let resolution = AttoKeymap.resolvedKeymap(env: env)
            XCTAssertEqual(resolution.bindings["editor.duplicate_lines"], AttoKeymap.parseBinding("cmd+1"))
            XCTAssertEqual(resolution.bindings["editor.delete_lines"], AttoKeymap.defaultBindings["editor.delete_lines"])
            XCTAssertEqual(resolution.bindings["editor.join_lines"], AttoKeymap.defaultBindings["editor.join_lines"])
            XCTAssertEqual(resolution.bindings["file.save"], AttoKeymap.defaultBindings["file.save"])
        }
    }

    private func withTemporaryKeymap(
        named fileName: String = "keymap.json",
        contents: String,
        _ body: ([String: String]) throws -> Void
    ) throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorSublimeKeymapTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keymapURL = tempDir.appendingPathComponent(fileName)
        try contents.write(to: keymapURL, atomically: true, encoding: .utf8)
        try body([AttoKeymap.userKeymapEnv: keymapURL.path])
    }
}
