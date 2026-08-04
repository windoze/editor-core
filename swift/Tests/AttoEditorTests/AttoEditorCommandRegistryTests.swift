import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
extension AttoEditorCommandTests {
    func testDefaultCommandPaletteIncludesCoreEditorCommandIDs() throws {
        let delegate = AttoAppDelegate()
        let ids = Set(delegate._defaultCommandsForTesting().map(\.id))

        XCTAssertTrue(ids.contains("editor.format_document"))
        XCTAssertTrue(ids.contains("editor.format_selection"))
        XCTAssertTrue(ids.contains("editor.duplicate_lines"))
        XCTAssertTrue(ids.contains("file.close_tab"))
        XCTAssertTrue(ids.contains("file.reload"))
        XCTAssertTrue(ids.contains("file.pin_tab"))
        XCTAssertTrue(ids.contains("file.close_all_tabs"))
        XCTAssertTrue(ids.contains("file.close_other_tabs"))
        XCTAssertTrue(ids.contains("file.close_tabs_to_right"))
        XCTAssertTrue(ids.contains("file.move_tab_left"))
        XCTAssertTrue(ids.contains("file.move_tab_right"))
        XCTAssertTrue(ids.contains("file.open_recent_project"))
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
        XCTAssertTrue(ids.contains("workspace.undo_last_workspace_edit"))
        XCTAssertTrue(ids.contains("workspace.redo_last_workspace_edit"))
        XCTAssertTrue(ids.contains("workspace.show_workspace_edit_history"))
        XCTAssertTrue(ids.contains("macro.toggle_recording"))
        XCTAssertTrue(ids.contains("macro.replay_last"))
        XCTAssertTrue(ids.contains("macro.save_named"))
        XCTAssertTrue(ids.contains("macro.replay_named"))
        XCTAssertTrue(ids.contains("macro.rename_named"))
        XCTAssertTrue(ids.contains("macro.delete_named"))
        XCTAssertTrue(ids.contains("macro.delete_named_batch"))
        XCTAssertTrue(ids.contains("macro.undo_delete"))
        XCTAssertTrue(ids.contains("macro.show_delete_history"))
        XCTAssertTrue(ids.contains("macro.manage_delete_history"))
        XCTAssertTrue(ids.contains("macro.remove_delete_history_entry"))
        XCTAssertTrue(ids.contains("macro.remove_delete_history_entries"))
        XCTAssertTrue(ids.contains("macro.clear_delete_history"))
        XCTAssertTrue(ids.contains("macro.import_file"))
        XCTAssertTrue(ids.contains("macro.export_named"))
        for feature in AttoSublimeFeatureBoundary.allCases {
            XCTAssertTrue(ids.contains(feature.commandID), feature.commandID)
        }
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
        XCTAssertTrue(ids.contains("lsp.show_workbench_panel"))
        XCTAssertTrue(ids.contains("lsp.show_workbench_dock"))
        XCTAssertTrue(ids.contains("lsp.show_workbench_history"))
        XCTAssertTrue(ids.contains("lsp.show_workbench_pinned_results"))
        XCTAssertTrue(ids.contains("lsp.show_workbench_selected_history"))
        XCTAssertTrue(ids.contains("lsp.jump_workbench_first_result"))
        XCTAssertTrue(ids.contains("lsp.jump_workbench_selected_result"))
        XCTAssertTrue(ids.contains("lsp.refresh_workbench_selected_result"))
        XCTAssertTrue(ids.contains("lsp.pin_workbench_current_results"))
        XCTAssertTrue(ids.contains("lsp.pin_workbench_selected_result"))
        XCTAssertTrue(ids.contains("lsp.unpin_workbench_current_results"))
        XCTAssertTrue(ids.contains("lsp.unpin_workbench_selected_result"))
        XCTAssertTrue(ids.contains("lsp.clear_workbench_stale_results"))
        XCTAssertTrue(ids.contains("lsp.clear_workbench_selected_stale_result"))
        XCTAssertTrue(ids.contains("lsp.show_problems_panel"))
        XCTAssertTrue(ids.contains("lsp.call_hierarchy_incoming"))
        XCTAssertTrue(ids.contains("lsp.call_hierarchy_outgoing"))
        XCTAssertTrue(ids.contains("lsp.type_hierarchy_supertypes"))
        XCTAssertTrue(ids.contains("lsp.type_hierarchy_subtypes"))
        XCTAssertTrue(ids.contains("lsp.show_hierarchy_panel"))
        XCTAssertTrue(ids.contains("lsp.refresh_hierarchy_panel"))
        XCTAssertTrue(ids.contains("lsp.expand_hierarchy_selection"))
        XCTAssertTrue(ids.contains("lsp.document_symbols"))
        XCTAssertTrue(ids.contains("lsp.workspace_symbols"))
        XCTAssertTrue(ids.contains("lsp.show_last_symbols"))
        XCTAssertTrue(ids.contains("lsp.show_symbol_history"))
        XCTAssertTrue(ids.contains("lsp.show_symbols_panel"))
        XCTAssertTrue(ids.contains("lsp.show_workspace_outline_panel"))
        XCTAssertTrue(ids.contains("lsp.completion"))
        XCTAssertTrue(ids.contains("lsp.signature_help"))
        XCTAssertTrue(ids.contains("lsp.rename"))
        XCTAssertTrue(ids.contains("lsp.code_actions"))
        XCTAssertTrue(ids.contains("lsp.code_lens_actions"))
        XCTAssertTrue(ids.contains("lsp.code_lens_at_cursor"))
        XCTAssertTrue(ids.contains("lsp.show_code_lens_panel"))
        XCTAssertTrue(ids.contains("lsp.refresh_code_lens"))
        XCTAssertTrue(ids.contains("lsp.refresh_inlay_hints"))
        XCTAssertTrue(ids.contains("lsp.show_inlay_hints_panel"))
        XCTAssertTrue(ids.contains("lsp.refresh_document_links"))
        XCTAssertTrue(ids.contains("lsp.show_document_links_panel"))
        XCTAssertTrue(ids.contains("lsp.quick_fix"))
        XCTAssertTrue(ids.contains("lsp.refactor"))
        XCTAssertTrue(ids.contains("lsp.source_actions"))
        XCTAssertTrue(ids.contains("lsp.organize_imports"))
        XCTAssertTrue(ids.contains("lsp.fix_all"))
        XCTAssertTrue(ids.contains("lsp.problems"))
        XCTAssertTrue(ids.contains("lsp.workspace_diagnostics"))
        XCTAssertTrue(ids.contains("lsp.show_workspace_problems_panel"))
        XCTAssertTrue(ids.contains("lsp.show_project_lsp_status"))
        XCTAssertTrue(ids.contains("lsp.show_project_lsp_health"))
        XCTAssertTrue(ids.contains("lsp.show_project_lsp_health_log"))
        XCTAssertTrue(ids.contains("lsp.show_project_lsp_dashboard"))
        XCTAssertTrue(ids.contains("lsp.clear_project_lsp_health_log"))
        XCTAssertTrue(ids.contains("lsp.export_project_lsp_health_log"))
        XCTAssertTrue(ids.contains("lsp.restart_server"))
        XCTAssertTrue(ids.contains("lsp.shutdown_server"))
        XCTAssertTrue(ids.contains("lsp.restart_project_servers"))
        XCTAssertTrue(ids.contains("lsp.shutdown_project_servers"))
        XCTAssertTrue(ids.contains("lsp.document_colors"))
        XCTAssertTrue(ids.contains("lsp.pick_document_color"))
        XCTAssertTrue(ids.contains("lsp.show_document_colors_panel"))
        XCTAssertTrue(ids.contains("lsp.refresh_document_colors"))
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

        let openRecentProject = try XCTUnwrap(commands.first { $0.id == "file.open_recent_project" })
        XCTAssertEqual(openRecentProject.group, "File")
        XCTAssertFalse(openRecentProject.requiresEditor)
        XCTAssertTrue(openRecentProject.isEnabled)

        let cursor = try XCTUnwrap(commands.first { $0.id == "cursor.move_down" })
        XCTAssertEqual(cursor.group, "Cursor")
        XCTAssertTrue(cursor.requiresEditor)
        XCTAssertFalse(cursor.isEnabled)

        let workspaceUndo = try XCTUnwrap(commands.first { $0.id == "workspace.undo_last_workspace_edit" })
        XCTAssertEqual(workspaceUndo.group, "Workspace")
        XCTAssertFalse(workspaceUndo.requiresEditor)
        XCTAssertFalse(workspaceUndo.isEnabled)

        let workspaceRedo = try XCTUnwrap(commands.first { $0.id == "workspace.redo_last_workspace_edit" })
        XCTAssertEqual(workspaceRedo.group, "Workspace")
        XCTAssertFalse(workspaceRedo.requiresEditor)
        XCTAssertFalse(workspaceRedo.isEnabled)

        let workspaceHistory = try XCTUnwrap(commands.first { $0.id == "workspace.show_workspace_edit_history" })
        XCTAssertEqual(workspaceHistory.group, "Workspace")
        XCTAssertFalse(workspaceHistory.requiresEditor)
        XCTAssertFalse(workspaceHistory.isEnabled)

        let closeRight = try XCTUnwrap(commands.first { $0.id == "file.close_tabs_to_right" })
        XCTAssertEqual(closeRight.group, "File")
        XCTAssertTrue(closeRight.requiresEditor)
        XCTAssertFalse(closeRight.isEnabled)

        let closeAll = try XCTUnwrap(commands.first { $0.id == "file.close_all_tabs" })
        XCTAssertEqual(closeAll.group, "File")
        XCTAssertTrue(closeAll.requiresEditor)
        XCTAssertFalse(closeAll.isEnabled)
    }

    func testCommandSurfacesReferenceRegisteredCommandIDs() throws {
        let delegate = AttoAppDelegate(keyBindings: AttoKeymap.defaultBindings)
        let registryIDs = Set(delegate._defaultCommandsForTesting().map(\.id))
        let menuIDs = Set(commandIDs(in: AttoMainMenuBuilder.build(appDelegate: delegate)))
        let defaultKeymapIDs = Set(AttoKeymap.defaultBindings.keys)

        XCTAssertTrue(
            menuIDs.subtracting(registryIDs).isEmpty,
            "Menu references commands missing from the registry: \(menuIDs.subtracting(registryIDs).sorted())"
        )
        XCTAssertTrue(
            defaultKeymapIDs.subtracting(registryIDs).isEmpty,
            "Default keymap references commands missing from the registry: \(defaultKeymapIDs.subtracting(registryIDs).sorted())"
        )
        XCTAssertTrue(menuIDs.contains("workbench.command_palette"))
        XCTAssertTrue(defaultKeymapIDs.contains("workbench.command_palette"))
    }

    func testRegisteredCommandsHaveDiscoverableSurfacePolicy() throws {
        let delegate = AttoAppDelegate(keyBindings: AttoKeymap.defaultBindings)
        let registryIDs = Set(delegate._defaultCommandsForTesting().map(\.id))
        let menuIDs = Set(commandIDs(in: AttoMainMenuBuilder.build(appDelegate: delegate)))
        let defaultKeymapIDs = Set(AttoKeymap.defaultBindings.keys)
        var paletteOnlyCommandIDs = Set(AttoEditorAreaViewController.CursorMovementCommand.allCases.map(\.id))
        paletteOnlyCommandIDs.insert("workspace.show_workspace_edit_history")

        let discoverableIDs = menuIDs.union(defaultKeymapIDs).union(paletteOnlyCommandIDs)
        XCTAssertTrue(
            registryIDs.subtracting(discoverableIDs).isEmpty,
            "Registered commands need menu/keymap coverage or an explicit palette-only policy: \(registryIDs.subtracting(discoverableIDs).sorted())"
        )
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

        let closeRight = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "file.close_tabs_to_right"))
        XCTAssertEqual(closeRight.macroPolicy, .recordable)
        XCTAssertFalse(closeRight.isParameterized)

        let closeAll = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "file.close_all_tabs"))
        XCTAssertEqual(closeAll.macroPolicy, .recordable)
        XCTAssertFalse(closeAll.isParameterized)

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

        let workspaceUndo = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "workspace.undo_last_workspace_edit"))
        XCTAssertEqual(workspaceUndo.macroPolicy, .notRecordable)
        XCTAssertEqual(
            workspaceUndo.requiredRuntimeFeatures,
            .workspaceEditTransactionUndoCommandRequirements
        )

        let workspaceRedo = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "workspace.redo_last_workspace_edit"))
        XCTAssertEqual(workspaceRedo.macroPolicy, .notRecordable)
        XCTAssertEqual(
            workspaceRedo.requiredRuntimeFeatures,
            .workspaceEditTransactionRedoCommandRequirements
        )

        let toggleMacro = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "macro.toggle_recording"))
        XCTAssertEqual(toggleMacro.macroPolicy, .notRecordable)
        let replayMacro = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "macro.replay_last"))
        XCTAssertEqual(replayMacro.macroPolicy, .notRecordable)
        let saveNamedMacro = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "macro.save_named"))
        XCTAssertEqual(saveNamedMacro.macroPolicy, .notRecordable)
        XCTAssertEqual(saveNamedMacro.parameters.map(\.name), ["name"])
        XCTAssertEqual(saveNamedMacro.parameters.first?.kind, .string)
        XCTAssertTrue(saveNamedMacro.parameters.first?.isRequired == true)
        XCTAssertEqual(saveNamedMacro.parameters.first?.allowsEmptyString, false)
        let replayNamedMacro = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "macro.replay_named"))
        XCTAssertEqual(replayNamedMacro.macroPolicy, .notRecordable)
        XCTAssertEqual(replayNamedMacro.parameters.map(\.name), ["name"])
        let renameNamedMacro = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "macro.rename_named"))
        XCTAssertEqual(renameNamedMacro.macroPolicy, .notRecordable)
        XCTAssertEqual(renameNamedMacro.parameters.map(\.name), ["oldName", "newName"])
        XCTAssertEqual(renameNamedMacro.parameters.first?.kind, .string)
        XCTAssertEqual(renameNamedMacro.parameters.last?.kind, .string)
        let deleteNamedMacro = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "macro.delete_named"))
        XCTAssertEqual(deleteNamedMacro.macroPolicy, .notRecordable)
        XCTAssertEqual(deleteNamedMacro.parameters.map(\.name), ["name"])
        let deleteNamedMacros = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "macro.delete_named_batch"))
        XCTAssertEqual(deleteNamedMacros.macroPolicy, .notRecordable)
        XCTAssertEqual(deleteNamedMacros.parameters.map(\.name), ["names"])
        XCTAssertEqual(deleteNamedMacros.parameters.first?.kind, .json)
        let undoDeleteMacro = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "macro.undo_delete"))
        XCTAssertEqual(undoDeleteMacro.macroPolicy, .notRecordable)
        XCTAssertFalse(undoDeleteMacro.isParameterized)
        let showDeleteHistory = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "macro.show_delete_history"))
        XCTAssertEqual(showDeleteHistory.macroPolicy, .notRecordable)
        XCTAssertFalse(showDeleteHistory.isParameterized)
        let manageDeleteHistory = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "macro.manage_delete_history"))
        XCTAssertEqual(manageDeleteHistory.macroPolicy, .notRecordable)
        XCTAssertFalse(manageDeleteHistory.isParameterized)
        let removeDeleteHistoryEntry = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "macro.remove_delete_history_entry"))
        XCTAssertEqual(removeDeleteHistoryEntry.macroPolicy, .notRecordable)
        XCTAssertEqual(removeDeleteHistoryEntry.parameters.map(\.name), ["index"])
        XCTAssertEqual(removeDeleteHistoryEntry.parameters.first?.kind, .integer)
        XCTAssertEqual(removeDeleteHistoryEntry.parameters.first?.minimumInteger, 1)
        let removeDeleteHistoryEntries = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "macro.remove_delete_history_entries"))
        XCTAssertEqual(removeDeleteHistoryEntries.macroPolicy, .notRecordable)
        XCTAssertEqual(removeDeleteHistoryEntries.parameters.map(\.name), ["indices"])
        XCTAssertEqual(removeDeleteHistoryEntries.parameters.first?.kind, .json)
        let clearDeleteHistory = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "macro.clear_delete_history"))
        XCTAssertEqual(clearDeleteHistory.macroPolicy, .notRecordable)
        XCTAssertFalse(clearDeleteHistory.isParameterized)
        let importMacro = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "macro.import_file"))
        XCTAssertEqual(importMacro.macroPolicy, .notRecordable)
        XCTAssertEqual(importMacro.parameters.map(\.name), ["path", "name"])
        XCTAssertEqual(importMacro.parameters[0].kind, .string)
        XCTAssertEqual(importMacro.parameters[1].kind, .string)
        let exportMacro = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "macro.export_named"))
        XCTAssertEqual(exportMacro.macroPolicy, .notRecordable)
        XCTAssertEqual(exportMacro.parameters.map(\.name), ["name", "path"])

        let openFile = try XCTUnwrap(delegate._commandSchemaForTesting(commandID: "file.open_file"))
        XCTAssertEqual(openFile.macroPolicy, .promptRequired)
        let openRecentProject = try XCTUnwrap(
            delegate._commandSchemaForTesting(commandID: "file.open_recent_project")
        )
        XCTAssertEqual(openRecentProject.macroPolicy, .promptRequired)
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
        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "workspace.undo_last_workspace_edit"))
        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "workspace.redo_last_workspace_edit"))

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
        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "workspace.undo_last_workspace_edit"))
        XCTAssertFalse(delegate._commandIsEnabledForTesting(commandID: "workspace.redo_last_workspace_edit"))
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
        defer {
            ctx.editorAreaController.workspaceEditHistoryPanelController?.hide()
            ctx.window.close()
        }
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

    private func commandIDs(in menu: NSMenu) -> [String] {
        var out: [String] = []
        for item in menu.items {
            if let commandID = item.representedObject as? String {
                out.append(commandID)
            }
            if let submenu = item.submenu {
                out.append(contentsOf: commandIDs(in: submenu))
            }
        }
        return out
    }
}
