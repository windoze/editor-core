import CEditorCoreUIFFI
import Foundation
import Metal

extension EditorUI {
    public func setRenderMetrics(fontSize: Float, lineHeightPx: Float, cellWidthPx: Float, paddingXPx: Float, paddingYPx: Float) throws {
        let status = editor_core_ui_ffi_editor_ui_set_render_metrics(handle, fontSize, lineHeightPx, cellWidthPx, paddingXPx, paddingYPx)
        try library.ensureStatus(status, context: "editor_ui_set_render_metrics")
    }

    public func setTextVerticalAlign(_ align: TextVerticalAlign) throws {
        let status = editor_core_ui_ffi_editor_ui_set_text_vertical_align(handle, align.rawValue)
        try library.ensureStatus(status, context: "editor_ui_set_text_vertical_align")
    }

    /// Configure a font fallback list for rendering (comma-separated family names).
    ///
    /// Example: `"Menlo, PingFang SC, Apple Color Emoji"`.
    ///
    /// Notes:
    /// - This affects glyph rasterization only; layout remains monospace-grid based.
    public func setFontFamiliesCSV(_ families: String) throws {
        let status = families.withCString { cstr in
            editor_core_ui_ffi_editor_ui_set_font_families_csv(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_set_font_families_csv")
    }

    /// Enable/disable font ligatures (e.g. Fira Code `->`, `!=`) in the Skia renderer.
    ///
    /// Notes:
    /// - This is visual-only; the editor model and hit-testing remain monospace-grid based.
    public func setFontLigaturesEnabled(_ enabled: Bool) throws {
        let status = editor_core_ui_ffi_editor_ui_set_font_ligatures_enabled(handle, enabled ? 1 : 0)
        try library.ensureStatus(status, context: "editor_ui_set_font_ligatures_enabled")
    }

    /// Configure per-font-family OpenType feature strings for the Skia renderer.
    ///
    /// Keys are font family names; values use HarfBuzz feature syntax (e.g. `"-calt +liga +ss01"`).
    ///
    /// Notes:
    /// - This replaces the whole map; an empty value means "no features for this font" (not deletion).
    /// - Only consulted when ligatures are enabled (see `setFontLigaturesEnabled`).
    public func setFontFeatureMap(_ entries: [String: String]) throws {
        let serialized = entries
            .map { "\($0.key)\t\($0.value)" }
            .sorted()
            .joined(separator: "\n")
        let status = serialized.withCString { cstr in
            editor_core_ui_ffi_editor_ui_set_font_feature_map(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_set_font_feature_map")
    }

    /// Set caret width in pixels (minimum 1px when visible).
    ///
    /// Notes:
    /// - This is an absolute pixel width; if you want a "point" width, multiply by the view's backing scale.
    public func setCaretWidthPx(_ widthPx: Float) throws {
        let status = editor_core_ui_ffi_editor_ui_set_caret_width_px(handle, widthPx)
        try library.ensureStatus(status, context: "editor_ui_set_caret_width_px")
    }

    /// Show/hide carets during rendering.
    ///
    /// Useful for UI-side caret blinking and focus handling.
    public func setCaretVisible(_ visible: Bool) throws {
        let status = editor_core_ui_ffi_editor_ui_set_caret_visible(handle, visible ? 1 : 0)
        try library.ensureStatus(status, context: "editor_ui_set_caret_visible")
    }

    public func setIndentGuidesEnabled(_ enabled: Bool) throws {
        let status = editor_core_ui_ffi_editor_ui_set_indent_guides_enabled(handle, enabled ? 1 : 0)
        try library.ensureStatus(status, context: "editor_ui_set_indent_guides_enabled")
    }

    public func setWhitespaceRenderMode(_ mode: WhitespaceRenderMode) throws {
        let status = editor_core_ui_ffi_editor_ui_set_whitespace_render_mode(handle, mode.rawValue)
        try library.ensureStatus(status, context: "editor_ui_set_whitespace_render_mode")
    }

    public func setFoldMarkerStyle(_ style: FoldMarkerStyle) throws {
        let status = editor_core_ui_ffi_editor_ui_set_fold_marker_style(handle, style.rawValue)
        try library.ensureStatus(status, context: "editor_ui_set_fold_marker_style")
    }

    public func setTabWidth(_ widthCells: UInt32) throws {
        let status = editor_core_ui_ffi_editor_ui_set_tab_width(handle, widthCells)
        try library.ensureStatus(status, context: "editor_ui_set_tab_width")
    }

    public func setTabKeyBehavior(_ behavior: TabKeyBehavior) throws {
        let status = editor_core_ui_ffi_editor_ui_set_tab_key_behavior(handle, behavior.rawValue)
        try library.ensureStatus(status, context: "editor_ui_set_tab_key_behavior")
    }

    /// Enable/disable auto-pairs behavior for typed characters.
    ///
    /// When enabled, single-character typing is routed through auto-pairs rules (auto-close,
    /// wrap selection, skip-over closing, delete-pair).
    public func setAutoPairsEnabled(_ enabled: Bool) throws {
        let status = editor_core_ui_ffi_editor_ui_set_auto_pairs_enabled(handle, enabled ? 1 : 0)
        try library.ensureStatus(status, context: "editor_ui_set_auto_pairs_enabled")
    }

    /// Enable/disable bracket-match highlighting.
    ///
    /// When enabled, the UI wrapper updates `StyleLayerId::BRACKET_MATCHES` after cursor moves and
    /// edits so the renderer can highlight matching delimiters.
    public func setBracketMatchHighlightsEnabled(_ enabled: Bool) throws {
        let status = editor_core_ui_ffi_editor_ui_set_bracket_match_highlights_enabled(handle, enabled ? 1 : 0)
        try library.ensureStatus(status, context: "editor_ui_set_bracket_match_highlights_enabled")
    }

    /// Enable/disable automatic LSP on-type formatting after trigger-character typing.
    ///
    /// Explicit `lspFormatOnType(...)` calls remain available when this implicit typing path is
    /// disabled.
    public func setLspOnTypeFormattingEnabled(_ enabled: Bool) throws {
        let status = editor_core_ui_ffi_editor_ui_set_lsp_on_type_formatting_enabled(handle, enabled ? 1 : 0)
        try library.ensureStatus(status, context: "editor_ui_set_lsp_on_type_formatting_enabled")
    }

    /// Configure the ASCII word-boundary character set for editor-friendly "word" operations.
    ///
    /// This is similar in spirit to VSCode's `wordSeparators`.
    ///
    /// Notes:
    /// - Only ASCII characters are configurable here; non-ASCII characters are always treated as boundaries.
    /// - ASCII whitespace is always treated as a boundary.
    public func setWordBoundaryAsciiBoundaryChars(_ boundaryChars: String) throws {
        let status = boundaryChars.withCString { cstr in
            editor_core_ui_ffi_editor_ui_set_word_boundary_ascii_boundary_chars(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_set_word_boundary_ascii_boundary_chars")
    }

    /// Reset word-boundary configuration to the default (ASCII identifier-like words).
    public func resetWordBoundaryDefaults() throws {
        let status = editor_core_ui_ffi_editor_ui_reset_word_boundary_defaults(handle)
        try library.ensureStatus(status, context: "editor_ui_reset_word_boundary_defaults")
    }

    public func setGutterWidthCells(_ widthCells: UInt32) throws {
        let status = editor_core_ui_ffi_editor_ui_set_gutter_width_cells(handle, widthCells)
        try library.ensureStatus(status, context: "editor_ui_set_gutter_width_cells")
    }

    public func logicalLineCount() throws -> UInt32 {
        var out: UInt32 = 0
        let status = editor_core_ui_ffi_editor_ui_get_logical_line_count(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_get_logical_line_count")
        return out
    }

    public func gutterWidthCells() throws -> UInt32 {
        var out: UInt32 = 0
        let status = editor_core_ui_ffi_editor_ui_get_gutter_width_cells(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_get_gutter_width_cells")
        return out
    }

    public func setViewportPx(widthPx: UInt32, heightPx: UInt32, scale: Float) throws {
        let status = editor_core_ui_ffi_editor_ui_set_viewport_px(handle, widthPx, heightPx, scale)
        try library.ensureStatus(status, context: "editor_ui_set_viewport_px")
    }

    public func scrollByRows(_ deltaRows: Int32) {
        editor_core_ui_ffi_editor_ui_scroll_by_rows(handle, deltaRows)
    }

    /// Smooth-scroll by a pixel delta (positive = scroll down, reveal later lines).
    public func scrollByPixels(_ deltaYPx: Float) {
        editor_core_ui_ffi_editor_ui_scroll_by_pixels(handle, deltaYPx)
    }

    public func viewportState() throws -> EcuViewportState {
        var ffi = CEditorCoreUIFFI.EcuViewportState(
            width_cells: 0,
            height_rows: 0,
            has_height: 0,
            scroll_top: 0,
            sub_row_offset: 0,
            overscan_rows: 0,
            visible_start: 0,
            visible_end: 0,
            prefetch_start: 0,
            prefetch_end: 0,
            total_visual_lines: 0
        )
        let status = withUnsafeMutablePointer(to: &ffi) { ptr in
            editor_core_ui_ffi_editor_ui_get_viewport_state(handle, ptr)
        }
        try library.ensureStatus(status, context: "editor_ui_get_viewport_state")
        return EcuViewportState(ffi: ffi)
    }

    /// Set the smooth-scroll position directly.
    ///
    /// - Parameters:
    ///   - topVisualRow: Top visual row anchor (after wrapping/folding).
    ///   - subRowOffset: Normalized 0..=65535 fraction within the row.
    public func setSmoothScrollState(topVisualRow: UInt32, subRowOffset: UInt32) {
        editor_core_ui_ffi_editor_ui_set_smooth_scroll_state(handle, topVisualRow, subRowOffset)
    }

    /// Adjust scroll position to ensure the primary caret is visible (best-effort).
    public func revealPrimaryCaret() throws {
        let status = editor_core_ui_ffi_editor_ui_reveal_primary_caret(handle)
        try library.ensureStatus(status, context: "editor_ui_reveal_primary_caret")
    }

    public func insertText(_ text: String) throws {
        let status = text.withCString { cstr in
            editor_core_ui_ffi_editor_ui_insert_text(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_insert_text")
    }

    /// Execute one editor command encoded as JSON and return command-result JSON.
    ///
    /// The schema matches the headless `EditorState.executeJSON(_:)` command plane, with UI-layer
    /// additions for snippets, auto-pairs config, and bracket-match highlight commands.
    public func executeCommandJSON(_ commandJSON: String) throws -> String {
        guard let ptr = commandJSON.withCString({ cstr in
            editor_core_ui_ffi_editor_ui_execute_command_json(handle, cstr)
        }) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_execute_command_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    /// Execute one editor command encoded as JSON and return a stable `{ ok, value, error, version }` envelope.
    ///
    /// This is the preferred migration path for hosts that want structured command failures without
    /// depending on the legacy null-pointer + `last_error_message` convention.
    public func executeCommandEnvelopeJSON(_ commandJSON: String) throws -> String {
        guard let ptr = commandJSON.withCString({ cstr in
            editor_core_ui_ffi_editor_ui_execute_command_envelope_json(handle, cstr)
        }) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_execute_command_envelope_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func executeCommandEnvelope(_ commandJSON: String) throws -> EcuJSONCommandEnvelope {
        try Self.decodeSnapshot(
            EcuJSONCommandEnvelope.self,
            from: executeCommandEnvelopeJSON(commandJSON),
            context: "editor_ui_execute_command_envelope"
        )
    }

    public func diagnosticsJSON() throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_diagnostics_json(handle) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_diagnostics_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func diagnosticsSnapshot() throws -> EcuDiagnosticsSnapshot {
        try Self.decodeSnapshot(
            EcuDiagnosticsSnapshot.self,
            from: diagnosticsJSON(),
            context: "editor_ui_diagnostics_snapshot"
        )
    }

    public func decorationsJSON() throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_decorations_json(handle) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_decorations_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func decorationsSnapshot() throws -> EcuDecorationsSnapshot {
        try Self.decodeSnapshot(
            EcuDecorationsSnapshot.self,
            from: decorationsJSON(),
            context: "editor_ui_decorations_snapshot"
        )
    }

    public func documentSymbolsJSON() throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_document_symbols_json(handle) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_document_symbols_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func documentSymbolsSnapshot() throws -> EcuDocumentSymbolsSnapshot {
        try Self.decodeSnapshot(
            EcuDocumentSymbolsSnapshot.self,
            from: documentSymbolsJSON(),
            context: "editor_ui_document_symbols_snapshot"
        )
    }

    public func foldingRegionsJSON() throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_folding_regions_json(handle) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_folding_regions_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func foldingRegionsSnapshot() throws -> EcuFoldingRegionsSnapshot {
        try Self.decodeSnapshot(
            EcuFoldingRegionsSnapshot.self,
            from: foldingRegionsJSON(),
            context: "editor_ui_folding_regions_snapshot"
        )
    }

    public func styleIntervalsJSON(start: UInt32, end: UInt32) throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_style_intervals_json(handle, start, end) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .internal,
                context: "editor_ui_style_intervals_json",
                message: library.lastErrorMessageString()
            )
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func styleIntervalsSnapshot(start: UInt32, end: UInt32) throws -> EcuStyleIntervalsSnapshot {
        try Self.decodeSnapshot(
            EcuStyleIntervalsSnapshot.self,
            from: styleIntervalsJSON(start: start, end: end),
            context: "editor_ui_style_intervals_snapshot"
        )
    }

    @discardableResult
    func executeCommandObject(_ object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object, options: [])
        guard let json = String(data: data, encoding: .utf8) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .invalidArgument,
                context: "editor_ui_encode_command_json",
                message: "failed to encode command JSON as UTF-8"
            )
        }
        return try executeCommandJSON(json)
    }

    @discardableResult
    func executeEditorCommand(kind: String, op: String, fields: [String: Any] = [:]) throws -> String {
        var object: [String: Any] = ["kind": kind, "op": op]
        for (key, value) in fields {
            object[key] = value
        }
        return try executeCommandObject(object)
    }

    static func decodeSnapshot<T: Decodable>(_ type: T.Type, from json: String, context: String) throws -> T {
        guard let data = json.data(using: .utf8) else {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .invalidArgument,
                context: context,
                message: "snapshot JSON is not valid UTF-8"
            )
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw EditorCoreUIFFIError.ffiStatus(
                code: .invalidArgument,
                context: context,
                message: String(describing: error)
            )
        }
    }

    static func jsonObject(for options: EcuSearchOptions) -> [String: Any] {
        [
            "case_sensitive": options.caseSensitive,
            "whole_word": options.wholeWord,
            "regex": options.regex,
        ]
    }

    @discardableResult
    public func replace(start: UInt32, length: UInt32, text: String) throws -> String {
        try executeEditorCommand(
            kind: "edit",
            op: "replace",
            fields: ["start": Int(start), "length": Int(length), "text": text]
        )
    }

    @discardableResult
    public func replaceCoalescingUndo(start: UInt32, length: UInt32, text: String) throws -> String {
        try executeEditorCommand(
            kind: "edit",
            op: "replace_coalescing_undo",
            fields: ["start": Int(start), "length": Int(length), "text": text]
        )
    }

    @discardableResult
    public func replaceCoalescingUndoWithSelection(
        start: UInt32,
        length: UInt32,
        text: String,
        selectionStart: UInt32,
        selectionEnd: UInt32
    ) throws -> String {
        try executeEditorCommand(
            kind: "edit",
            op: "replace_coalescing_undo_with_selection",
            fields: [
                "start": Int(start),
                "length": Int(length),
                "text": text,
                "selection_start": Int(selectionStart),
                "selection_end": Int(selectionEnd),
            ]
        )
    }

    @discardableResult
    public func typeChar(_ ch: String) throws -> String {
        try executeEditorCommand(kind: "edit", op: "type_char", fields: ["ch": ch])
    }

    @discardableResult
    public func insertNewline(autoIndent: Bool = false) throws -> String {
        try executeEditorCommand(kind: "edit", op: "insert_newline", fields: ["auto_indent": autoIndent])
    }

    @discardableResult
    public func indent() throws -> String {
        try executeEditorCommand(kind: "edit", op: "indent")
    }

    @discardableResult
    public func outdent() throws -> String {
        try executeEditorCommand(kind: "edit", op: "outdent")
    }

    @discardableResult
    public func duplicateLines() throws -> String {
        try executeEditorCommand(kind: "edit", op: "duplicate_lines")
    }

    @discardableResult
    public func deleteLines() throws -> String {
        try executeEditorCommand(kind: "edit", op: "delete_lines")
    }

    @discardableResult
    public func moveLinesUp() throws -> String {
        try executeEditorCommand(kind: "edit", op: "move_lines_up")
    }

    @discardableResult
    public func moveLinesDown() throws -> String {
        try executeEditorCommand(kind: "edit", op: "move_lines_down")
    }

    @discardableResult
    public func joinLines() throws -> String {
        try executeEditorCommand(kind: "edit", op: "join_lines")
    }

    @discardableResult
    public func splitLine() throws -> String {
        try executeEditorCommand(kind: "edit", op: "split_line")
    }

    @discardableResult
    public func toggleComment(_ config: EcuCommentConfig) throws -> String {
        try executeEditorCommand(kind: "edit", op: "toggle_comment", fields: ["config": config.jsonObject])
    }

    @discardableResult
    public func applyTextEdits(_ edits: [EcuTextEdit]) throws -> String {
        try executeEditorCommand(
            kind: "edit",
            op: "apply_text_edits",
            fields: ["edits": edits.map(\.jsonObject)]
        )
    }

    @discardableResult
    public func applySnippet(
        start: UInt32,
        end: UInt32,
        snippet: String,
        additionalEdits: [EcuTextEdit] = []
    ) throws -> String {
        try executeEditorCommand(
            kind: "edit",
            op: "apply_snippet",
            fields: [
                "start": Int(start),
                "end": Int(end),
                "snippet": snippet,
                "additional_edits": additionalEdits.map(\.jsonObject),
            ]
        )
    }

    @discardableResult
    public func deleteToPrevTabStop() throws -> String {
        try executeEditorCommand(kind: "edit", op: "delete_to_prev_tab_stop")
    }

    @discardableResult
    public func endUndoGroup() throws -> String {
        try executeEditorCommand(kind: "edit", op: "end_undo_group")
    }

    @discardableResult
    public func moveTo(line: UInt32, column: UInt32) throws -> String {
        try executeEditorCommand(
            kind: "cursor",
            op: "move_to",
            fields: ["line": Int(line), "column": Int(column)]
        )
    }

    @discardableResult
    public func moveBy(deltaLine: Int32, deltaColumn: Int32) throws -> String {
        try executeEditorCommand(
            kind: "cursor",
            op: "move_by",
            fields: ["delta_line": Int(deltaLine), "delta_column": Int(deltaColumn)]
        )
    }

    @discardableResult
    public func addNextOccurrence(options: EcuSearchOptions = EcuSearchOptions()) throws -> String {
        try executeEditorCommand(
            kind: "cursor",
            op: "add_next_occurrence",
            fields: ["options": Self.jsonObject(for: options)]
        )
    }

    @discardableResult
    public func addAllOccurrences(options: EcuSearchOptions = EcuSearchOptions()) throws -> String {
        try executeEditorCommand(
            kind: "cursor",
            op: "add_all_occurrences",
            fields: ["options": Self.jsonObject(for: options)]
        )
    }

    @discardableResult
    public func snippetNextPlaceholder() throws -> String {
        try executeEditorCommand(kind: "cursor", op: "snippet_next_placeholder")
    }

    @discardableResult
    public func snippetPrevPlaceholder() throws -> String {
        try executeEditorCommand(kind: "cursor", op: "snippet_prev_placeholder")
    }

    @discardableResult
    public func setViewportWidthCells(_ widthCells: UInt32) throws -> String {
        try executeEditorCommand(
            kind: "view",
            op: "set_viewport_width",
            fields: ["width": Int(widthCells)]
        )
    }

    @discardableResult
    public func setWrapMode(_ mode: EcuWrapMode) throws -> String {
        try executeEditorCommand(kind: "view", op: "set_wrap_mode", fields: ["mode": mode.rawValue])
    }

    @discardableResult
    public func setWrapIndent(_ indent: EcuWrapIndent) throws -> String {
        try executeEditorCommand(kind: "view", op: "set_wrap_indent", fields: ["indent": indent.jsonObject])
    }

    @discardableResult
    public func setIndentationConfig(_ config: EcuIndentationConfig) throws -> String {
        try executeEditorCommand(
            kind: "view",
            op: "set_indentation_config",
            fields: ["config": config.jsonObject]
        )
    }

    @discardableResult
    public func setAutoPairsConfig(_ config: EcuAutoPairsConfig) throws -> String {
        try executeEditorCommand(
            kind: "view",
            op: "set_auto_pairs_config",
            fields: ["config": config.jsonObject]
        )
    }

    public func viewportJSON(startRow: UInt32, count: UInt32) throws -> String {
        try executeEditorCommand(
            kind: "view",
            op: "get_viewport",
            fields: ["start_row": Int(startRow), "count": Int(count)]
        )
    }

    @discardableResult
    public func fold(startLine: UInt32, endLine: UInt32) throws -> String {
        try executeEditorCommand(
            kind: "style",
            op: "fold",
            fields: ["start_line": Int(startLine), "end_line": Int(endLine)]
        )
    }

    @discardableResult
    public func unfold(startLine: UInt32) throws -> String {
        try executeEditorCommand(kind: "style", op: "unfold", fields: ["start_line": Int(startLine)])
    }

    @discardableResult
    public func unfoldAll() throws -> String {
        try executeEditorCommand(kind: "style", op: "unfold_all")
    }

    @discardableResult
    public func updateBracketMatchHighlights() throws -> String {
        try executeEditorCommand(kind: "style", op: "update_bracket_match_highlights")
    }

    @discardableResult
    public func clearBracketMatchHighlights() throws -> String {
        try executeEditorCommand(kind: "style", op: "clear_bracket_match_highlights")
    }

    public func insertTab() throws {
        let status = editor_core_ui_ffi_editor_ui_insert_tab(handle)
        try library.ensureStatus(status, context: "editor_ui_insert_tab")
    }

    public func insertBacktab() throws {
        let status = editor_core_ui_ffi_editor_ui_insert_backtab(handle)
        try library.ensureStatus(status, context: "editor_ui_insert_backtab")
    }

    public func hasActiveSnippetSession() throws -> Bool {
        var out: UInt8 = 0
        let status = editor_core_ui_ffi_editor_ui_has_active_snippet_session(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_has_active_snippet_session")
        return out != 0
    }

    public func backspace() throws {
        let status = editor_core_ui_ffi_editor_ui_backspace(handle)
        try library.ensureStatus(status, context: "editor_ui_backspace")
    }

    public func deleteForward() throws {
        let status = editor_core_ui_ffi_editor_ui_delete_forward(handle)
        try library.ensureStatus(status, context: "editor_ui_delete_forward")
    }

    public func deleteWordBack() throws {
        let status = editor_core_ui_ffi_editor_ui_delete_word_back(handle)
        try library.ensureStatus(status, context: "editor_ui_delete_word_back")
    }

    public func deleteWordForward() throws {
        let status = editor_core_ui_ffi_editor_ui_delete_word_forward(handle)
        try library.ensureStatus(status, context: "editor_ui_delete_word_forward")
    }

    public func addStyle(start: UInt32, end: UInt32, styleId: UInt32) throws {
        let status = editor_core_ui_ffi_editor_ui_add_style(handle, start, end, styleId)
        try library.ensureStatus(status, context: "editor_ui_add_style")
    }

    public func removeStyle(start: UInt32, end: UInt32, styleId: UInt32) throws {
        let status = editor_core_ui_ffi_editor_ui_remove_style(handle, start, end, styleId)
        try library.ensureStatus(status, context: "editor_ui_remove_style")
    }

    /// Replace match highlight ranges (e.g. search matches) as a dedicated overlay layer.
    ///
    /// Passing an empty array clears the layer.
    public func setMatchHighlights(_ ranges: [EcuSelectionRange]) throws {
        let ffi = ranges.map { $0.ffi }
        let status = ffi.withUnsafeBufferPointer { ptr in
            editor_core_ui_ffi_editor_ui_set_match_highlights(handle, ptr.baseAddress, UInt32(ptr.count))
        }
        try library.ensureStatus(status, context: "editor_ui_set_match_highlights")
    }

    /// Set an active search query and update match highlights accordingly.
    ///
    /// Returns the match count.
    public func setSearchQuery(_ query: String, options: EcuSearchOptions = EcuSearchOptions()) throws -> UInt32 {
        var count: UInt32 = 0
        let status = query.withCString { cstr in
            editor_core_ui_ffi_editor_ui_search_set_query(handle, cstr, options.ffiCaseSensitive, options.ffiWholeWord, options.ffiRegex, &count)
        }
        try library.ensureStatus(status, context: "editor_ui_search_set_query")
        return count
    }

    public func clearSearchQuery() throws {
        let status = editor_core_ui_ffi_editor_ui_search_clear(handle)
        try library.ensureStatus(status, context: "editor_ui_search_clear")
    }

    /// Find the next occurrence of `query` and select it (primary selection only).
    ///
    /// Returns `true` when a match was found.
    public func findNext(_ query: String, options: EcuSearchOptions = EcuSearchOptions()) throws -> Bool {
        var found: UInt8 = 0
        let status = query.withCString { cstr in
            editor_core_ui_ffi_editor_ui_find_next(handle, cstr, options.ffiCaseSensitive, options.ffiWholeWord, options.ffiRegex, &found)
        }
        try library.ensureStatus(status, context: "editor_ui_find_next")
        return found != 0
    }

    /// Find the previous occurrence of `query` and select it (primary selection only).
    ///
    /// Returns `true` when a match was found.
    public func findPrev(_ query: String, options: EcuSearchOptions = EcuSearchOptions()) throws -> Bool {
        var found: UInt8 = 0
        let status = query.withCString { cstr in
            editor_core_ui_ffi_editor_ui_find_prev(handle, cstr, options.ffiCaseSensitive, options.ffiWholeWord, options.ffiRegex, &found)
        }
        try library.ensureStatus(status, context: "editor_ui_find_prev")
        return found != 0
    }

    /// Replace the current match (based on selection/caret) and return how many occurrences were replaced.
    public func replaceCurrent(
        query: String,
        replacement: String,
        options: EcuSearchOptions = EcuSearchOptions()
    ) throws -> UInt32 {
        var replaced: UInt32 = 0
        let status = query.withCString { queryCStr in
            replacement.withCString { replCStr in
                editor_core_ui_ffi_editor_ui_replace_current(
                    handle,
                    queryCStr,
                    replCStr,
                    options.ffiCaseSensitive,
                    options.ffiWholeWord,
                    options.ffiRegex,
                    &replaced
                )
            }
        }
        try library.ensureStatus(status, context: "editor_ui_replace_current")
        return replaced
    }

    /// Replace all matches and return how many occurrences were replaced.
    public func replaceAll(
        query: String,
        replacement: String,
        options: EcuSearchOptions = EcuSearchOptions()
    ) throws -> UInt32 {
        var replaced: UInt32 = 0
        let status = query.withCString { queryCStr in
            replacement.withCString { replCStr in
                editor_core_ui_ffi_editor_ui_replace_all(
                    handle,
                    queryCStr,
                    replCStr,
                    options.ffiCaseSensitive,
                    options.ffiWholeWord,
                    options.ffiRegex,
                    &replaced
                )
            }
        }
        try library.ensureStatus(status, context: "editor_ui_replace_all")
        return replaced
    }

    public func undo() throws {
        let status = editor_core_ui_ffi_editor_ui_undo(handle)
        try library.ensureStatus(status, context: "editor_ui_undo")
    }

    public func redo() throws {
        let status = editor_core_ui_ffi_editor_ui_redo(handle)
        try library.ensureStatus(status, context: "editor_ui_redo")
    }

    public func moveVisualByRows(_ deltaRows: Int32) throws {
        let status = editor_core_ui_ffi_editor_ui_move_visual_by_rows(handle, deltaRows)
        try library.ensureStatus(status, context: "editor_ui_move_visual_by_rows")
    }

    public func moveGraphemeLeft() throws {
        let status = editor_core_ui_ffi_editor_ui_move_grapheme_left(handle)
        try library.ensureStatus(status, context: "editor_ui_move_grapheme_left")
    }

    public func moveGraphemeRight() throws {
        let status = editor_core_ui_ffi_editor_ui_move_grapheme_right(handle)
        try library.ensureStatus(status, context: "editor_ui_move_grapheme_right")
    }

    public func moveWordLeft() throws {
        let status = editor_core_ui_ffi_editor_ui_move_word_left(handle)
        try library.ensureStatus(status, context: "editor_ui_move_word_left")
    }

    public func moveWordRight() throws {
        let status = editor_core_ui_ffi_editor_ui_move_word_right(handle)
        try library.ensureStatus(status, context: "editor_ui_move_word_right")
    }

    /// Jump the primary caret to the matching bracket (if any).
    public func moveToMatchingBracket() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_matching_bracket(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_matching_bracket")
    }
}
