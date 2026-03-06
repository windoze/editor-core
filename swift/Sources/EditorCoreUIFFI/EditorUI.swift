import CEditorCoreUIFFI
import Foundation
import Metal

public final class EditorUI {
    public let library: EditorCoreUIFFILibrary
    private let handle: OpaquePointer

    public init(library: EditorCoreUIFFILibrary, initialText: String = "", viewportWidthCells: UInt32 = 120) throws {
        self.library = library
        guard let ptr = initialText.withCString({ cstr in
            editor_core_ui_ffi_editor_ui_new(cstr, viewportWidthCells)
        }) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_new", message: library.lastErrorMessageString())
        }
        self.handle = ptr
    }

    deinit {
        editor_core_ui_ffi_editor_ui_free(handle)
    }

    public func setTheme(_ theme: EcuTheme) throws {
        var ffiTheme = theme.ffi
        let status = withUnsafePointer(to: &ffiTheme) { ptr in
            editor_core_ui_ffi_editor_ui_set_theme(handle, ptr)
        }
        try library.ensureStatus(status, context: "editor_ui_set_theme")
    }

    public func setStyleColors(_ styles: [EcuStyleColors]) throws {
        let ffi = styles.map { $0.ffi }
        let status = ffi.withUnsafeBufferPointer { ptr in
            editor_core_ui_ffi_editor_ui_set_style_colors(handle, ptr.baseAddress, UInt32(ptr.count))
        }
        try library.ensureStatus(status, context: "editor_ui_set_style_colors")
    }

    public func sublimeSetSyntaxYAML(_ yaml: String) throws {
        let status = yaml.withCString { cstr in
            editor_core_ui_ffi_editor_ui_sublime_set_syntax_yaml(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_sublime_set_syntax_yaml")
    }

    public func sublimeSetSyntaxPath(_ path: String) throws {
        let status = path.withCString { cstr in
            editor_core_ui_ffi_editor_ui_sublime_set_syntax_path(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_sublime_set_syntax_path")
    }

    public func sublimeDisable() {
        editor_core_ui_ffi_editor_ui_sublime_disable(handle)
    }

    public func sublimeStyleId(forScope scope: String) throws -> UInt32 {
        var out: UInt32 = 0
        let status = scope.withCString { cstr in
            editor_core_ui_ffi_editor_ui_sublime_style_id_for_scope(handle, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_sublime_style_id_for_scope")
        return out
    }

    public func sublimeScope(forStyleId styleId: UInt32) throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_sublime_scope_for_style_id(handle, styleId) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_sublime_scope_for_style_id", message: library.lastErrorMessageString())
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func treeSitterRustEnableDefault() throws {
        let status = editor_core_ui_ffi_editor_ui_treesitter_rust_enable_default(handle)
        try library.ensureStatus(status, context: "editor_ui_treesitter_rust_enable_default")
    }

    public func treeSitterRustEnable(highlightsQuery: String, foldsQuery: String? = nil) throws {
        let status: Int32 = highlightsQuery.withCString { highlightsCStr in
            if let foldsQuery {
                return foldsQuery.withCString { foldsCStr in
                    editor_core_ui_ffi_editor_ui_treesitter_rust_enable_with_queries(handle, highlightsCStr, foldsCStr)
                }
            }
            return editor_core_ui_ffi_editor_ui_treesitter_rust_enable_with_queries(handle, highlightsCStr, nil)
        }
        try library.ensureStatus(status, context: "editor_ui_treesitter_rust_enable_with_queries")
    }

    public func treeSitterDisable() {
        editor_core_ui_ffi_editor_ui_treesitter_disable(handle)
    }

    /// Poll and apply any completed async processing (Tree-sitter highlighting/folding).
    ///
    /// This call is non-blocking: it never waits for background work.
    ///
    /// - Returns:
    ///   - `applied`: whether new processing edits were applied.
    ///   - `pending`: whether there is still work pending in the background.
    public func pollProcessing() throws -> (applied: Bool, pending: Bool) {
        var applied: UInt8 = 0
        var pending: UInt8 = 0
        let status = editor_core_ui_ffi_editor_ui_poll_processing(handle, &applied, &pending)
        try library.ensureStatus(status, context: "editor_ui_poll_processing")
        return (applied != 0, pending != 0)
    }

    public func treeSitterStyleId(forCapture captureName: String) throws -> UInt32 {
        var out: UInt32 = 0
        let status = captureName.withCString { cstr in
            editor_core_ui_ffi_editor_ui_treesitter_style_id_for_capture(handle, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_treesitter_style_id_for_capture")
        return out
    }

    public func treeSitterCapture(forStyleId styleId: UInt32) throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_treesitter_capture_for_style_id(handle, styleId) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_treesitter_capture_for_style_id", message: library.lastErrorMessageString())
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func lspApplyDiagnosticsJSON(_ publishDiagnosticsParamsJSON: String) throws {
        let status = publishDiagnosticsParamsJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_diagnostics_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_diagnostics_json")
    }

    public func lspApplyInlayHintsJSON(_ inlayHintsResultJSON: String) throws {
        let status = inlayHintsResultJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_inlay_hints_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_inlay_hints_json")
    }

    public func lspApplyCodeLensJSON(_ codeLensResultJSON: String) throws {
        let status = codeLensResultJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_code_lens_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_code_lens_json")
    }

    public func lspApplyDocumentLinksJSON(_ documentLinksResultJSON: String) throws {
        let status = documentLinksResultJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_document_links_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_document_links_json")
    }

    public func lspApplyDocumentHighlightsJSON(_ documentHighlightsResultJSON: String) throws {
        let status = documentHighlightsResultJSON.withCString { cstr in
            editor_core_ui_ffi_editor_ui_lsp_apply_document_highlights_json(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_document_highlights_json")
    }

    public func lspApplySemanticTokens(_ data: [UInt32]) throws {
        let status = data.withUnsafeBufferPointer { ptr in
            editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens(handle, ptr.baseAddress, UInt32(ptr.count))
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_semantic_tokens")
    }

    public func setRenderMetrics(fontSize: Float, lineHeightPx: Float, cellWidthPx: Float, paddingXPx: Float, paddingYPx: Float) throws {
        let status = editor_core_ui_ffi_editor_ui_set_render_metrics(handle, fontSize, lineHeightPx, cellWidthPx, paddingXPx, paddingYPx)
        try library.ensureStatus(status, context: "editor_ui_set_render_metrics")
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

    public func insertText(_ text: String) throws {
        let status = text.withCString { cstr in
            editor_core_ui_ffi_editor_ui_insert_text(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_insert_text")
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

    public func moveToVisualLineStart() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_visual_line_start(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_visual_line_start")
    }

    public func moveToVisualLineEnd() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_visual_line_end(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_visual_line_end")
    }

    public func moveToDocumentStart() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_document_start(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_document_start")
    }

    public func moveToDocumentEnd() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_document_end(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_document_end")
    }

    public func moveVisualByPages(_ deltaPages: Int32) throws {
        let status = editor_core_ui_ffi_editor_ui_move_visual_by_pages(handle, deltaPages)
        try library.ensureStatus(status, context: "editor_ui_move_visual_by_pages")
    }

    public func moveGraphemeLeftAndModifySelection() throws {
        let status = editor_core_ui_ffi_editor_ui_move_grapheme_left_and_modify_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_move_grapheme_left_and_modify_selection")
    }

    public func moveGraphemeRightAndModifySelection() throws {
        let status = editor_core_ui_ffi_editor_ui_move_grapheme_right_and_modify_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_move_grapheme_right_and_modify_selection")
    }

    public func moveWordLeftAndModifySelection() throws {
        let status = editor_core_ui_ffi_editor_ui_move_word_left_and_modify_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_move_word_left_and_modify_selection")
    }

    public func moveWordRightAndModifySelection() throws {
        let status = editor_core_ui_ffi_editor_ui_move_word_right_and_modify_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_move_word_right_and_modify_selection")
    }

    public func moveToVisualLineStartAndModifySelection() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_visual_line_start_and_modify_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_visual_line_start_and_modify_selection")
    }

    public func moveToVisualLineEndAndModifySelection() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_visual_line_end_and_modify_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_visual_line_end_and_modify_selection")
    }

    public func moveToDocumentStartAndModifySelection() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_document_start_and_modify_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_document_start_and_modify_selection")
    }

    public func moveToDocumentEndAndModifySelection() throws {
        let status = editor_core_ui_ffi_editor_ui_move_to_document_end_and_modify_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_move_to_document_end_and_modify_selection")
    }

    public func moveVisualByPagesAndModifySelection(_ deltaPages: Int32) throws {
        let status = editor_core_ui_ffi_editor_ui_move_visual_by_pages_and_modify_selection(handle, deltaPages)
        try library.ensureStatus(status, context: "editor_ui_move_visual_by_pages_and_modify_selection")
    }

    public func moveVisualByRowsAndModifySelection(_ deltaRows: Int32) throws {
        let status = editor_core_ui_ffi_editor_ui_move_visual_by_rows_and_modify_selection(handle, deltaRows)
        try library.ensureStatus(status, context: "editor_ui_move_visual_by_rows_and_modify_selection")
    }

    public func setMarkedText(_ text: String) throws {
        let status = text.withCString { cstr in
            editor_core_ui_ffi_editor_ui_set_marked_text(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_set_marked_text")
    }

    /// Set IME marked text (preedit) with selection and optional replacement range.
    ///
    /// - `selectedStart/selectedLen`: selection within `text` (Unicode scalar offsets).
    /// - `replaceStart/replaceLen`: document char-offset range to replace.
    ///   Pass `UInt32.max` for `replaceStart` to let Rust pick (existing marked range / current selection).
    public func setMarkedText(
        _ text: String,
        selectedStart: UInt32,
        selectedLen: UInt32,
        replaceStart: UInt32 = UInt32.max,
        replaceLen: UInt32 = 0
    ) throws {
        let status = text.withCString { cstr in
            editor_core_ui_ffi_editor_ui_set_marked_text_ex(handle, cstr, selectedStart, selectedLen, replaceStart, replaceLen)
        }
        try library.ensureStatus(status, context: "editor_ui_set_marked_text_ex")
    }

    public func unmarkText() {
        editor_core_ui_ffi_editor_ui_unmark_text(handle)
    }

    public func commitText(_ text: String) throws {
        let status = text.withCString { cstr in
            editor_core_ui_ffi_editor_ui_commit_text(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_commit_text")
    }

    public func mouseDown(xPx: Float, yPx: Float) throws {
        let status = editor_core_ui_ffi_editor_ui_mouse_down(handle, xPx, yPx)
        try library.ensureStatus(status, context: "editor_ui_mouse_down")
    }

    public func mouseDragged(xPx: Float, yPx: Float) throws {
        let status = editor_core_ui_ffi_editor_ui_mouse_dragged(handle, xPx, yPx)
        try library.ensureStatus(status, context: "editor_ui_mouse_dragged")
    }

    public func mouseUp() {
        editor_core_ui_ffi_editor_ui_mouse_up(handle)
    }

    public func renderRGBA(into buffer: inout [UInt8]) throws -> Int {
        var required: UInt32 = 0
        var status = editor_core_ui_ffi_editor_ui_render_rgba(handle, nil, 0, &required)
        guard let code = EcuStatus(rawValue: status) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_render_rgba(size_query)", message: "unknown status \(status)")
        }
        guard code == .bufferTooSmall || code == .ok else {
            throw EditorCoreUIFFIError.ffiStatus(code: code, context: "editor_ui_render_rgba(size_query)", message: library.lastErrorMessageString())
        }

        let requiredCount = Int(required)
        if buffer.count != requiredCount {
            buffer = Array(repeating: 0, count: requiredCount)
        }

        status = buffer.withUnsafeMutableBufferPointer { ptr in
            editor_core_ui_ffi_editor_ui_render_rgba(handle, ptr.baseAddress, UInt32(ptr.count), &required)
        }
        try library.ensureStatus(status, context: "editor_ui_render_rgba")
        return requiredCount
    }

    // MARK: - Metal / GPU rendering (macOS)

    public func enableMetal(device: MTLDevice, commandQueue: MTLCommandQueue) throws {
        let devicePtr = Unmanaged.passUnretained(device).toOpaque()
        let queuePtr = Unmanaged.passUnretained(commandQueue).toOpaque()
        let status = editor_core_ui_ffi_editor_ui_enable_metal(handle, devicePtr, queuePtr)
        try library.ensureStatus(status, context: "editor_ui_enable_metal")
    }

    public func renderMetal(into texture: MTLTexture) throws {
        let texPtr = Unmanaged.passUnretained(texture).toOpaque()
        let status = editor_core_ui_ffi_editor_ui_render_metal(handle, texPtr)
        try library.ensureStatus(status, context: "editor_ui_render_metal")
    }

    public func text() throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_get_text(handle) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_get_text", message: library.lastErrorMessageString())
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    /// Get selected text (primary + secondary selections), joined with `\\n`.
    public func selectedText() throws -> String {
        guard let ptr = editor_core_ui_ffi_editor_ui_get_selected_text(handle) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_get_selected_text", message: library.lastErrorMessageString())
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }

    public func selectionOffsets() throws -> (start: UInt32, end: UInt32) {
        var start: UInt32 = 0
        var end: UInt32 = 0
        let status = editor_core_ui_ffi_editor_ui_get_selection_offsets(handle, &start, &end)
        try library.ensureStatus(status, context: "editor_ui_get_selection_offsets")
        return (start, end)
    }

    /// Delete only non-empty selections (primary + secondary), keeping empty carets intact.
    ///
    /// Intended for clipboard "cut" behavior.
    public func deleteSelectionsOnly() throws {
        let status = editor_core_ui_ffi_editor_ui_delete_selections_only(handle)
        try library.ensureStatus(status, context: "editor_ui_delete_selections_only")
    }

    public func selections() throws -> (ranges: [EcuSelectionRange], primaryIndex: UInt32) {
        var required: UInt32 = 0
        var primary: UInt32 = 0
        var status = editor_core_ui_ffi_editor_ui_get_selections(handle, nil, 0, &required, &primary)
        guard let code = EcuStatus(rawValue: status) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_get_selections(size_query)", message: "unknown status \(status)")
        }
        guard code == .bufferTooSmall || code == .ok else {
            throw EditorCoreUIFFIError.ffiStatus(code: code, context: "editor_ui_get_selections(size_query)", message: library.lastErrorMessageString())
        }

        var ffiRanges = Array(repeating: CEditorCoreUIFFI.EcuSelectionRange(start: 0, end: 0), count: Int(required))
        status = ffiRanges.withUnsafeMutableBufferPointer { ptr in
            editor_core_ui_ffi_editor_ui_get_selections(handle, ptr.baseAddress, UInt32(ptr.count), &required, &primary)
        }
        try library.ensureStatus(status, context: "editor_ui_get_selections")
        let ranges = ffiRanges.map { EcuSelectionRange(start: $0.start, end: $0.end) }
        return (ranges, primary)
    }

    public func setSelections(_ ranges: [EcuSelectionRange], primaryIndex: UInt32) throws {
        let ffi = ranges.map { $0.ffi }
        let status = ffi.withUnsafeBufferPointer { ptr in
            editor_core_ui_ffi_editor_ui_set_selections(handle, ptr.baseAddress, UInt32(ptr.count), primaryIndex)
        }
        try library.ensureStatus(status, context: "editor_ui_set_selections")
    }

    public func setRectSelection(anchorOffset: UInt32, activeOffset: UInt32) throws {
        let status = editor_core_ui_ffi_editor_ui_set_rect_selection(handle, anchorOffset, activeOffset)
        try library.ensureStatus(status, context: "editor_ui_set_rect_selection")
    }

    public func clearSecondarySelections() throws {
        let status = editor_core_ui_ffi_editor_ui_clear_secondary_selections(handle)
        try library.ensureStatus(status, context: "editor_ui_clear_secondary_selections")
    }

    public func addCursorAbove() throws {
        let status = editor_core_ui_ffi_editor_ui_add_cursor_above(handle)
        try library.ensureStatus(status, context: "editor_ui_add_cursor_above")
    }

    public func addCursorBelow() throws {
        let status = editor_core_ui_ffi_editor_ui_add_cursor_below(handle)
        try library.ensureStatus(status, context: "editor_ui_add_cursor_below")
    }

    public func addNextOccurrence() throws {
        let status = editor_core_ui_ffi_editor_ui_add_next_occurrence(handle)
        try library.ensureStatus(status, context: "editor_ui_add_next_occurrence")
    }

    public func addAllOccurrences() throws {
        let status = editor_core_ui_ffi_editor_ui_add_all_occurrences(handle)
        try library.ensureStatus(status, context: "editor_ui_add_all_occurrences")
    }

    public func selectWord() throws {
        let status = editor_core_ui_ffi_editor_ui_select_word(handle)
        try library.ensureStatus(status, context: "editor_ui_select_word")
    }

    public func selectLine() throws {
        let status = editor_core_ui_ffi_editor_ui_select_line(handle)
        try library.ensureStatus(status, context: "editor_ui_select_line")
    }

    public func setLineSelection(anchorOffset: UInt32, activeOffset: UInt32) throws {
        let status = editor_core_ui_ffi_editor_ui_set_line_selection_offsets(handle, anchorOffset, activeOffset)
        try library.ensureStatus(status, context: "editor_ui_set_line_selection_offsets")
    }

    public func selectParagraph(atCharOffset charOffset: UInt32) throws {
        let status = editor_core_ui_ffi_editor_ui_select_paragraph_at_char_offset(handle, charOffset)
        try library.ensureStatus(status, context: "editor_ui_select_paragraph_at_char_offset")
    }

    public func setParagraphSelection(anchorOffset: UInt32, activeOffset: UInt32) throws {
        let status = editor_core_ui_ffi_editor_ui_set_paragraph_selection_offsets(handle, anchorOffset, activeOffset)
        try library.ensureStatus(status, context: "editor_ui_set_paragraph_selection_offsets")
    }

    public func expandSelection() throws {
        let status = editor_core_ui_ffi_editor_ui_expand_selection(handle)
        try library.ensureStatus(status, context: "editor_ui_expand_selection")
    }

    public func expandSelectionBy(unit: EcuExpandSelectionUnit, count: UInt32, direction: EcuExpandSelectionDirection) throws {
        let status = editor_core_ui_ffi_editor_ui_expand_selection_by(handle, unit.rawValue, count, direction.rawValue)
        try library.ensureStatus(status, context: "editor_ui_expand_selection_by")
    }

    public func addCaret(atCharOffset charOffset: UInt32, makePrimary: Bool) throws {
        let status = editor_core_ui_ffi_editor_ui_add_caret_at_char_offset(handle, charOffset, makePrimary ? 1 : 0)
        try library.ensureStatus(status, context: "editor_ui_add_caret_at_char_offset")
    }

    public func markedRange() throws -> (hasMarked: Bool, start: UInt32, len: UInt32) {
        var has: UInt8 = 0
        var start: UInt32 = 0
        var len: UInt32 = 0
        let status = editor_core_ui_ffi_editor_ui_get_marked_range(handle, &has, &start, &len)
        try library.ensureStatus(status, context: "editor_ui_get_marked_range")
        return (has != 0, start, len)
    }

    public func charOffsetToLogicalPosition(offset: UInt32) throws -> (line: UInt32, column: UInt32) {
        var line: UInt32 = 0
        var col: UInt32 = 0
        let status = editor_core_ui_ffi_editor_ui_char_offset_to_logical_position(handle, offset, &line, &col)
        try library.ensureStatus(status, context: "editor_ui_char_offset_to_logical_position")
        return (line, col)
    }

    public func charOffsetToViewPoint(offset: UInt32) throws -> (xPx: Float, yPx: Float, lineHeightPx: Float) {
        var x: Float = 0
        var y: Float = 0
        var lineH: Float = 0
        let status = editor_core_ui_ffi_editor_ui_char_offset_to_view_point(handle, offset, &x, &y, &lineH)
        try library.ensureStatus(status, context: "editor_ui_char_offset_to_view_point")
        return (x, y, lineH)
    }

    public func viewPointToCharOffset(xPx: Float, yPx: Float) throws -> UInt32 {
        var offset: UInt32 = 0
        let status = editor_core_ui_ffi_editor_ui_view_point_to_char_offset(handle, xPx, yPx, &offset)
        try library.ensureStatus(status, context: "editor_ui_view_point_to_char_offset")
        return offset
    }

    /// Hit-test a view point and return the raw LSP `DocumentLink` JSON payload (if present).
    public func documentLinkJSONAtViewPoint(xPx: Float, yPx: Float) throws -> String? {
        var has: UInt8 = 0
        var ptr: UnsafeMutablePointer<CChar>?
        let status = editor_core_ui_ffi_editor_ui_get_document_link_json_at_view_point(handle, xPx, yPx, &has, &ptr)
        try library.ensureStatus(status, context: "editor_ui_get_document_link_json_at_view_point")
        guard has != 0, let ptr else {
            return nil
        }
        defer { editor_core_ui_ffi_string_free(ptr) }
        return String(cString: ptr)
    }
}
