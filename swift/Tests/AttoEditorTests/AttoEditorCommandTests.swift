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
        XCTAssertTrue(ids.contains("lsp.call_hierarchy_incoming"))
        XCTAssertTrue(ids.contains("lsp.call_hierarchy_outgoing"))
        XCTAssertTrue(ids.contains("lsp.type_hierarchy_supertypes"))
        XCTAssertTrue(ids.contains("lsp.type_hierarchy_subtypes"))
        XCTAssertTrue(ids.contains("lsp.document_symbols"))
        XCTAssertTrue(ids.contains("lsp.workspace_symbols"))
        XCTAssertTrue(ids.contains("lsp.show_last_symbols"))
        XCTAssertTrue(ids.contains("lsp.show_symbol_history"))
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
        XCTAssertTrue(ids.contains("lsp.document_colors"))
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
        XCTAssertNotNil(findMenuItem(commandID: "lsp.call_hierarchy_incoming", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.call_hierarchy_outgoing", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.type_hierarchy_supertypes", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.type_hierarchy_subtypes", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.document_symbols", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.workspace_symbols", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_last_symbols", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.show_symbol_history", in: menu))
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
        XCTAssertNotNil(findMenuItem(commandID: "lsp.document_colors", in: menu))
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
        XCTAssertEqual(snapshot.symbols.map(\.name), ["openProject", "Project"])
        XCTAssertEqual(snapshot.placeholder, "Filter workspace symbols...")

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

    private func makeEditorArea(workspaceRootURL: URL) -> AttoEditorAreaViewController {
        AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: workspaceRootURL
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
