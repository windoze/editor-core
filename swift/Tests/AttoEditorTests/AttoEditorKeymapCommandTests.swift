import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testKeymapParsesSublimeStyleBindingsAndOverridesDefaults() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keymapURL = tempDir.appendingPathComponent("keymap.json")
        try """
        [
          { "keys": ["cmd+shift+l"], "command": "editor.duplicate_lines" },
          { "key": "super+/", "command": "editor.toggle_line_comment" },
          { "key": "f2", "command": "lsp.rename" }
        ]
        """.write(to: keymapURL, atomically: true, encoding: .utf8)

        let env = [AttoKeymap.userKeymapEnv: keymapURL.path]
        let user = AttoKeymap.loadUserBindings(env: env)
        XCTAssertEqual(user["editor.duplicate_lines"]?.keyEquivalent, "l")
        XCTAssertEqual(
            user["editor.duplicate_lines"]?.modifiers.intersection(.deviceIndependentFlagsMask),
            [.command, .shift]
        )
        XCTAssertEqual(user["editor.toggle_line_comment"]?.keyEquivalent, "/")
        XCTAssertEqual(
            user["editor.toggle_line_comment"]?.modifiers.intersection(.deviceIndependentFlagsMask),
            [.command]
        )
        XCTAssertEqual(user["lsp.rename"]?.keyEquivalent, AttoKeymap.parseBinding("f2")?.keyEquivalent)
        XCTAssertEqual(user["lsp.rename"]?.modifiers.intersection(.deviceIndependentFlagsMask), [])
        XCTAssertEqual(AttoKeymap.parseBinding("super+ctrl+up")?.keyEquivalent, AttoKeymap.parseBinding("up")?.keyEquivalent)
        XCTAssertEqual(
            AttoKeymap.parseBinding("super+ctrl+up")?.modifiers.intersection(.deviceIndependentFlagsMask),
            [.command, .control]
        )
        XCTAssertEqual(AttoKeymap.parseBinding("cmd+shift+arrowleft")?.keyEquivalent, AttoKeymap.parseBinding("left")?.keyEquivalent)
        XCTAssertEqual(
            AttoKeymap.parseBinding("cmd+shift+arrowleft")?.modifiers.intersection(.deviceIndependentFlagsMask),
            [.command, .shift]
        )

        let resolved = AttoKeymap.resolvedBindings(env: env)
        XCTAssertEqual(resolved["editor.duplicate_lines"]?.keyEquivalent, "l")
        XCTAssertEqual(resolved["file.save"]?.keyEquivalent, "s")
        XCTAssertEqual(resolved["lsp.completion"]?.keyEquivalent, " ")
        XCTAssertEqual(
            resolved["lsp.completion"]?.modifiers.intersection(.deviceIndependentFlagsMask),
            [.control]
        )
        XCTAssertEqual(resolved["lsp.signature_help"]?.keyEquivalent, " ")
        XCTAssertEqual(
            resolved["lsp.signature_help"]?.modifiers.intersection(.deviceIndependentFlagsMask),
            [.control, .shift]
        )
        XCTAssertEqual(resolved["lsp.rename"]?.keyEquivalent, AttoKeymap.parseBinding("f2")?.keyEquivalent)
        XCTAssertEqual(resolved["lsp.code_actions"]?.keyEquivalent, ".")
        XCTAssertEqual(
            resolved["lsp.code_actions"]?.modifiers.intersection(.deviceIndependentFlagsMask),
            [.command]
        )
        XCTAssertEqual(resolved["editor.format_selection"]?.keyEquivalent, "f")
        XCTAssertEqual(
            resolved["editor.format_selection"]?.modifiers.intersection(.deviceIndependentFlagsMask),
            [.option, .shift]
        )
        XCTAssertEqual(resolved["editor.select_line"]?.keyEquivalent, "l")
        XCTAssertEqual(
            resolved["editor.select_line"]?.modifiers.intersection(.deviceIndependentFlagsMask),
            [.command]
        )
        XCTAssertEqual(resolved["editor.add_next_occurrence"]?.keyEquivalent, "d")
        XCTAssertEqual(
            resolved["editor.add_next_occurrence"]?.modifiers.intersection(.deviceIndependentFlagsMask),
            [.command]
        )
        XCTAssertEqual(resolved["editor.add_all_occurrences"]?.keyEquivalent, "g")
        XCTAssertEqual(
            resolved["editor.add_all_occurrences"]?.modifiers.intersection(.deviceIndependentFlagsMask),
            [.command, .control]
        )
        XCTAssertEqual(resolved["editor.move_lines_up"], AttoKeymap.parseBinding("super+ctrl+up"))
        XCTAssertEqual(resolved["editor.move_lines_down"], AttoKeymap.parseBinding("super+ctrl+down"))
        XCTAssertEqual(resolved["file.move_tab_left"], AttoKeymap.parseBinding("super+shift+["))
        XCTAssertEqual(resolved["file.move_tab_right"], AttoKeymap.parseBinding("super+shift+]"))
        XCTAssertEqual(resolved["go.line"], AttoKeymap.parseBinding("ctrl+g"))
        XCTAssertEqual(resolved["macro.toggle_recording"], AttoKeymap.parseBinding("ctrl+q"))
        XCTAssertEqual(resolved["macro.replay_last"], AttoKeymap.parseBinding("ctrl+shift+q"))
    }

    func testKeymapParsesExtendedSublimeStyleKeyNames() throws {
        let literalPlus = try XCTUnwrap(AttoKeymap.parseBinding("cmd++"))
        XCTAssertEqual(literalPlus.keyEquivalent, "+")
        XCTAssertEqual(literalPlus.modifiers.intersection(.deviceIndependentFlagsMask), [.command])
        XCTAssertEqual(AttoKeymap.parseBinding("cmd+plus"), literalPlus)

        XCTAssertEqual(AttoKeymap.parseBinding("cmd+minus")?.keyEquivalent, "-")
        XCTAssertEqual(AttoKeymap.parseBinding("cmd+equal")?.keyEquivalent, "=")
        XCTAssertEqual(AttoKeymap.parseBinding("cmd+comma")?.keyEquivalent, ",")
        XCTAssertEqual(AttoKeymap.parseBinding("cmd+period")?.keyEquivalent, ".")
        XCTAssertEqual(AttoKeymap.parseBinding("cmd+slash"), AttoKeymap.parseBinding("cmd+/"))
        XCTAssertEqual(AttoKeymap.parseBinding("cmd+backslash")?.keyEquivalent, "\\")
        XCTAssertEqual(AttoKeymap.parseBinding("cmd+semicolon")?.keyEquivalent, ";")
        XCTAssertEqual(AttoKeymap.parseBinding("cmd+quote")?.keyEquivalent, "'")
        XCTAssertEqual(AttoKeymap.parseBinding("cmd+grave")?.keyEquivalent, "`")
        XCTAssertEqual(AttoKeymap.parseBinding("cmd+left_bracket"), AttoKeymap.parseBinding("cmd+["))
        XCTAssertEqual(AttoKeymap.parseBinding("cmd+right-bracket"), AttoKeymap.parseBinding("cmd+]"))

        let delete = try XCTUnwrap(AttoKeymap.parseBinding("super+delete"))
        XCTAssertEqual(delete.modifiers.intersection(.deviceIndependentFlagsMask), [.command])
        XCTAssertEqual(AttoKeymap.displayText(forKeyEquivalent: delete.keyEquivalent), "delete")
        XCTAssertEqual(AttoKeymap.displayText(forKeyEquivalent: try XCTUnwrap(AttoKeymap.parseBinding("insert")).keyEquivalent), "insert")
        XCTAssertEqual(AttoKeymap.displayText(forKeyEquivalent: try XCTUnwrap(AttoKeymap.parseBinding("clear")).keyEquivalent), "clear")
        XCTAssertEqual(AttoKeymap.displayText(forKeyEquivalent: try XCTUnwrap(AttoKeymap.parseBinding("help")).keyEquivalent), "help")
        XCTAssertEqual(AttoKeymap.displayText(forKeyEquivalent: try XCTUnwrap(AttoKeymap.parseBinding("begin")).keyEquivalent), "begin")
    }

    func testKeymapContextConditionsFilterBindingsAndResolveUserConflicts() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keymapURL = tempDir.appendingPathComponent("keymap.json")
        try """
        [
          { "key": "cmd+1", "command": "file.new" },
          {
            "key": "cmd+1",
            "command": "editor.duplicate_lines",
            "context": [
              { "key": "has_active_editor", "operator": "equal", "operand": true }
            ]
          },
          {
            "key": "cmd+2",
            "command": "editor.delete_lines",
            "context": [
              { "key": "selector", "operator": "regex_match", "operand": "source\\\\.(swift|rust)" }
            ]
          },
          {
            "key": "cmd+3",
            "command": "editor.join_lines",
            "context": [
              { "key": "selection_empty", "operator": "not_equal", "operand": true }
            ]
          },
          {
            "key": "cmd+4",
            "command": "editor.split_line",
            "context": [
              { "key": "selector", "operator": "not_regex_match", "operand": "source\\\\.swift" }
            ]
          }
        ]
        """.write(to: keymapURL, atomically: true, encoding: .utf8)

        let env = [AttoKeymap.userKeymapEnv: keymapURL.path]
        let globalOnly = AttoKeymap.loadUserBindings(env: env)
        XCTAssertEqual(globalOnly["file.new"], AttoKeymap.parseBinding("cmd+1"))
        XCTAssertNil(globalOnly["editor.duplicate_lines"])
        XCTAssertNil(globalOnly["editor.delete_lines"])
        XCTAssertNil(globalOnly["editor.join_lines"])

        let swiftEditorContext = AttoKeymapContext(values: [
            "has_active_editor": .bool(true),
            "selector": .string("source.swift"),
            "selection_empty": .bool(false),
        ])
        let resolution = AttoKeymap.resolvedKeymap(env: env, context: swiftEditorContext)

        XCTAssertNil(resolution.bindings["file.new"])
        XCTAssertEqual(resolution.bindings["editor.duplicate_lines"], AttoKeymap.parseBinding("cmd+1"))
        XCTAssertEqual(resolution.bindings["editor.delete_lines"], AttoKeymap.parseBinding("cmd+2"))
        XCTAssertEqual(resolution.bindings["editor.join_lines"], AttoKeymap.parseBinding("cmd+3"))
        XCTAssertNil(resolution.bindings["editor.split_line"])

        let conflict = try XCTUnwrap(resolution.conflicts.first {
            $0.keptCommand == "editor.duplicate_lines" && $0.shadowedCommand == "file.new"
        })
        XCTAssertEqual(conflict.binding, AttoKeymap.parseBinding("cmd+1"))
    }

    func testKeymapContextRegexMatchAndContainsHaveDistinctSemantics() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keymapURL = tempDir.appendingPathComponent("keymap.json")
        try """
        [
          {
            "key": "cmd+5",
            "command": "test.regex_full",
            "context": [
              { "key": "selector", "operator": "regex_match", "operand": "source\\\\.swift meta\\\\.function" }
            ]
          },
          {
            "key": "cmd+6",
            "command": "test.regex_full_partial_reject",
            "context": [
              { "key": "selector", "operator": "regex_match", "operand": "source\\\\.swift" }
            ]
          },
          {
            "key": "cmd+7",
            "command": "test.regex_contains",
            "context": [
              { "key": "selector", "operator": "regex_contains", "operand": "meta\\\\.function" }
            ]
          },
          {
            "key": "cmd+8",
            "command": "test.not_regex_contains",
            "context": [
              { "key": "selector", "operator": "not_regex_contains", "operand": "text\\\\.plain" }
            ]
          },
          {
            "key": "cmd+9",
            "command": "test.not_regex_contains_reject",
            "context": [
              { "key": "selector", "operator": "not_regex_contains", "operand": "meta\\\\.function" }
            ]
          },
          {
            "key": "cmd+0",
            "command": "test.not_regex_match",
            "context": [
              { "key": "selector", "operator": "not_regex_match", "operand": "source\\\\.swift" }
            ]
          }
        ]
        """.write(to: keymapURL, atomically: true, encoding: .utf8)

        let env = [AttoKeymap.userKeymapEnv: keymapURL.path]
        let globalOnly = AttoKeymap.resolvedKeymap(env: env)
        XCTAssertNil(globalOnly.bindings["test.regex_full"])
        XCTAssertNil(globalOnly.bindings["test.regex_contains"])

        let context = AttoKeymapContext(values: [
            "selector": .string("source.swift meta.function"),
        ])
        let resolution = AttoKeymap.resolvedKeymap(env: env, context: context)
        XCTAssertEqual(resolution.bindings["test.regex_full"], AttoKeymap.parseBinding("cmd+5"))
        XCTAssertNil(resolution.bindings["test.regex_full_partial_reject"])
        XCTAssertEqual(resolution.bindings["test.regex_contains"], AttoKeymap.parseBinding("cmd+7"))
        XCTAssertEqual(resolution.bindings["test.not_regex_contains"], AttoKeymap.parseBinding("cmd+8"))
        XCTAssertNil(resolution.bindings["test.not_regex_contains_reject"])
        XCTAssertEqual(resolution.bindings["test.not_regex_match"], AttoKeymap.parseBinding("cmd+0"))
    }

    func testKeymapContextMatchAllEvaluatesMultiValueContexts() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keymapURL = tempDir.appendingPathComponent("keymap.json")
        try """
        [
          {
            "key": "cmd+1",
            "command": "test.any_nonempty_selection",
            "context": [
              { "key": "selection_empty", "operator": "equal", "operand": false }
            ]
          },
          {
            "key": "cmd+2",
            "command": "test.all_nonempty_selection",
            "context": [
              { "key": "selection_empty", "operator": "equal", "operand": false, "match_all": true }
            ]
          },
          {
            "key": "cmd+3",
            "command": "test.all_source_selector",
            "context": [
              { "key": "selector", "operator": "regex_contains", "operand": "source\\\\.swift", "match_all": true }
            ]
          },
          {
            "key": "cmd+4",
            "command": "test.all_not_string_selector",
            "context": [
              { "key": "selector", "operator": "not_regex_contains", "operand": "string\\\\.quoted", "match_all": true }
            ]
          }
        ]
        """.write(to: keymapURL, atomically: true, encoding: .utf8)

        let env = [AttoKeymap.userKeymapEnv: keymapURL.path]
        let mixedContext = AttoKeymapContext(values: [
            "selection_empty": .list([.bool(false), .bool(true)]),
            "selector": .list([
                .string("source.swift"),
                .string("source.swift string.quoted"),
            ]),
        ])
        let mixedResolution = AttoKeymap.resolvedKeymap(env: env, context: mixedContext)
        XCTAssertEqual(mixedResolution.bindings["test.any_nonempty_selection"], AttoKeymap.parseBinding("cmd+1"))
        XCTAssertNil(mixedResolution.bindings["test.all_nonempty_selection"])
        XCTAssertEqual(mixedResolution.bindings["test.all_source_selector"], AttoKeymap.parseBinding("cmd+3"))
        XCTAssertNil(mixedResolution.bindings["test.all_not_string_selector"])

        let allContext = AttoKeymapContext(values: [
            "selection_empty": .list([.bool(false), .bool(false)]),
            "selector": .list([
                .string("source.swift"),
                .string("source.swift meta.function"),
            ]),
        ])
        let allResolution = AttoKeymap.resolvedKeymap(env: env, context: allContext)
        XCTAssertEqual(allResolution.bindings["test.any_nonempty_selection"], AttoKeymap.parseBinding("cmd+1"))
        XCTAssertEqual(allResolution.bindings["test.all_nonempty_selection"], AttoKeymap.parseBinding("cmd+2"))
        XCTAssertEqual(allResolution.bindings["test.all_source_selector"], AttoKeymap.parseBinding("cmd+3"))
        XCTAssertEqual(allResolution.bindings["test.all_not_string_selector"], AttoKeymap.parseBinding("cmd+4"))
    }

    func testKeymapDynamicContextDispatchesActiveEditorBindings() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keymapURL = tempDir.appendingPathComponent("keymap.json")
        try """
        [
          {
            "key": "cmd+1",
            "command": "editor.duplicate_lines",
            "context": [
              { "key": "has_active_editor", "operand": true },
              { "key": "selection_empty", "operand": false, "match_all": true },
              { "key": "selector", "operator": "regex_contains", "operand": "source\\\\.swift", "match_all": true }
            ]
          },
          {
            "key": "cmd+2",
            "command": "go.line",
            "args": { "line": 2, "column": 1 },
            "context": [
              { "key": "file_extension", "operand": "swift" }
            ]
          }
        ]
        """.write(to: keymapURL, atomically: true, encoding: .utf8)

        let env = [AttoKeymap.userKeymapEnv: keymapURL.path]
        let delegate = AttoAppDelegate(
            keyBindings: [:],
            keymapResolver: { context in AttoKeymap.resolvedKeymap(env: env, context: context) }
        )
        let duplicateBinding = try XCTUnwrap(AttoKeymap.parseBinding("cmd+1"))
        let goLineBinding = try XCTUnwrap(AttoKeymap.parseBinding("cmd+2"))

        XCTAssertFalse(delegate._handleKeyBindingForTesting(duplicateBinding))

        let fileURL = tempDir.appendingPathComponent("context.swift")
        try "abc\ndef\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)
        XCTAssertFalse(delegate._handleKeyBindingForTesting(duplicateBinding))

        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 3)], primaryIndex: 0)
        let keymapContext = delegate._keymapContextForTesting()
        XCTAssertEqual(keymapContext.values["has_active_editor"], .bool(true))
        XCTAssertEqual(keymapContext.values["file_extension"], .string("swift"))
        XCTAssertEqual(keymapContext.values["selector"], .string("source.swift"))
        XCTAssertEqual(keymapContext.values["selection_empty"], .bool(false))

        XCTAssertTrue(delegate._handleKeyBindingForTesting(duplicateBinding))
        XCTAssertEqual(try editorView.editor.text(), "abc\nabc\ndef\n")

        XCTAssertEqual(delegate._keyBindingArgumentsForTesting(commandID: "go.line"), [
            "line": .integer(2),
            "column": .integer(1),
        ])
        XCTAssertTrue(delegate._handleKeyBindingForTesting(goLineBinding))
        XCTAssertEqual(try editorView.editor.selectionOffsets().start, 4)
    }

    func testKeymapUserBindingShadowsConflictingDefaultShortcut() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keymapURL = tempDir.appendingPathComponent("keymap.json")
        try """
        [
          { "key": "cmd+s", "command": "editor.duplicate_lines" }
        ]
        """.write(to: keymapURL, atomically: true, encoding: .utf8)

        let env = [AttoKeymap.userKeymapEnv: keymapURL.path]
        let resolution = AttoKeymap.resolvedKeymap(env: env)

        XCTAssertEqual(resolution.bindings["editor.duplicate_lines"], AttoKeymap.parseBinding("cmd+s"))
        XCTAssertNil(resolution.bindings["file.save"])
        let conflict = try XCTUnwrap(resolution.conflicts.first {
            $0.keptCommand == "editor.duplicate_lines" && $0.shadowedCommand == "file.save"
        })
        XCTAssertEqual(conflict.binding, AttoKeymap.parseBinding("cmd+s"))
    }

    func testKeymapArgsRouteThroughMenuCommandExecution() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keymapURL = tempDir.appendingPathComponent("keymap.json")
        try """
        [
          {
            "key": "ctrl+g",
            "command": "go.line",
            "args": { "line": 2, "column": 3 }
          },
          {
            "key": "cmd+shift+x",
            "command": "editor.apply_snippet",
            "args": { "snippet": "X$0", "unknown": { "nested": true } }
          }
        ]
        """.write(to: keymapURL, atomically: true, encoding: .utf8)

        let env = [AttoKeymap.userKeymapEnv: keymapURL.path]
        let resolution = AttoKeymap.resolvedKeymap(env: env)
        XCTAssertEqual(resolution.bindings["go.line"], AttoKeymap.parseBinding("ctrl+g"))
        XCTAssertEqual(
            resolution.arguments["go.line"],
            ["line": .integer(2), "column": .integer(3)]
        )
        XCTAssertEqual(resolution.arguments["editor.apply_snippet"]?["snippet"], .string("X$0"))
        XCTAssertEqual(resolution.arguments["editor.apply_snippet"]?["unknown"], .json(#"{"nested":true}"#))

        let delegate = AttoAppDelegate(
            keyBindings: resolution.bindings,
            keyBindingArguments: resolution.arguments
        )
        XCTAssertEqual(delegate._keyBindingArgumentsForTesting(commandID: "go.line"), [
            "line": .integer(2),
            "column": .integer(3),
        ])

        let fileURL = tempDir.appendingPathComponent("keymap-args.txt")
        try "abc\ndef\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)

        let menu = AttoMainMenuBuilder.build(appDelegate: delegate)
        let goLineItem = try XCTUnwrap(findMenuItem(commandID: "go.line", in: menu))
        delegate.commandMenuItemClicked(goLineItem)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        let offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 6)
        XCTAssertEqual(offsets.end, 6)
    }

    func testKeymapChordSequencesDispatchThroughCommandPath() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keymapURL = tempDir.appendingPathComponent("keymap.json")
        try """
        [
          {
            "keys": ["ctrl+k", "ctrl+g"],
            "command": "go.line",
            "args": { "line": 2, "column": 1 }
          }
        ]
        """.write(to: keymapURL, atomically: true, encoding: .utf8)

        let env = [AttoKeymap.userKeymapEnv: keymapURL.path]
        let resolution = AttoKeymap.resolvedKeymap(env: env)
        let chord = AttoKeySequence(bindings: [
            try XCTUnwrap(AttoKeymap.parseBinding("ctrl+k")),
            try XCTUnwrap(AttoKeymap.parseBinding("ctrl+g")),
        ])
        XCTAssertNil(resolution.bindings["go.line"])
        XCTAssertEqual(resolution.sequences["go.line"], chord)
        XCTAssertEqual(resolution.arguments["go.line"], ["line": .integer(2), "column": .integer(1)])

        var keySequenceStatusTexts: [String?] = []
        let delegate = AttoAppDelegate(
            keyBindings: resolution.bindings,
            keyBindingArguments: resolution.arguments,
            keySequences: resolution.sequences,
            keySequenceStatusHandler: { keySequenceStatusTexts.append($0) }
        )
        XCTAssertNil(delegate._keyBindingForTesting(commandID: "go.line"))
        XCTAssertEqual(delegate._keySequenceForTesting(commandID: "go.line"), chord)

        let fileURL = tempDir.appendingPathComponent("keymap-chord.txt")
        try "abc\ndef\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        XCTAssertEqual(try editorView.editor.selectionOffsets().start, 0)

        XCTAssertTrue(delegate._handleKeyBindingForTesting(chord.bindings[0]))
        XCTAssertEqual(keySequenceStatusTexts.last!, "Keys: ctrl+k")
        XCTAssertEqual(try editorView.editor.selectionOffsets().start, 0)

        XCTAssertTrue(delegate._handleKeyBindingForTesting(chord.bindings[1]))
        XCTAssertNil(keySequenceStatusTexts.last!)
        let offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 4)
        XCTAssertEqual(offsets.end, 4)
    }

    func testKeymapChordPrefixCanExpireOrBeCancelled() throws {
        let chord = AttoKeySequence(bindings: [
            try XCTUnwrap(AttoKeymap.parseBinding("ctrl+k")),
            try XCTUnwrap(AttoKeymap.parseBinding("ctrl+g")),
        ])
        var keySequenceStatusTexts: [String?] = []
        let delegate = AttoAppDelegate(
            keyBindings: [:],
            keySequences: ["go.line": chord],
            keySequencePrefixTimeoutSeconds: 0,
            keySequenceStatusHandler: { keySequenceStatusTexts.append($0) }
        )

        XCTAssertTrue(delegate._handleKeyBindingForTesting(chord.bindings[0]))
        XCTAssertEqual(delegate._pendingKeySequenceForTesting(), [chord.bindings[0]])
        XCTAssertEqual(keySequenceStatusTexts.last!, "Keys: ctrl+k")

        delegate._expirePendingKeySequenceForTesting()
        XCTAssertTrue(delegate._pendingKeySequenceForTesting().isEmpty)
        XCTAssertNil(keySequenceStatusTexts.last!)
        XCTAssertFalse(delegate._handleKeyBindingForTesting(chord.bindings[1]))
        XCTAssertTrue(delegate._pendingKeySequenceForTesting().isEmpty)

        XCTAssertTrue(delegate._handleKeyBindingForTesting(chord.bindings[0]))
        XCTAssertEqual(delegate._pendingKeySequenceForTesting(), [chord.bindings[0]])
        XCTAssertEqual(keySequenceStatusTexts.last!, "Keys: ctrl+k")

        let escape = try XCTUnwrap(AttoKeymap.parseBinding("escape"))
        XCTAssertTrue(delegate._handleKeyBindingForTesting(escape))
        XCTAssertTrue(delegate._pendingKeySequenceForTesting().isEmpty)
        XCTAssertNil(keySequenceStatusTexts.last!)
        XCTAssertFalse(delegate._handleKeyBindingForTesting(chord.bindings[1]))
    }

    func testKeymapChordPrefixUpdatesActiveWindowStatusText() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let chord = AttoKeySequence(bindings: [
            try XCTUnwrap(AttoKeymap.parseBinding("ctrl+k")),
            try XCTUnwrap(AttoKeymap.parseBinding("ctrl+g")),
        ])
        let delegate = AttoAppDelegate(
            keyBindings: [:],
            keySequences: ["go.line": chord],
            keySequencePrefixTimeoutSeconds: 0
        )

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }

        XCTAssertTrue(delegate._handleKeyBindingForTesting(chord.bindings[0]))
        XCTAssertEqual(ctx.editorAreaController._transientStatusTextForTesting(), "Keys: ctrl+k")

        delegate._expirePendingKeySequenceForTesting()
        XCTAssertNil(ctx.editorAreaController._transientStatusTextForTesting())
    }

    func testMainMenuItemsUseCommandIDsAndResolvedKeymap() throws {
        let delegate = AttoAppDelegate(
            keyBindings: [
                "editor.duplicate_lines": AttoKeyBinding(keyEquivalent: "l", modifiers: [.command, .shift]),
                "workspace.undo_last_workspace_edit": AttoKeyBinding(keyEquivalent: "z", modifiers: [.command, .option]),
                "workspace.redo_last_workspace_edit": AttoKeyBinding(keyEquivalent: "z", modifiers: [.command, .option, .shift]),
            ]
        )
        let menu = AttoMainMenuBuilder.build(appDelegate: delegate)

        let fileMenu = try XCTUnwrap(topLevelMenu(title: "File", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "file.reload", in: fileMenu))
        XCTAssertNotNil(findMenuItem(commandID: "file.pin_tab", in: fileMenu))
        XCTAssertNotNil(findMenuItem(commandID: "file.open_recent_project", in: fileMenu))
        XCTAssertNotNil(findMenuItem(commandID: "file.close_all_tabs", in: fileMenu))
        XCTAssertNotNil(findMenuItem(commandID: "file.close_other_tabs", in: fileMenu))
        XCTAssertNotNil(findMenuItem(commandID: "file.close_tabs_to_right", in: fileMenu))
        XCTAssertNotNil(findMenuItem(commandID: "file.move_tab_left", in: fileMenu))
        XCTAssertNotNil(findMenuItem(commandID: "file.move_tab_right", in: fileMenu))

        let item = try XCTUnwrap(findMenuItem(commandID: "editor.duplicate_lines", in: menu))
        XCTAssertEqual(item.representedObject as? String, "editor.duplicate_lines")
        XCTAssertEqual(item.identifier?.rawValue, "AttoCommand.editor.duplicate_lines")
        XCTAssertEqual(item.action, #selector(AttoAppDelegate.commandMenuItemClicked(_:)))
        XCTAssertTrue((item.target as AnyObject) === delegate)
        XCTAssertEqual(item.keyEquivalent, "l")
        XCTAssertEqual(
            item.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask),
            [.command, .shift]
        )

        XCTAssertNotNil(findMenuItem(commandID: "editor.format_document", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "editor.format_selection", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "settings.open_user_settings", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "settings.open_workspace_settings", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "settings.validate_user_settings", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "settings.validate_workspace_settings", in: menu))
        let workspaceUndo = try XCTUnwrap(findMenuItem(commandID: "workspace.undo_last_workspace_edit", in: menu))
        XCTAssertEqual(workspaceUndo.keyEquivalent, "z")
        XCTAssertEqual(
            workspaceUndo.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask),
            [.command, .option]
        )
        let workspaceRedo = try XCTUnwrap(findMenuItem(commandID: "workspace.redo_last_workspace_edit", in: menu))
        XCTAssertEqual(workspaceRedo.keyEquivalent, "z")
        XCTAssertEqual(
            workspaceRedo.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask),
            [.command, .option, .shift]
        )
        XCTAssertNotNil(findMenuItem(commandID: "editor.apply_snippet", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "editor.snippet_next_placeholder", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "editor.snippet_prev_placeholder", in: menu))

        let selectionMenu = try XCTUnwrap(topLevelMenu(title: "Selection", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "editor.add_next_occurrence", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "editor.add_all_occurrences", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "editor.select_word", in: selectionMenu))
        XCTAssertNotNil(findMenuItem(commandID: "editor.select_line", in: selectionMenu))
        XCTAssertNotNil(findMenuItem(commandID: "editor.expand_selection", in: selectionMenu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.selection_range", in: selectionMenu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.linked_editing", in: selectionMenu))
        XCTAssertNotNil(findMenuItem(commandID: "editor.add_cursor_above", in: selectionMenu))
        XCTAssertNotNil(findMenuItem(commandID: "editor.add_cursor_below", in: selectionMenu))
        XCTAssertNotNil(findMenuItem(commandID: "editor.add_next_occurrence", in: selectionMenu))
        XCTAssertNotNil(findMenuItem(commandID: "editor.add_all_occurrences", in: selectionMenu))

        let toolsMenu = try XCTUnwrap(topLevelMenu(title: "Tools", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "macro.toggle_recording", in: toolsMenu))
        XCTAssertNotNil(findMenuItem(commandID: "macro.replay_last", in: toolsMenu))
        XCTAssertNotNil(findMenuItem(commandID: "macro.save_named", in: toolsMenu))
        XCTAssertNotNil(findMenuItem(commandID: "macro.replay_named", in: toolsMenu))
        XCTAssertNotNil(findMenuItem(commandID: "macro.rename_named", in: toolsMenu))
        XCTAssertNotNil(findMenuItem(commandID: "macro.delete_named", in: toolsMenu))
        XCTAssertNotNil(findMenuItem(commandID: "macro.delete_named_batch", in: toolsMenu))
        XCTAssertNotNil(findMenuItem(commandID: "macro.undo_delete", in: toolsMenu))
        XCTAssertNotNil(findMenuItem(commandID: "macro.show_delete_history", in: toolsMenu))
        XCTAssertNotNil(findMenuItem(commandID: "macro.manage_delete_history", in: toolsMenu))
        XCTAssertNotNil(findMenuItem(commandID: "macro.remove_delete_history_entry", in: toolsMenu))
        XCTAssertNotNil(findMenuItem(commandID: "macro.remove_delete_history_entries", in: toolsMenu))
        XCTAssertNotNil(findMenuItem(commandID: "macro.clear_delete_history", in: toolsMenu))
        XCTAssertNotNil(findMenuItem(commandID: "macro.import_file", in: toolsMenu))
        XCTAssertNotNil(findMenuItem(commandID: "macro.export_named", in: toolsMenu))

        XCTAssertNotNil(findMenuItem(commandID: "view.wrap.word", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "view.split_right", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "view.focus_next_pane", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "view.focus_previous_pane", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "view.move_pane_left", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "view.move_pane_right", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "view.close_pane", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "editor.fold_selection", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.refresh_folding_ranges", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "go.line", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.go_to_definition", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.find_references", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_last_locations", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_location_history", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_workbench_panel", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_workbench_dock", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_workbench_history", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_workbench_pinned_results", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_workbench_selected_history", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.jump_workbench_first_result", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.jump_workbench_selected_result", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.refresh_workbench_selected_result", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.pin_workbench_current_results", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.pin_workbench_selected_result", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.unpin_workbench_current_results", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.unpin_workbench_selected_result", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.clear_workbench_stale_results", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.clear_workbench_selected_stale_result", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_problems_panel", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.call_hierarchy_incoming", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.call_hierarchy_outgoing", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.type_hierarchy_supertypes", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.type_hierarchy_subtypes", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_hierarchy_panel", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.refresh_hierarchy_panel", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.expand_hierarchy_selection", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.document_symbols", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.workspace_symbols", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_last_symbols", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_symbol_history", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_symbols_panel", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.completion", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.signature_help", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.rename", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.code_actions", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.code_lens_actions", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.code_lens_at_cursor", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_code_lens_panel", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.refresh_code_lens", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.refresh_inlay_hints", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_inlay_hints_panel", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.refresh_document_links", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_document_links_panel", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.quick_fix", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.refactor", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.source_actions", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.organize_imports", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.fix_all", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.problems", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.workspace_diagnostics", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_workspace_problems_panel", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_project_lsp_status", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_project_lsp_health", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_project_lsp_health_log", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_project_lsp_dashboard", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.clear_project_lsp_health_log", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.export_project_lsp_health_log", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.restart_server", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.shutdown_server", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.restart_project_servers", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.shutdown_project_servers", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.document_colors", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.pick_document_color", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_document_colors_panel", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.refresh_document_colors", in: menu))
    }

    func testKeymapContextUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("keymap-local.txt")
        let projectedURL = tempDir.appendingPathComponent("keymap-projected.py")
        try "print(1)\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let tab = try XCTUnwrap(vc.tabs.first)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(tab.coreTabID)
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        let keymapContext = vc.keymapContextForActiveState()
        XCTAssertEqual(keymapContext.values["file_name"], .string("keymap-projected.py"))
        XCTAssertEqual(keymapContext.values["file_extension"], .string("py"))
        XCTAssertEqual(keymapContext.values["syntax"], .string("python"))
        XCTAssertEqual(keymapContext.values["selector"], .string("source.python"))
    }
}
