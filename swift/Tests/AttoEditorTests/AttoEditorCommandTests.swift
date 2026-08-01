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
        XCTAssertTrue(ids.contains("view.wrap.word"))
        XCTAssertTrue(ids.contains("view.split_right"))
        XCTAssertTrue(ids.contains("view.focus_next_pane"))
        XCTAssertTrue(ids.contains("view.focus_previous_pane"))
        XCTAssertTrue(ids.contains("view.close_pane"))
        XCTAssertTrue(ids.contains("lsp.go_to_definition"))
        XCTAssertTrue(ids.contains("lsp.go_to_declaration"))
        XCTAssertTrue(ids.contains("lsp.go_to_type_definition"))
        XCTAssertTrue(ids.contains("lsp.go_to_implementation"))
        XCTAssertTrue(ids.contains("lsp.find_references"))
        XCTAssertTrue(ids.contains("lsp.call_hierarchy_incoming"))
        XCTAssertTrue(ids.contains("lsp.call_hierarchy_outgoing"))
        XCTAssertTrue(ids.contains("lsp.type_hierarchy_supertypes"))
        XCTAssertTrue(ids.contains("lsp.type_hierarchy_subtypes"))
        XCTAssertTrue(ids.contains("lsp.document_symbols"))
        XCTAssertTrue(ids.contains("lsp.workspace_symbols"))
        XCTAssertTrue(ids.contains("lsp.completion"))
        XCTAssertTrue(ids.contains("lsp.signature_help"))
        XCTAssertTrue(ids.contains("lsp.rename"))
        XCTAssertTrue(ids.contains("lsp.code_actions"))
        XCTAssertTrue(ids.contains("lsp.code_lens_actions"))
        XCTAssertTrue(ids.contains("lsp.quick_fix"))
        XCTAssertTrue(ids.contains("lsp.refactor"))
        XCTAssertTrue(ids.contains("lsp.source_actions"))
        XCTAssertTrue(ids.contains("lsp.organize_imports"))
        XCTAssertTrue(ids.contains("lsp.fix_all"))
        XCTAssertTrue(ids.contains("lsp.problems"))
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
    }

    func testEditorCommandsAreDisabledWithoutActiveEditor() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let menu = AttoMainMenuBuilder.build(appDelegate: delegate)
        let item = try XCTUnwrap(findMenuItem(commandID: "editor.duplicate_lines", in: menu))

        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "editor.duplicate_lines"))
        XCTAssertFalse(delegate.validateMenuItem(item))
        XCTAssertFalse(delegate.executeCommand(id: "editor.duplicate_lines"))
    }

    func testWorkspaceSymbolsPromptRequiresActiveEditor() throws {
        let vc = makeEditorArea(workspaceRootURL: FileManager.default.temporaryDirectory)
        _ = vc.view

        XCTAssertFalse(vc.promptWorkspaceSymbolsInActiveTab(initialQuery: "app"))
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
    }

    func testMainMenuItemsUseCommandIDsAndResolvedKeymap() throws {
        let delegate = AttoAppDelegate(
            keyBindings: [
                "editor.duplicate_lines": AttoKeyBinding(keyEquivalent: "l", modifiers: [.command, .shift]),
            ]
        )
        let menu = AttoMainMenuBuilder.build(appDelegate: delegate)

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
        XCTAssertNotNil(findMenuItem(commandID: "view.close_pane", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "editor.fold_selection", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.refresh_folding_ranges", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.go_to_definition", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.find_references", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.call_hierarchy_incoming", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.call_hierarchy_outgoing", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.type_hierarchy_supertypes", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.type_hierarchy_subtypes", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.document_symbols", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.workspace_symbols", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.completion", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.signature_help", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.rename", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.code_actions", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.code_lens_actions", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.quick_fix", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.refactor", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.source_actions", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.organize_imports", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.fix_all", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.problems", in: menu))
        XCTAssertNotNil(findMenuItem(commandID: "lsp.document_colors", in: menu))
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
