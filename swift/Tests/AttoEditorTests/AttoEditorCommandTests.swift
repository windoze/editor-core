import AppKit
@testable import AttoEditor
import EditorCoreUI
import EditorCoreUIFFI
import XCTest

@MainActor
final class AttoEditorCommandTests: XCTestCase {
    private func allowWorkspaceEditPreviewConfirmation(_ vc: AttoEditorAreaViewController) {
        vc._setWorkspaceEditPreviewDecisionProviderForTesting { _ in .apply }
    }

    func testDefaultCommandPaletteIncludesCoreEditorCommandIDs() throws {
        let delegate = AttoAppDelegate()
        let ids = Set(delegate._defaultCommandsForTesting().map(\.id))

        XCTAssertTrue(ids.contains("editor.format_document"))
        XCTAssertTrue(ids.contains("editor.format_selection"))
        XCTAssertTrue(ids.contains("editor.duplicate_lines"))
        XCTAssertTrue(ids.contains("file.close_tab"))
        XCTAssertTrue(ids.contains("file.close_all_tabs"))
        XCTAssertTrue(ids.contains("file.close_other_tabs"))
        XCTAssertTrue(ids.contains("file.close_tabs_to_right"))
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
        XCTAssertTrue(ids.contains("workspace.undo_last_workspace_edit"))
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
        XCTAssertTrue(ids.contains("lsp.restart_project_servers"))
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

        let workspaceUndo = try XCTUnwrap(commands.first { $0.id == "workspace.undo_last_workspace_edit" })
        XCTAssertEqual(workspaceUndo.group, "Workspace")
        XCTAssertFalse(workspaceUndo.requiresEditor)
        XCTAssertFalse(workspaceUndo.isEnabled)

        let closeRight = try XCTUnwrap(commands.first { $0.id == "file.close_tabs_to_right" })
        XCTAssertEqual(closeRight.group, "File")
        XCTAssertTrue(closeRight.requiresEditor)
        XCTAssertFalse(closeRight.isEnabled)

        let closeAll = try XCTUnwrap(commands.first { $0.id == "file.close_all_tabs" })
        XCTAssertEqual(closeAll.group, "File")
        XCTAssertTrue(closeAll.requiresEditor)
        XCTAssertFalse(closeAll.isEnabled)
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
        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "workspace.undo_last_workspace_edit"))

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

    func testApplyTypedFoldingRangesResultUpdatesDerivedState() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("typed-folds.txt")
        try """
        import A
        import B
        let value = 1
        """.write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        let result = try JSONDecoder().decode(EcuLspFoldingRangeResult.self, from: Data("""
        [
          {
            "startLine": 0,
            "endLine": 1,
            "kind": "imports"
          }
        ]
        """.utf8))

        XCTAssertTrue(vc.applyFoldingRangesResultToActiveTab(result))

        let regions = vc._activeDerivedStateForTesting().foldingRegions.regions
        XCTAssertEqual(regions.count, 1)
        XCTAssertEqual(regions[0].startLine, 0)
        XCTAssertEqual(regions[0].endLine, 1)
        XCTAssertFalse(regions[0].isCollapsed)
        XCTAssertEqual(regions[0].placeholder, "use ...")
    }

    func testUnifiedLspFeedbackUpdatesTransientStatusForEmptyFoldingRanges() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("empty-folds.txt")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        let result = try JSONDecoder().decode(EcuLspFoldingRangeResult.self, from: Data("[]".utf8))
        XCTAssertTrue(vc.applyFoldingRangesResultToActiveTab(result, showFeedback: true))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Folding ranges: no results")
    }

    func testApplyTypedSemanticTokensResultUpdatesDerivedStateAndBaseline() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("semantic.txt")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        let full = try JSONDecoder().decode(EcuLspSemanticTokensResult.self, from: Data("""
        {
          "resultId": "full-1",
          "data": [0, 4, 5, 7, 0]
        }
        """.utf8))

        XCTAssertTrue(vc.applySemanticTokensResultToActiveTab(full))
        var baseline = try XCTUnwrap(vc._activeSemanticTokensBaselineForTesting())
        XCTAssertEqual(baseline.resultId, "full-1")
        XCTAssertEqual(baseline.data, [0, 4, 5, 7, 0])
        var semanticLayer = try XCTUnwrap(vc._activeDerivedStateForTesting().styleIntervals.layers.first { $0.layer == 1 })
        var interval = try XCTUnwrap(semanticLayer.intervals.first)
        XCTAssertEqual(interval.start, 4)
        XCTAssertEqual(interval.end, 9)
        XCTAssertEqual(interval.styleId, 0x0007_0000)

        let delta = try JSONDecoder().decode(EcuLspSemanticTokensResult.self, from: Data("""
        {
          "resultId": "delta-1",
          "edits": [
            { "start": 2, "deleteCount": 1, "data": [3] }
          ]
        }
        """.utf8))

        XCTAssertTrue(vc.applySemanticTokensResultToActiveTab(delta))
        baseline = try XCTUnwrap(vc._activeSemanticTokensBaselineForTesting())
        XCTAssertEqual(baseline.resultId, "delta-1")
        XCTAssertEqual(baseline.data, [0, 4, 3, 7, 0])
        semanticLayer = try XCTUnwrap(vc._activeDerivedStateForTesting().styleIntervals.layers.first { $0.layer == 1 })
        interval = try XCTUnwrap(semanticLayer.intervals.first)
        XCTAssertEqual(interval.start, 4)
        XCTAssertEqual(interval.end, 7)
        XCTAssertEqual(interval.styleId, 0x0007_0000)
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

    func testRefreshAuxiliaryLspDecorationsRequireEnabledLsp() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("auxiliary.txt")
        try "let value = demo()\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.refreshInlayHintsInActiveTab(showFeedback: false))
        XCTAssertFalse(vc.refreshDocumentLinksInActiveTab(showFeedback: false))
    }

    func testUnresolvedDocumentLinkClickUsesResolveFeedbackWhenLspDisabled() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("links.txt")
        try "a c\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.lspApplyDocumentLinksJSON("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 1 },
              "end": { "line": 0, "character": 2 }
            },
            "data": { "id": 42 }
          }
        ]
        """)

        let point = try editorView.editor.charOffsetToViewPoint(offset: 1)
        XCTAssertFalse(editorView.openDocumentLinkIfPresent(xPx: point.xPx + 1, yPx: point.yPx + 1))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Document link resolve: unavailable")
    }

    func testDocumentLinkPanelUsesDerivedDecorations() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("links-panel.txt")
        let text = """
        docs
        local
        """
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.lspApplyDocumentLinksJSON("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 4 }
            },
            "target": "https://example.com/docs",
            "tooltip": "Open docs"
          },
          {
            "range": {
              "start": { "line": 1, "character": 0 },
              "end": { "line": 1, "character": 5 }
            },
            "tooltip": "Resolve local link",
            "data": { "id": 7 }
          }
        ]
        """)

        XCTAssertTrue(vc.showDocumentLinksPanelInActiveTab())
        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.documentLinkPanel
        })
        XCTAssertEqual(panel.title, "Document Links (2)")

        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.documentLinkPanelSearchField, in: root) as? NSSearchField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.documentLinkPanelTable, in: root) as? NSTableView
        )
        XCTAssertEqual(searchField.placeholderString, "Filter document links...")
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(vc._documentLinkPanelRowCountForTesting(), 2)
        XCTAssertEqual(vc._documentLinkPanelItemsForTesting().map(\.title), [
            "https://example.com/docs",
            "Resolve local link",
        ])
        XCTAssertEqual(vc._documentLinkPanelItemsForTesting().map(\.target), [
            "https://example.com/docs",
            nil,
        ])
        XCTAssertTrue(vc._documentLinkPanelIsVisibleForTesting())
    }

    func testInlayHintClickUsesResolveFeedbackWhenLspDisabled() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("hints.txt")
        try "ab\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let hintJSON = """
        {
          "position": { "line": 0, "character": 1 },
          "label": ": Int",
          "data": { "id": 42 }
        }
        """
        XCTAssertFalse(editorView.onInlayHintClick?(hintJSON) ?? true)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Inlay hint resolve: unavailable")
    }

    func testInlayHintPanelUsesDerivedDecorations() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("inlay-panel.swift")
        let text = """
        let value = makeValue()
        call(value)
        """
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        defer { window.close() }
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.lspApplyInlayHintsJSON("""
        [
          {
            "position": { "line": 0, "character": 9 },
            "label": ": Int",
            "kind": 1
          },
          {
            "position": { "line": 1, "character": 5 },
            "label": [{ "value": "argument:" }],
            "kind": 2
          }
        ]
        """)

        XCTAssertTrue(vc.showInlayHintsPanelInActiveTab())
        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.inlayHintPanel
        })
        XCTAssertEqual(panel.title, "Inlay Hints (2)")

        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.inlayHintPanelSearchField, in: root) as? NSSearchField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.inlayHintPanelTable, in: root) as? NSTableView
        )
        XCTAssertEqual(searchField.placeholderString, "Filter inlay hints...")
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(vc._inlayHintPanelRowCountForTesting(), 2)
        XCTAssertEqual(vc._inlayHintPanelItemsForTesting().map(\.title), [": Int", "argument:"])
        XCTAssertEqual(vc._inlayHintPanelItemsForTesting().compactMap(\.kindLabel), ["Type", "Parameter"])
        XCTAssertTrue(vc._inlayHintPanelIsVisibleForTesting())
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

    func testCodeLensPanelUsesDerivedDecorations() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("lens-panel.swift")
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

        XCTAssertTrue(vc.showCodeLensPanelInActiveTab())
        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.codeLensPanel
        })
        XCTAssertEqual(panel.title, "Code Lens (2)")

        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.codeLensPanelSearchField, in: root) as? NSSearchField
        )
        let table = try XCTUnwrap(
            findView(identifier: AttoAccessibilityID.codeLensPanelTable, in: root) as? NSTableView
        )
        XCTAssertEqual(searchField.placeholderString, "Filter code lens actions...")
        XCTAssertEqual(table.numberOfRows, 2)
        XCTAssertEqual(vc._codeLensPanelRowCountForTesting(), 2)
        XCTAssertEqual(vc._codeLensPanelItemsForTesting().map(\.title), ["Run One", "Run Two"])
        XCTAssertTrue(vc._codeLensPanelIsVisibleForTesting())
    }

    func testCodeLensActionTitlesUseCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("lens-local.swift")
        let projectedURL = tempDir.appendingPathComponent("lens-projected.swift")
        let text = """
        func one() {}
        func two() {}
        """
        try text.write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let tab = try XCTUnwrap(vc.tabs.first)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(tab.coreTabID)
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.lspApplyCodeLensJSON("""
        [
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
        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.CodeLens"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 1)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        let title = try XCTUnwrap(cell.textField?.stringValue)
        XCTAssertTrue(title.contains("Run Two"))
        XCTAssertTrue(title.contains("lens-projected.swift:2:1"))
        XCTAssertFalse(title.contains("lens-local.swift"))
    }

    func testTypedCodeLensResultSummaryUsesTypedPayload() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vc = makeEditorArea(workspaceRootURL: tempDir)

        let result = try JSONDecoder().decode(EcuLspCodeLensResult.self, from: Data("""
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
        """.utf8))

        let summary = vc._codeLensResultSummaryForTesting(result)
        XCTAssertNil(summary.errorMessage)
        XCTAssertEqual(summary.count, 2)

        let error = try JSONDecoder().decode(EcuLspCodeLensResult.self, from: Data("""
        {
          "error": {
            "code": -32603,
            "message": "code lens failed"
          }
        }
        """.utf8))

        let errorSummary = vc._codeLensResultSummaryForTesting(error)
        XCTAssertEqual(errorSummary.errorMessage, "code lens failed")
        XCTAssertEqual(errorSummary.count, 0)
    }

    func testTypedAuxiliaryResultSummariesUseTypedPayload() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vc = makeEditorArea(workspaceRootURL: tempDir)

        let inlayHints = try JSONDecoder().decode(EcuLspInlayHintResult.self, from: Data("""
        [
          {
            "position": { "line": 0, "character": 4 },
            "label": ": Int",
            "kind": 1
          },
          {
            "position": { "line": 1, "character": 7 },
            "label": [{ "value": "name:" }],
            "kind": 2
          }
        ]
        """.utf8))
        let inlaySummary = vc._inlayHintResultSummaryForTesting(inlayHints)
        XCTAssertNil(inlaySummary.errorMessage)
        XCTAssertEqual(inlaySummary.count, 2)

        let documentLinks = try JSONDecoder().decode(EcuLspDocumentLinkResult.self, from: Data("""
        [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 5 }
            },
            "target": "file:///tmp/readme.md"
          }
        ]
        """.utf8))
        let linkSummary = vc._documentLinkResultSummaryForTesting(documentLinks)
        XCTAssertNil(linkSummary.errorMessage)
        XCTAssertEqual(linkSummary.count, 1)

        let error = try JSONDecoder().decode(EcuLspDocumentLinkResult.self, from: Data("""
        {
          "error": {
            "code": -32603,
            "message": "links failed"
          }
        }
        """.utf8))
        let errorSummary = vc._documentLinkResultSummaryForTesting(error)
        XCTAssertEqual(errorSummary.errorMessage, "links failed")
        XCTAssertEqual(errorSummary.count, 0)
    }

    func testResolvedInlayHintUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("inlay-source-uri.txt")
        let projectedURL = tempDir.appendingPathComponent("inlay-projected-uri.txt")
        try "alpha\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "projected\n".write(to: projectedURL, atomically: true, encoding: .utf8)

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

        let hint = try JSONDecoder().decode(EcuLspInlayHint.self, from: Data("""
        {
          "position": { "line": 0, "character": 0 },
          "label": ": String",
          "textEdits": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 0 }
              },
              "newText": "hint "
            }
          ]
        }
        """.utf8))
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))

        XCTAssertTrue(vc.consumeResolvedInlayHint(hint, in: editorView, showFeedback: false))
        XCTAssertEqual(try editorView.editor.text(), "hint alpha\n")
        XCTAssertEqual(try String(contentsOf: projectedURL, encoding: .utf8), "projected\n")
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
                "workspace.undo_last_workspace_edit": AttoKeyBinding(keyEquivalent: "z", modifiers: [.command, .option]),
            ]
        )
        let menu = AttoMainMenuBuilder.build(appDelegate: delegate)

        let fileMenu = try XCTUnwrap(topLevelMenu(title: "File", in: menu))
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
        let workspaceUndo = try XCTUnwrap(findMenuItem(commandID: "workspace.undo_last_workspace_edit", in: menu))
        XCTAssertEqual(workspaceUndo.keyEquivalent, "z")
        XCTAssertEqual(
            workspaceUndo.keyEquivalentModifierMask.intersection(.deviceIndependentFlagsMask),
            [.command, .option]
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
        XCTAssertNotNil(findMenuItem(commandID: "lsp.restart_project_servers", in: menu))
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

    func testTypedWorkspaceDiagnosticsResultNavigatesWithoutPanelWindow() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("typed-diagnostics.swift")
        try "first\nab😀cd\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        let result = try JSONDecoder().decode(EcuLspWorkspaceDiagnosticResult.self, from: Data("""
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
                  "message": "typed diagnostic"
                }
              ]
            }
          ]
        }
        """.utf8))

        XCTAssertTrue(vc.showWorkspaceDiagnosticsResultInActiveTab(result))

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
        var diagnosticsLifecycle = vc._diagnosticsLifecycleHistoryForTesting()
        var workspaceLifecycleEntries = diagnosticsLifecycle.filter { $0.family == "diagnostics.workspace" }
        var activeLifecycleEntries = diagnosticsLifecycle.filter { $0.family == "diagnostics.active" }
        XCTAssertEqual(workspaceLifecycleEntries.last?.snapshot.scope, .workspace)
        XCTAssertEqual(workspaceLifecycleEntries.last?.snapshot.problems.map(\.message), [
            "first workspace problem",
            "second workspace warning",
        ])
        XCTAssertEqual(activeLifecycleEntries.last?.snapshot.problems.map(\.message), [
            "first workspace problem",
            "second workspace warning",
        ])
        XCTAssertEqual(vc._activeMinimapDiagnosticMarkersForTesting(), [
            EditorCoreSkiaMinimapMarker(logicalLine: 0, kind: .error),
            EditorCoreSkiaMinimapMarker(logicalLine: 1, kind: .warning),
        ])
        XCTAssertEqual(vc._activeGutterDiagnosticMarkersForTesting(), [
            EditorCoreSkiaGutterDiagnosticMarker(logicalLine: 0, charOffset: 0, kind: .error),
            EditorCoreSkiaGutterDiagnosticMarker(logicalLine: 1, charOffset: 6, kind: .warning),
        ])
        let statusBar = try XCTUnwrap(findSubview(of: AttoStatusBarView.self, in: vc.view))
        var statusLabels = findSubviews(of: NSTextField.self, in: statusBar)
        XCTAssertTrue(statusLabels.contains { $0.stringValue == "Problems: 2" })

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
        XCTAssertEqual(vc._workspaceProblemsPanelUnifiedProblemsForTesting().map(\.message), [
            "first workspace problem",
            "second workspace warning",
        ])
        XCTAssertEqual(vc._workspaceProblemsPanelUnifiedProblemsForTesting().map(\.source), [.workspace, .workspace])
        XCTAssertTrue(vc._workspaceProblemsPanelIsVisibleForTesting())
        let diagnosticsCursor = vc._latestDiagnosticsLifecycleSequenceForTesting()
        let diagnosticsResultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()
        vc._updateStatusBarForTesting()
        XCTAssertEqual(vc._diagnosticsLifecycleEventsForTesting(after: diagnosticsCursor), [])
        XCTAssertEqual(vc._lspResultLifecycleEventsForTesting(after: diagnosticsResultEventCursor), [])

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
        XCTAssertEqual(vc._workspaceProblemsPanelUnifiedProblemsForTesting().map(\.message), ["third workspace problem"])
        XCTAssertEqual(vc._workspaceProblemsPanelUnifiedProblemsForTesting().map(\.source), [.workspace])
        XCTAssertEqual(vc._workspaceProblemsPanelRowCountForTesting(), 1)
        let newDiagnosticsEvents = vc._diagnosticsLifecycleEventsForTesting(after: diagnosticsCursor)
        XCTAssertEqual(newDiagnosticsEvents.map(\.family), ["diagnostics.workspace", "diagnostics.active"])
        XCTAssertEqual(newDiagnosticsEvents.last?.snapshot.problems.map(\.message), ["third workspace problem"])
        let newResultEvents = vc._lspResultLifecycleEventsForTesting(after: diagnosticsResultEventCursor)
        XCTAssertEqual(newResultEvents.map(\.family), ["diagnostics.workspace", "diagnostics.active"])
        XCTAssertEqual(newResultEvents.map(\.sourceSequence), newDiagnosticsEvents.map { Optional($0.sequence) })
        let activeDiagnosticsScope = try XCTUnwrap(newDiagnosticsEvents.last?.snapshot.scope)
        XCTAssertEqual(
            newResultEvents.map(\.payload),
            [
                .diagnostics(
                    scope: .workspace,
                    problemCount: 1,
                    markerCount: 0,
                    isStale: false,
                    staleReason: nil
                ),
                .diagnostics(
                    scope: activeDiagnosticsScope,
                    problemCount: 1,
                    markerCount: 1,
                    isStale: false,
                    staleReason: nil
                ),
            ]
        )
        diagnosticsLifecycle = vc._diagnosticsLifecycleHistoryForTesting()
        workspaceLifecycleEntries = diagnosticsLifecycle.filter { $0.family == "diagnostics.workspace" }
        activeLifecycleEntries = diagnosticsLifecycle.filter { $0.family == "diagnostics.active" }
        XCTAssertEqual(
            Array(workspaceLifecycleEntries.map(\.snapshot.statusText).suffix(2)),
            ["Problems: 2", "Problems: 1"]
        )
        XCTAssertEqual(activeLifecycleEntries.last?.snapshot.problems.map(\.message), ["third workspace problem"])
        XCTAssertEqual(vc._activeMinimapDiagnosticMarkersForTesting(), [
            EditorCoreSkiaMinimapMarker(logicalLine: 2, kind: .error),
        ])
        XCTAssertEqual(vc._activeGutterDiagnosticMarkersForTesting(), [
            EditorCoreSkiaGutterDiagnosticMarker(logicalLine: 2, charOffset: 13, kind: .error),
        ])
        statusLabels = findSubviews(of: NSTextField.self, in: statusBar)
        XCTAssertTrue(statusLabels.contains { $0.stringValue == "Problems: 1" })
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
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

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
        let persistentMetadataLabel = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspLocationPanelMetadataLabel,
                in: persistentRoot
            ) as? NSTextField
        )
        let persistentTable = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspLocationPanelTable,
                in: persistentRoot
            ) as? NSTableView
        )
        XCTAssertEqual(persistentTable.numberOfRows, 2)
        XCTAssertEqual(vc._lspLocationPanelSnapshotForTesting(), snapshot)
        let panelEntry = try XCTUnwrap(vc._lspLocationPanelEntryForTesting())
        XCTAssertEqual(panelEntry.sequence, 1)
        XCTAssertEqual(panelEntry.family, "locations")
        XCTAssertTrue(panelEntry.title.hasPrefix("Implementations:"))
        XCTAssertEqual(panelEntry.state, .fresh)
        XCTAssertEqual(panelEntry.snapshot, snapshot)
        XCTAssertEqual(persistentMetadataLabel.stringValue, "Fresh | Result #1 | locations | \(panelEntry.title)")
        XCTAssertTrue(vc._lspLocationPanelIsVisibleForTesting())

        vc._updateStatusBarForTesting()
        try editorView.editor.insertText("!")
        vc._updateStatusBarForTesting()

        let stalePanelEntry = try XCTUnwrap(vc._lspLocationPanelEntryForTesting())
        XCTAssertEqual(stalePanelEntry.sequence, panelEntry.sequence)
        XCTAssertEqual(stalePanelEntry.state, .stale(reason: "document edited"))
        XCTAssertEqual(
            persistentMetadataLabel.stringValue,
            "Stale: document edited | Result #1 | locations | \(panelEntry.title)"
        )

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
        let locationEntries = vc._lspLocationResultLifecycleHistoryForTesting()
        XCTAssertEqual(locationEntries.map(\.sequence), [1, 2])
        XCTAssertEqual(locationEntries.map(\.family), ["locations", "locations"])
        XCTAssertEqual(locationEntries.map(\.state), [.stale(reason: "document edited"), .fresh])
        XCTAssertEqual(locationEntries.map(\.snapshot.kind), [.implementation, .definition])
        XCTAssertTrue(locationEntries[0].title.hasPrefix("Implementations:"))
        XCTAssertTrue(locationEntries[1].title.hasPrefix("Definitions:"))
        let resultEvents = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
            .filter { $0.family == "locations" }
        XCTAssertEqual(resultEvents.map(\.family), ["locations", "locations"])
        XCTAssertEqual(resultEvents.map(\.sourceSequence), locationEntries.map { Optional($0.sequence) })
        XCTAssertEqual(
            resultEvents.map(\.payload),
            [
                .locations(kind: "implementation", itemCount: 2),
                .locations(kind: "definition", itemCount: 1),
            ]
        )
        let updatedPanelSnapshot = try XCTUnwrap(vc._lspLocationPanelSnapshotForTesting())
        XCTAssertEqual(updatedPanelSnapshot.kind, .definition)
        let updatedPanelEntry = try XCTUnwrap(vc._lspLocationPanelEntryForTesting())
        XCTAssertEqual(updatedPanelEntry.sequence, 2)
        XCTAssertEqual(updatedPanelEntry.family, "locations")
        XCTAssertTrue(updatedPanelEntry.title.hasPrefix("Definitions:"))
        XCTAssertEqual(updatedPanelEntry.state, .fresh)
        XCTAssertEqual(updatedPanelEntry.snapshot, updatedPanelSnapshot)
        XCTAssertEqual(persistentMetadataLabel.stringValue, "Fresh | Result #2 | locations | \(updatedPanelEntry.title)")
        XCTAssertEqual(vc._lspLocationPanelRowCountForTesting(), 1)

        let projectErrorCursor = vc._latestProjectLspPanelErrorEventSequenceForTesting()
        XCTAssertFalse(vc._recordProjectLspPanelErrorForTesting(
            family: "completion",
            title: "LSP Completion",
            slot: "completion",
            status: "error",
            message: "completion failed"
        ))
        XCTAssertTrue(vc._recordProjectLspPanelErrorForTesting(
            family: "locations",
            title: "LSP References",
            slot: "references",
            status: "error",
            message: "server busy"
        ))
        let projectErrors = vc._projectLspPanelErrorEventsForTesting(after: projectErrorCursor)
        XCTAssertEqual(projectErrors.count, 1)
        XCTAssertEqual(projectErrors[0].family, "locations")
        XCTAssertEqual(projectErrors[0].slot, "references")
        XCTAssertEqual(projectErrors[0].message, "LSP References: server busy")
        let projectErrorPanelEntry = try XCTUnwrap(vc._lspLocationPanelEntryForTesting())
        XCTAssertEqual(projectErrorPanelEntry.sequence, updatedPanelEntry.sequence)
        XCTAssertEqual(projectErrorPanelEntry.state, .error(message: "LSP References: server busy"))
        XCTAssertEqual(
            persistentMetadataLabel.stringValue,
            "Error: LSP References: server busy | Result #2 | locations | \(updatedPanelEntry.title)"
        )

        let activeEditorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        activeEditorView.editor.lspDisable()
        XCTAssertFalse(vc.goToImplementationInActiveTab())
        let errorPanelEntry = try XCTUnwrap(vc._lspLocationPanelEntryForTesting())
        XCTAssertEqual(errorPanelEntry.sequence, updatedPanelEntry.sequence)
        XCTAssertEqual(errorPanelEntry.state, .error(message: "Implementation: unavailable"))
        XCTAssertEqual(
            persistentMetadataLabel.stringValue,
            "Error: Implementation: unavailable | Result #2 | locations | \(updatedPanelEntry.title)"
        )

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

    func testProjectLspPanelRecordsStatusFailures() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let cursor = vc._latestProjectLspPanelErrorEventSequenceForTesting()

        XCTAssertFalse(vc._recordProjectLspStatusFailureForTesting(status: EcuLspStatusSnapshot(
            availability: .enabled,
            state: .ready,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: "fake-lsp"),
            activity: nil,
            detail: nil,
            capabilities: nil,
            workspaceFolders: []
        )))

        XCTAssertTrue(vc._recordProjectLspStatusFailureForTesting(status: EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: nil, version: nil, command: "fake-lsp"),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(
                pid: 123,
                state: .exited,
                exitCode: 7,
                stderrTail: "fatal: missing workspace\nlast line"
            ),
            workspaceFolders: [
                EcuLspWorkspaceFolder(uri: tempDir.absoluteString, name: tempDir.lastPathComponent),
            ]
        )))

        let events = vc._projectLspPanelErrorEventsForTesting(after: cursor)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].source, .status)
        XCTAssertEqual(events[0].family, "lsp")
        XCTAssertEqual(events[0].slot, "lsp_status")
        XCTAssertEqual(events[0].method, "lsp/status")
        XCTAssertEqual(events[0].requestId, 0)
        XCTAssertEqual(events[0].status, "failed")
        XCTAssertTrue(events[0].title.contains("LSP fake-lsp"))
        XCTAssertTrue(events[0].title.contains("Failed"))
        XCTAssertTrue(events[0].message.contains("server exited"))
        XCTAssertTrue(events[0].message.contains("stderr:"))
        XCTAssertTrue(events[0].message.contains("fatal: missing workspace"))
        XCTAssertTrue(events[0].message.contains("last line"))
    }

    func testProjectLspProcessHealthRecordsStatusSnapshots() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let cursor = vc._latestProjectLspProcessHealthEventSequenceForTesting()

        XCTAssertFalse(vc._recordProjectLspProcessHealthForTesting(status: EcuLspStatusSnapshot(
            availability: .disabled,
            state: .disabled,
            server: nil,
            activity: nil,
            detail: nil,
            capabilities: nil,
            workspaceFolders: []
        )))

        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: EcuLspStatusSnapshot(
            availability: .enabled,
            state: .ready,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: "fake-lsp"),
            activity: nil,
            detail: nil,
            capabilities: nil,
            process: EcuLspProcessStatus(pid: 456, state: .running),
            workspaceFolders: []
        )))
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: nil, version: nil, command: "fake-lsp"),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(
                pid: 456,
                state: .exited,
                exitCode: 7,
                stderrTail: "health stderr"
            ),
            workspaceFolders: []
        )))

        let events = vc._projectLspProcessHealthEventsForTesting(after: cursor)
        XCTAssertEqual(events.count, 2)
        XCTAssertEqual(events[0].availability, "enabled")
        XCTAssertEqual(events[0].state, "ready")
        XCTAssertEqual(events[0].process.pid, 456)
        XCTAssertEqual(events[0].process.state, .running)
        XCTAssertEqual(events[1].availability, "failed")
        XCTAssertEqual(events[1].state, "failed")
        XCTAssertEqual(events[1].detail, "server exited\nstderr:\nhealth stderr")
        XCTAssertEqual(events[1].process.state, .exited)
        XCTAssertEqual(events[1].process.exitCode, 7)
        XCTAssertEqual(events[1].process.stderrTail, "health stderr")
    }

    func testProjectLspStatusEventsPanelShowsRecordedFailures() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        let vc = makeEditorArea(workspaceRootURL: tempDir, projectLspProcessHealthLogStore: logStore)
        let window = attachToWindow(vc)
        defer { window.close() }

        XCTAssertFalse(vc.showProjectLspStatusEventsPanel())
        XCTAssertTrue(vc._recordProjectLspStatusFailureForTesting(status: EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: "fake-lsp"),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(
                pid: 321,
                state: .exited,
                exitCode: 9,
                stderrTail: "panel stderr tail"
            ),
            workspaceFolders: []
        )))
        XCTAssertTrue(vc.showProjectLspStatusEventsPanel())

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.ProjectStatusEvents")
        })
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.ProjectStatusEvents"),
                in: root
            ) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter LSP status events...")
        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.ProjectStatusEvents"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 1)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(cell.textField?.stringValue.contains("Status") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("server exited") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("panel stderr tail") == true)
    }

    func testProjectLspProcessHealthPanelShowsRecordedStatusSnapshots() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        let suiteName = "atto_command_lsp_dashboard_policy_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AttoPreferences(defaults: defaults, env: [:])
        preferences.setLspAutoRestartEnabled(false)
        preferences.setLspAutoRestartMaxAttempts(7)
        preferences.setLspAutoRestartBaseDelaySeconds(2.5)

        let vc = makeEditorArea(
            workspaceRootURL: tempDir,
            preferences: preferences,
            projectLspProcessHealthLogStore: logStore
        )
        let window = attachToWindow(vc)
        defer { window.close() }

        XCTAssertFalse(vc.showProjectLspProcessHealthPanel())
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: "fake-lsp"),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(
                pid: 321,
                state: .exited,
                exitCode: 9,
                stderrTail: "health panel stderr"
            ),
            workspaceFolders: []
        )))
        XCTAssertTrue(vc.showProjectLspProcessHealthPanel())

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.ProjectProcessHealth")
        })
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.ProjectProcessHealth"),
                in: root
            ) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter LSP process health...")
        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.ProjectProcessHealth"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 1)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(cell.textField?.stringValue.contains("Health") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("fake-lsp") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("failed/failed") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("process exited pid 321 exit 9") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("health panel stderr") == true)
    }

    func testProjectLspDashboardPanelShowsStatusAndHealthSnapshots() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        let suiteName = "atto_command_lsp_dashboard_policy_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AttoPreferences(defaults: defaults, env: [:])
        preferences.setLspAutoRestartEnabled(false)
        preferences.setLspAutoRestartMaxAttempts(7)
        preferences.setLspAutoRestartBaseDelaySeconds(2.5)

        let vc = makeEditorArea(
            workspaceRootURL: tempDir,
            preferences: preferences,
            projectLspProcessHealthLogStore: logStore
        )
        let window = attachToWindow(vc)
        defer { window.close() }

        XCTAssertFalse(vc.showProjectLspDashboardPanel())
        let status = EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: "fake-lsp"),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(
                pid: 321,
                state: .exited,
                exitCode: 9,
                stderrTail: "dashboard stderr"
            ),
            workspaceFolders: []
        )
        XCTAssertTrue(vc._recordProjectLspStatusFailureForTesting(status: status))
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: status))
        XCTAssertTrue(vc.showProjectLspDashboardPanel())

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.ProjectDashboard")
        })
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.ProjectDashboard"),
                in: root
            ) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter LSP project health...")
        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.ProjectDashboard"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 17)

        let summaryCell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(summaryCell.textField?.stringValue.contains("Summary -") == true)
        XCTAssertTrue(summaryCell.textField?.stringValue.contains("status failures 1") == true)
        XCTAssertTrue(summaryCell.textField?.stringValue.contains("health events 1") == true)
        XCTAssertTrue(summaryCell.textField?.stringValue.contains("persisted logs 1") == true)

        let policyCell = try XCTUnwrap(table.view(atColumn: 0, row: 1, makeIfNecessary: true) as? NSTableCellView)
        let policyTitle = policyCell.textField?.stringValue ?? ""
        XCTAssertTrue(policyTitle.contains("Recovery Policy -"), policyTitle)
        XCTAssertTrue(policyTitle.contains("auto-restart off"), policyTitle)
        XCTAssertTrue(policyTitle.contains("max attempts 7"), policyTitle)
        XCTAssertTrue(policyTitle.contains("base delay 2.5s"), policyTitle)

        let actionCell = try XCTUnwrap(table.view(atColumn: 0, row: 2, makeIfNecessary: true) as? NSTableCellView)
        let actionTitle = actionCell.textField?.stringValue ?? ""
        XCTAssertTrue(actionTitle.contains("Recovery Action - Enable auto-restart"), actionTitle)

        let increaseAttemptsCell = try XCTUnwrap(table.view(atColumn: 0, row: 3, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (increaseAttemptsCell.textField?.stringValue ?? "").contains("Recovery Action - Increase max attempts to 8")
        )
        let decreaseAttemptsCell = try XCTUnwrap(table.view(atColumn: 0, row: 4, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (decreaseAttemptsCell.textField?.stringValue ?? "").contains("Recovery Action - Decrease max attempts to 6")
        )
        let increaseBaseDelayCell = try XCTUnwrap(table.view(atColumn: 0, row: 5, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (increaseBaseDelayCell.textField?.stringValue ?? "").contains("Recovery Action - Increase base delay to 3.5s")
        )
        let decreaseBaseDelayCell = try XCTUnwrap(table.view(atColumn: 0, row: 6, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (decreaseBaseDelayCell.textField?.stringValue ?? "").contains("Recovery Action - Decrease base delay to 1.5s")
        )

        let trendCell = try XCTUnwrap(table.view(atColumn: 0, row: 7, makeIfNecessary: true) as? NSTableCellView)
        let trendTitle = trendCell.textField?.stringValue ?? ""
        XCTAssertTrue(trendTitle.contains("Trend - persisted logs"), trendTitle)
        XCTAssertTrue(trendTitle.contains("last 1h 1 failed 1"), trendTitle)
        XCTAssertTrue(trendTitle.contains("last 24h 1 failed 1"), trendTitle)

        let serverCell = try XCTUnwrap(table.view(atColumn: 0, row: 8, makeIfNecessary: true) as? NSTableCellView)
        let serverTitle = serverCell.textField?.stringValue ?? ""
        XCTAssertTrue(serverTitle.contains("Server - fake-lsp"), serverTitle)
        XCTAssertTrue(serverTitle.contains("health events 1 failed 1"), serverTitle)
        XCTAssertTrue(serverTitle.contains("persisted logs 1 failed 1"), serverTitle)
        XCTAssertTrue(serverTitle.contains("recovery enabled"), serverTitle)
        XCTAssertTrue(serverTitle.contains("max attempts 7"), serverTitle)
        XCTAssertTrue(serverTitle.contains("base delay 2.5s"), serverTitle)
        XCTAssertTrue(serverTitle.contains("global policy"), serverTitle)
        XCTAssertTrue(serverTitle.contains("latest process exited"), serverTitle)

        let serverActionCell = try XCTUnwrap(table.view(atColumn: 0, row: 9, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (serverActionCell.textField?.stringValue ?? "").contains("Recovery Action - Disable auto-restart for fake-lsp")
        )

        let serverResetPolicyCell = try XCTUnwrap(table.view(atColumn: 0, row: 10, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (serverResetPolicyCell.textField?.stringValue ?? "").contains("Recovery Action - Reset recovery policy for fake-lsp to global")
        )

        let serverIncreaseAttemptsCell = try XCTUnwrap(table.view(atColumn: 0, row: 11, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (serverIncreaseAttemptsCell.textField?.stringValue ?? "").contains("Recovery Action - Increase max attempts for fake-lsp to 8")
        )
        let serverDecreaseAttemptsCell = try XCTUnwrap(table.view(atColumn: 0, row: 12, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (serverDecreaseAttemptsCell.textField?.stringValue ?? "").contains("Recovery Action - Decrease max attempts for fake-lsp to 6")
        )
        let serverIncreaseBaseDelayCell = try XCTUnwrap(table.view(atColumn: 0, row: 13, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (serverIncreaseBaseDelayCell.textField?.stringValue ?? "").contains("Recovery Action - Increase base delay for fake-lsp to 3.5s")
        )
        let serverDecreaseBaseDelayCell = try XCTUnwrap(table.view(atColumn: 0, row: 14, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(
            (serverDecreaseBaseDelayCell.textField?.stringValue ?? "").contains("Recovery Action - Decrease base delay for fake-lsp to 1.5s")
        )

        let statusCell = try XCTUnwrap(table.view(atColumn: 0, row: 15, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(statusCell.textField?.stringValue.contains("Status -") == true)
        XCTAssertTrue(statusCell.textField?.stringValue.contains("server exited") == true)

        let healthCell = try XCTUnwrap(table.view(atColumn: 0, row: 16, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(healthCell.textField?.stringValue.contains("Health -") == true)
        XCTAssertTrue(healthCell.textField?.stringValue.contains("fake-lsp") == true)
        XCTAssertTrue(healthCell.textField?.stringValue.contains("dashboard stderr") == true)

        XCTAssertFalse(preferences.isLspAutoRestartDisabledForServer(serverName: "fake-lsp", serverCommand: nil))
        XCTAssertTrue(vc._runProjectLspDashboardCommandForTesting(id: "lsp.project_dashboard.server_recovery.0"))
        XCTAssertTrue(preferences.isLspAutoRestartDisabledForServer(serverName: "fake-lsp", serverCommand: nil))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP auto-restart disabled for fake-lsp")

        XCTAssertEqual(preferences.effectiveLspAutoRestartMaxAttempts(serverName: "fake-lsp", serverCommand: nil), 7)
        XCTAssertTrue(vc._runProjectLspDashboardCommandForTesting(
            id: "lsp.project_dashboard.server_recovery.increase_max_attempts.0"
        ))
        XCTAssertEqual(preferences.effectiveLspAutoRestartMaxAttempts(serverName: "fake-lsp", serverCommand: nil), 8)
        XCTAssertEqual(preferences.effectiveLspAutoRestartMaxAttempts, 7)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP auto-restart max attempts 8 for fake-lsp")

        XCTAssertEqual(preferences.effectiveLspAutoRestartBaseDelaySeconds(serverName: "fake-lsp", serverCommand: nil), 2.5)
        XCTAssertTrue(vc._runProjectLspDashboardCommandForTesting(
            id: "lsp.project_dashboard.server_recovery.increase_base_delay.0"
        ))
        XCTAssertEqual(preferences.effectiveLspAutoRestartBaseDelaySeconds(serverName: "fake-lsp", serverCommand: nil), 3.5)
        XCTAssertEqual(preferences.effectiveLspAutoRestartBaseDelaySeconds, 2.5)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP auto-restart base delay 3.5s for fake-lsp")

        XCTAssertTrue(preferences.hasLspAutoRestartPolicyOverrideForServer(serverName: "fake-lsp", serverCommand: nil))
        XCTAssertTrue(vc._runProjectLspDashboardCommandForTesting(
            id: "lsp.project_dashboard.server_recovery.reset_policy.0"
        ))
        XCTAssertFalse(preferences.hasLspAutoRestartPolicyOverrideForServer(serverName: "fake-lsp", serverCommand: nil))
        XCTAssertFalse(preferences.isLspAutoRestartDisabledForServer(serverName: "fake-lsp", serverCommand: nil))
        XCTAssertEqual(preferences.effectiveLspAutoRestartMaxAttempts(serverName: "fake-lsp", serverCommand: nil), 7)
        XCTAssertEqual(preferences.effectiveLspAutoRestartBaseDelaySeconds(serverName: "fake-lsp", serverCommand: nil), 2.5)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP auto-restart policy reset for fake-lsp")

        XCTAssertEqual(preferences.effectiveLspAutoRestartMaxAttempts, 7)
        XCTAssertTrue(vc._runProjectLspDashboardCommandForTesting(
            id: "lsp.project_dashboard.increase_auto_restart_max_attempts"
        ))
        XCTAssertEqual(preferences.effectiveLspAutoRestartMaxAttempts, 8)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP auto-restart max attempts 8")

        XCTAssertEqual(preferences.effectiveLspAutoRestartBaseDelaySeconds, 2.5)
        XCTAssertTrue(vc._runProjectLspDashboardCommandForTesting(
            id: "lsp.project_dashboard.increase_auto_restart_base_delay"
        ))
        XCTAssertEqual(preferences.effectiveLspAutoRestartBaseDelaySeconds, 3.5)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP auto-restart base delay 3.5s")

        XCTAssertFalse(preferences.effectiveLspAutoRestartEnabled)
        table.selectRowIndexes(IndexSet(integer: 2), byExtendingSelection: false)
        let controller = try XCTUnwrap(searchField.delegate as? AttoCommandPaletteController)
        XCTAssertTrue(controller.control(
            searchField,
            textView: NSTextView(),
            doCommandBy: #selector(NSResponder.insertNewline(_:))
        ))
        XCTAssertTrue(preferences.effectiveLspAutoRestartEnabled)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP auto-restart enabled")
    }

    func testProjectLspProcessHealthPanelFallsBackToPersistedLog() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 3,
                sourceSequence: 30,
                tabId: 77,
                viewIndex: 0,
                viewId: 700,
                serverName: "persisted-lsp",
                serverCommand: "persisted-lsp",
                availability: "failed",
                state: "failed",
                detail: "persisted exit",
                process: EcuLspProcessStatus(
                    pid: 999,
                    state: .exited,
                    exitCode: 12,
                    stderrTail: "persisted stderr"
                )
            ),
            workspaceRootURL: tempDir,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_200)
        )

        let vc = makeEditorArea(workspaceRootURL: tempDir, projectLspProcessHealthLogStore: logStore)
        let window = attachToWindow(vc)
        defer { window.close() }

        XCTAssertEqual(vc._projectLspProcessHealthEventsForTesting(after: 0), [])
        XCTAssertTrue(vc.showProjectLspProcessHealthPanel())

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.ProjectProcessHealth")
        })
        let root = try XCTUnwrap(panel.contentView)
        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.ProjectProcessHealth"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 1)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(cell.textField?.stringValue.contains("persisted-lsp") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("process exited pid 999 exit 12") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("persisted stderr") == true)
    }

    func testProjectLspProcessHealthLogPanelShowsPersistedLog() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let otherRoot = tempDir.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 1,
                sourceSequence: 10,
                tabId: 1,
                viewIndex: 0,
                viewId: 100,
                serverName: "other-lsp",
                serverCommand: "other-lsp",
                availability: "failed",
                state: "failed",
                detail: "other exit",
                process: EcuLspProcessStatus(pid: 100, state: .exited, exitCode: 1)
            ),
            workspaceRootURL: otherRoot,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_200)
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 2,
                sourceSequence: 20,
                tabId: 2,
                viewIndex: 1,
                viewId: 200,
                serverName: "persisted-lsp",
                serverCommand: "persisted-lsp",
                availability: "failed",
                state: "failed",
                detail: "persisted exit",
                process: EcuLspProcessStatus(
                    pid: 999,
                    state: .exited,
                    exitCode: 12,
                    stderrTail: "persisted stderr"
                )
            ),
            workspaceRootURL: tempDir,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_201)
        )

        let vc = makeEditorArea(workspaceRootURL: tempDir, projectLspProcessHealthLogStore: logStore)
        let window = attachToWindow(vc)
        defer { window.close() }

        XCTAssertTrue(vc.showProjectLspProcessHealthLogPanel())

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.ProjectProcessHealthLog")
        })
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.ProjectProcessHealthLog"),
                in: root
            ) as? NSSearchField
        )
        XCTAssertEqual(searchField.placeholderString, "Filter LSP process health log...")
        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.ProjectProcessHealthLog"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 1)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(cell.textField?.stringValue.contains("persisted-lsp") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("process exited pid 999 exit 12") == true)
        XCTAssertTrue(cell.textField?.stringValue.contains("persisted stderr") == true)
        XCTAssertFalse(cell.textField?.stringValue.contains("other-lsp") == true)
    }

    func testProjectLspProcessHealthLogPanelUsesFieldFilterQuery() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 1,
                sourceSequence: 10,
                tabId: 1,
                viewIndex: 0,
                viewId: 100,
                serverName: "rust-analyzer",
                serverCommand: "rust-analyzer",
                availability: "failed",
                state: "failed",
                detail: "rust exit",
                process: EcuLspProcessStatus(
                    pid: 101,
                    state: .exited,
                    exitCode: 1,
                    stderrTail: "rust stderr"
                )
            ),
            workspaceRootURL: tempDir,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_200)
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 2,
                sourceSequence: 20,
                tabId: 2,
                viewIndex: 1,
                viewId: 200,
                serverName: "pyright",
                serverCommand: "pyright-langserver",
                availability: "failed",
                state: "failed",
                detail: "pyright exit",
                process: EcuLspProcessStatus(
                    pid: 202,
                    state: .exited,
                    exitCode: 2,
                    stderrTail: "pyright stderr"
                )
            ),
            workspaceRootURL: tempDir,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_201)
        )

        let vc = makeEditorArea(workspaceRootURL: tempDir, projectLspProcessHealthLogStore: logStore)
        let window = attachToWindow(vc)
        defer { window.close() }

        XCTAssertTrue(vc.showProjectLspProcessHealthLogPanel())

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.ProjectProcessHealthLog")
        })
        let root = try XCTUnwrap(panel.contentView)
        let searchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteSearchField(prefix: "AttoEditor.LSP.ProjectProcessHealthLog"),
                in: root
            ) as? NSSearchField
        )
        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.ProjectProcessHealthLog"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 2)

        searchField.stringValue = "server:pyright process:exited"
        vc.projectLspProcessHealthLogController?.controlTextDidChange(
            Notification(name: NSControl.textDidChangeNotification, object: searchField)
        )

        XCTAssertEqual(table.numberOfRows, 1)
        let cell = try XCTUnwrap(table.view(atColumn: 0, row: 0, makeIfNecessary: true) as? NSTableCellView)
        XCTAssertTrue(cell.textField?.stringValue.contains("pyright") == true)
        XCTAssertFalse(cell.textField?.stringValue.contains("rust-analyzer") == true)
    }

    func testClearProjectLspProcessHealthLogClearsCurrentWorkspaceOnly() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let otherRoot = tempDir.appendingPathComponent("other", isDirectory: true)
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 1,
                sourceSequence: 10,
                tabId: 1,
                viewIndex: 0,
                viewId: 100,
                serverName: "current-lsp",
                serverCommand: "current-lsp",
                availability: "failed",
                state: "failed",
                detail: "current exit",
                process: EcuLspProcessStatus(pid: 101, state: .exited, exitCode: 1)
            ),
            workspaceRootURL: tempDir,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_200)
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 2,
                sourceSequence: 20,
                tabId: 2,
                viewIndex: 0,
                viewId: 200,
                serverName: "other-lsp",
                serverCommand: "other-lsp",
                availability: "enabled",
                state: "ready",
                detail: nil,
                process: EcuLspProcessStatus(pid: 202, state: .running)
            ),
            workspaceRootURL: otherRoot,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_201)
        )

        let vc = makeEditorArea(workspaceRootURL: tempDir, projectLspProcessHealthLogStore: logStore)
        XCTAssertTrue(vc.clearProjectLspProcessHealthLog(confirmBeforeClearing: false))
        XCTAssertFalse(vc.showProjectLspProcessHealthLogPanel())
        XCTAssertEqual(logStore.loadRecent(workspaceRootURL: tempDir, limit: 10), [])
        XCTAssertEqual(logStore.loadRecent(workspaceRootURL: otherRoot, limit: 10).map(\.serverName), ["other-lsp"])
        XCTAssertFalse(vc.clearProjectLspProcessHealthLog(confirmBeforeClearing: false))
    }

    func testClearProjectLspProcessHealthLogCanBeCancelledByConfirmation() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 1,
                sourceSequence: 10,
                tabId: 1,
                viewIndex: 0,
                viewId: 100,
                serverName: "current-lsp",
                serverCommand: "current-lsp",
                availability: "failed",
                state: "failed",
                detail: "current exit",
                process: EcuLspProcessStatus(pid: 101, state: .exited, exitCode: 1)
            ),
            workspaceRootURL: tempDir,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_200)
        )

        let vc = makeEditorArea(workspaceRootURL: tempDir, projectLspProcessHealthLogStore: logStore)
        XCTAssertFalse(vc.clearProjectLspProcessHealthLog(confirmationProvider: { false }))
        XCTAssertEqual(logStore.loadRecent(workspaceRootURL: tempDir, limit: 10).map(\.serverName), ["current-lsp"])

        XCTAssertTrue(vc.clearProjectLspProcessHealthLog(confirmationProvider: { true }))
        XCTAssertEqual(logStore.loadRecent(workspaceRootURL: tempDir, limit: 10), [])
    }

    func testExportProjectLspProcessHealthLogExportsCurrentWorkspaceOnly() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let otherRoot = tempDir.appendingPathComponent("other", isDirectory: true)
        let emptyRoot = tempDir.appendingPathComponent("empty", isDirectory: true)
        try FileManager.default.createDirectory(at: otherRoot, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: emptyRoot, withIntermediateDirectories: true)
        let logStore = AttoProjectLspProcessHealthLogStore(
            logFileURL: tempDir.appendingPathComponent("lsp-health.jsonl")
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 1,
                sourceSequence: 10,
                tabId: 1,
                viewIndex: 0,
                viewId: 100,
                serverName: "current-lsp",
                serverCommand: "current-lsp",
                availability: "failed",
                state: "failed",
                detail: "current exit",
                process: EcuLspProcessStatus(pid: 101, state: .exited, exitCode: 1)
            ),
            workspaceRootURL: tempDir,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_200)
        )
        try logStore.append(
            event: AttoProjectLspProcessHealthEvent(
                sequence: 2,
                sourceSequence: 20,
                tabId: 2,
                viewIndex: 0,
                viewId: 200,
                serverName: "other-lsp",
                serverCommand: "other-lsp",
                availability: "enabled",
                state: "ready",
                detail: nil,
                process: EcuLspProcessStatus(pid: 202, state: .running)
            ),
            workspaceRootURL: otherRoot,
            recordedAt: Date(timeIntervalSince1970: 1_785_715_201)
        )

        let exportURL = tempDir.appendingPathComponent("exports/current.jsonl")
        let vc = makeEditorArea(workspaceRootURL: tempDir, projectLspProcessHealthLogStore: logStore)
        XCTAssertTrue(vc.exportProjectLspProcessHealthLog(to: exportURL))
        let exported = try String(contentsOf: exportURL, encoding: .utf8)
        XCTAssertTrue(exported.contains("current-lsp"))
        XCTAssertFalse(exported.contains("other-lsp"))
        XCTAssertEqual(exported.split(whereSeparator: \.isNewline).count, 1)

        let emptyExportURL = tempDir.appendingPathComponent("exports/empty.jsonl")
        let emptyVC = makeEditorArea(workspaceRootURL: emptyRoot, projectLspProcessHealthLogStore: logStore)
        XCTAssertFalse(emptyVC.exportProjectLspProcessHealthLog(to: emptyExportURL))
        XCTAssertFalse(FileManager.default.fileExists(atPath: emptyExportURL.path))
    }

    func testEmptyLocationResultUsesUnifiedFeedbackStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("definition.swift")
        try "func call() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.showLspLocationResultJSONInActiveTab("[]", kind: .definition))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Definition: no results")
    }

    func testLspTargetNavigationUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("lsp-target-source.swift")
        let projectedURL = tempDir.appendingPathComponent("lsp-target-projected.swift")
        try "aa\nlet target = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "projected".write(to: projectedURL, atomically: true, encoding: .utf8)

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

        vc.navigateToLspTarget(.init(
            uri: projectedURL.standardizedFileURL.absoluteString,
            line: 1,
            utf16Character: 4
        ))

        XCTAssertEqual(vc.tabs.count, 1)
        XCTAssertEqual(vc.selectedTabID, tab.id)

        let offsets = try tab.editCore.editor.selectionOffsets()
        let position = try tab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
        XCTAssertEqual(position.line, 1)
        XCTAssertEqual(position.column, 4)
    }

    func testEmptySymbolResultsUseUnifiedFeedbackStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("symbols.swift")
        try "func call() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.showDocumentSymbolResultJSONInActiveTab("[]"))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Document symbols: no results")

        XCTAssertFalse(vc.showWorkspaceSymbolResultJSONInActiveTab("[]", query: "  App  "))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Workspace symbols: no results")
    }

    func testWorkspaceOutlinePanelAggregatesDocumentSymbolSnapshots() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let appURL = tempDir.appendingPathComponent("App.swift")
        let modelURL = tempDir.appendingPathComponent("Model.swift")
        try "struct App {\n  func run() {}\n}\n".write(to: appURL, atomically: true, encoding: .utf8)
        try "final class Model {}\n".write(to: modelURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)

        vc.openFile(url: appURL, mode: .pinned)
        XCTAssertTrue(vc.showDocumentSymbolResultJSONInActiveTab("""
        [
          {
            "name": "App",
            "kind": 23,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 2, "character": 1 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 7 },
              "end": { "line": 0, "character": 10 }
            },
            "children": [
              {
                "name": "run",
                "detail": "fn()",
                "kind": 12,
                "range": {
                  "start": { "line": 1, "character": 2 },
                  "end": { "line": 1, "character": 15 }
                },
                "selectionRange": {
                  "start": { "line": 1, "character": 7 },
                  "end": { "line": 1, "character": 10 }
                }
              }
            ]
          }
        ]
        """))

        vc.openFile(url: modelURL, mode: .pinned)
        XCTAssertTrue(vc.showDocumentSymbolResultJSONInActiveTab("""
        [
          {
            "name": "Model",
            "kind": 5,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 20 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 12 },
              "end": { "line": 0, "character": 17 }
            }
          }
        ]
        """))

        let outline = vc._workspaceOutlineSnapshotForTesting()
        XCTAssertEqual(outline.documents.map(\.title), ["App.swift", "Model.swift"])
        XCTAssertEqual(outline.documents.map(\.symbolCount), [2, 1])
        XCTAssertEqual(outline.symbols.map(\.name), ["App", "run", "Model"])
        XCTAssertEqual(outline.symbols.map(\.containerName), ["App.swift", "App.swift", "Model.swift"])

        XCTAssertTrue(vc.showWorkspaceOutlinePanel())
        let persistentPanel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.lspSymbolPanel
        })
        XCTAssertEqual(persistentPanel.title, "Workspace Outline (3)")
        let persistentRoot = try XCTUnwrap(persistentPanel.contentView)
        let persistentSearchField = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspSymbolPanelSearchField,
                in: persistentRoot
            ) as? NSSearchField
        )
        XCTAssertEqual(persistentSearchField.placeholderString, "Filter workspace outline...")
        let persistentMetadataLabel = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspSymbolPanelMetadataLabel,
                in: persistentRoot
            ) as? NSTextField
        )
        XCTAssertEqual(
            persistentMetadataLabel.stringValue,
            "Fresh | Result #3 | symbols | Workspace Outline: 2 files, 3 symbols"
        )
        XCTAssertEqual(vc._lspSymbolPanelRowCountForTesting(), 3)
        XCTAssertEqual(vc._lspSymbolPanelSnapshotForTesting()?.symbols.map(\.name), ["App", "run", "Model"])
    }

    func testDocumentSymbolsUseCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("SymbolsSource.swift")
        let projectedURL = tempDir.appendingPathComponent("SymbolsProjected.swift")
        try "struct Source {}\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "struct Projected {}\n".write(to: projectedURL, atomically: true, encoding: .utf8)

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

        XCTAssertTrue(vc.showDocumentSymbolResultJSONInActiveTab("""
        [
          {
            "name": "Source",
            "kind": 23,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 16 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 7 },
              "end": { "line": 0, "character": 13 }
            }
          }
        ]
        """))

        let symbolSnapshot = try XCTUnwrap(vc._lastLspSymbolResultForTesting())
        XCTAssertEqual(symbolSnapshot.symbols.map(\.target.uri), [
            projectedURL.standardizedFileURL.absoluteString,
        ])

        let outline = vc._workspaceOutlineSnapshotForTesting()
        XCTAssertEqual(outline.documents.map(\.uri), [
            projectedURL.standardizedFileURL.absoluteString,
        ])
        XCTAssertEqual(outline.symbols.map(\.target.uri), [
            projectedURL.standardizedFileURL.absoluteString,
        ])
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
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

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
        let persistentMetadataLabel = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspSymbolPanelMetadataLabel,
                in: persistentRoot
            ) as? NSTextField
        )
        XCTAssertEqual(
            persistentMetadataLabel.stringValue,
            "Fresh | Result #1 | symbols | Workspace Symbols: Project: 2 results"
        )
        let persistentTable = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.lspSymbolPanelTable,
                in: persistentRoot
            ) as? NSTableView
        )
        XCTAssertEqual(persistentTable.numberOfRows, 2)
        XCTAssertEqual(vc._lspSymbolPanelSnapshotForTesting(), snapshot)
        let panelEntry = try XCTUnwrap(vc._lspSymbolPanelEntryForTesting())
        XCTAssertEqual(panelEntry.sequence, 1)
        XCTAssertEqual(panelEntry.family, "symbols")
        XCTAssertEqual(panelEntry.title, "Workspace Symbols: Project: 2 results")
        XCTAssertEqual(panelEntry.state, .fresh)
        XCTAssertEqual(panelEntry.snapshot, snapshot)
        XCTAssertTrue(vc._lspSymbolPanelIsVisibleForTesting())

        vc._updateStatusBarForTesting()
        try editorView.editor.insertText("!")
        vc._updateStatusBarForTesting()

        let stalePanelEntry = try XCTUnwrap(vc._lspSymbolPanelEntryForTesting())
        XCTAssertEqual(stalePanelEntry.sequence, panelEntry.sequence)
        XCTAssertEqual(stalePanelEntry.state, .stale(reason: "document edited"))
        XCTAssertEqual(
            persistentMetadataLabel.stringValue,
            "Stale: document edited | Result #1 | symbols | Workspace Symbols: Project: 2 results"
        )

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
        let symbolEntries = vc._lspSymbolResultLifecycleHistoryForTesting()
        XCTAssertEqual(symbolEntries.map(\.sequence), [1, 2])
        XCTAssertEqual(symbolEntries.map(\.family), ["symbols", "symbols"])
        XCTAssertEqual(symbolEntries.map(\.state), [.stale(reason: "document edited"), .fresh])
        XCTAssertEqual(symbolEntries.map(\.snapshot.title), ["Workspace Symbols: Project", "Workspace Symbols: Open"])
        XCTAssertEqual(symbolEntries.map(\.title), ["Workspace Symbols: Project: 2 results", "Workspace Symbols: Open: 1 results"])
        let resultEvents = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
            .filter { $0.family == "symbols" }
        XCTAssertEqual(resultEvents.map(\.family), ["symbols", "symbols"])
        XCTAssertEqual(resultEvents.map(\.sourceSequence), symbolEntries.map { Optional($0.sequence) })
        XCTAssertEqual(
            resultEvents.map(\.payload),
            [
                .symbols(title: "Workspace Symbols: Project", itemCount: 2),
                .symbols(title: "Workspace Symbols: Open", itemCount: 1),
            ]
        )
        let updatedPanelSnapshot = try XCTUnwrap(vc._lspSymbolPanelSnapshotForTesting())
        XCTAssertEqual(updatedPanelSnapshot.title, "Workspace Symbols: Open")
        let updatedPanelEntry = try XCTUnwrap(vc._lspSymbolPanelEntryForTesting())
        XCTAssertEqual(updatedPanelEntry.sequence, 2)
        XCTAssertEqual(updatedPanelEntry.family, "symbols")
        XCTAssertEqual(updatedPanelEntry.title, "Workspace Symbols: Open: 1 results")
        XCTAssertEqual(updatedPanelEntry.state, .fresh)
        XCTAssertEqual(updatedPanelEntry.snapshot, updatedPanelSnapshot)
        XCTAssertEqual(persistentMetadataLabel.stringValue, "Fresh | Result #2 | symbols | Workspace Symbols: Open: 1 results")
        XCTAssertEqual(vc._lspSymbolPanelRowCountForTesting(), 1)

        let projectErrorCursor = vc._latestProjectLspPanelErrorEventSequenceForTesting()
        XCTAssertFalse(vc._recordProjectLspPanelErrorForTesting(
            family: "locations",
            title: "LSP References",
            slot: "references",
            status: "success",
            message: "ignored"
        ))
        XCTAssertTrue(vc._recordProjectLspPanelErrorForTesting(
            family: "symbols",
            title: "LSP Workspace Symbols",
            slot: "workspace_symbols",
            status: "timeout",
            message: ""
        ))
        let projectErrors = vc._projectLspPanelErrorEventsForTesting(after: projectErrorCursor)
        XCTAssertEqual(projectErrors.count, 1)
        XCTAssertEqual(projectErrors[0].family, "symbols")
        XCTAssertEqual(projectErrors[0].slot, "workspace_symbols")
        XCTAssertEqual(projectErrors[0].message, "LSP Workspace Symbols: timeout")
        let projectErrorPanelEntry = try XCTUnwrap(vc._lspSymbolPanelEntryForTesting())
        XCTAssertEqual(projectErrorPanelEntry.sequence, updatedPanelEntry.sequence)
        XCTAssertEqual(projectErrorPanelEntry.state, .error(message: "LSP Workspace Symbols: timeout"))
        XCTAssertEqual(
            persistentMetadataLabel.stringValue,
            "Error: LSP Workspace Symbols: timeout | Result #2 | symbols | Workspace Symbols: Open: 1 results"
        )

        let activeEditorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        activeEditorView.editor.lspDisable()
        XCTAssertFalse(vc.showWorkspaceSymbolsInActiveTab(query: "Broken"))
        let errorPanelEntry = try XCTUnwrap(vc._lspSymbolPanelEntryForTesting())
        XCTAssertEqual(errorPanelEntry.sequence, updatedPanelEntry.sequence)
        XCTAssertEqual(errorPanelEntry.state, .error(message: "Workspace symbols: unavailable"))
        XCTAssertEqual(
            persistentMetadataLabel.stringValue,
            "Error: Workspace symbols: unavailable | Result #2 | symbols | Workspace Symbols: Open: 1 results"
        )

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

    func testCodeActionResultRecordsLspResultEvent() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("code-actions.swift")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

        XCTAssertTrue(vc._showCodeActionResultJSONForTesting("""
        [
          {
            "title": "Fix import",
            "kind": "quickfix",
            "isPreferred": true
          },
          {
            "title": "Extract method",
            "kind": "refactor.extract"
          }
        ]
        """, onlyKinds: ["quickfix"]))

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.commandPalettePanel(prefix: "AttoEditor.LSP.CodeActions")
        })
        let root = try XCTUnwrap(panel.contentView)
        let table = try XCTUnwrap(
            findView(
                identifier: AttoAccessibilityID.commandPaletteTable(prefix: "AttoEditor.LSP.CodeActions"),
                in: root
            ) as? NSTableView
        )
        XCTAssertEqual(table.numberOfRows, 1)

        let events = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
        XCTAssertEqual(events.map(\.family), ["code_actions"])
        XCTAssertEqual(events.last?.title, "Code Actions: quickfix: 1 result")
        XCTAssertNil(events.last?.sourceSequence)
        XCTAssertEqual(events.last?.payload, .codeActions(onlyKinds: ["quickfix"], itemCount: 1))
    }

    func testCompletionResultRecordsLspResultEvent() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("completion.swift")
        try "pri".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

        XCTAssertTrue(vc._showCompletionResultJSONForTesting("""
        {
          "isIncomplete": false,
          "items": [
            { "label": "print", "kind": 3, "detail": "(value: Any)" },
            { "label": "private", "kind": 14 }
          ]
        }
        """))

        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.completionPanel
        })
        let root = try XCTUnwrap(panel.contentView)
        let table = try XCTUnwrap(findView(identifier: AttoAccessibilityID.completionTable, in: root) as? NSTableView)
        XCTAssertEqual(table.numberOfRows, 2)

        let events = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
        XCTAssertEqual(events.map(\.family), ["completion"])
        XCTAssertEqual(events.last?.title, "Completion: 2 items")
        XCTAssertNil(events.last?.sourceSequence)
        XCTAssertEqual(events.last?.payload, .completion(itemCount: 2))
    }

    func testEmptyCompletionResultUsesUnifiedFeedbackStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("completion-empty.swift")
        try "pri".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc._showCompletionResultJSONForTesting(#"{ "isIncomplete": false, "items": [] }"#))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Completion: no results")
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

    func testApplyTypedLinkedEditingRangeResultCreatesMulticursorSelections() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("typed-linked.txt")
        try "foo + foo\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 7, end: 7)], primaryIndex: 0)

        let result = try JSONDecoder().decode(EcuLspLinkedEditingRangeResult.self, from: Data("""
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
        """.utf8))

        XCTAssertTrue(vc.applyLinkedEditingRangeResultToActiveTab(result, caretOffset: 7))

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

    func testEmptyColorResultsUseUnifiedFeedbackStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("empty-color.txt")
        try "let color = \"#ff0000\"\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        vc.openFile(url: fileURL, mode: .pinned)
        let tabID = try XCTUnwrap(vc.openFileItems().first?.id)

        XCTAssertFalse(vc.showDocumentColorResultJSONInActiveTab("[]", showFeedback: true))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Document colors: no results")

        let item = AttoLspDocumentColorParser.Item(
            range: EcuSelectionRange(start: 13, end: 20),
            startLine: 0,
            startUTF16Character: 13,
            color: AttoLspDocumentColorParser.Color(red: 1, green: 0, blue: 0, alpha: 1)
        )
        XCTAssertFalse(vc.showColorPresentationResultJSONInActiveTab(
            "[]",
            item: item,
            tabID: tabID,
            showFeedback: true
        ))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Color presentations: no results")
    }

    func testEmptyCodeActionResultsUseUnifiedFeedbackStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("empty-code-actions.txt")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc._showCodeActionResultJSONForTesting("[]", showFeedback: true))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Code actions: no results")
    }

    func testEmptyRenameResultUsesUnifiedFeedbackStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("empty-rename.swift")
        try "let oldName = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc._applyRenameResultJSONForTesting(#"{}"#, newName: "newName", showFeedback: true))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Rename: no results")
    }

    func testEmptyHierarchyResultsUseUnifiedFeedbackStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("empty-hierarchy.swift")
        try "func caller() {}\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc._showHierarchyResultJSONForTesting("[]", kind: "callIncoming", showFeedback: true))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Call hierarchy: no results")

        XCTAssertFalse(vc._showHierarchyResultJSONForTesting("[]", kind: "typeSupertypes", showFeedback: true))
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Type hierarchy: no results")
    }

    func testFormattingResultsUseUnifiedFeedbackStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("formatting.swift")
        try "let value = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.formatDocumentWithLspInActiveTab())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Format document: unavailable")

        XCTAssertFalse(vc.formatSelectionWithLspInActiveTab())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Format selection: no results")
    }

    func testDocumentColorResultsRecordLspResultEvents() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("color-events.txt")
        try "let color = \"#ff0000\"\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let tabID = try XCTUnwrap(vc.openFileItems().first?.id)
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

        let documentColorJSON = """
        [
          {
            "range": {
              "start": { "line": 0, "character": 13 },
              "end": { "line": 0, "character": 20 }
            },
            "color": { "red": 1, "green": 0, "blue": 0, "alpha": 1 }
          }
        ]
        """
        XCTAssertTrue(vc.showDocumentColorResultJSONInActiveTab(documentColorJSON))
        let item = try XCTUnwrap(AttoLspDocumentColorParser.items(
            fromDocumentColorResultJSON: documentColorJSON,
            documentText: try editorView.editor.text()
        ).first)

        XCTAssertTrue(vc.showColorPresentationResultJSONInActiveTab("""
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
          },
          { "label": "#ff0000" }
        ]
        """, item: item, tabID: tabID))

        let events = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
            .filter { $0.family == "document_colors" || $0.family == "color_presentations" }
        XCTAssertEqual(events.map(\.family), ["document_colors", "color_presentations"])
        XCTAssertEqual(
            events.map(\.payload),
            [
                .documentColors(mode: "presentations", itemCount: 1),
                .colorPresentations(itemCount: 2),
            ]
        )
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

    func testApplyTypedSelectionRangeResultExpandsActiveSelection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("typed-selection.txt")
        try "let value = call(arg)\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.setSelections([EcuSelectionRange(start: 17, end: 20)], primaryIndex: 0)

        let result = try JSONDecoder().decode(EcuLspSelectionRangeResult.self, from: Data("""
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
              }
            }
          }
        ]
        """.utf8))

        XCTAssertTrue(vc.applySelectionRangeResultToActiveTab(result))
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
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

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
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "aBc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "Xother\n")
        XCTAssertTrue(window.title.contains("●"))
    }

    func testWorkspaceEditTransactionUndoRestoresAppProjectionAndFiles() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("undo-main.txt")
        let otherURL = tempDir.appendingPathComponent("undo-other.txt")
        try "abc\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "other\n".write(to: otherURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(vc)

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

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        var editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "aBc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "Xother\n")
        XCTAssertTrue(window.title.contains("●"))

        XCTAssertTrue(vc._undoLastCoreWorkspaceEditTransactionForTesting())
        editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "abc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "other\n")
        XCTAssertFalse(window.title.contains("●"))
        XCTAssertFalse(vc._undoLastCoreWorkspaceEditTransactionForTesting())
    }

    func testWorkspaceEditTransactionUndoCommandRestoresAppProjectionAndFiles() throws {
        let delegate = AttoAppDelegate(keyBindings: [:])
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("undo-command-main.txt")
        let otherURL = tempDir.appendingPathComponent("undo-command-other.txt")
        try "abc\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "other\n".write(to: otherURL, atomically: true, encoding: .utf8)

        let ctx = delegate._createWindowForTesting(workspaceRootURL: tempDir)
        defer { ctx.window.close() }
        ctx.editorAreaController.openFile(url: fileURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(ctx.editorAreaController)

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

        XCTAssertTrue(ctx.editorAreaController.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        var editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        XCTAssertEqual(try editorView.editor.text(), "aBc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "Xother\n")
        XCTAssertTrue(ctx.window.title.contains("●"))

        XCTAssertTrue(delegate._commandIsEnabledForTesting(commandID: "workspace.undo_last_workspace_edit"))
        XCTAssertTrue(delegate.executeCommand(id: "workspace.undo_last_workspace_edit"))

        editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: ctx.editorAreaController.view))
        XCTAssertEqual(try editorView.editor.text(), "abc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "other\n")
        XCTAssertFalse(ctx.window.title.contains("●"))
    }

    func testWorkspaceEditPreviewConfirmationCanCancelCoreTransaction() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("preview-cancel.txt")
        let otherURL = tempDir.appendingPathComponent("preview-other.txt")
        try "abc\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "other\n".write(to: otherURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        var capturedPreview: AttoWorkspaceEditPreview?
        vc._setWorkspaceEditPreviewDecisionProviderForTesting { preview in
            capturedPreview = preview
            return .cancel
        }
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

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

        XCTAssertFalse(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor
        )

        let preview = try XCTUnwrap(capturedPreview)
        XCTAssertTrue(preview.requiresConfirmation)
        XCTAssertTrue(preview.displayText.contains("Workspace edit preview."))
        XCTAssertTrue(preview.displayText.contains("preview-cancel.txt"))
        XCTAssertTrue(preview.displayText.contains("preview-other.txt"))
        XCTAssertEqual(preview.sections.count, 2)
        XCTAssertTrue(preview.sections.contains { section in
            section.title == "preview-cancel.txt"
                && section.detailText.contains("-abc")
                && section.detailText.contains("+aBc")
        })
        XCTAssertTrue(preview.sections.contains { section in
            section.title == "preview-other.txt"
                && section.detailText.contains("-other")
                && section.detailText.contains("+Xother")
        })
        XCTAssertEqual(vc._transientStatusTextForTesting(), "Workspace edit cancelled")

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "abc\n")
        XCTAssertEqual(try String(contentsOf: otherURL, encoding: .utf8), "other\n")
    }

    func testWorkspaceEditPreviewTextUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("preview-source-uri.txt")
        let projectedURL = tempDir.appendingPathComponent("preview-projected-uri.txt")
        try "alpha\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "projected\n".write(to: projectedURL, atomically: true, encoding: .utf8)

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

        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"unsaved "}"#))

        XCTAssertEqual(
            vc.workspaceEditPreviewText(for: projectedURL.standardizedFileURL.absoluteString),
            "unsaved alpha\n"
        )
    }

    func testWorkspaceEditApplyPreservesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("apply-source-uri.txt")
        let projectedURL = tempDir.appendingPathComponent("apply-projected-uri.txt")
        try "alpha\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "projected\n".write(to: projectedURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(vc)

        let tab = try XCTUnwrap(vc.tabs.first)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(tab.coreTabID)
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        let workspaceEdit = """
        {
          "changes": {
            "\(projectedURL.standardizedFileURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "updated "
              }
            ]
          }
        }
        """

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "updated alpha\n")
        XCTAssertEqual(vc.tabs.count, 1)
        XCTAssertEqual(tab.fileURL.standardizedFileURL, projectedURL.standardizedFileURL)
        XCTAssertEqual(try String(contentsOf: projectedURL, encoding: .utf8), "projected\n")
    }

    func testWorkspaceEditApplicationUsesCoreVersionPreflight() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("versioned.txt")
        try "abc\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "textDocument": {
                "uri": "\(fileURL.absoluteString)",
                "version": 1
              },
              "edits": [
                {
                  "range": {
                    "start": { "line": 0, "character": 1 },
                    "end": { "line": 0, "character": 2 }
                  },
                  "newText": "B"
                }
              ]
            }
          ]
        }
        """

        XCTAssertFalse(window.title.contains("●"))
        XCTAssertFalse(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "abc\n")
        XCTAssertEqual(try String(contentsOf: fileURL, encoding: .utf8), "abc\n")
        XCTAssertFalse(window.title.contains("●"))
    }

    func testRenameResultRecordsLspResultEvent() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("rename-event.swift")
        try "let oldName = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)
        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        let resultEventCursor = vc._latestLspResultLifecycleEventSequenceForTesting()

        XCTAssertTrue(vc._applyRenameResultJSONForTesting("""
        {
          "changes": {
            "\(fileURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 4 },
                  "end": { "line": 0, "character": 11 }
                },
                "newText": "newName"
              }
            ]
          }
        }
        """, newName: "newName"))

        XCTAssertEqual(try editorView.editor.text(), "let newName = 1\n")
        let events = vc._lspResultLifecycleEventsForTesting(after: resultEventCursor)
        let renameEvents = events.filter { $0.family == "rename" }
        XCTAssertEqual(renameEvents.count, 1)
        XCTAssertEqual(renameEvents.last?.title, "Rename: newName")
        XCTAssertNil(renameEvents.last?.sourceSequence)
        XCTAssertEqual(
            renameEvents.last?.payload,
            .rename(newName: "newName", documentCount: 1, resourceOperationCount: 0, applied: true)
        )
    }

    func testRenameResultUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("rename-source-uri.swift")
        let projectedURL = tempDir.appendingPathComponent("rename-projected-uri.swift")
        try "let oldName = 1\n".write(to: fileURL, atomically: true, encoding: .utf8)
        try "projected\n".write(to: projectedURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        allowWorkspaceEditPreviewConfirmation(vc)

        let tab = try XCTUnwrap(vc.tabs.first)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(tab.coreTabID)
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        XCTAssertTrue(vc._applyRenameResultJSONForTesting("""
        {
          "changes": {
            "\(projectedURL.standardizedFileURL.absoluteString)": [
              {
                "range": {
                  "start": { "line": 0, "character": 4 },
                  "end": { "line": 0, "character": 11 }
                },
                "newText": "newName"
              }
            ]
          }
        }
        """, newName: "newName"))

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "let newName = 1\n")
        XCTAssertEqual(try String(contentsOf: projectedURL, encoding: .utf8), "projected\n")
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
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

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
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )

        var editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "aBc\n")

        vc.selectFile(url: secondURL)
        editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "dEf\n")
        XCTAssertEqual(try String(contentsOf: secondURL, encoding: .utf8), "def\n")

        let secondItem = try XCTUnwrap(vc.openFileItems().first { $0.url.standardizedFileURL == secondURL.standardizedFileURL })
        XCTAssertTrue(secondItem.isDirty)
    }

    func testWorkspaceEditOpenTabProjectionCreatesUndoGroups() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("undo-first.txt")
        let secondURL = tempDir.appendingPathComponent("undo-second.txt")
        try "abc\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "def\n".write(to: secondURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.selectFile(url: firstURL)
        allowWorkspaceEditPreviewConfirmation(vc)

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
        editorView.undo(nil)
        XCTAssertEqual(try editorView.editor.text(), "abc\n")

        vc.selectFile(url: secondURL)
        editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        XCTAssertEqual(try editorView.editor.text(), "dEf\n")
        editorView.undo(nil)
        XCTAssertEqual(try editorView.editor.text(), "def\n")
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
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

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
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
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
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

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
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try String(contentsOf: renamedURL, encoding: .utf8), "old\n")

        let items = vc.openFileItems()
        XCTAssertFalse(items.contains { $0.url.standardizedFileURL == oldURL.standardizedFileURL })
        let renamedItem = try XCTUnwrap(items.first { $0.url.standardizedFileURL == renamedURL.standardizedFileURL })
        XCTAssertTrue(renamedItem.isDirty)
        let snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertTrue(snapshot.tabs.contains { tab in
            tab.documentURI == renamedURL.standardizedFileURL.absoluteString
        })

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
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

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
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: deleteURL.path))
        XCTAssertFalse(vc.openFileItems().contains { $0.url.standardizedFileURL == deleteURL.standardizedFileURL })
        XCTAssertTrue(vc.openFileItems().contains { $0.url.standardizedFileURL == keepURL.standardizedFileURL })
    }

    func testWorkspaceEditRemovedTabCallbackUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let keepURL = tempDir.appendingPathComponent("keep-projected-delete.txt")
        let localURL = tempDir.appendingPathComponent("delete-local-open.txt")
        let projectedURL = tempDir.appendingPathComponent("delete-projected-open.txt")
        try "keep\n".write(to: keepURL, atomically: true, encoding: .utf8)
        try "delete\n".write(to: localURL, atomically: true, encoding: .utf8)
        try "projected delete\n".write(to: projectedURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: keepURL, mode: .pinned)
        vc.openFile(url: localURL, mode: .pinned)
        vc.selectFile(url: keepURL)
        allowWorkspaceEditPreviewConfirmation(vc)

        let tab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == localURL.standardizedFileURL })
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(tab.coreTabID)
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, localURL.standardizedFileURL)

        var closedURLs: [URL] = []
        vc.onDidCloseFile = { closedURLs.append($0.standardizedFileURL) }

        let workspaceEdit = """
        {
          "documentChanges": [
            {
              "kind": "delete",
              "uri": "\(projectedURL.standardizedFileURL.absoluteString)"
            }
          ]
        }
        """

        XCTAssertTrue(vc.applyWorkspaceEditJSONToActiveTab(workspaceEdit))
        XCTAssertFalse(vc.tabs.contains { $0.id == tab.id })
        XCTAssertEqual(closedURLs, [projectedURL.standardizedFileURL])
        XCTAssertFalse(FileManager.default.fileExists(atPath: projectedURL.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: localURL.path))
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
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

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
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
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
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())

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
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
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
        allowWorkspaceEditPreviewConfirmation(vc)
        let coreTransactionCursor = try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting())
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
        XCTAssertEqual(
            try XCTUnwrap(vc._coreWorkspaceEditTransactionLatestSequenceForTesting()),
            coreTransactionCursor + 1
        )
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

    func testDiagnosticsLifecycleMarksActiveDiagnosticsStaleAfterDocumentEdit() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("diagnostics-stale.txt")
        try "abc\ndef\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
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
              "message": "first diagnostic"
            }
          ],
          "version": 1
        }
        """)
        vc._updateStatusBarForTesting()
        XCTAssertFalse(vc._currentDiagnosticsLifecycleEntryForTesting()?.snapshot.isStale ?? true)
        XCTAssertEqual(
            vc._currentDiagnosticsLifecycleEntryForTesting()?.snapshot.problems.map(\.message),
            ["first diagnostic"]
        )

        let baselineCursor = vc._latestDiagnosticsLifecycleSequenceForTesting()
        try editorView.editor.insertText("!")
        vc._updateStatusBarForTesting()

        let staleEvents = vc._diagnosticsLifecycleEventsForTesting(after: baselineCursor)
        XCTAssertEqual(staleEvents.map(\.family), ["diagnostics.active"])
        let staleSnapshot = try XCTUnwrap(staleEvents.last?.snapshot)
        XCTAssertTrue(staleSnapshot.isStale)
        XCTAssertEqual(staleSnapshot.staleReason, .documentEdited)
        XCTAssertEqual(staleSnapshot.problems.map(\.message), ["first diagnostic"])

        let staleCursor = vc._latestDiagnosticsLifecycleSequenceForTesting()
        try editorView.editor.lspApplyDiagnosticsJSON("""
        {
          "uri": "\(fileURL.absoluteString)",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 1, "character": 0 },
                "end": { "line": 1, "character": 3 }
              },
              "severity": 2,
              "source": "unit-test",
              "message": "updated diagnostic"
            }
          ],
          "version": 2
        }
        """)
        vc._updateStatusBarForTesting()

        let refreshedEvents = vc._diagnosticsLifecycleEventsForTesting(after: staleCursor)
        XCTAssertEqual(refreshedEvents.map(\.family), ["diagnostics.active"])
        let refreshedSnapshot = try XCTUnwrap(refreshedEvents.last?.snapshot)
        XCTAssertFalse(refreshedSnapshot.isStale)
        XCTAssertNil(refreshedSnapshot.staleReason)
        XCTAssertEqual(refreshedSnapshot.problems.map(\.message), ["updated diagnostic"])
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
        XCTAssertEqual(vc._problemsPanelUnifiedProblemsForTesting().map(\.message), [
            "first line problem",
            "second line warning",
        ])
        XCTAssertEqual(vc._problemsPanelUnifiedProblemsForTesting().map(\.source), [.active, .active])
        XCTAssertTrue(vc._problemsPanelIsVisibleForTesting())

        XCTAssertTrue(vc.showWorkspaceDiagnosticsResultJSONInActiveTab("""
        {
          "items": [
            {
              "uri": "\(fileURL.absoluteString)",
              "kind": "full",
              "resultId": "panel-workspace-1",
              "items": [
                {
                  "range": {
                    "start": { "line": 1, "character": 0 },
                    "end": { "line": 1, "character": 3 }
                  },
                  "severity": 1,
                  "source": "workspace-test",
                  "message": "workspace current file problem"
                }
              ]
            },
            {
              "uri": "\(tempDir.appendingPathComponent("other.txt").absoluteString)",
              "kind": "full",
              "resultId": "panel-workspace-other",
              "items": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 1 }
                  },
                  "severity": 2,
                  "source": "workspace-test",
                  "message": "workspace other file warning"
                }
              ]
            }
          ]
        }
        """))
        XCTAssertEqual(panel.title, "Problems (3)")
        XCTAssertEqual(vc._problemsPanelUnifiedProblemsForTesting().map(\.message), [
            "first line problem",
            "second line warning",
            "workspace current file problem",
        ])
        XCTAssertEqual(vc._problemsPanelUnifiedProblemsForTesting().map(\.source), [.active, .active, .workspace])

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
        XCTAssertEqual(panel.title, "Problems (2)")
        XCTAssertEqual(vc._problemsPanelUnifiedProblemsForTesting().map(\.message), [
            "third line problem",
            "workspace current file problem",
        ])
        XCTAssertEqual(vc._problemsPanelUnifiedProblemsForTesting().map(\.source), [.active, .workspace])
        XCTAssertEqual(vc._problemsPanelRowCountForTesting(), 2)
    }

    func testActiveProblemsUseCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("diagnostics-local.swift")
        let projectedURL = tempDir.appendingPathComponent("diagnostics-projected.swift")
        try "abc\ndef\n".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let tab = try XCTUnwrap(vc.tabs.first)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(tab.coreTabID)
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        let editorView = try XCTUnwrap(findSubview(of: EditorCoreSkiaView.self, in: vc.view))
        try editorView.editor.lspApplyDiagnosticsJSON("""
        {
          "uri": "\(projectedURL.standardizedFileURL.absoluteString)",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 3 }
              },
              "severity": 1,
              "source": "unit-test",
              "message": "active projected problem"
            }
          ],
          "version": 1
        }
        """)

        XCTAssertTrue(vc.showWorkspaceDiagnosticsResultJSONInActiveTab("""
        {
          "items": [
            {
              "uri": "\(projectedURL.standardizedFileURL.absoluteString)",
              "kind": "full",
              "resultId": "projected-diagnostics",
              "items": [
                {
                  "range": {
                    "start": { "line": 1, "character": 1 },
                    "end": { "line": 1, "character": 2 }
                  },
                  "severity": 2,
                  "source": "workspace-test",
                  "message": "projected workspace problem"
                }
              ]
            }
          ]
        }
        """))

        let lifecycleEntry = try XCTUnwrap(vc._currentDiagnosticsLifecycleEntryForTesting())
        XCTAssertEqual(lifecycleEntry.family, "diagnostics.active")
        XCTAssertEqual(lifecycleEntry.title, "diagnostics-projected.swift")
        guard case let .activeTab(tabID: lifecycleTabID, fileURL: lifecycleURL) = lifecycleEntry.snapshot.scope else {
            return XCTFail("Expected active-tab diagnostics scope")
        }
        XCTAssertEqual(lifecycleTabID, tab.id)
        XCTAssertEqual(lifecycleURL, projectedURL.standardizedFileURL)
        XCTAssertEqual(lifecycleEntry.snapshot.problems.map(\.message), [
            "active projected problem",
            "projected workspace problem",
        ])
        XCTAssertEqual(lifecycleEntry.snapshot.problems.map(\.source), [.active, .workspace])
        XCTAssertEqual(lifecycleEntry.snapshot.markerProjections, [
            AttoDiagnosticMarkerProjection(logicalLine: 0, charOffset: 0, severity: .error, source: .active),
            AttoDiagnosticMarkerProjection(logicalLine: 1, charOffset: 5, severity: .warning, source: .workspace),
        ])

        let activeProblem = try XCTUnwrap(lifecycleEntry.snapshot.problems.first { $0.source == .active })
        XCTAssertTrue(vc.displayTitle(for: activeProblem, in: tab).contains("diagnostics-projected.swift:1:1"))

        XCTAssertTrue(vc.showProblemsPanelInActiveTab())
        let panel = try XCTUnwrap(window.childWindows?.first {
            $0.identifier?.rawValue == AttoAccessibilityID.problemsPanel
        })
        XCTAssertEqual(panel.title, "Problems (2)")
        XCTAssertEqual(vc._problemsPanelUnifiedProblemsForTesting().map(\.message), [
            "active projected problem",
            "projected workspace problem",
        ])
        XCTAssertEqual(vc._problemsPanelUnifiedProblemsForTesting().map(\.source), [.active, .workspace])
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

    func testPrepareRenameDialogSeedUsesTypedResult() throws {
        let fallback = AttoLspRenameSupport.DialogSeed(initialName: "fallback", placeholder: "Fallback")
        let placeholder = try JSONDecoder().decode(EcuLspPrepareRenameResult.self, from: Data("""
        {
          "range": {
            "start": { "line": 0, "character": 4 },
            "end": { "line": 0, "character": 9 }
          },
          "placeholder": "serverName"
        }
        """.utf8))

        XCTAssertEqual(
            AttoLspRenameSupport.dialogSeed(
                documentText: "let alpha = beta\n",
                selectedText: "",
                caretOffset: 0,
                prepareRenameResult: placeholder,
                fallback: fallback
            ),
            AttoLspRenameSupport.DialogSeed(initialName: "serverName", placeholder: "serverName")
        )

        let rangeOnly = try JSONDecoder().decode(EcuLspPrepareRenameResult.self, from: Data("""
        {
          "start": { "line": 0, "character": 4 },
          "end": { "line": 0, "character": 9 }
        }
        """.utf8))
        XCTAssertEqual(
            AttoLspRenameSupport.dialogSeed(
                documentText: "let alpha = beta\n",
                selectedText: "",
                caretOffset: 0,
                prepareRenameResult: rangeOnly,
                fallback: fallback
            ),
            AttoLspRenameSupport.DialogSeed(initialName: "alpha", placeholder: "Fallback")
        )

        let defaultBehavior = try JSONDecoder().decode(
            EcuLspPrepareRenameResult.self,
            from: Data(#"{"defaultBehavior":true}"#.utf8)
        )
        XCTAssertEqual(
            AttoLspRenameSupport.dialogSeed(
                documentText: "let alpha = beta\n",
                selectedText: "",
                caretOffset: 0,
                prepareRenameResult: defaultBehavior,
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

    func testToggleLineCommentUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("script-local.txt")
        let projectedURL = tempDir.appendingPathComponent("script-projected.py")
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

    func testLanguageIndentationConfigUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("indent-local.txt")
        let projectedURL = tempDir.appendingPathComponent("indent-projected.js")
        try "{".write(to: fileURL, atomically: true, encoding: .utf8)

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

        vc.applyLanguageConfiguration(for: tab)

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

        var snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.workspaceRoots, [tempDir.standardizedFileURL.absoluteString])

        let alternateRoot = tempDir.appendingPathComponent("alternate", isDirectory: true)
        try FileManager.default.createDirectory(at: alternateRoot, withIntermediateDirectories: true)
        vc.setWorkspaceRootURL(alternateRoot)
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.workspaceRoots, [alternateRoot.standardizedFileURL.absoluteString])
        vc.setWorkspaceRootURL(tempDir)
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.workspaceRoots, [tempDir.standardizedFileURL.absoluteString])

        vc.openFile(url: firstURL, mode: .preview)
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.count, 1)
        XCTAssertEqual(snapshot.tabs[0].title, "first.txt")
        XCTAssertEqual(snapshot.tabs[0].documentURI, firstURL.standardizedFileURL.absoluteString)
        XCTAssertTrue(snapshot.tabs[0].isPreview)

        vc.openFile(url: secondURL, mode: .preview)
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.count, 1)
        XCTAssertEqual(snapshot.tabs[0].title, "second.txt")
        XCTAssertEqual(snapshot.tabs[0].documentURI, secondURL.standardizedFileURL.absoluteString)
        XCTAssertTrue(snapshot.tabs[0].isPreview)

        vc.openFile(url: secondURL, mode: .pinned)
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.count, 1)
        XCTAssertEqual(snapshot.tabs[0].title, "second.txt")
        XCTAssertEqual(snapshot.tabs[0].documentURI, secondURL.standardizedFileURL.absoluteString)
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

    func testWorkspaceRootChangeNotifiesOpenTabLspWorkspaceFolders() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first.txt")
        let secondURL = tempDir.appendingPathComponent("second.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        let firstCaptureURL = tempDir.appendingPathComponent("first-lsp-stdin.txt")
        let secondCaptureURL = tempDir.appendingPathComponent("second-lsp-stdin.txt")
        let firstScriptURL = tempDir.appendingPathComponent("first-fake-lsp.sh")
        let secondScriptURL = tempDir.appendingPathComponent("second-fake-lsp.sh")
        try writeFakeLspServerScript(captureURL: firstCaptureURL, scriptURL: firstScriptURL)
        try writeFakeLspServerScript(captureURL: secondCaptureURL, scriptURL: secondScriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        let firstTab = try XCTUnwrap(vc.activeTab)
        try firstTab.editCore.editor.lspEnable(
            command: firstScriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: firstURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        vc.openFile(url: secondURL, mode: .pinned)
        let secondTab = try XCTUnwrap(vc.activeTab)
        try secondTab.editCore.editor.lspEnable(
            command: secondScriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: secondURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer {
            firstTab.editCore.editor.lspDisable()
            secondTab.editCore.editor.lspDisable()
        }

        let alternateRoot = tempDir.appendingPathComponent("alternate", isDirectory: true)
        try FileManager.default.createDirectory(at: alternateRoot, withIntermediateDirectories: true)
        vc.setWorkspaceRootURL(alternateRoot)

        let firstCaptured = waitForCapturedLspInput(
            at: firstCaptureURL,
            containing: "workspace/didChangeWorkspaceFolders"
        )
        let secondCaptured = waitForCapturedLspInput(
            at: secondCaptureURL,
            containing: "workspace/didChangeWorkspaceFolders"
        )
        for captured in [firstCaptured, secondCaptured] {
            XCTAssertTrue(captured.contains(#""method":"workspace/didChangeWorkspaceFolders""#), captured)
            XCTAssertTrue(captured.contains(alternateRoot.standardizedFileURL.absoluteString), captured)
            XCTAssertTrue(captured.contains(tempDir.standardizedFileURL.absoluteString), captured)
        }
    }

    func testWorkspaceRootChangeAutoStartsConfiguredOpenTabLsp() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("auto_start.rs")
        try "fn main() {}".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("auto-start-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("auto-start-fake-lsp.sh")
        try writeFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc._setLspEnvironmentProviderForTesting {
            [
                "ATTO_EDITOR_DISABLE_LSP": "1",
                "ATTO_EDITOR_LSP_CMD": scriptURL.path,
            ]
        }
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        XCTAssertFalse(try tab.editCore.editor.lspIsEnabled())
        XCTAssertNil(tab.lspServerConfig)

        vc._setLspEnvironmentProviderForTesting {
            [
                "ATTO_EDITOR_LSP_CMD": scriptURL.path,
            ]
        }
        let alternateRoot = tempDir.appendingPathComponent("alternate", isDirectory: true)
        try FileManager.default.createDirectory(at: alternateRoot, withIntermediateDirectories: true)
        vc.setWorkspaceRootURL(alternateRoot)
        defer { tab.editCore.editor.lspDisable() }

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )
        XCTAssertTrue(try tab.editCore.editor.lspIsEnabled())
        XCTAssertEqual(tab.lspServerConfig?.command, scriptURL.path)
        XCTAssertEqual(tab.lspServerConfig?.languageId, "rust")
        XCTAssertTrue(captured.contains(fileURL.standardizedFileURL.absoluteString), captured)
        XCTAssertTrue(captured.contains(alternateRoot.standardizedFileURL.absoluteString), captured)
    }

    func testProjectLspLaunchConfigsSyncToCoreProjectStore() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let rustURL = tempDir.appendingPathComponent("main.rs")
        let swiftURL = tempDir.appendingPathComponent("App.swift")
        try "fn main() {}".write(to: rustURL, atomically: true, encoding: .utf8)
        try "print(\"hello\")".write(to: swiftURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc._setLspEnvironmentProviderForTesting { ["ATTO_EDITOR_DISABLE_LSP": "1"] }
        vc.openFile(url: rustURL, mode: .pinned)
        let rustTab = try XCTUnwrap(vc.activeTab)
        XCTAssertEqual(try vc._coreMultiDocumentSnapshotForTesting()?.tabs.first?.languageId, "rust")
        let rustConfig = AttoLspServerLaunchConfig(
            command: "/usr/bin/rust-analyzer",
            args: "--stdio --log-file",
            languageId: "rust"
        )
        rustTab.lspServerConfig = rustConfig
        vc.syncProjectLspServerConfigsToCore()

        var configsByKey = Dictionary(
            uniqueKeysWithValues: try vc._coreProjectLspServerConfigsForTesting().map { ($0.key, $0) }
        )
        let rustKey = "rust:/usr/bin/rust-analyzer:--stdio:--log-file"
        let rootURI = tempDir.standardizedFileURL.absoluteString
        let projectedRust = try XCTUnwrap(configsByKey[rustKey])
        XCTAssertEqual(projectedRust.command, "/usr/bin/rust-analyzer")
        XCTAssertEqual(projectedRust.args, ["--stdio", "--log-file"])
        XCTAssertEqual(projectedRust.languageId, "rust")
        XCTAssertEqual(projectedRust.workspaceRoots, [rootURI])
        XCTAssertTrue(projectedRust.autoStart)

        vc.openFile(url: swiftURL, mode: .pinned)
        let swiftTab = try XCTUnwrap(vc.activeTab)
        XCTAssertEqual(try vc._coreMultiDocumentSnapshotForTesting()?.tabs.last?.languageId, "swift")
        let swiftConfig = AttoLspServerLaunchConfig(
            command: "/usr/bin/sourcekit-lsp",
            args: nil,
            languageId: "swift"
        )
        swiftTab.lspServerConfig = swiftConfig
        swiftTab.suppressesAutomaticLspStart = true
        vc.syncProjectLspServerConfigsToCore()

        configsByKey = Dictionary(
            uniqueKeysWithValues: try vc._coreProjectLspServerConfigsForTesting().map { ($0.key, $0) }
        )
        let swiftKey = "swift:/usr/bin/sourcekit-lsp"
        XCTAssertEqual(Set(configsByKey.keys), [rustKey, swiftKey])
        XCTAssertFalse(try XCTUnwrap(configsByKey[swiftKey]).autoStart)

        vc.closeTab(id: rustTab.id)
        configsByKey = Dictionary(
            uniqueKeysWithValues: try vc._coreProjectLspServerConfigsForTesting().map { ($0.key, $0) }
        )
        XCTAssertEqual(Set(configsByKey.keys), [swiftKey])

        swiftTab.lspServerConfig = nil
        vc.syncProjectLspServerConfigsToCore()
        XCTAssertEqual(try vc._coreProjectLspServerConfigsForTesting(), [])
    }

    func testRestartLspServerRequiresSavedLaunchConfig() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("plain.txt")
        try "plain".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.restartLspServerInActiveTab())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP server restart: unavailable")
    }

    func testRestartLspServerRestartsActiveTabSession() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("restart.txt")
        try "restart".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("restart-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("restart-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        XCTAssertTrue(vc.restartLspServerInActiveTab())

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#,
            minimumOccurrences: 2
        )
        XCTAssertGreaterThanOrEqual(occurrenceCount(of: "--session--", in: captured), 2, captured)
        XCTAssertGreaterThanOrEqual(
            occurrenceCount(of: #""method":"textDocument/didOpen""#, in: captured),
            2,
            captured
        )
        XCTAssertTrue(captured.contains(fileURL.standardizedFileURL.absoluteString), captured)
        XCTAssertTrue(captured.contains(#""languageId":"plaintext""#), captured)
        XCTAssertEqual(tab.lspServerConfig, config)
        XCTAssertEqual(tab.syntaxLanguageId, "plaintext")
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP server restarted")
    }

    func testProjectLspProcessHealthAutoRestartsExitedConfiguredTab() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("auto_restart.txt")
        try "restart".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("auto-restart-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("auto-restart-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: scriptURL.path),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(
                pid: 321,
                state: .exited,
                exitCode: 9,
                stderrTail: "crash"
            ),
            workspaceFolders: []
        )))

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#,
            minimumOccurrences: 2
        )
        XCTAssertGreaterThanOrEqual(
            occurrenceCount(of: #""method":"textDocument/didOpen""#, in: captured),
            2,
            captured
        )
        XCTAssertTrue(captured.contains(fileURL.standardizedFileURL.absoluteString), captured)
        XCTAssertEqual(tab.lspServerConfig, config)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP server auto-restarted")
    }

    func testProjectLspAutoRestartCanBeDisabledByPreferences() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let suiteName = "atto_command_lsp_auto_restart_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AttoPreferences(defaults: defaults, env: [:])
        preferences.setLspAutoRestartEnabled(false)

        let fileURL = tempDir.appendingPathComponent("auto_restart_disabled.txt")
        try "restart".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("auto-restart-disabled-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("auto-restart-disabled-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir, preferences: preferences)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: scriptURL.path),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(
                pid: 321,
                state: .exited,
                exitCode: 9,
                stderrTail: "crash"
            ),
            workspaceFolders: []
        )))

        let captured = try String(contentsOf: captureURL, encoding: .utf8)
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 0)
        XCTAssertEqual(occurrenceCount(of: #""method":"textDocument/didOpen""#, in: captured), 1, captured)
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 1, captured)
    }

    func testProjectLspAutoRestartCanBeDisabledForServerByPreferences() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let suiteName = "atto_command_lsp_auto_restart_server_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AttoPreferences(defaults: defaults, env: [:])
        preferences.setLspAutoRestartDisabled(true, forServerName: "fake-lsp", serverCommand: nil)
        XCTAssertTrue(preferences.effectiveLspAutoRestartEnabled)

        let fileURL = tempDir.appendingPathComponent("auto_restart_server_disabled.txt")
        try "restart".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("auto-restart-server-disabled-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("auto-restart-server-disabled-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir, preferences: preferences)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: scriptURL.path),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(
                pid: 321,
                state: .exited,
                exitCode: 9,
                stderrTail: "crash"
            ),
            workspaceFolders: []
        )))

        let captured = try String(contentsOf: captureURL, encoding: .utf8)
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 0)
        XCTAssertEqual(occurrenceCount(of: #""method":"textDocument/didOpen""#, in: captured), 1, captured)
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 1, captured)
    }

    func testProjectLspAutoRestartUsesServerSpecificBackoffPolicy() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("auto_restart_server_policy.txt")
        try "restart".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("auto-restart-server-policy-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("auto-restart-server-policy-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let suiteName = "atto_command_lsp_auto_restart_server_policy_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AttoPreferences(defaults: defaults, env: [:])
        preferences.setLspAutoRestartMaxAttempts(0)
        preferences.setLspAutoRestartBaseDelaySeconds(30)
        preferences.setLspAutoRestartMaxAttempts(2, forServerName: "fake-lsp", serverCommand: nil)
        preferences.setLspAutoRestartBaseDelaySeconds(1, forServerName: "fake-lsp", serverCommand: nil)

        var now = Date(timeIntervalSince1970: 10_000)
        let vc = makeEditorArea(workspaceRootURL: tempDir, preferences: preferences)
        vc._setProjectLspAutoRestartNowProviderForTesting { now }
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        let failedStatus = EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: scriptURL.path),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(pid: 321, state: .exited, exitCode: 9, stderrTail: "crash"),
            workspaceFolders: []
        )

        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: failedStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 1)
        var captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#,
            minimumOccurrences: 2
        )
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 2, captured)

        now = Date(timeIntervalSince1970: 10_000.5)
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: failedStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 1)
        captured = try String(contentsOf: captureURL, encoding: .utf8)
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 2, captured)

        now = Date(timeIntervalSince1970: 10_001)
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: failedStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 2)
        captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#,
            minimumOccurrences: 3
        )
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 3, captured)

        now = Date(timeIntervalSince1970: 10_002)
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: failedStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 2)
        captured = try String(contentsOf: captureURL, encoding: .utf8)
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 3, captured)
    }

    func testProjectLspAutoRestartUsesBackoffAndResetsAfterHealthyStatus() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("auto_restart_backoff.txt")
        try "restart".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("auto-restart-backoff-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("auto-restart-backoff-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let suiteName = "atto_command_lsp_auto_restart_backoff_\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let preferences = AttoPreferences(defaults: defaults, env: [:])
        preferences.setLspAutoRestartMaxAttempts(2)
        preferences.setLspAutoRestartBaseDelaySeconds(2)

        var now = Date(timeIntervalSince1970: 10_000)
        let vc = makeEditorArea(workspaceRootURL: tempDir, preferences: preferences)
        vc._setProjectLspAutoRestartNowProviderForTesting { now }
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        let config = AttoLspServerLaunchConfig(
            command: scriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try tab.editCore.editor.lspEnable(
            command: config.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: config.languageId
        )
        tab.lspServerConfig = config
        defer { tab.editCore.editor.lspDisable() }

        _ = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        let failedStatus = EcuLspStatusSnapshot(
            availability: .failed,
            state: .failed,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: scriptURL.path),
            activity: nil,
            detail: "server exited",
            capabilities: nil,
            process: EcuLspProcessStatus(pid: 321, state: .exited, exitCode: 9, stderrTail: "crash"),
            workspaceFolders: []
        )
        let healthyStatus = EcuLspStatusSnapshot(
            availability: .enabled,
            state: .ready,
            server: EcuLspServerStatus(name: "fake-lsp", version: nil, command: scriptURL.path),
            activity: nil,
            detail: nil,
            capabilities: nil,
            process: EcuLspProcessStatus(pid: 322, state: .running),
            workspaceFolders: []
        )

        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: failedStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 1)
        var captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#,
            minimumOccurrences: 2
        )
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 2, captured)

        now = Date(timeIntervalSince1970: 10_001)
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: failedStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 1)
        captured = try String(contentsOf: captureURL, encoding: .utf8)
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 2, captured)

        now = Date(timeIntervalSince1970: 10_002)
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: failedStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 2)
        captured = waitForCapturedLspInput(
            at: captureURL,
            containing: #""method":"textDocument/didOpen""#,
            minimumOccurrences: 3
        )
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 3, captured)

        now = Date(timeIntervalSince1970: 10_006)
        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: failedStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 2)
        captured = try String(contentsOf: captureURL, encoding: .utf8)
        XCTAssertEqual(occurrenceCount(of: "--session--", in: captured), 3, captured)

        XCTAssertTrue(vc._recordProjectLspProcessHealthForTesting(status: healthyStatus))
        XCTAssertEqual(vc._projectLspAutoRestartAttemptsForTesting(tabId: coreTabID), 0)
    }

    func testRestartProjectLspServersRequiresConfiguredTabs() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("plain.txt")
        try "plain".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = vc.view
        vc.openFile(url: fileURL, mode: .pinned)

        XCTAssertFalse(vc.restartProjectLspServers())
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP server restart: unavailable")
    }

    func testRestartProjectLspServersRestartsConfiguredOpenTabs() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first.txt")
        let secondURL = tempDir.appendingPathComponent("second.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)

        let firstCaptureURL = tempDir.appendingPathComponent("first-project-lsp-stdin.txt")
        let secondCaptureURL = tempDir.appendingPathComponent("second-project-lsp-stdin.txt")
        let firstScriptURL = tempDir.appendingPathComponent("first-project-fake-lsp.sh")
        let secondScriptURL = tempDir.appendingPathComponent("second-project-fake-lsp.sh")
        try writeAppendingFakeLspServerScript(captureURL: firstCaptureURL, scriptURL: firstScriptURL)
        try writeAppendingFakeLspServerScript(captureURL: secondCaptureURL, scriptURL: secondScriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        let firstTab = try XCTUnwrap(vc.activeTab)
        let firstConfig = AttoLspServerLaunchConfig(
            command: firstScriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try firstTab.editCore.editor.lspEnable(
            command: firstConfig.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: firstURL.standardizedFileURL.absoluteString,
            languageId: firstConfig.languageId
        )
        firstTab.lspServerConfig = firstConfig

        vc.openFile(url: secondURL, mode: .pinned)
        let secondTab = try XCTUnwrap(vc.activeTab)
        let secondConfig = AttoLspServerLaunchConfig(
            command: secondScriptURL.path,
            args: nil,
            languageId: "plaintext"
        )
        try secondTab.editCore.editor.lspEnable(
            command: secondConfig.command,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: secondURL.standardizedFileURL.absoluteString,
            languageId: secondConfig.languageId
        )
        secondTab.lspServerConfig = secondConfig
        defer {
            firstTab.editCore.editor.lspDisable()
            secondTab.editCore.editor.lspDisable()
        }

        _ = waitForCapturedLspInput(
            at: firstCaptureURL,
            containing: #""method":"textDocument/didOpen""#
        )
        _ = waitForCapturedLspInput(
            at: secondCaptureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        XCTAssertTrue(vc.restartProjectLspServers())

        let firstCaptured = waitForCapturedLspInput(
            at: firstCaptureURL,
            containing: #""method":"textDocument/didOpen""#,
            minimumOccurrences: 2
        )
        let secondCaptured = waitForCapturedLspInput(
            at: secondCaptureURL,
            containing: #""method":"textDocument/didOpen""#,
            minimumOccurrences: 2
        )
        XCTAssertGreaterThanOrEqual(
            occurrenceCount(of: "--session--", in: firstCaptured),
            2,
            firstCaptured
        )
        XCTAssertGreaterThanOrEqual(
            occurrenceCount(of: "--session--", in: secondCaptured),
            2,
            secondCaptured
        )
        XCTAssertTrue(firstCaptured.contains(firstURL.standardizedFileURL.absoluteString), firstCaptured)
        XCTAssertTrue(secondCaptured.contains(secondURL.standardizedFileURL.absoluteString), secondCaptured)
        XCTAssertEqual(firstTab.lspServerConfig, firstConfig)
        XCTAssertEqual(secondTab.lspServerConfig, secondConfig)
        XCTAssertEqual(vc._transientStatusTextForTesting(), "LSP servers restarted: 2")
    }

    func testSaveAndCloseNotifyLspDocumentLifecycle() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("lifecycle.txt")
        try "initial".write(to: fileURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("lifecycle-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("lifecycle-fake-lsp.sh")
        try writeFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)
        let tab = try XCTUnwrap(vc.activeTab)
        try tab.editCore.editor.lspEnable(
            command: scriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: fileURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer { tab.editCore.editor.lspDisable() }

        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":" saved"}"#))
        vc.saveActiveTab()
        vc.closeActiveTab()

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: "textDocument/didClose"
        )
        XCTAssertTrue(captured.contains(#""method":"textDocument/didSave""#), captured)
        XCTAssertTrue(captured.contains(#""method":"textDocument/didClose""#), captured)
        XCTAssertTrue(captured.contains(fileURL.standardizedFileURL.absoluteString), captured)
        XCTAssertTrue(captured.contains(" savedinitial"), captured)
    }

    func testOpenSaveAndCloseNotifyExistingLspSessions() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first.txt")
        let secondURL = tempDir.appendingPathComponent("second.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second opened".write(to: secondURL, atomically: true, encoding: .utf8)
        let captureURL = tempDir.appendingPathComponent("open-lsp-stdin.txt")
        let scriptURL = tempDir.appendingPathComponent("open-fake-lsp.sh")
        try writeFakeLspServerScript(captureURL: captureURL, scriptURL: scriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        let firstTab = try XCTUnwrap(vc.activeTab)
        try firstTab.editCore.editor.lspEnable(
            command: scriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: firstURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )
        defer { firstTab.editCore.editor.lspDisable() }

        vc.openFile(url: secondURL, mode: .pinned)
        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":"changed "}"#))
        vc.saveActiveTab()
        vc.closeActiveTab()

        let captured = waitForCapturedLspInput(
            at: captureURL,
            containing: "textDocument/didClose"
        )
        XCTAssertTrue(captured.contains(#""method":"textDocument/didOpen""#), captured)
        XCTAssertTrue(captured.contains(#""method":"textDocument/didChange""#), captured)
        XCTAssertTrue(captured.contains(#""method":"textDocument/didSave""#), captured)
        XCTAssertTrue(captured.contains(#""method":"textDocument/didClose""#), captured)
        XCTAssertTrue(captured.contains(secondURL.standardizedFileURL.absoluteString), captured)
        XCTAssertTrue(captured.contains(#""languageId":"plaintext""#), captured)
        XCTAssertTrue(captured.contains("changed"), captured)
        XCTAssertTrue(captured.contains("second opened"), captured)
    }

    func testCloseAllTabsReleasesOwnedLspSessionsWithoutDuplicateDidClose() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-close.txt")
        let secondURL = tempDir.appendingPathComponent("second-close.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        let firstCaptureURL = tempDir.appendingPathComponent("first-close-lsp-stdin.txt")
        let secondCaptureURL = tempDir.appendingPathComponent("second-close-lsp-stdin.txt")
        let firstScriptURL = tempDir.appendingPathComponent("first-close-fake-lsp.sh")
        let secondScriptURL = tempDir.appendingPathComponent("second-close-fake-lsp.sh")
        try writeFakeLspServerScript(captureURL: firstCaptureURL, scriptURL: firstScriptURL)
        try writeFakeLspServerScript(captureURL: secondCaptureURL, scriptURL: secondScriptURL)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        let firstTab = try XCTUnwrap(vc.activeTab)
        try firstTab.editCore.editor.lspEnable(
            command: firstScriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: firstURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )

        vc.openFile(url: secondURL, mode: .pinned)
        let secondTab = try XCTUnwrap(vc.activeTab)
        try secondTab.editCore.editor.lspEnable(
            command: secondScriptURL.path,
            rootURI: tempDir.standardizedFileURL.absoluteString,
            documentURI: secondURL.standardizedFileURL.absoluteString,
            languageId: "plaintext"
        )

        _ = waitForCapturedLspInput(
            at: firstCaptureURL,
            containing: #""method":"textDocument/didOpen""#
        )
        _ = waitForCapturedLspInput(
            at: secondCaptureURL,
            containing: #""method":"textDocument/didOpen""#
        )

        XCTAssertEqual(vc.closeAllTabsForWindow(), 2)

        let firstCaptured = waitForCapturedLspInput(
            at: firstCaptureURL,
            containing: #""method":"textDocument/didClose""#
        )
        let secondCaptured = waitForCapturedLspInput(
            at: secondCaptureURL,
            containing: #""method":"textDocument/didClose""#
        )
        XCTAssertEqual(
            occurrenceCount(of: #""method":"textDocument/didClose""#, in: firstCaptured),
            1,
            firstCaptured
        )
        XCTAssertEqual(
            occurrenceCount(of: #""method":"textDocument/didClose""#, in: secondCaptured),
            1,
            secondCaptured
        )
        XCTAssertFalse(try firstTab.editCore.editor.lspIsEnabled())
        XCTAssertFalse(try secondTab.editCore.editor.lspIsEnabled())
        XCTAssertTrue(vc.tabs.isEmpty)
        let snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertTrue(snapshot.tabs.isEmpty)
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
        XCTAssertEqual(tabSnapshot.documentURI, fileURL.standardizedFileURL.absoluteString)
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

    func testFindInOpenTabsUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("opened-search-uri.txt")
        let projectedURL = tempDir.appendingPathComponent("projected-opened-search-uri.txt")
        try "alpha".write(to: fileURL, atomically: true, encoding: .utf8)
        try "projected".write(to: projectedURL, atomically: true, encoding: .utf8)

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

        XCTAssertTrue(vc.executeActiveEditorCommandJSON(#"{"kind":"edit","op":"insert_text","text":" needle"}"#))

        let results = vc.findInOpenTabs(query: "needle")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].url.standardizedFileURL, projectedURL.standardizedFileURL)
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

    func testCloseTabGroupCommandsUseCoreTabProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-close.txt")
        let secondURL = tempDir.appendingPathComponent("second-close.txt")
        let thirdURL = tempDir.appendingPathComponent("third-close.txt")
        let fourthURL = tempDir.appendingPathComponent("fourth-close.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)
        try "fourth".write(to: fourthURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.openFile(url: thirdURL, mode: .pinned)
        vc.openFile(url: fourthURL, mode: .pinned)

        let secondTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == secondURL.standardizedFileURL })
        let thirdTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == thirdURL.standardizedFileURL })
        let fourthTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == fourthURL.standardizedFileURL })
        XCTAssertEqual(vc.selectedTabID, fourthTab.id)

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        XCTAssertTrue(try coreDocuments.moveTab(fromIndex: 3, toIndex: 1))
        try coreDocuments.setActiveTab(try XCTUnwrap(secondTab.coreTabID))
        XCTAssertEqual(vc.activeTab?.id, secondTab.id)

        XCTAssertEqual(vc.closeTabsToRightOfActiveTab(), 1)
        XCTAssertFalse(vc.tabs.contains { $0.id == thirdTab.id })
        XCTAssertTrue(vc.tabs.contains { $0.id == fourthTab.id })
        XCTAssertEqual(vc.selectedTabID, secondTab.id)

        var snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.map(\.title), [
            "first-close.txt",
            "fourth-close.txt",
            "second-close.txt",
        ])
        XCTAssertEqual(vc.openFileItems().map { $0.url.lastPathComponent }, [
            "first-close.txt",
            "fourth-close.txt",
            "second-close.txt",
        ])

        XCTAssertEqual(vc.closeOtherTabsForActiveTab(), 2)
        snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(snapshot.tabs.map(\.title), ["second-close.txt"])
        XCTAssertEqual(snapshot.activeTabId, try XCTUnwrap(secondTab.coreTabID))
        XCTAssertEqual(vc.openFileItems().map { $0.url.lastPathComponent }, ["second-close.txt"])
    }

    func testCloseAllTabsUsesCoreTabProjectionOrder() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-close-all.txt")
        let secondURL = tempDir.appendingPathComponent("second-close-all.txt")
        let thirdURL = tempDir.appendingPathComponent("third-close-all.txt")
        let fourthURL = tempDir.appendingPathComponent("fourth-close-all.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)
        try "fourth".write(to: fourthURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.openFile(url: thirdURL, mode: .pinned)
        vc.openFile(url: fourthURL, mode: .pinned)

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        XCTAssertTrue(try coreDocuments.moveTab(fromIndex: 3, toIndex: 1))
        XCTAssertEqual(try coreDocuments.snapshot().tabs.map(\.title), [
            "first-close-all.txt",
            "fourth-close-all.txt",
            "second-close-all.txt",
            "third-close-all.txt",
        ])

        var closedNames: [String] = []
        vc.onDidCloseFile = { url in
            closedNames.append(url.lastPathComponent)
        }

        XCTAssertEqual(vc.closeAllTabsForWindow(), 4)
        XCTAssertEqual(closedNames, [
            "first-close-all.txt",
            "fourth-close-all.txt",
            "second-close-all.txt",
            "third-close-all.txt",
        ])
        XCTAssertTrue(vc.tabs.isEmpty)
        XCTAssertTrue(vc.openFileItems().isEmpty)

        let snapshot = try XCTUnwrap(vc._coreMultiDocumentSnapshotForTesting())
        XCTAssertTrue(snapshot.tabs.isEmpty)
        XCTAssertNil(snapshot.activeTabId)
    }

    func testCloseTabCallbackUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("close-local.txt")
        let projectedURL = tempDir.appendingPathComponent("close-projected.txt")
        try "close".write(to: fileURL, atomically: true, encoding: .utf8)

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

        var closedURLs: [URL] = []
        vc.onDidCloseFile = { closedURLs.append($0.standardizedFileURL) }
        vc.closeTab(id: tab.id)

        XCTAssertTrue(vc.tabs.isEmpty)
        XCTAssertEqual(closedURLs, [projectedURL.standardizedFileURL])
    }

    func testSessionSnapshotUsesCoreTabProjectionWhenAvailable() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-session.txt")
        let secondURL = tempDir.appendingPathComponent("second-session.txt")
        let thirdURL = tempDir.appendingPathComponent("third-session.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.openFile(url: thirdURL, mode: .pinned)

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        let thirdTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == thirdURL.standardizedFileURL })
        let thirdCoreTabID = try XCTUnwrap(thirdTab.coreTabID)
        XCTAssertEqual(vc.openFileItems().map { $0.url.lastPathComponent }, [
            "first-session.txt",
            "second-session.txt",
            "third-session.txt",
        ])

        XCTAssertTrue(try coreDocuments.moveTab(fromIndex: 2, toIndex: 0))
        try coreDocuments.setActiveTab(thirdCoreTabID)
        XCTAssertEqual(try coreDocuments.splitTab(thirdCoreTabID, viewportWidthCells: 120), 1)
        try coreDocuments.setActiveViewIndex(tabId: thirdCoreTabID, viewIndex: 1)

        let session = vc.makeSessionSnapshot()
        XCTAssertEqual(session.tabs.map { URL(fileURLWithPath: $0.filePath).lastPathComponent }, [
            "third-session.txt",
            "first-session.txt",
            "second-session.txt",
        ])
        XCTAssertEqual(session.selectedTabIndex, 0)
        XCTAssertEqual(session.tabs[0].paneCount, 2)
        XCTAssertEqual(session.tabs[0].activePaneIndex, 1)
        XCTAssertEqual(session.tabs[0].paneLayout?.axis, .horizontal)
        XCTAssertEqual(session.tabs[0].paneLayout?.flattenedPaneCount, 2)
        XCTAssertEqual(session.tabs[0].paneLayout?.clampedActivePaneIndex, 1)
    }

    func testOpenFileProjectionUsesCoreTabSnapshotWhenAvailable() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-opened.txt")
        let secondURL = tempDir.appendingPathComponent("second-opened.txt")
        let thirdURL = tempDir.appendingPathComponent("third-opened.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.openFile(url: thirdURL, mode: .pinned)

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        let secondTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == secondURL.standardizedFileURL })
        let secondCoreTabID = try XCTUnwrap(secondTab.coreTabID)
        XCTAssertTrue(try coreDocuments.moveTab(fromIndex: 2, toIndex: 0))
        try coreDocuments.setActiveTab(secondCoreTabID)
        try coreDocuments.replaceTabText(tabId: secondCoreTabID, text: "second dirty", markSaved: false)

        let items = vc.openFileItems()
        XCTAssertEqual(items.map { $0.url.lastPathComponent }, [
            "third-opened.txt",
            "first-opened.txt",
            "second-opened.txt",
        ])
        let dirtyItem = try XCTUnwrap(items.first { $0.url.standardizedFileURL == secondURL.standardizedFileURL })
        XCTAssertTrue(dirtyItem.isDirty)
        XCTAssertEqual(dirtyItem.title, "● second-opened.txt")

        var callbackItems: [AttoEditorAreaViewController.OpenFileItem] = []
        var callbackSelectedID: UUID?
        vc.onOpenFilesChanged = { items, selectedID in
            callbackItems = items
            callbackSelectedID = selectedID
        }
        vc.refreshTabBar()

        XCTAssertEqual(callbackItems.map { $0.url.lastPathComponent }, [
            "third-opened.txt",
            "first-opened.txt",
            "second-opened.txt",
        ])
        XCTAssertEqual(callbackSelectedID, secondTab.id)
    }

    func testCoreTabTitleUpdateUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("title-local-tab.txt")
        let projectedURL = tempDir.appendingPathComponent("title-projected-tab.txt")
        try "title".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let tab = try XCTUnwrap(vc.tabs.first)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        let coreTabID = try XCTUnwrap(tab.coreTabID)
        try coreDocuments.setTabDocumentURI(projectedURL.standardizedFileURL.absoluteString, tabId: coreTabID)
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        vc.updateCoreTabTitle(tab)

        let snapshotTab = try XCTUnwrap(try coreDocuments.snapshot().tabs.first { $0.id == coreTabID })
        XCTAssertEqual(snapshotTab.title, "title-projected-tab.txt")
    }

    func testSelectAndOpenFileUseCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-uri.txt")
        let secondURL = tempDir.appendingPathComponent("second-uri.txt")
        let renamedURL = tempDir.appendingPathComponent("renamed-uri.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "renamed".write(to: renamedURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)

        let firstTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == firstURL.standardizedFileURL })
        let secondTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == secondURL.standardizedFileURL })
        XCTAssertEqual(vc.selectedTabID, secondTab.id)

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            renamedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(firstTab.coreTabID)
        )
        XCTAssertEqual(firstTab.fileURL.standardizedFileURL, firstURL.standardizedFileURL)
        XCTAssertTrue(vc.openFileItems().contains { $0.url.standardizedFileURL == renamedURL.standardizedFileURL })

        vc.selectFile(url: renamedURL)
        XCTAssertEqual(vc.selectedTabID, firstTab.id)
        XCTAssertTrue(vc.contentHostView.subviews.contains { $0 === firstTab.editCore })

        vc.selectFile(url: secondURL)
        XCTAssertEqual(vc.selectedTabID, secondTab.id)

        XCTAssertTrue(vc.openFile(url: renamedURL, mode: .pinned))
        XCTAssertEqual(vc.tabs.count, 2)
        XCTAssertEqual(vc.selectedTabID, firstTab.id)
        XCTAssertEqual(try coreDocuments.snapshot().tabs.count, 2)
    }

    func testOpenFileLocationUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-location-uri.txt")
        let secondURL = tempDir.appendingPathComponent("second-location-uri.txt")
        let renamedURL = tempDir.appendingPathComponent("renamed-location-uri.txt")
        try "aa\nbb\ncc\n".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "renamed".write(to: renamedURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)

        let firstTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == firstURL.standardizedFileURL })
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            renamedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(firstTab.coreTabID)
        )

        XCTAssertTrue(vc.openFile(
            url: renamedURL,
            mode: .pinned,
            location: .init(line1: 2, column1: 2)
        ))
        XCTAssertEqual(vc.tabs.count, 2)
        XCTAssertEqual(vc.selectedTabID, firstTab.id)

        let offsets = try firstTab.editCore.editor.selectionOffsets()
        let position = try firstTab.editCore.editor.charOffsetToLogicalPosition(offset: offsets.end)
        XCTAssertEqual(position.line, 1)
        XCTAssertEqual(position.column, 1)
    }

    func testActiveTabProjectionUsesCoreActiveTabWhenAvailable() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-active.txt")
        let secondURL = tempDir.appendingPathComponent("second-active.txt")
        let thirdURL = tempDir.appendingPathComponent("third-active.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.openFile(url: thirdURL, mode: .pinned)
        XCTAssertEqual(vc.selectedTabID, vc.tabs.first { $0.fileURL.standardizedFileURL == thirdURL.standardizedFileURL }?.id)

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        let secondTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == secondURL.standardizedFileURL })
        let secondCoreTabID = try XCTUnwrap(secondTab.coreTabID)
        try coreDocuments.setActiveTab(secondCoreTabID)

        XCTAssertEqual(vc.activeTab?.id, secondTab.id)
        let keymapContext = vc.keymapContextForActiveState()
        XCTAssertEqual(keymapContext.values["file_name"], .string("second-active.txt"))
        XCTAssertEqual(keymapContext.values["file_extension"], .string("txt"))

        vc.updateWindowTitle()
        XCTAssertEqual(window.title, "AttoEditor — second-active.txt")
    }

    func testWindowTitleUsesCoreDocumentURIProjection() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("title-local.txt")
        let projectedURL = tempDir.appendingPathComponent("title-projected.txt")
        try "title".write(to: fileURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        let window = attachToWindow(vc)
        vc.openFile(url: fileURL, mode: .pinned)

        let tab = try XCTUnwrap(vc.tabs.first)
        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setTabDocumentURI(
            projectedURL.standardizedFileURL.absoluteString,
            tabId: try XCTUnwrap(tab.coreTabID)
        )
        XCTAssertEqual(tab.fileURL.standardizedFileURL, fileURL.standardizedFileURL)

        vc.updateWindowTitle()
        XCTAssertEqual(window.title, "AttoEditor — title-projected.txt")
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

    func testRefreshTabBarProjectsAppKitContentToCoreActiveTab() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let firstURL = tempDir.appendingPathComponent("first-content.txt")
        let secondURL = tempDir.appendingPathComponent("second-content.txt")
        let thirdURL = tempDir.appendingPathComponent("third-content.txt")
        try "first".write(to: firstURL, atomically: true, encoding: .utf8)
        try "second".write(to: secondURL, atomically: true, encoding: .utf8)
        try "third".write(to: thirdURL, atomically: true, encoding: .utf8)

        let vc = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(vc)
        vc.openFile(url: firstURL, mode: .pinned)
        vc.openFile(url: secondURL, mode: .pinned)
        vc.openFile(url: thirdURL, mode: .pinned)

        let secondTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == secondURL.standardizedFileURL })
        let thirdTab = try XCTUnwrap(vc.tabs.first { $0.fileURL.standardizedFileURL == thirdURL.standardizedFileURL })
        XCTAssertEqual(vc.selectedTabID, thirdTab.id)
        XCTAssertTrue(vc.contentHostView.subviews.contains { $0 === thirdTab.editCore })

        let coreDocuments = try XCTUnwrap(vc.coreDocuments)
        try coreDocuments.setActiveTab(try XCTUnwrap(secondTab.coreTabID))
        XCTAssertEqual(vc.activeTab?.id, secondTab.id)
        XCTAssertTrue(vc.contentHostView.subviews.contains { $0 === thirdTab.editCore })

        vc.refreshTabBar()

        XCTAssertEqual(vc.selectedTabID, secondTab.id)
        XCTAssertTrue(vc.contentHostView.subviews.contains { $0 === secondTab.editCore })
        XCTAssertFalse(vc.contentHostView.subviews.contains { $0 === thirdTab.editCore })
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
        XCTAssertEqual(restoredSnapshot.tabs[0].paneLayout?.axis, .horizontal)
        XCTAssertEqual(restoredSnapshot.tabs[0].paneLayout?.flattenedPaneCount, 2)
        XCTAssertEqual(restoredSnapshot.tabs[0].paneLayout?.clampedActivePaneIndex, 0)

        let coreSnapshot = try XCTUnwrap(restored._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(coreSnapshot.tabs.count, 1)
        XCTAssertEqual(coreSnapshot.tabs[0].viewCount, 2)
        XCTAssertEqual(coreSnapshot.tabs[0].activeViewIndex, 0)
    }

    func testSessionRestorePrefersPaneLayoutSnapshotOverLegacyPaneCount() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("AttoEditorCommandTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let fileURL = tempDir.appendingPathComponent("session-layout.txt")
        try "abc".write(to: fileURL, atomically: true, encoding: .utf8)

        let tabSnapshot = AttoTabSnapshot(
            filePath: fileURL.path,
            isPreview: false,
            showsMinimap: true,
            paneCount: 1,
            activePaneIndex: 0,
            paneLayout: AttoPaneLayoutSnapshot.horizontalSplit(paneCount: 3, activePaneIndex: 2)
        )

        let restored = makeEditorArea(workspaceRootURL: tempDir)
        _ = attachToWindow(restored)
        restored.restoreSession(tabs: [tabSnapshot], selectedTabIndex: 0)
        restored.view.layoutSubtreeIfNeeded()

        let editorViews = findSubviews(of: EditorCoreSkiaView.self, in: restored.view)
        XCTAssertEqual(editorViews.count, 3)

        let restoredSnapshot = restored.makeSessionSnapshot()
        XCTAssertEqual(restoredSnapshot.tabs.count, 1)
        XCTAssertEqual(restoredSnapshot.tabs[0].paneCount, 3)
        XCTAssertEqual(restoredSnapshot.tabs[0].activePaneIndex, 2)
        XCTAssertEqual(restoredSnapshot.tabs[0].paneLayout?.flattenedPaneCount, 3)
        XCTAssertEqual(restoredSnapshot.tabs[0].paneLayout?.clampedActivePaneIndex, 2)

        let coreSnapshot = try XCTUnwrap(restored._coreMultiDocumentSnapshotForTesting())
        XCTAssertEqual(coreSnapshot.tabs.count, 1)
        XCTAssertEqual(coreSnapshot.tabs[0].viewCount, 3)
        XCTAssertEqual(coreSnapshot.tabs[0].activeViewIndex, 2)
    }

    private func makeEditorArea(
        workspaceRootURL: URL,
        preferences: AttoPreferences = .shared,
        projectLspProcessHealthLogStore: AttoProjectLspProcessHealthLogStore = AttoProjectLspProcessHealthLogStore()
    ) -> AttoEditorAreaViewController {
        AttoEditorAreaViewController(
            library: EditorCoreUIFFILibrary(),
            theme: EditorCoreSkiaTheme.defaultLight(),
            workspaceRootURL: workspaceRootURL,
            preferences: preferences,
            projectLspProcessHealthLogStore: projectLspProcessHealthLogStore
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

    private func waitForCapturedLspInput(at url: URL, containing needle: String) -> String {
        for _ in 0..<100 {
            let captured = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if captured.contains(needle) {
                return captured
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func waitForCapturedLspInput(
        at url: URL,
        containing needle: String,
        minimumOccurrences: Int
    ) -> String {
        for _ in 0..<100 {
            let captured = (try? String(contentsOf: url, encoding: .utf8)) ?? ""
            if occurrenceCount(of: needle, in: captured) >= minimumOccurrences {
                return captured
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return (try? String(contentsOf: url, encoding: .utf8)) ?? ""
    }

    private func occurrenceCount(of needle: String, in haystack: String) -> Int {
        guard needle.isEmpty == false else { return 0 }
        return haystack.components(separatedBy: needle).count - 1
    }

    private func writeFakeLspServerScript(captureURL: URL, scriptURL: URL) throws {
        let initBody = #"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}"#
        let capturePath = captureURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        #!/bin/sh
        body='\(initBody)'
        printf 'Content-Length: %s\\r\\n\\r\\n%s' "${#body}" "$body"
        cat > '\(capturePath)'
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
    }

    private func writeAppendingFakeLspServerScript(captureURL: URL, scriptURL: URL) throws {
        let initBody = #"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}"#
        let capturePath = captureURL.path.replacingOccurrences(of: "'", with: "'\\''")
        let script = """
        #!/bin/sh
        body='\(initBody)'
        printf 'Content-Length: %s\\r\\n\\r\\n%s' "${#body}" "$body"
        printf '\\n--session--\\n' >> '\(capturePath)'
        cat >> '\(capturePath)'
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
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
