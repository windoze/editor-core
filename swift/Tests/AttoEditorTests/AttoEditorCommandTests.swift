import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoEditorCommandTests: XCTestCase {
    func testDefaultCommandPaletteIncludesCoreEditorCommandIDs() throws {
        let delegate = AttoAppDelegate()
        let ids = Set(delegate._defaultCommandsForTesting().map(\.id))

        XCTAssertTrue(ids.contains("editor.format_document"))
        XCTAssertTrue(ids.contains("editor.format_selection"))
        XCTAssertTrue(ids.contains("editor.duplicate_lines"))
        XCTAssertTrue(ids.contains("file.close_tab"))
        XCTAssertTrue(ids.contains("file.move_tab_left"))
        XCTAssertTrue(ids.contains("file.move_tab_right"))
        XCTAssertTrue(ids.contains("editor.delete_lines"))
        XCTAssertTrue(ids.contains("editor.move_lines_up"))
        XCTAssertTrue(ids.contains("editor.move_lines_down"))
        XCTAssertTrue(ids.contains("editor.join_lines"))
        XCTAssertTrue(ids.contains("editor.split_line"))
        XCTAssertTrue(ids.contains("editor.apply_snippet"))
        XCTAssertTrue(ids.contains("editor.snippet_next_placeholder"))
        XCTAssertTrue(ids.contains("editor.snippet_prev_placeholder"))
        XCTAssertTrue(ids.contains("editor.add_next_occurrence"))
        XCTAssertTrue(ids.contains("editor.add_all_occurrences"))
        XCTAssertTrue(ids.contains("editor.select_word"))
        XCTAssertTrue(ids.contains("editor.select_line"))
        XCTAssertTrue(ids.contains("editor.expand_selection"))
        XCTAssertTrue(ids.contains("editor.add_cursor_above"))
        XCTAssertTrue(ids.contains("editor.add_cursor_below"))
        XCTAssertTrue(ids.contains("editor.toggle_line_comment"))
        XCTAssertTrue(ids.contains("editor.fold_selection"))
        XCTAssertTrue(ids.contains("editor.unfold"))
        XCTAssertTrue(ids.contains("editor.unfold_all"))
        for command in AttoEditorAreaViewController.CursorMovementCommand.allCases {
            XCTAssertTrue(ids.contains(command.id), command.id)
        }
        XCTAssertTrue(ids.contains("view.wrap.word"))
        XCTAssertTrue(ids.contains("view.split_right"))
        XCTAssertTrue(ids.contains("view.focus_next_pane"))
        XCTAssertTrue(ids.contains("view.focus_previous_pane"))
        XCTAssertTrue(ids.contains("view.move_pane_left"))
        XCTAssertTrue(ids.contains("view.move_pane_right"))
        XCTAssertTrue(ids.contains("view.close_pane"))
        XCTAssertTrue(ids.contains("go.line"))
        XCTAssertTrue(ids.contains("lsp.go_to_definition"))
        XCTAssertTrue(ids.contains("lsp.go_to_declaration"))
        XCTAssertTrue(ids.contains("lsp.go_to_type_definition"))
        XCTAssertTrue(ids.contains("lsp.go_to_implementation"))
        XCTAssertTrue(ids.contains("lsp.find_references"))
        XCTAssertTrue(ids.contains("lsp.show_last_locations"))
        XCTAssertTrue(ids.contains("lsp.show_location_history"))
        XCTAssertTrue(ids.contains("lsp.show_locations_panel"))
        XCTAssertTrue(ids.contains("lsp.show_problems_panel"))
        XCTAssertTrue(ids.contains("lsp.call_hierarchy_incoming"))
        XCTAssertTrue(ids.contains("lsp.call_hierarchy_outgoing"))
        XCTAssertTrue(ids.contains("lsp.type_hierarchy_supertypes"))
        XCTAssertTrue(ids.contains("lsp.type_hierarchy_subtypes"))
        XCTAssertTrue(ids.contains("lsp.document_symbols"))
        XCTAssertTrue(ids.contains("lsp.workspace_symbols"))
        XCTAssertTrue(ids.contains("lsp.show_last_symbols"))
        XCTAssertTrue(ids.contains("lsp.show_symbol_history"))
        XCTAssertTrue(ids.contains("lsp.show_symbols_panel"))
        XCTAssertTrue(ids.contains("lsp.completion"))
        XCTAssertTrue(ids.contains("lsp.signature_help"))
        XCTAssertTrue(ids.contains("lsp.rename"))
        XCTAssertTrue(ids.contains("lsp.code_actions"))
        XCTAssertTrue(ids.contains("lsp.code_lens_actions"))
        XCTAssertTrue(ids.contains("lsp.code_lens_at_cursor"))
        XCTAssertTrue(ids.contains("lsp.refresh_code_lens"))
        XCTAssertTrue(ids.contains("lsp.quick_fix"))
        XCTAssertTrue(ids.contains("lsp.refactor"))
        XCTAssertTrue(ids.contains("lsp.source_actions"))
        XCTAssertTrue(ids.contains("lsp.organize_imports"))
        XCTAssertTrue(ids.contains("lsp.fix_all"))
        XCTAssertTrue(ids.contains("lsp.problems"))
        XCTAssertTrue(ids.contains("lsp.workspace_diagnostics"))
        XCTAssertTrue(ids.contains("lsp.show_workspace_problems_panel"))
        XCTAssertTrue(ids.contains("lsp.document_colors"))
        XCTAssertTrue(ids.contains("lsp.pick_document_color"))
        XCTAssertTrue(ids.contains("lsp.refresh_folding_ranges"))
        XCTAssertTrue(ids.contains("lsp.selection_range"))
        XCTAssertTrue(ids.contains("lsp.linked_editing"))
    }

    func testCommandRegistryCarriesMetadataAndAvailability() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let commands = delegate._defaultCommandsForTesting()

        let duplicate = try XCTUnwrap(commands.first { $0.id == "editor.duplicate_lines" })
        XCTAssertEqual(duplicate.group, "Edit")
        XCTAssertTrue(duplicate.requiresEditor)
        XCTAssertFalse(duplicate.isEnabled)

        let openFile = try XCTUnwrap(commands.first { $0.id == "file.open_file" })
        XCTAssertEqual(openFile.group, "File")
        XCTAssertFalse(openFile.requiresEditor)
        XCTAssertTrue(openFile.isEnabled)

        let cursor = try XCTUnwrap(commands.first { $0.id == "cursor.move_down" })
        XCTAssertEqual(cursor.group, "Cursor")
        XCTAssertTrue(cursor.requiresEditor)
        XCTAssertFalse(cursor.isEnabled)
    }

    func testCommandRegistryCarriesParameterSchemasAndMacroPolicies() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        XCTAssertTrue(delegate._commandConflictsForTesting().isEmpty)

        let duplicate = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "editor.duplicate_lines"))
        XCTAssertEqual(duplicate.macroPolicy, .recordable)
        XCTAssertEqual(duplicate.defaultPayloadJSON, #"{"kind":"edit","op":"duplicate_lines"}"#)
        XCTAssertEqual(duplicate.requiredRuntimeFeatures, .jsonCommandDispatch)
        XCTAssertFalse(duplicate.isParameterized)

        let snippet = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "editor.apply_snippet"))
        XCTAssertEqual(snippet.macroPolicy, .recordableWithArguments)
        XCTAssertEqual(snippet.parameters.map(\.name), ["snippet"])
        XCTAssertEqual(snippet.parameters.first?.kind, .string)
        XCTAssertTrue(snippet.parameters.first?.isRequired == true)
        XCTAssertTrue(snippet.requiredRuntimeFeatures.isEmpty)

        let goLine = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "go.line"))
        XCTAssertEqual(goLine.macroPolicy, .recordableWithArguments)
        XCTAssertEqual(goLine.parameters.map(\.name), ["line", "column"])
        XCTAssertEqual(goLine.parameters[0].kind, .integer)
        XCTAssertEqual(goLine.parameters[0].minimumInteger, 1)
        XCTAssertEqual(goLine.parameters[1].defaultValue, .integer(1))
        XCTAssertTrue(goLine.requiredRuntimeFeatures.isEmpty)
        XCTAssertEqual(
            try goLine.normalizedArguments(["line": .integer(42)]),
            ["line": .integer(42), "column": .integer(1)]
        )
        XCTAssertThrowsError(try goLine.normalizedArguments(["line": .integer(0)]))
        XCTAssertThrowsError(try goLine.normalizedArguments(["line": .string("42")]))

        let workspaceSymbols = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "lsp.workspace_symbols"))
        XCTAssertEqual(workspaceSymbols.parameters.map(\.name), ["query"])
        XCTAssertEqual(workspaceSymbols.requiredRuntimeFeatures, .lspInteractiveCommandRequirements)
        XCTAssertEqual(
            try workspaceSymbols.normalizedArguments([:]),
            ["query": .string("")]
        )

        let rename = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "lsp.rename"))
        XCTAssertEqual(rename.parameters.map(\.name), ["newName"])
        XCTAssertEqual(rename.macroPolicy, .recordableWithArguments)
        XCTAssertEqual(rename.requiredRuntimeFeatures, .lspWorkspaceEditCommandRequirements)

        let openFile = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "file.open_file"))
        XCTAssertEqual(openFile.macroPolicy, .promptRequired)
    }

    func testCommandRegistryDisablesCommandsForMissingOptionalRuntimeFeatures() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("runtime.txt")
        try "a\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "editor.duplicate_lines"))
        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "editor.apply_snippet"))
        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "editor.format_document"))
        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "lsp.workspace_symbols"))
        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "lsp.rename"))

        delegate._setRuntimeInfoForTesting(EditorCoreUIFFIRuntimeInfo(
            abiVersion: AttoRuntimeCompatibility.minimumUIABIVersion,
            version: "test",
            features: AttoRuntimeCompatibility.requiredFeatures.reduce([]) { acc, required in
                acc.union(required.feature)
            }
        ))

        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "editor.duplicate_lines"))
        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "editor.apply_snippet"))
        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "editor.format_document"))
        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "lsp.workspace_symbols"))
        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "lsp.rename"))
        XCTAssertFalse(delegate.executeCommand(id: "lsp.workspace_symbols", arguments: ["query": .string("A")]))
    }

    func testEditorCommandsAreDisabledWithoutActiveEditor() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let menu = AttoMainMenuBuilder.build(appDelegate: delegate)
        let item = try XCTUnwrap(findMenuItem(commandID: "editor.duplicate_lines", in: menu))

        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "editor.duplicate_lines"))
        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "cursor.move_down"))
        XCTAssertFalse(delegate.validateMenuItem(item))
        XCTAssertFalse(delegate.executeCommand(id: "editor.duplicate_lines"))
        XCTAssertFalse(delegate.executeCommand(id: "cursor.move_down"))
    }

    func testWorkspaceSymbolsPromptRequiresActiveEditor() throws {
        let vc = makeEditorArea(workspaceRootURL: FileManager.default.temporaryDirectory)
        _ = vc.view

        XCTAssertFalse(vc.promptWorkspaceSymbolsInActiveTab(initialQuery: "app"))
    }

    func testWorkspaceSymbolsPromptRequiresEnabledLsp() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("symbols.swift")
        try "func app() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.promptWorkspaceSymbolsInActiveTab(initialQuery: "app"))
        XCTAssertNil(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.WorkspaceSymbolSearch")
        })
    }

    func testApplyFoldingRangesResultUpdatesDerivedState() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("folds.txt")
        try """
        import A
        import B
        let value = 1
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(
            vc.applyFoldingRangesResultJSONToActiveTab(
                #"[{"startLine":0,"endLine":1,"kind":"imports"}]"#
            )
        )

        let regions = vc._activeDerivedStateForTesting().foldingRegions.regions
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].startLine, 0)
        XCTAssertEqual(regions[0].endLine, 1)
        XCTAssertFalse(regions[0].isCollapsed)
        XCTAssertEqual(regions[0].placeholder, "use ...")
    }

    func testRefreshCodeLensRequiresEnabledLsp() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("lens.txt")
        try "func demo() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.refreshCodeLensInActiveTab(showFeedback: false))
    }

    func testCodeLensAtCursorFiltersActionsToCurrentLine() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("lens.swift")
        let text = """
        func one() {}
        func two() {}
        """
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.lspApplyCodeLensJSON("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 0 }
            },
            "command": { "title": "Run One", "command": "test.runOne" }
          },
          {
            "range": {
              "start": { "line": 1, "character": 0 },
              "end": { "line": 1, "character": 0 }
            },
            "command": { "title": "Run Two", "command": "test.runTwo" }
          }
        ]
        """)
        let secondLineStart = UInt32("func one() {}\n".unicodeScalars.count)
        try editorView.editor.setSelections(
            [EcuSelectionRange(start: secondLineStart, end: secondLineStart)],
            primaryIndex: 0
        )

        XCTAssertTrue(vc.showCodeLensActionsAtCursorInActiveTab())

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.CodeLens")
        })
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.CodeLens"),
                in: root
            ) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter current-line code lens actions...")

        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.CodeLens"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 1)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(cell.textField?.stringValue.contains("Run Two") == true)
        XCTAssertFalse(cell.textField?.stringValue.contains("Run One") == true)
    }

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
            ]
        )
        let menu = AttoMainMenuBuilder.build(appDelegate: delegate)

        let fileMenu = try XCTUnwrap(topLevelMenu(title: "File", in: menu))
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
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_problems_panel", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.call_hierarchy_incoming", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.call_hierarchy_outgoing", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.type_hierarchy_supertypes", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.type_hierarchy_subtypes", in: menu))
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
        XCTAssertNotNil(findMenuItem(commandID: "lsp.refresh_code_lens", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.quick_fix", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.refactor", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.source_actions", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.organize_imports", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.fix_all", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.problems", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.workspace_diagnostics", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_workspace_problems_panel", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.document_colors", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.pick_document_color", in: menu))
    }

    func testWorkspaceDiagnosticsResultNavigatesWithoutPanelWindow() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("diagnostics.swift")
        try "first\nab😀cd\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(vc.showWorkspaceDiagnosticsResultJSONInActiveTab("""
        {
          "items": [
            {
              "uri": "\(fileURL.absoluteString)",
              "kind": "full",
              "resultId": "diag-1",
              "items": [
                {
                  "range": {
                    "start": { "line": 1, "character": 2 },
                    "end": { "line": 1, "character": 4 }
                  },
                  "severity": 1,
                  "message": "demo diagnostic"
                }
              ]
            }
          ]
        }
        """))

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let selections = try editorView.editor.selections()
        XCTAssertEqual(selections.ranges, [EcuSelectionRange(start: 8, end: 8)])
        XCTAssertEqual(selections.primaryIndex, 0)
    }

    func testWorkspaceProblemsPanelUsesStoredDiagnosticsAndRefreshesWithResults() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("workspace-problems.swift")
        try "first\nsecond\nthird\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(vc.showWorkspaceDiagnosticsResultJSONInActiveTab("""
        {
          "items": [
            {
              "uri": "\(fileURL.absoluteString)",
              "kind": "full",
              "resultId": "diag-1",
              "items": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 5 }
                  },
                  "severity": 1,
                  "source": "unit-test",
                  "message": "first workspace problem"
                },
                {
                  "range": {
                    "start": { "line": 1, "character": 0 },
                    "end": { "line": 1, "character": 6 }
                  },
                  "severity": 2,
                  "source": "unit-test",
                  "message": "second workspace warning"
                }
              ]
            }
          ]
        }
        """))

        XCTAssertEqual(vc._workspaceProblemsSnapshotForTesting().diagnostics.map(\.message), [
            "first workspace problem",
            "second workspace warning",
        ])

        XCTAssertTrue(vc.showWorkspaceProblemsPanelInActiveTab())
        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.workspaceProblemsPanel
        })
        XCTAssertEqual(panel.title, "Workspace Problems (2)")
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.workspaceProblemsPanelSearchField, in: root) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter workspace problems...")
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.workspaceProblemsPanelTable, in: root) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertTrue(vc._workspaceProblemsPanelIsVisibleForTesting())

        XCTAssertTrue(vc.showWorkspaceDiagnosticsResultJSONInActiveTab("""
        {
          "items": [
            {
              "uri": "\(fileURL.absoluteString)",
              "kind": "full",
              "resultId": "diag-2",
              "items": [
                {
                  "range": {
                    "start": { "line": 2, "character": 0 },
                    "end": { "line": 2, "character": 5 }
                  },
                  "severity": 1,
                  "source": "unit-test",
                  "message": "third workspace problem"
                }
              ]
            }
          ]
        }
        """))
        XCTAssertEqual(panel.title, "Workspace Problems (1)")
        XCTAssertEqual(vc._workspaceProblemsPanelDiagnosticsForTesting().map(\.message), ["third workspace problem"])
        XCTAssertEqual(vc._workspaceProblemsPanelRowCountForTesting(), 1)
    }

    func testImplementationMultiLocationResultUsesPanel() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("impl.swift")
        try "func one() {}\nfunc two() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(vc.showLspLocationResultJSONInActiveTab("""
        [
          {
            "uri": "\(fileURL.absoluteString)",
            "range": {
              "start": { "line": 0, "character": 5 },
              "end": { "line": 0, "character": 8 }
            }
          },
          {
            "uri": "\(fileURL.absoluteString)",
            "range": {
              "start": { "line": 1, "character": 5 },
              "end": { "line": 1, "character": 8 }
            }
          }
        ]
        """, kind: .implementation))

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.LocationResults")
        })
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.LocationResults"),
                in: root
            ) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter implementations...")

        let snapshot = try XCTUnwrap(vc._lastLspLocationResultForTesting())
        XCTAssertEqual(snapshot.kind, .implementation)
        XCTAssertEqual(snapshot.items.count, 2)

        XCTAssertTrue(vc.showLspLocationPanel())
        let persistentPanel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.lspLocationPanel
        })
        XCTAssertEqual(persistentPanel.title, "Implementations (2)")
        let persistentRoot = try XCTUnwrap(persistentPanel.contentView)
        let persistentSearchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspLocationPanelSearchField,
                in: persistentRoot
            ) as? NSSearchField
        )
        XCTAssertEqual(persistentSearchField.placeholderString, "Filter implementations...")
        let persistentTable = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspLocationPanelTable,
                in: persistentRoot
            ) as? NSTableView
        )
        XCTAssertEqual(persistentTable.numberOfRows, 2)
        XCTAssertEqual(vc._lspLocationPanelSnapshotForTesting(), snapshot)
        XCTAssertTrue(vc._lspLocationPanelIsVisibleForTesting())

        panel.close()
        XCTAssertTrue(vc.showLastLspLocationResults())

        let reopenedPanel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.LocationResults")
        })
        let reopenedRoot = try XCTUnwrap(reopenedPanel.contentView)
        let reopenedSearchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.LocationResults"),
                in: reopenedRoot
            ) as? NSSearchField
        )
        XCTAssertEqual(reopenedSearchField.placeholderString, "Filter implementations...")

        reopenedPanel.close()
        XCTAssertTrue(vc.showLspLocationResultJSONInActiveTab("""
        {
          "uri": "\(fileURL.absoluteString)",
          "range": {
            "start": { "line": 0, "character": 0 },
            "end": { "line": 0, "character": 3 }
          }
        }
        """, kind: .definition))
        XCTAssertEqual(vc._lspLocationResultHistoryForTesting().map(\.kind), [.implementation, .definition])
        let updatedPanelSnapshot = try XCTUnwrap(vc._lspLocationPanelSnapshotForTesting())
        XCTAssertEqual(updatedPanelSnapshot.kind, .definition)
        XCTAssertEqual(vc._lspLocationPanelRowCountForTesting(), 1)

        XCTAssertTrue(vc.showLspLocationHistory())
        let historyPanel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.LocationHistory")
        })
        let historyRoot = try XCTUnwrap(historyPanel.contentView)
        let historySearchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.LocationHistory"),
                in: historyRoot
            ) as? NSSearchField
        )
        XCTAssertEqual(historySearchField.placeholderString, "Filter location history...")
        let historyTable = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.LocationHistory"),
                in: historyRoot
            ) as? NSTableView
        )
        XCTAssertEqual(historyTable.numberOfRows, 2)
        let firstCell = try XCTUnwrap(historyTable.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(firstCell.textField?.stringValue.contains("Definitions") == true)
    }

    func testWorkspaceSymbolResultCanBeReopened() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("symbols.swift")
        try "func openProject() {}\nstruct Project {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(vc.showWorkspaceSymbolResultJSONInActiveTab("""
        [
          {
            "name": "openProject",
            "kind": 12,
            "location": {
              "uri": "\(fileURL.absoluteString)",
              "range": {
                "start": { "line": 0, "character": 5 },
                "end": { "line": 0, "character": 16 }
              }
            }
          },
          {
            "name": "Project",
            "kind": 23,
            "location": { "uri": "\(fileURL.absoluteString)" }
          }
        ]
        """, query: "Project"))

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.SymbolResults")
        })
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.SymbolResults"),
                in: root
            ) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter workspace symbols...")

        let snapshot = try XCTUnwrap(vc._lastLspSymbolResultForTesting())
        XCTAssertEqual(snapshot.symbols.map(\.name), ["Project", "openProject"])
        XCTAssertEqual(snapshot.placeholder, "Filter workspace symbols...")

        XCTAssertTrue(vc.showLspSymbolPanel())
        let persistentPanel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.lspSymbolPanel
        })
        XCTAssertEqual(persistentPanel.title, "Workspace Symbols: Project (2)")
        let persistentRoot = try XCTUnwrap(persistentPanel.contentView)
        let persistentSearchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspSymbolPanelSearchField,
                in: persistentRoot
            ) as? NSSearchField
        )
        XCTAssertEqual(persistentSearchField.placeholderString, "Filter workspace symbols...")
        let persistentTable = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspSymbolPanelTable,
                in: persistentRoot
            ) as? NSTableView
        )
        XCTAssertEqual(persistentTable.numberOfRows, 2)
        XCTAssertEqual(vc._lspSymbolPanelSnapshotForTesting(), snapshot)
        XCTAssertTrue(vc._lspSymbolPanelIsVisibleForTesting())

        panel.close()
        XCTAssertTrue(vc.showLastLspSymbolResults())

        let reopenedPanel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.SymbolResults")
        })
        let reopenedRoot = try XCTUnwrap(reopenedPanel.contentView)
        let reopenedSearchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.SymbolResults"),
                in: reopenedRoot
            ) as? NSSearchField
        )
        XCTAssertEqual(reopenedSearchField.placeholderString, "Filter workspace symbols...")

        reopenedPanel.close()
        XCTAssertTrue(vc.showWorkspaceSymbolResultJSONInActiveTab("""
        [
          {
            "name": "openProject",
            "kind": 12,
            "location": {
              "uri": "\(fileURL.absoluteString)",
              "range": {
                "start": { "line": 0, "character": 5 },
                "end": { "line": 0, "character": 16 }
              }
            }
          }
        ]
        """, query: "Open"))

        let history = vc._lspSymbolResultHistoryForTesting()
        XCTAssertEqual(history.map(\.title), ["Workspace Symbols: Project", "Workspace Symbols: Open"])
        let updatedPanelSnapshot = try XCTUnwrap(vc._lspSymbolPanelSnapshotForTesting())
        XCTAssertEqual(updatedPanelSnapshot.title, "Workspace Symbols: Open")
        XCTAssertEqual(vc._lspSymbolPanelRowCountForTesting(), 1)

        XCTAssertTrue(vc.showLspSymbolHistory())
        let historyPanel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.SymbolHistory")
        })
        let historyRoot = try XCTUnwrap(historyPanel.contentView)
        let historySearchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.SymbolHistory"),
                in: historyRoot
            ) as? NSSearchField
        )
        XCTAssertEqual(historySearchField.placeholderString, "Filter symbol history...")
        let historyTable = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.SymbolHistory"),
                in: historyRoot
            ) as? NSTableView
        )
        XCTAssertEqual(historyTable.numberOfRows, 2)
        let firstCell = try XCTUnwrap(historyTable.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(firstCell.textField?.stringValue.contains("Workspace Symbols: Open") == true)
    }

    func testApplyLinkedEditingRangeResultCreatesMulticursorSelections() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("linked.txt")
        try "foo + foo\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 7, end: 7)], primaryIndex: 0)

        let json = """
        {
          "ranges": [
            {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 3 }
            },
            {
              "start": { "line": 0, "character": 6 },
              "end": { "line": 0, "character": 9 }
            }
          ],
          "wordPattern": "[A-Za-z]+"
        }
        """

        XCTAssertTrue(vc.applyLinkedEditingRangeResultJSONToActiveTab(json, caretOffset: 7))

        let selections = try editorView.editor.selections()
        XCTAssertEqual(
            selections.ranges,
            [
                EcuSelectionRange(start: 0, end: 3),
                EcuSelectionRange(start: 6, end: 9),
            ]
        )
        XCTAssertEqual(selections.primaryIndex, 1)
        XCTAssertTrue(vc._linkedEditingSessionIsActiveForTesting())
    }

    func testApplyLinkedEditingRangeResultRejectsWordPatternMismatch() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("linked-mismatch.txt")
        try "123 + 123\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        let json = """
        {
          "ranges": [
            {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 3 }
            },
            {
              "start": { "line": 0, "character": 6 },
              "end": { "line": 0, "character": 9 }
            }
          ],
          "wordPattern": "[A-Za-z]+"
        }
        """

        XCTAssertFalse(vc.applyLinkedEditingRangeResultJSONToActiveTab(json, caretOffset: 0))

        let selections = try editorView.editor.selections()
        XCTAssertEqual(selections.ranges, [EcuSelectionRange(start: 0, end: 0)])
        XCTAssertEqual(selections.primaryIndex, 0)
        XCTAssertFalse(vc._linkedEditingSessionIsActiveForTesting())
    }

    func testLinkedEditingSessionPersistsAcrossTextMutationAndExitsOnNavigation() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("linked-session.txt")
        try "foo + foo\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 7, end: 7)], primaryIndex: 0)

        let json = """
        {
          "ranges": [
            {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 3 }
            },
            {
              "start": { "line": 0, "character": 6 },
              "end": { "line": 0, "character": 9 }
            }
          ],
          "wordPattern": "[A-Za-z]+"
        }
        """

        XCTAssertTrue(vc.applyLinkedEditingRangeResultJSONToActiveTab(json, caretOffset: 7))
        XCTAssertTrue(vc._linkedEditingSessionIsActiveForTesting())

        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"view","op":"set_wrap_mode","mode":"word"}"#))
        XCTAssertTrue(vc._linkedEditingSessionIsActiveForTesting())

        editorView.insertText("b", replacementRange: NSRange(location: NSNotFound, length: 0))

        XCTAssertEqual(try editorView.editor.text(), "b + b\n")
        XCTAssertTrue(vc._linkedEditingSessionIsActiveForTesting())

        XCTAssertTrue(vc.performCursorMovementCommand(.moveLeft))
        XCTAssertFalse(vc._linkedEditingSessionIsActiveForTesting())
    }

    func testApplyColorPresentationMutatesActiveDocument() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("color.txt")
        try "let color = \"#ff0000\"\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let presentation = try XCTUnwrap(AttoLspDocumentColorParser.presentations(
            fromColorPresentationResultJSON: """
            [
              {
                "label": "rgb(255, 0, 0)",
                "textEdit": {
                  "range": {
                    "start": { "line": 0, "character": 13 },
                    "end": { "line": 0, "character": 20 }
                  },
                  "newText": "rgb(255, 0, 0)"
                }
              }
            ]
            """,
            documentText: try editorView.editor.text()
        ).first)

        XCTAssertFalse(window.title.contains("●"))
        XCTAssertTrue(vc.applyColorPresentationToActiveTab(presentation))
        XCTAssertEqual(try editorView.editor.text(), "let color = \"rgb(255, 0, 0)\"\n")
        XCTAssertTrue(window.title.contains("●"))
    }

    func testApplySnippetCommandUsesPrimarySelection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("snippet.txt")
        try "".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        XCTAssertTrue(vc.applySnippetInActiveTab("println!(${1:msg})$0"))
        XCTAssertEqual(try editorView.editor.text(), "println!(msg)")
        XCTAssertTrue(try editorView.editor.hasActiveSnippetSession())
    }

    func testAddOccurrenceCommandsUseFindSearchOptions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("occurrences.txt")
        try "foo Foo foo\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        vc.showFindBar()

        let caseSensitiveButton = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.findCaseSensitiveButton, in: vc.view) as? NSButton
        )
        caseSensitiveButton.state = .off

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 3)], primaryIndex: 0)

        XCTAssertTrue(vc.addAllOccurrencesInActiveTab())
        XCTAssertEqual(try editorView.editor.selections().ranges.count, 3)
    }

    func testPickDocumentColorResultOpensPickerAtColorRange() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("pick-color.txt")
        try "let color = \"#ff0000\"\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        var pickerWasOpened = false
        vc._setDocumentColorPickerForTesting { initialColor in
            pickerWasOpened = true
            XCTAssertEqual(initialColor.redComponent, 1, accuracy: 0.001)
            XCTAssertEqual(initialColor.greenComponent, 0, accuracy: 0.001)
            XCTAssertEqual(initialColor.blueComponent, 0, accuracy: 0.001)
            XCTAssertEqual(initialColor.alphaComponent, 1, accuracy: 0.001)
            return nil
        }
        defer { vc._setDocumentColorPickerForTesting(nil) }

        XCTAssertTrue(vc.pickDocumentColorResultJSONInActiveTab("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 13 },
              "end": { "line": 0, "character": 20 }
            },
            "color": { "red": 1, "green": 0, "blue": 0, "alpha": 1 }
          }
        ]
        """))

        XCTAssertTrue(pickerWasOpened)
        XCTAssertEqual(
            try editorView.editor.selections().ranges,
            [EcuSelectionRange(start: 13, end: 20)]
        )
    }

    func testApplySelectionRangeResultExpandsActiveSelection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("selection.txt")
        try "let value = call(arg)\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 17, end: 20)], primaryIndex: 0)

        let resultJSON = """
        [
          {
            "range": {
              "start": { "line": 0, "character": 17 },
              "end": { "line": 0, "character": 20 }
            },
            "parent": {
              "range": {
                "start": { "line": 0, "character": 12 },
                "end": { "line": 0, "character": 21 }
              },
              "parent": {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 21 }
                }
              }
            }
          }
        ]
        """

        XCTAssertTrue(vc.applySelectionRangeResultJSONToActiveTab(resultJSON))
        let offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 12)
        XCTAssertEqual(offsets.end, 21)
    }

    func testApplySelectionRangeResultExpandsMultipleSelectionsByResultOrder() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("selection-multi.txt")
        try "let one = call(a)\nlet two = call(b)\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections(
            [
                EcuSelectionRange(start: 15, end: 16),
                EcuSelectionRange(start: 33, end: 34),
            ],
            primaryIndex: 1
        )

        let resultJSON = """
        [
          {
            "range": {
              "start": { "line": 0, "character": 15 },
              "end": { "line": 0, "character": 16 }
            },
            "parent": {
              "range": {
                "start": { "line": 0, "character": 10 },
                "end": { "line": 0, "character": 17 }
              }
            }
          },
          {
            "range": {
              "start": { "line": 1, "character": 15 },
              "end": { "line": 1, "character": 16 }
            },
            "parent": {
              "range": {
                "start": { "line": 1, "character": 10 },
                "end": { "line": 1, "character": 17 }
              }
            }
          }
        ]
        """

        XCTAssertTrue(vc.applySelectionRangeResultJSONToActiveTab(resultJSON))
        let selections = try editorView.editor.selections()
        XCTAssertEqual(
            selections.ranges,
            [
                EcuSelectionRange(start: 10, end: 17),
                EcuSelectionRange(start: 28, end: 35),
            ]
        )
        XCTAssertEqual(selections.primaryIndex, 1)
    }

    func testExecuteCommandUsesRegisteredCommandIDs() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("a.txt")
        try "a\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "editor.duplicate_lines"))
        XCTAssertTrue(delegate.executeCommand(id: "editor.duplicate_lines"))
        XCTAssertFalse(delegate.executeCommand(id: "missing.command"))

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        XCTAssertEqual(try editorView.editor.text(), "a\na\n")
    }

    func testExecuteCommandAcceptsTypedArgumentsForParameterizedCommands() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("args.txt")
        try "abc\ndef\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        XCTAssertFalse(delegate.executeCommand(id: "go.line", arguments: [:]))
        XCTAssertFalse(delegate.executeCommand(id: "go.line", arguments: ["line": .integer(0)]))

        XCTAssertTrue(delegate.executeCommand(
            id: "go.line",
            arguments: ["line": .integer(2), "column": .integer(3)]
        ))
        let offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 6)
        XCTAssertEqual(offsets.end, 6)

        XCTAssertFalse(delegate.executeCommand(id: "editor.apply_snippet", arguments: ["snippet": .string("")]))
        XCTAssertTrue(delegate.executeCommand(
            id: "editor.apply_snippet",
            arguments: ["snippet": .string("X$0")]
        ))
        XCTAssertEqual(try editorView.editor.text(), "abc\ndeXf\n")

        XCTAssertFalse(delegate.executeCommand(id: "editor.duplicate_lines", arguments: ["unused": .boolean(true)]))
    }

    func testCursorMovementCommandsUseRegisteredCommandPath() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let text = "abc def\nghi jkl\n"
        let fileURL = tempDir.appendingPathComponent("cursor.txt")
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        XCTAssertTrue(delegate.executeCommand(id: "cursor.move_word_right"))
        var offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 3)
        XCTAssertEqual(offsets.end, 3)

        XCTAssertTrue(delegate.executeCommand(id: "cursor.move_right"))
        offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 4)
        XCTAssertEqual(offsets.end, 4)

        XCTAssertTrue(delegate.executeCommand(id: "cursor.select_word_right"))
        offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 4)
        XCTAssertEqual(offsets.end, 7)

        XCTAssertTrue(delegate.executeCommand(id: "cursor.move_left"))
        offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 4)
        XCTAssertEqual(offsets.end, 4)

        XCTAssertTrue(delegate.executeCommand(id: "cursor.document_end"))
        offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, UInt32(text.count))
        XCTAssertEqual(offsets.end, UInt32(text.count))

        XCTAssertTrue(delegate.executeCommand(id: "cursor.select_document_start"))
        offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 0)
        XCTAssertEqual(offsets.end, UInt32(text.count))
    }

    func testActiveEditorCommandJSONMutatesTextAndDirtyState() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("a.txt")
        try "a\nb\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(window.title.contains("●"))
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"duplicate_lines"}"#))

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "a\na\nb\n")
        XCTAssertTrue(window.title.contains("●"))
    }

    func testWorkspaceEditApplicationMutatesTextAndDirtyState() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("rename.txt")
        let otherURL = tempDir.appendingPathComponent("other.txt")
        try "abc\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "other\n".write(to: otherURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let workspaceEdit = """
        {
          "changes": {
            "\(fileURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 1 },
                  "end": { "line": 0, "character": 2 }
                },
                "newText": "B"
              }
            ],
            "\(otherURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "X"
              }
            ]
          }
        }
        """

        XCTAssertFalse(window.title.contains("●"))
        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "aBc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "Xother\n")
        XCTAssertTrue(window.title.contains("●"))
    }

    func testWorkspaceEditApplicationMutatesAlreadyOpenCrossFileTab() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first.txt")
        let secondURL = tempDir.appendingPathComponent("second.txt")
        try "abc\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "def\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.selectFile(url: firstURL)

        let workspaceEdit = """
        {
          "changes": {
            "\(firstURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 1 },
                  "end": { "line": 0, "character": 2 }
                },
                "newText": "B"
              }
            ],
            "\(secondURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 1 },
                  "end": { "line": 0, "character": 2 }
                },
                "newText": "E"
              }
            ]
          }
        }
        """

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))

        var editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "aBc\n")

        vc.selectFile(url: secondURL)
        editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "dEf\n")
        XCTAssertEqual(try String(contentsOf: secondURL, encoding: .utf8), "def\n")

        let secondItem = try XCTUnwrap(vc.openFileItems().first { $0.url.standardizedFileURL == secondURL.standardizedFileURL })
        XCTAssertTrue(secondItem.isDirty)
    }

    func testWorkspaceEditResourceOperationsApplyToUnopenedLocalFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let activeURL = tempDir.appendingPathComponent("active.txt")
        let createdURL = tempDir.appendingPathComponent("created.txt")
        let oldURL = tempDir.appendingPathComponent("old.txt")
        let renamedURL = tempDir.appendingPathComponent("renamed.txt")
        let removedURL = tempDir.appendingPathComponent("removed.txt")
        try "active\n".write(to: activeURL, atomically: true, encoding: .utf8)
        try "old\n".write(to: oldURL, atomically: true, encoding: .utf8)
        try "remove\n".write(to: removedURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: activeURL, mode: .pinned)

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "create",
              "uri": "\(createdURL.absoluteString)",
              "options": { "overwrite": true }
            },
            {
              "textDocument": { "uri": "\(createdURL.absoluteString)", "version": null },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "created\\n"
                }
              ]
            },
            {
              "kind": "rename",
              "oldUri": "\(oldURL.absoluteString)",
              "newUri": "\(renamedURL.absoluteString)"
            },
            {
              "kind": "delete",
              "uri": "\(removedURL.absoluteString)"
            }
          ]
        }
        """

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(try String(contentsOf: createdURL, encoding: .utf8), "created\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try String(contentsOf: renamedURL, encoding: .utf8), "old\n")
        XCTAssertFalse(FileManager.default.fileExists(atPath: removedURL.path))

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "active\n")
    }

    func testWorkspaceEditResourceOperationRenamesOpenTabAndAppliesFollowingEdits() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let oldURL = tempDir.appendingPathComponent("old-open.txt")
        let renamedURL = tempDir.appendingPathComponent("renamed-open.txt")
        try "old\n".write(to: oldURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: oldURL, mode: .pinned)

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "rename",
              "oldUri": "\(oldURL.absoluteString)",
              "newUri": "\(renamedURL.absoluteString)"
            },
            {
              "textDocument": { "uri": "\(renamedURL.absoluteString)", "version": null },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 0 }
                  },
                  "newText": "renamed "
                }
              ]
            }
          ]
        }
        """

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try String(contentsOf: renamedURL, encoding: .utf8), "old\n")

        let items = vc.openFileItems()
        XCTAssertFalse(items.contains { $0.url.standardizedFileURL == oldURL.standardizedFileURL })
        let renamedItem = try XCTUnwrap(items.first { $0.url.standardizedFileURL == renamedURL.standardizedFileURL })
        XCTAssertTrue(renamedItem.isDirty)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "renamed old\n")
    }

    func testWorkspaceEditResourceOperationDeletesOpenCleanTab() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keepURL = tempDir.appendingPathComponent("keep.txt")
        let deleteURL = tempDir.appendingPathComponent("delete-open.txt")
        try "keep\n".write(to: keepURL, atomically: true, encoding: .utf8)
        try "delete\n".write(to: deleteURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: keepURL, mode: .pinned)
        vc.openFile(url: deleteURL, mode: .pinned)
        vc.selectFile(url: keepURL)

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "delete",
              "uri": "\(deleteURL.absoluteString)"
            }
          ]
        }
        """

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertFalse(FileManager.default.fileExists(atPath: deleteURL.path))
        XCTAssertFalse(vc.openFileItems().contains { $0.url.standardizedFileURL == deleteURL.standardizedFileURL })
        XCTAssertTrue(vc.openFileItems().contains { $0.url.standardizedFileURL == keepURL.standardizedFileURL })
    }

    func testWorkspaceEditResourceOperationOverwritesOpenCleanTabCreate() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let url = tempDir.appendingPathComponent("overwrite-open.txt")
        try "existing\n".write(to: url, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: url, mode: .pinned)

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "create",
              "uri": "\(url.absoluteString)",
              "options": { "overwrite": true }
            }
          ]
        }
        """

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), "")
        let item = try XCTUnwrap(vc.openFileItems().first { $0.url.standardizedFileURL == url.standardizedFileURL })
        XCTAssertFalse(item.isDirty)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "")
    }

    func testWorkspaceEditResourceOperationSkipsDirtyOpenTabDelete() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("dirty-delete.txt")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: dirtyURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "delete",
              "uri": "\(dirtyURL.absoluteString)"
            }
          ]
        }
        """

        XCTAssertFalse(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyURL.path))
        let dirtyItem = try XCTUnwrap(vc.openFileItems().first { $0.url.standardizedFileURL == dirtyURL.standardizedFileURL })
        XCTAssertTrue(dirtyItem.isDirty)
    }

    func testWorkspaceEditResourceOperationUsesCoreDirtyWhenSwiftCacheIsStale() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let dirtyURL = tempDir.appendingPathComponent("core-dirty-delete.txt")
        try "dirty\n".write(to: dirtyURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: dirtyURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"!"}"#))

        vc._setActiveTabDirtyCacheForTesting(false)
        XCTAssertTrue(vc._activeTabDirtyForDataLossDecisionForTesting())

        vc._setActiveTabDirtyCacheForTesting(false)
        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "delete",
              "uri": "\(dirtyURL.absoluteString)"
            }
          ]
        }
        """

        XCTAssertFalse(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertTrue(FileManager.default.fileExists(atPath: dirtyURL.path))
        let dirtyItem = try XCTUnwrap(vc.openFileItems().first { $0.url.standardizedFileURL == dirtyURL.standardizedFileURL })
        XCTAssertTrue(dirtyItem.isDirty)
    }

    func testShowProblemsUsesDerivedDiagnosticsAndNavigatesWithoutPanelWindow() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("problems.txt")
        try "abc\ndef\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let diagnostics = """
        {
          "uri": "\(fileURL.absoluteString)",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 1, "character": 1 },
                "end": { "line": 1, "character": 2 }
              },
              "severity": 1,
              "source": "unit-test",
              "message": "second line problem"
            }
          ],
          "version": 1
        }
        """
        try editorView.editor.lspApplyDiagnosticsJSON(diagnostics)

        XCTAssertTrue(vc.showProblemsInActiveTab())

        let snapshot = vc._activeDerivedStateForTesting()
        XCTAssertEqual(snapshot.diagnostics.diagnostics.count, 1)
        XCTAssertEqual(snapshot.diagnostics.diagnostics[0].message, "second line problem")
        XCTAssertEqual(snapshot.diagnostics.diagnostics[0].severity, .error)

        let offsets = try editorView.editor.selectionOffsets()
        XCTAssertEqual(offsets.start, 5)
        XCTAssertEqual(offsets.end, 6)
    }

    func testProblemsPanelUsesDerivedDiagnosticsAndRefreshesWithStatusUpdate() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("problems-panel.txt")
        try "abc\ndef\nghi\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.lspApplyDiagnosticsJSON("""
        {
          "uri": "\(fileURL.absoluteString)",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 3 }
              },
              "severity": 1,
              "source": "unit-test",
              "message": "first line problem"
            },
            {
              "range": {
                "start": { "line": 1, "character": 1 },
                "end": { "line": 1, "character": 2 }
              },
              "severity": 2,
              "source": "unit-test",
              "message": "second line warning"
            }
          ],
          "version": 1
        }
        """)

        XCTAssertTrue(vc.showProblemsPanelInActiveTab())
        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.problemsPanel
        })
        XCTAssertEqual(panel.title, "Problems (2)")
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.problemsPanelSearchField, in: root) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter problems...")
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.problemsPanelTable, in: root) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(vc._problemsPanelDiagnosticsForTesting().map(\.message), [
            "first line problem",
            "second line warning",
        ])
        XCTAssertTrue(vc._problemsPanelIsVisibleForTesting())

        try editorView.editor.lspApplyDiagnosticsJSON("""
        {
          "uri": "\(fileURL.absoluteString)",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 2, "character": 0 },
                "end": { "line": 2, "character": 3 }
              },
              "severity": 1,
              "source": "unit-test",
              "message": "third line problem"
            }
          ],
          "version": 2
        }
        """)
        vc._updateStatusBarForTesting()
        XCTAssertEqual(panel.title, "Problems (1)")
        XCTAssertEqual(vc._problemsPanelDiagnosticsForTesting().map(\.message), ["third line problem"])
        XCTAssertEqual(vc._problemsPanelRowCountForTesting(), 1)
    }

    func testRenameCandidateUsesSelectionOrIdentifierAtCaret() throws {
        XCTAssertEqual(
            AttoLspRenameSupport.candidateName(documentText: "let alpha = beta\n", selectedText: "alpha", caretOffset: 0),
            "alpha"
        )
        XCTAssertEqual(
            AttoLspRenameSupport.candidateName(documentText: "let alpha = beta\n", selectedText: "", caretOffset: 7),
            "alpha"
        )
        XCTAssertEqual(
            AttoLspRenameSupport.candidateName(documentText: "let alpha = beta\n", selectedText: "", caretOffset: 9),
            "alpha"
        )
        XCTAssertEqual(
            AttoLspRenameSupport.candidateName(documentText: "let alpha = beta\n", selectedText: "alpha\nbeta", caretOffset: 0),
            "let"
        )
    }

    func testPrepareRenameDialogSeedUsesPlaceholderRangeAndFallback() throws {
        let fallback = AttoLspRenameSupport.DialogSeed(initialName: "fallback", placeholder: nil)

        let placeholderJSON = """
        {
          "range": {
            "start": { "line": 0, "character": 4 },
            "end": { "line": 0, "character": 9 }
          },
          "placeholder": "serverName"
        }
        """
        XCTAssertEqual(
            AttoLspRenameSupport.dialogSeed(
                documentText: "let alpha = beta\n",
                selectedText: "",
                caretOffset: 0,
                prepareRenameResultJSON: placeholderJSON,
                fallback: fallback
            ),
            AttoLspRenameSupport.DialogSeed(initialName: "serverName", placeholder: "serverName")
        )

        let rangeOnlyJSON = """
        {
          "start": { "line": 0, "character": 4 },
          "end": { "line": 0, "character": 9 }
        }
        """
        XCTAssertEqual(
            AttoLspRenameSupport.dialogSeed(
                documentText: "let alpha = beta\n",
                selectedText: "",
                caretOffset: 0,
                prepareRenameResultJSON: rangeOnlyJSON,
                fallback: fallback
            ).initialName,
            "alpha"
        )

        let emojiText = "let emoji_\u{1F600} = 1\n"
        let emojiRangeJSON = """
        {
          "start": { "line": 0, "character": 4 },
          "end": { "line": 0, "character": 12 }
        }
        """
        XCTAssertEqual(
            AttoLspRenameSupport.dialogSeed(
                documentText: emojiText,
                selectedText: "",
                caretOffset: 0,
                prepareRenameResultJSON: emojiRangeJSON,
                fallback: fallback
            ).initialName,
            "emoji_\u{1F600}"
        )

        XCTAssertEqual(
            AttoLspRenameSupport.dialogSeed(
                documentText: "let alpha = beta\n",
                selectedText: "",
                caretOffset: 0,
                prepareRenameResultJSON: #"{"defaultBehavior":true}"#,
                fallback: fallback
            ),
            fallback
        )
    }

    func testToggleLineCommentUsesFileLanguageDefault() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("script.py")
        try "print(1)\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        XCTAssertTrue(vc.toggleLineCommentInActiveTab())
        XCTAssertEqual(try editorView.editor.text(), "# print(1)\n")
    }

    func testToggleLineCommentUsesUserLanguageOverride() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let suiteName = "atto_command_comment_override_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let preferences = AttoPreferences(defaults: defaults, env: [:])
        preferences.setCommentConfiguration(.line("##"), forLanguageKey: "python")

        let fileURL = tempDir.appendingPathComponent("script.py")
        try "print(1)\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir, preferences: preferences)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 0)], primaryIndex: 0)

        XCTAssertTrue(vc.toggleLineCommentInActiveTab())
        XCTAssertEqual(try editorView.editor.text(), "## print(1)\n")
    }

    func testToggleCommentUsesBlockLanguageConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("index.html")
        try "<div></div>\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 0, end: 11)], primaryIndex: 0)

        XCTAssertTrue(vc.toggleLineCommentInActiveTab())
        XCTAssertEqual(try editorView.editor.text(), "<!--<div></div>-->\n")
    }

    func testOpenFileAppliesLanguageIndentationConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("script.js")
        try "{".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.moveTo(line: 0, column: 1)
        try editorView.editor.insertNewline(autoIndent: true)

        XCTAssertEqual(try editorView.editor.text(), "{\n  ")
    }

    func testGoToLineCommandParsesInputAndMovesCaret() throws {
        XCTAssertEqual(
            AttoEditorAreaViewController.parseGoToLineTarget("3:2"),
            AttoEditorAreaViewController.GoToLineTarget(line1: 3, column1: 2)
        )
        XCTAssertEqual(
            AttoEditorAreaViewController.parseGoToLineTarget("4"),
            AttoEditorAreaViewController.GoToLineTarget(line1: 4, column1: 1)
        )
        XCTAssertNil(AttoEditorAreaViewController.parseGoToLineTarget("0:1"))
        XCTAssertNil(AttoEditorAreaViewController.parseGoToLineTarget("3:"))
        XCTAssertNil(AttoEditorAreaViewController.parseGoToLineTarget("abc"))

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("goto-line.txt")
        try "aa\nbb\ncc\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertTrue(vc.goToLineInActiveTab(input: "3:2"))
        let offsets = try editorView.editor.selectionOffsets()
        let pos = try editorView.editor.charOffsetToLogicalPosition(offset: offsets.end)
        XCTAssertEqual(pos.line, 2)
        XCTAssertEqual(pos.column, 1)

        XCTAssertFalse(vc.goToLineInActiveTab(input: "x:y"))
    }

    func testCoreMultiDocumentMirrorTracksTabsAndPanes() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first.txt")
        let secondURL = tempDir.appendingPathComponent("second.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)

        vc.openFile(url: firstURL, mode: .preview)
        var snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.count, 1)
        XCTAssertEqual(snapshot.tabs[0].title, "first.txt")
        XCTAssertTrue(snapshot.tabs[0].isPreview)

        vc.openFile(url: secondURL, mode: .preview)
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.count, 1)
        XCTAssertEqual(snapshot.tabs[0].title, "second.txt")
        XCTAssertTrue(snapshot.tabs[0].isPreview)

        vc.openFile(url: secondURL, mode: .pinned)
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.count, 1)
        XCTAssertEqual(snapshot.tabs[0].title, "second.txt")
        XCTAssertFalse(snapshot.tabs[0].isPreview)
        XCTAssertEqual(snapshot.activeTabId, snapshot.tabs[0].id)

        XCTAssertTrue(vc.splitActiveTabRight())
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs[0].viewCount, 2)
        XCTAssertEqual(snapshot.tabs[0].activeViewIndex, 1)

        XCTAssertTrue(vc.focusPreviousPaneInActiveTab())
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs[0].activeViewIndex, 0)

        XCTAssertTrue(vc.closeActivePane())
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs[0].viewCount, 1)
        XCTAssertEqual(snapshot.tabs[0].activeViewIndex, 0)

        vc.closeActiveTab()
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertTrue(snapshot.tabs.isEmpty)
        XCTAssertNil(snapshot.activeTabId)
    }

    func testCoreMultiDocumentMirrorTracksEditedTextDirtyAndSearch() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("mirror.txt")
        try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        var snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        let tabId = try XCTUnwrap(snapshot.activeTabId)
        var tabSnapshot = try XCTUnwrap(snapshot.tabs.first { $0.id == tabId })
        XCTAssertFalse(tabSnapshot.isModified)

        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":" needle"}"#))

        let results = try XCTUnwrap(vc._coreMultiDocumentSearchForTesting(query: "needle"))
        XCTAssertEqual(results.map(\.tabId), [tabId])
        XCTAssertEqual(results.flatMap(\.matches).count, 1)

        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        tabSnapshot = try XCTUnwrap(snapshot.tabs.first { $0.id == tabId })
        XCTAssertTrue(tabSnapshot.isModified)

        vc.saveActiveTab()
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        tabSnapshot = try XCTUnwrap(snapshot.tabs.first { $0.id == tabId })
        XCTAssertFalse(tabSnapshot.isModified)
    }

    func testFindInOpenTabsUsesCoreMirrorForUnsavedText() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("opened-search.txt")
        try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":" needle"}"#))
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "alpha")

        let results = vc.findInOpenTabs(query: "needle")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].url.standardizedFileURL, fileURL.standardizedFileURL)
        XCTAssertEqual(results[0].line1, 1)
        XCTAssertEqual(results[0].column1, 2)
        XCTAssertEqual(results[0].lineText, "needlealpha")
    }

    func testSplitRightCreatesSharedDocumentPane() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("split.txt")
        try "abc".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertEqual(findSubviews(of: EditorCoreSkiaView.self, in: vc.view).count, 1)
        XCTAssertTrue(vc.splitActiveTabRight())
        vc.view.layoutSubtreeIfNeeded()

        let editorViews = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(editorViews.count, 2)

        try editorViews[1].editor.insertText("!")
        XCTAssertEqual(try editorViews[0].editor.text(), "!abc")
        XCTAssertEqual(try editorViews[1].editor.text(), "!abc")

        let clickPoint = editorViews[0].convert(NSPoint(x: 5, y: 5), to: nil)
        guard let mouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: clickPoint,
            modifierFlags: [],
            timestamp: ProcessInfo.processInfo.systemUptime,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 1.0
        ) else {
            XCTFail("Unable to construct split pane mouseDown event")
            return
        }
        editorViews[0].mouseDown(with: mouseDown)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"?"}"#))
        XCTAssertEqual(try editorViews[0].editor.text(), "?!abc")
    }

    func testPaneFocusAndCloseCommandsUseActivePane() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("panes.txt")
        try "abc".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(vc.splitActiveTabRight())
        vc.view.layoutSubtreeIfNeeded()
        let editorViews = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(editorViews.count, 2)

        XCTAssertTrue(vc.focusPreviousPaneInActiveTab())
        XCTAssertTrue(vc.focusNextPaneInActiveTab())
        XCTAssertTrue(vc.closeActivePane())
        vc.view.layoutSubtreeIfNeeded()

        let remaining = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(remaining.count, 1)
        XCTAssertTrue(remaining[0] === editorViews[0])
        XCTAssertFalse(vc.closeActivePane())
    }

    func testMovePaneCommandsReorderAppKitProjectionAndCoreMirror() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("move-panes.txt")
        try "abc".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertTrue(vc.splitActiveTabRight())
        XCTAssertTrue(vc.splitActiveTabRight())
        vc.view.layoutSubtreeIfNeeded()

        let original = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(original.count, 3)

        XCTAssertTrue(vc.moveActivePaneLeft())
        vc.view.layoutSubtreeIfNeeded()
        var moved = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertEqual(moved.count, 3)
        XCTAssertTrue(moved[0] === original[0])
        XCTAssertTrue(moved[1] === original[2])
        XCTAssertTrue(moved[2] === original[1])
        var snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs[0].viewCount, 3)
        XCTAssertEqual(snapshot.tabs[0].activeViewIndex, 1)

        XCTAssertTrue(vc.moveActivePaneLeft())
        vc.view.layoutSubtreeIfNeeded()
        moved = findSubviews(of: EditorCoreSkiaView.self, in: vc.view)
        XCTAssertTrue(moved[0] === original[2])
        XCTAssertTrue(moved[1] === original[0])
        XCTAssertTrue(moved[2] === original[1])
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs[0].activeViewIndex, 0)

        XCTAssertFalse(vc.moveActivePaneLeft())
        XCTAssertTrue(vc.moveActivePaneRight())
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs[0].activeViewIndex, 1)
    }

    func testMoveTabCommandsReorderAppKitProjectionAndCoreMirror() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-tab.txt")
        let secondURL = tempDir.appendingPathComponent("second-tab.txt")
        let thirdURL = tempDir.appendingPathComponent("third-tab.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.openFile(url: thirdURL, mode: .pinned)

        XCTAssertEqual(vc.openFileItems().map { $0.url.lastPathComponent }, [
            "first-tab.txt",
            "second-tab.txt",
            "third-tab.txt",
        ])
        XCTAssertFalse(vc.moveActiveTabRight())

        XCTAssertTrue(vc.moveActiveTabLeft())
        XCTAssertEqual(vc.openFileItems().map { $0.url.lastPathComponent }, [
            "first-tab.txt",
            "third-tab.txt",
            "second-tab.txt",
        ])
        var snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.map(\.title), [
            "first-tab.txt",
            "third-tab.txt",
            "second-tab.txt",
        ])
        XCTAssertEqual(snapshot.tabs.first(where: { $0.isActive })?.title, "third-tab.txt")

        XCTAssertTrue(vc.moveActiveTabLeft())
        XCTAssertEqual(vc.openFileItems().map { $0.url.lastPathComponent }, [
            "third-tab.txt",
            "first-tab.txt",
            "second-tab.txt",
        ])
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.map(\.title), [
            "third-tab.txt",
            "first-tab.txt",
            "second-tab.txt",
        ])
        XCTAssertEqual(snapshot.tabs.first(where: { $0.isActive })?.title, "third-tab.txt")

        XCTAssertFalse(vc.moveActiveTabLeft())
        XCTAssertTrue(vc.moveActiveTabRight())
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.map(\.title), [
            "first-tab.txt",
            "third-tab.txt",
            "second-tab.txt",
        ])
    }

    func testSessionRestoreRestoresSplitPanesIntoCoreMirror() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("session-split.txt")
        try "abc".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        XCTAssertTrue(vc.splitActiveTabRight())
        XCTAssertTrue(vc.focusPreviousPaneInActiveTab())

        let snapshot = vc.makeSessionSnapshot()
        XCTAssertEqual(snapshot.tabs.count, 1)
        XCTAssertEqual(snapshot.tabs[0].paneCount, 2)
        XCTAssertEqual(snapshot.tabs[0].activePaneIndex, 0)

        let restored = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(restored)
        restored.restoreSession(tabs: snapshot.tabs, selectedTabIndex: snapshot.selectedTabIndex)
        restored.view.layoutSubtreeIfNeeded()

        let editorViews = findSubviews(of: EditorCoreSkiaView.self, in: restored.view)
        XCTAssertEqual(editorViews.count, 2)

        let restoredSnapshot = restored.makeSessionSnapshot()
        XCTAssertEqual(restoredSnapshot.tabs.count, 1)
        XCTAssertEqual(restoredSnapshot.tabs[0].paneCount, 2)
        XCTAssertEqual(restoredSnapshot.tabs[0].activePaneIndex, 0)

        let coreSnapshot = try XCTUnwrap(restored._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(coreSnapshot.tabs.count, 1)
        XCTAssertEqual(coreSnapshot.tabs[0].viewCount, 2)
        XCTAssertEqual(coreSnapshot.tabs[0].activeViewIndex, 0)
    }

    private func makeEditorArea(
        workspaceRootURL: URL,
        preferences: AttoPreferences = .shared
    ) -> AttoEditorAreaViewController {
        AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: workspaceRootURL,
            preferences: preferences
        )
    }

    @discardableResult
    private func attachToWindow(_ vc: AttoEditorAreaViewController) -> NSWindow {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 500),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = vc
        window.makeKeyAndOrderFront(nil)
        vc.view.layoutSubtreeIfNeeded()
        return window
    }

    private func findSubview<T: NSView>(of type: T.Type, in root: NSView) -> T? {
        if let v = root as? T { return v }
        for child in root.subviews {
            if let found = findSubview(of: type, in: child) {
                return found
            }
        }
        return nil
    }

    private func findSubviews<T: NSView>(of type: T.Type, in root: NSView) -> [T] {
        var out: [T] = []
        if let v = root as? T {
            out.append(v)
        }
        for child in root.subviews {
            out.append(contentsOf: findSubviews(of: type, in: child))
        }
        return out
    }

    private func findView(identifier: String, in root: NSView) -> NSView? {
        if root.identifier?.rawValue == identifier {
            return root
        }
        for child in root.subviews {
            if let found = findView(identifier: identifier, in: child) {
                return found
            }
        }
        return nil
    }

    private func findMenuItem(commandID: String, in menu: NSMenu) -> NSMenuItem? {
        for item in menu.items {
            if item.representedObject as? String == commandID {
                return item
            }
            if let submenu = item.submenu, let found = findMenuItem(commandID: commandID, in: submenu) {
                return found
            }
        }
        return nil
    }

    private func topLevelMenu(title: String, in menu: NSMenu) -> NSMenu? {
        for item in menu.items {
            if item.submenu?.title == title {
                return item.submenu
            }
        }
        return nil
    }
}
