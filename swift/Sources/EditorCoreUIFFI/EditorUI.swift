import Foundation

public final class EditorUI {
    public let library: EditorCoreUIFFILibrary
    private let handle: OpaquePointer

    public init(library: EditorCoreUIFFILibrary, initialText: String = "", viewportWidthCells: UInt32 = 120) throws {
        self.library = library
        guard let ptr = initialText.withCString({ cstr in
            library.editorUiNewFn(cstr, viewportWidthCells)
        }) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_new", message: library.lastErrorMessageString())
        }
        self.handle = ptr
    }

    deinit {
        library.editorUiFreeFn(handle)
    }

    public func setTheme(_ theme: EcuTheme) throws {
        var ffiTheme = theme.ffi
        let status = withUnsafePointer(to: &ffiTheme) { ptr in
            library.editorUiSetThemeFn(handle, UnsafeRawPointer(ptr))
        }
        try library.ensureStatus(status, context: "editor_ui_set_theme")
    }

    public func setStyleColors(_ styles: [EcuStyleColors]) throws {
        let ffi = styles.map { $0.ffi }
        let status = ffi.withUnsafeBufferPointer { ptr in
            library.editorUiSetStyleColorsFn(handle, ptr.baseAddress.map { UnsafeRawPointer($0) }, UInt32(ptr.count))
        }
        try library.ensureStatus(status, context: "editor_ui_set_style_colors")
    }

    public func sublimeSetSyntaxYAML(_ yaml: String) throws {
        let status = yaml.withCString { cstr in
            library.editorUiSublimeSetSyntaxYAMLFn(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_sublime_set_syntax_yaml")
    }

    public func sublimeSetSyntaxPath(_ path: String) throws {
        let status = path.withCString { cstr in
            library.editorUiSublimeSetSyntaxPathFn(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_sublime_set_syntax_path")
    }

    public func sublimeDisable() {
        library.editorUiSublimeDisableFn(handle)
    }

    public func sublimeStyleId(forScope scope: String) throws -> UInt32 {
        var out: UInt32 = 0
        let status = scope.withCString { cstr in
            library.editorUiSublimeStyleIdForScopeFn(handle, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_sublime_style_id_for_scope")
        return out
    }

    public func sublimeScope(forStyleId styleId: UInt32) throws -> String {
        guard let ptr = library.editorUiSublimeScopeForStyleIdFn(handle, styleId) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_sublime_scope_for_style_id", message: library.lastErrorMessageString())
        }
        defer { library.stringFreeFn(ptr) }
        return String(cString: ptr)
    }

    public func treeSitterRustEnableDefault() throws {
        let status = library.editorUiTreeSitterRustEnableDefaultFn(handle)
        try library.ensureStatus(status, context: "editor_ui_treesitter_rust_enable_default")
    }

    public func treeSitterRustEnable(highlightsQuery: String, foldsQuery: String? = nil) throws {
        let status: Int32 = highlightsQuery.withCString { highlightsCStr in
            if let foldsQuery {
                return foldsQuery.withCString { foldsCStr in
                    library.editorUiTreeSitterRustEnableWithQueriesFn(handle, highlightsCStr, foldsCStr)
                }
            }
            return library.editorUiTreeSitterRustEnableWithQueriesFn(handle, highlightsCStr, nil)
        }
        try library.ensureStatus(status, context: "editor_ui_treesitter_rust_enable_with_queries")
    }

    public func treeSitterDisable() {
        library.editorUiTreeSitterDisableFn(handle)
    }

    public func treeSitterStyleId(forCapture captureName: String) throws -> UInt32 {
        var out: UInt32 = 0
        let status = captureName.withCString { cstr in
            library.editorUiTreeSitterStyleIdForCaptureFn(handle, cstr, &out)
        }
        try library.ensureStatus(status, context: "editor_ui_treesitter_style_id_for_capture")
        return out
    }

    public func treeSitterCapture(forStyleId styleId: UInt32) throws -> String {
        guard let ptr = library.editorUiTreeSitterCaptureForStyleIdFn(handle, styleId) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_treesitter_capture_for_style_id", message: library.lastErrorMessageString())
        }
        defer { library.stringFreeFn(ptr) }
        return String(cString: ptr)
    }

    public func lspApplyDiagnosticsJSON(_ publishDiagnosticsParamsJSON: String) throws {
        let status = publishDiagnosticsParamsJSON.withCString { cstr in
            library.editorUiLspApplyDiagnosticsJSONFn(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_diagnostics_json")
    }

    public func lspApplySemanticTokens(_ data: [UInt32]) throws {
        let status = data.withUnsafeBufferPointer { ptr in
            library.editorUiLspApplySemanticTokensFn(handle, ptr.baseAddress, UInt32(ptr.count))
        }
        try library.ensureStatus(status, context: "editor_ui_lsp_apply_semantic_tokens")
    }

    public func setRenderMetrics(fontSize: Float, lineHeightPx: Float, cellWidthPx: Float, paddingXPx: Float, paddingYPx: Float) throws {
        let status = library.editorUiSetRenderMetricsFn(handle, fontSize, lineHeightPx, cellWidthPx, paddingXPx, paddingYPx)
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
            library.editorUiSetFontFamiliesCSVFn(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_set_font_families_csv")
    }

    public func setGutterWidthCells(_ widthCells: UInt32) throws {
        let status = library.editorUiSetGutterWidthCellsFn(handle, widthCells)
        try library.ensureStatus(status, context: "editor_ui_set_gutter_width_cells")
    }

    public func setViewportPx(widthPx: UInt32, heightPx: UInt32, scale: Float) throws {
        let status = library.editorUiSetViewportPxFn(handle, widthPx, heightPx, scale)
        try library.ensureStatus(status, context: "editor_ui_set_viewport_px")
    }

    public func scrollByRows(_ deltaRows: Int32) {
        library.editorUiScrollByRowsFn(handle, deltaRows)
    }

    public func insertText(_ text: String) throws {
        let status = text.withCString { cstr in
            library.editorUiInsertTextFn(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_insert_text")
    }

    public func backspace() throws {
        let status = library.editorUiBackspaceFn(handle)
        try library.ensureStatus(status, context: "editor_ui_backspace")
    }

    public func deleteForward() throws {
        let status = library.editorUiDeleteForwardFn(handle)
        try library.ensureStatus(status, context: "editor_ui_delete_forward")
    }

    public func addStyle(start: UInt32, end: UInt32, styleId: UInt32) throws {
        let status = library.editorUiAddStyleFn(handle, start, end, styleId)
        try library.ensureStatus(status, context: "editor_ui_add_style")
    }

    public func removeStyle(start: UInt32, end: UInt32, styleId: UInt32) throws {
        let status = library.editorUiRemoveStyleFn(handle, start, end, styleId)
        try library.ensureStatus(status, context: "editor_ui_remove_style")
    }

    public func undo() throws {
        let status = library.editorUiUndoFn(handle)
        try library.ensureStatus(status, context: "editor_ui_undo")
    }

    public func redo() throws {
        let status = library.editorUiRedoFn(handle)
        try library.ensureStatus(status, context: "editor_ui_redo")
    }

    public func moveVisualByRows(_ deltaRows: Int32) throws {
        let status = library.editorUiMoveVisualByRowsFn(handle, deltaRows)
        try library.ensureStatus(status, context: "editor_ui_move_visual_by_rows")
    }

    public func moveGraphemeLeft() throws {
        let status = library.editorUiMoveGraphemeLeftFn(handle)
        try library.ensureStatus(status, context: "editor_ui_move_grapheme_left")
    }

    public func moveGraphemeRight() throws {
        let status = library.editorUiMoveGraphemeRightFn(handle)
        try library.ensureStatus(status, context: "editor_ui_move_grapheme_right")
    }

    public func moveGraphemeLeftAndModifySelection() throws {
        let status = library.editorUiMoveGraphemeLeftAndModifySelectionFn(handle)
        try library.ensureStatus(status, context: "editor_ui_move_grapheme_left_and_modify_selection")
    }

    public func moveGraphemeRightAndModifySelection() throws {
        let status = library.editorUiMoveGraphemeRightAndModifySelectionFn(handle)
        try library.ensureStatus(status, context: "editor_ui_move_grapheme_right_and_modify_selection")
    }

    public func moveVisualByRowsAndModifySelection(_ deltaRows: Int32) throws {
        let status = library.editorUiMoveVisualByRowsAndModifySelectionFn(handle, deltaRows)
        try library.ensureStatus(status, context: "editor_ui_move_visual_by_rows_and_modify_selection")
    }

    public func setMarkedText(_ text: String) throws {
        let status = text.withCString { cstr in
            library.editorUiSetMarkedTextFn(handle, cstr)
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
            library.editorUiSetMarkedTextExFn(handle, cstr, selectedStart, selectedLen, replaceStart, replaceLen)
        }
        try library.ensureStatus(status, context: "editor_ui_set_marked_text_ex")
    }

    public func unmarkText() {
        library.editorUiUnmarkTextFn(handle)
    }

    public func commitText(_ text: String) throws {
        let status = text.withCString { cstr in
            library.editorUiCommitTextFn(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_commit_text")
    }

    public func mouseDown(xPx: Float, yPx: Float) throws {
        let status = library.editorUiMouseDownFn(handle, xPx, yPx)
        try library.ensureStatus(status, context: "editor_ui_mouse_down")
    }

    public func mouseDragged(xPx: Float, yPx: Float) throws {
        let status = library.editorUiMouseDraggedFn(handle, xPx, yPx)
        try library.ensureStatus(status, context: "editor_ui_mouse_dragged")
    }

    public func mouseUp() {
        library.editorUiMouseUpFn(handle)
    }

    public func renderRGBA(into buffer: inout [UInt8]) throws -> Int {
        var required: UInt32 = 0
        var status = library.editorUiRenderRGBAFn(handle, nil, 0, &required)
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
            library.editorUiRenderRGBAFn(handle, ptr.baseAddress, UInt32(ptr.count), &required)
        }
        try library.ensureStatus(status, context: "editor_ui_render_rgba")
        return requiredCount
    }

    public func text() throws -> String {
        guard let ptr = library.editorUiGetTextFn(handle) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_get_text", message: library.lastErrorMessageString())
        }
        defer { library.stringFreeFn(ptr) }
        return String(cString: ptr)
    }

    public func selectionOffsets() throws -> (start: UInt32, end: UInt32) {
        var start: UInt32 = 0
        var end: UInt32 = 0
        let status = library.editorUiGetSelectionOffsetsFn(handle, &start, &end)
        try library.ensureStatus(status, context: "editor_ui_get_selection_offsets")
        return (start, end)
    }

    public func selections() throws -> (ranges: [EcuSelectionRange], primaryIndex: UInt32) {
        var required: UInt32 = 0
        var primary: UInt32 = 0
        var status = library.editorUiGetSelectionsFn(handle, nil, 0, &required, &primary)
        guard let code = EcuStatus(rawValue: status) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: "editor_ui_get_selections(size_query)", message: "unknown status \(status)")
        }
        guard code == .bufferTooSmall || code == .ok else {
            throw EditorCoreUIFFIError.ffiStatus(code: code, context: "editor_ui_get_selections(size_query)", message: library.lastErrorMessageString())
        }

        var ffiRanges = Array(repeating: _EcuSelectionRangeFFI(start: 0, end: 0), count: Int(required))
        status = ffiRanges.withUnsafeMutableBufferPointer { ptr in
            library.editorUiGetSelectionsFn(handle, ptr.baseAddress.map { UnsafeMutableRawPointer($0) }, UInt32(ptr.count), &required, &primary)
        }
        try library.ensureStatus(status, context: "editor_ui_get_selections")
        let ranges = ffiRanges.map { EcuSelectionRange(start: $0.start, end: $0.end) }
        return (ranges, primary)
    }

    public func setSelections(_ ranges: [EcuSelectionRange], primaryIndex: UInt32) throws {
        let ffi = ranges.map { $0.ffi }
        let status = ffi.withUnsafeBufferPointer { ptr in
            library.editorUiSetSelectionsFn(handle, ptr.baseAddress.map { UnsafeRawPointer($0) }, UInt32(ptr.count), primaryIndex)
        }
        try library.ensureStatus(status, context: "editor_ui_set_selections")
    }

    public func setRectSelection(anchorOffset: UInt32, activeOffset: UInt32) throws {
        let status = library.editorUiSetRectSelectionFn(handle, anchorOffset, activeOffset)
        try library.ensureStatus(status, context: "editor_ui_set_rect_selection")
    }

    public func clearSecondarySelections() throws {
        let status = library.editorUiClearSecondarySelectionsFn(handle)
        try library.ensureStatus(status, context: "editor_ui_clear_secondary_selections")
    }

    public func addCursorAbove() throws {
        let status = library.editorUiAddCursorAboveFn(handle)
        try library.ensureStatus(status, context: "editor_ui_add_cursor_above")
    }

    public func addCursorBelow() throws {
        let status = library.editorUiAddCursorBelowFn(handle)
        try library.ensureStatus(status, context: "editor_ui_add_cursor_below")
    }

    public func addNextOccurrence() throws {
        let status = library.editorUiAddNextOccurrenceFn(handle)
        try library.ensureStatus(status, context: "editor_ui_add_next_occurrence")
    }

    public func addAllOccurrences() throws {
        let status = library.editorUiAddAllOccurrencesFn(handle)
        try library.ensureStatus(status, context: "editor_ui_add_all_occurrences")
    }

    public func selectWord() throws {
        let status = library.editorUiSelectWordFn(handle)
        try library.ensureStatus(status, context: "editor_ui_select_word")
    }

    public func selectLine() throws {
        let status = library.editorUiSelectLineFn(handle)
        try library.ensureStatus(status, context: "editor_ui_select_line")
    }

    public func expandSelection() throws {
        let status = library.editorUiExpandSelectionFn(handle)
        try library.ensureStatus(status, context: "editor_ui_expand_selection")
    }

    public func addCaret(atCharOffset charOffset: UInt32, makePrimary: Bool) throws {
        let status = library.editorUiAddCaretAtCharOffsetFn(handle, charOffset, makePrimary ? 1 : 0)
        try library.ensureStatus(status, context: "editor_ui_add_caret_at_char_offset")
    }

    public func markedRange() throws -> (hasMarked: Bool, start: UInt32, len: UInt32) {
        var has: UInt8 = 0
        var start: UInt32 = 0
        var len: UInt32 = 0
        let status = library.editorUiGetMarkedRangeFn(handle, &has, &start, &len)
        try library.ensureStatus(status, context: "editor_ui_get_marked_range")
        return (has != 0, start, len)
    }

    public func charOffsetToViewPoint(offset: UInt32) throws -> (xPx: Float, yPx: Float, lineHeightPx: Float) {
        var x: Float = 0
        var y: Float = 0
        var lineH: Float = 0
        let status = library.editorUiCharOffsetToViewPointFn(handle, offset, &x, &y, &lineH)
        try library.ensureStatus(status, context: "editor_ui_char_offset_to_view_point")
        return (x, y, lineH)
    }

    public func viewPointToCharOffset(xPx: Float, yPx: Float) throws -> UInt32 {
        var offset: UInt32 = 0
        let status = library.editorUiViewPointToCharOffsetFn(handle, xPx, yPx, &offset)
        try library.ensureStatus(status, context: "editor_ui_view_point_to_char_offset")
        return offset
    }
}
