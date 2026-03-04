import Foundation

public final class EditorCoreUIFFILibrary {
    typealias FnVersion = @convention(c) () -> UnsafeMutablePointer<CChar>?
    typealias FnLastErrorMessage = @convention(c) () -> UnsafeMutablePointer<CChar>?
    typealias FnStringFree = @convention(c) (UnsafeMutablePointer<CChar>?) -> Void

    typealias FnEditorUiNew = @convention(c) (UnsafePointer<CChar>?, UInt32) -> OpaquePointer?
    typealias FnEditorUiFree = @convention(c) (OpaquePointer?) -> Void

    typealias FnEditorUiSetTheme = @convention(c) (OpaquePointer?, UnsafeRawPointer?) -> Int32
    typealias FnEditorUiSetStyleColors = @convention(c) (OpaquePointer?, UnsafeRawPointer?, UInt32) -> Int32
    typealias FnEditorUiSublimeSetSyntaxYAML = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    typealias FnEditorUiSublimeSetSyntaxPath = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    typealias FnEditorUiSublimeDisable = @convention(c) (OpaquePointer?) -> Void
    typealias FnEditorUiSublimeStyleIdForScope = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafeMutablePointer<UInt32>?) -> Int32
    typealias FnEditorUiSublimeScopeForStyleId = @convention(c) (OpaquePointer?, UInt32) -> UnsafeMutablePointer<CChar>?

    typealias FnEditorUiTreeSitterRustEnableDefault = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUiTreeSitterRustEnableWithQueries = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafePointer<CChar>?) -> Int32
    typealias FnEditorUiTreeSitterDisable = @convention(c) (OpaquePointer?) -> Void
    typealias FnEditorUiTreeSitterStyleIdForCapture = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UnsafeMutablePointer<UInt32>?) -> Int32
    typealias FnEditorUiTreeSitterCaptureForStyleId = @convention(c) (OpaquePointer?, UInt32) -> UnsafeMutablePointer<CChar>?

    typealias FnEditorUiLspApplyDiagnosticsJSON = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    typealias FnEditorUiLspApplySemanticTokens = @convention(c) (OpaquePointer?, UnsafePointer<UInt32>?, UInt32) -> Int32

    typealias FnEditorUiSetRenderMetrics = @convention(c) (OpaquePointer?, Float, Float, Float, Float, Float) -> Int32
    typealias FnEditorUiSetFontFamiliesCSV = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    typealias FnEditorUiSetFontLigaturesEnabled = @convention(c) (OpaquePointer?, UInt8) -> Int32
    typealias FnEditorUiSetGutterWidthCells = @convention(c) (OpaquePointer?, UInt32) -> Int32
    typealias FnEditorUiSetViewportPx = @convention(c) (OpaquePointer?, UInt32, UInt32, Float) -> Int32
    typealias FnEditorUiScrollByRows = @convention(c) (OpaquePointer?, Int32) -> Void

    typealias FnEditorUiInsertText = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    typealias FnEditorUiBackspace = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUiDeleteForward = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUiAddStyle = @convention(c) (OpaquePointer?, UInt32, UInt32, UInt32) -> Int32
    typealias FnEditorUiRemoveStyle = @convention(c) (OpaquePointer?, UInt32, UInt32, UInt32) -> Int32
    typealias FnEditorUiUndo = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUiRedo = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUiMoveVisualByRows = @convention(c) (OpaquePointer?, Int32) -> Int32
    typealias FnEditorUiMoveGraphemeLeft = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUiMoveGraphemeRight = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUiMoveGraphemeLeftAndModifySelection = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUiMoveGraphemeRightAndModifySelection = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUiMoveVisualByRowsAndModifySelection = @convention(c) (OpaquePointer?, Int32) -> Int32

    typealias FnEditorUiSetMarkedText = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32
    typealias FnEditorUiSetMarkedTextEx = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?, UInt32, UInt32, UInt32, UInt32) -> Int32
    typealias FnEditorUiUnmarkText = @convention(c) (OpaquePointer?) -> Void
    typealias FnEditorUiCommitText = @convention(c) (OpaquePointer?, UnsafePointer<CChar>?) -> Int32

    typealias FnEditorUiMouseDown = @convention(c) (OpaquePointer?, Float, Float) -> Int32
    typealias FnEditorUiMouseDragged = @convention(c) (OpaquePointer?, Float, Float) -> Int32
    typealias FnEditorUiMouseUp = @convention(c) (OpaquePointer?) -> Void

    typealias FnEditorUiRenderRGBA = @convention(c) (
        OpaquePointer?,
        UnsafeMutablePointer<UInt8>?,
        UInt32,
        UnsafeMutablePointer<UInt32>?
    ) -> Int32

    typealias FnEditorUiGetText = @convention(c) (OpaquePointer?) -> UnsafeMutablePointer<CChar>?

    typealias FnEditorUiGetSelectionOffsets = @convention(c) (OpaquePointer?, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> Int32
    typealias FnEditorUiGetSelections = @convention(c) (OpaquePointer?, UnsafeMutableRawPointer?, UInt32, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> Int32
    typealias FnEditorUiSetSelections = @convention(c) (OpaquePointer?, UnsafeRawPointer?, UInt32, UInt32) -> Int32
    typealias FnEditorUiSetRectSelection = @convention(c) (OpaquePointer?, UInt32, UInt32) -> Int32

    typealias FnEditorUiClearSecondarySelections = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUiAddCursorAbove = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUiAddCursorBelow = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUiAddNextOccurrence = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUiAddAllOccurrences = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUiSelectWord = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUiSelectLine = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUiSetLineSelectionOffsets = @convention(c) (OpaquePointer?, UInt32, UInt32) -> Int32
    typealias FnEditorUiSelectParagraphAtCharOffset = @convention(c) (OpaquePointer?, UInt32) -> Int32
    typealias FnEditorUiSetParagraphSelectionOffsets = @convention(c) (OpaquePointer?, UInt32, UInt32) -> Int32
    typealias FnEditorUiExpandSelection = @convention(c) (OpaquePointer?) -> Int32
    typealias FnEditorUiAddCaretAtCharOffset = @convention(c) (OpaquePointer?, UInt32, UInt8) -> Int32

    typealias FnEditorUiGetMarkedRange = @convention(c) (OpaquePointer?, UnsafeMutablePointer<UInt8>?, UnsafeMutablePointer<UInt32>?, UnsafeMutablePointer<UInt32>?) -> Int32
    typealias FnEditorUiCharOffsetToViewPoint = @convention(c) (OpaquePointer?, UInt32, UnsafeMutablePointer<Float>?, UnsafeMutablePointer<Float>?, UnsafeMutablePointer<Float>?) -> Int32
    typealias FnEditorUiViewPointToCharOffset = @convention(c) (OpaquePointer?, Float, Float, UnsafeMutablePointer<UInt32>?) -> Int32

    private let dylib: DynamicLibrary
    public let resolvedLibraryPath: String

    private let versionFn: FnVersion
    private let lastErrorMessageFn: FnLastErrorMessage
    let stringFreeFn: FnStringFree

    let editorUiNewFn: FnEditorUiNew
    let editorUiFreeFn: FnEditorUiFree
    let editorUiSetThemeFn: FnEditorUiSetTheme
    let editorUiSetStyleColorsFn: FnEditorUiSetStyleColors
    let editorUiSublimeSetSyntaxYAMLFn: FnEditorUiSublimeSetSyntaxYAML
    let editorUiSublimeSetSyntaxPathFn: FnEditorUiSublimeSetSyntaxPath
    let editorUiSublimeDisableFn: FnEditorUiSublimeDisable
    let editorUiSublimeStyleIdForScopeFn: FnEditorUiSublimeStyleIdForScope
    let editorUiSublimeScopeForStyleIdFn: FnEditorUiSublimeScopeForStyleId

    let editorUiTreeSitterRustEnableDefaultFn: FnEditorUiTreeSitterRustEnableDefault
    let editorUiTreeSitterRustEnableWithQueriesFn: FnEditorUiTreeSitterRustEnableWithQueries
    let editorUiTreeSitterDisableFn: FnEditorUiTreeSitterDisable
    let editorUiTreeSitterStyleIdForCaptureFn: FnEditorUiTreeSitterStyleIdForCapture
    let editorUiTreeSitterCaptureForStyleIdFn: FnEditorUiTreeSitterCaptureForStyleId

    let editorUiLspApplyDiagnosticsJSONFn: FnEditorUiLspApplyDiagnosticsJSON
    let editorUiLspApplySemanticTokensFn: FnEditorUiLspApplySemanticTokens

    let editorUiSetRenderMetricsFn: FnEditorUiSetRenderMetrics
    let editorUiSetFontFamiliesCSVFn: FnEditorUiSetFontFamiliesCSV
    let editorUiSetFontLigaturesEnabledFn: FnEditorUiSetFontLigaturesEnabled
    let editorUiSetGutterWidthCellsFn: FnEditorUiSetGutterWidthCells
    let editorUiSetViewportPxFn: FnEditorUiSetViewportPx
    let editorUiScrollByRowsFn: FnEditorUiScrollByRows
    let editorUiInsertTextFn: FnEditorUiInsertText
    let editorUiBackspaceFn: FnEditorUiBackspace
    let editorUiDeleteForwardFn: FnEditorUiDeleteForward
    let editorUiAddStyleFn: FnEditorUiAddStyle
    let editorUiRemoveStyleFn: FnEditorUiRemoveStyle
    let editorUiUndoFn: FnEditorUiUndo
    let editorUiRedoFn: FnEditorUiRedo
    let editorUiMoveVisualByRowsFn: FnEditorUiMoveVisualByRows
    let editorUiMoveGraphemeLeftFn: FnEditorUiMoveGraphemeLeft
    let editorUiMoveGraphemeRightFn: FnEditorUiMoveGraphemeRight
    let editorUiMoveGraphemeLeftAndModifySelectionFn: FnEditorUiMoveGraphemeLeftAndModifySelection
    let editorUiMoveGraphemeRightAndModifySelectionFn: FnEditorUiMoveGraphemeRightAndModifySelection
    let editorUiMoveVisualByRowsAndModifySelectionFn: FnEditorUiMoveVisualByRowsAndModifySelection
    let editorUiSetMarkedTextFn: FnEditorUiSetMarkedText
    let editorUiSetMarkedTextExFn: FnEditorUiSetMarkedTextEx
    let editorUiUnmarkTextFn: FnEditorUiUnmarkText
    let editorUiCommitTextFn: FnEditorUiCommitText
    let editorUiMouseDownFn: FnEditorUiMouseDown
    let editorUiMouseDraggedFn: FnEditorUiMouseDragged
    let editorUiMouseUpFn: FnEditorUiMouseUp
    let editorUiRenderRGBAFn: FnEditorUiRenderRGBA
    let editorUiGetTextFn: FnEditorUiGetText
    let editorUiGetSelectionOffsetsFn: FnEditorUiGetSelectionOffsets
    let editorUiGetSelectionsFn: FnEditorUiGetSelections
    let editorUiSetSelectionsFn: FnEditorUiSetSelections
    let editorUiSetRectSelectionFn: FnEditorUiSetRectSelection

    let editorUiClearSecondarySelectionsFn: FnEditorUiClearSecondarySelections
    let editorUiAddCursorAboveFn: FnEditorUiAddCursorAbove
    let editorUiAddCursorBelowFn: FnEditorUiAddCursorBelow
    let editorUiAddNextOccurrenceFn: FnEditorUiAddNextOccurrence
    let editorUiAddAllOccurrencesFn: FnEditorUiAddAllOccurrences
    let editorUiSelectWordFn: FnEditorUiSelectWord
    let editorUiSelectLineFn: FnEditorUiSelectLine
    let editorUiSetLineSelectionOffsetsFn: FnEditorUiSetLineSelectionOffsets
    let editorUiSelectParagraphAtCharOffsetFn: FnEditorUiSelectParagraphAtCharOffset
    let editorUiSetParagraphSelectionOffsetsFn: FnEditorUiSetParagraphSelectionOffsets
    let editorUiExpandSelectionFn: FnEditorUiExpandSelection
    let editorUiAddCaretAtCharOffsetFn: FnEditorUiAddCaretAtCharOffset

    let editorUiGetMarkedRangeFn: FnEditorUiGetMarkedRange
    let editorUiCharOffsetToViewPointFn: FnEditorUiCharOffsetToViewPoint
    let editorUiViewPointToCharOffsetFn: FnEditorUiViewPointToCharOffset

    public init(explicitPath: String? = nil) throws {
        let candidates = Self.candidateLibraryPaths(explicitPath: explicitPath)
        var errors: [String] = []
        var loaded: DynamicLibrary?
        var resolved: String?

        for path in candidates {
            do {
                loaded = try DynamicLibrary(path: path)
                resolved = path
                break
            } catch {
                errors.append(String(describing: error))
            }
        }

        guard let dylib = loaded, let resolved else {
            throw EditorCoreUIFFIError.failedToLoadLibrary(tried: candidates, errors: errors)
        }

        self.dylib = dylib
        self.resolvedLibraryPath = resolved

        versionFn = try dylib.loadSymbol("editor_core_ui_ffi_version", as: FnVersion.self)
        lastErrorMessageFn = try dylib.loadSymbol("editor_core_ui_ffi_last_error_message", as: FnLastErrorMessage.self)
        stringFreeFn = try dylib.loadSymbol("editor_core_ui_ffi_string_free", as: FnStringFree.self)

        editorUiNewFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_new", as: FnEditorUiNew.self)
        editorUiFreeFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_free", as: FnEditorUiFree.self)
        editorUiSetThemeFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_set_theme", as: FnEditorUiSetTheme.self)
        editorUiSetStyleColorsFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_set_style_colors", as: FnEditorUiSetStyleColors.self)
        editorUiSublimeSetSyntaxYAMLFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_sublime_set_syntax_yaml", as: FnEditorUiSublimeSetSyntaxYAML.self)
        editorUiSublimeSetSyntaxPathFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_sublime_set_syntax_path", as: FnEditorUiSublimeSetSyntaxPath.self)
        editorUiSublimeDisableFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_sublime_disable", as: FnEditorUiSublimeDisable.self)
        editorUiSublimeStyleIdForScopeFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_sublime_style_id_for_scope", as: FnEditorUiSublimeStyleIdForScope.self)
        editorUiSublimeScopeForStyleIdFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_sublime_scope_for_style_id", as: FnEditorUiSublimeScopeForStyleId.self)

        editorUiTreeSitterRustEnableDefaultFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_treesitter_rust_enable_default", as: FnEditorUiTreeSitterRustEnableDefault.self)
        editorUiTreeSitterRustEnableWithQueriesFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_treesitter_rust_enable_with_queries", as: FnEditorUiTreeSitterRustEnableWithQueries.self)
        editorUiTreeSitterDisableFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_treesitter_disable", as: FnEditorUiTreeSitterDisable.self)
        editorUiTreeSitterStyleIdForCaptureFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_treesitter_style_id_for_capture", as: FnEditorUiTreeSitterStyleIdForCapture.self)
        editorUiTreeSitterCaptureForStyleIdFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_treesitter_capture_for_style_id", as: FnEditorUiTreeSitterCaptureForStyleId.self)

        editorUiLspApplyDiagnosticsJSONFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_lsp_apply_diagnostics_json", as: FnEditorUiLspApplyDiagnosticsJSON.self)
        editorUiLspApplySemanticTokensFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens", as: FnEditorUiLspApplySemanticTokens.self)

        editorUiSetRenderMetricsFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_set_render_metrics", as: FnEditorUiSetRenderMetrics.self)
        editorUiSetFontFamiliesCSVFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_set_font_families_csv", as: FnEditorUiSetFontFamiliesCSV.self)
        editorUiSetFontLigaturesEnabledFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_set_font_ligatures_enabled", as: FnEditorUiSetFontLigaturesEnabled.self)
        editorUiSetGutterWidthCellsFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_set_gutter_width_cells", as: FnEditorUiSetGutterWidthCells.self)
        editorUiSetViewportPxFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_set_viewport_px", as: FnEditorUiSetViewportPx.self)
        editorUiScrollByRowsFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_scroll_by_rows", as: FnEditorUiScrollByRows.self)
        editorUiInsertTextFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_insert_text", as: FnEditorUiInsertText.self)
        editorUiBackspaceFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_backspace", as: FnEditorUiBackspace.self)
        editorUiDeleteForwardFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_delete_forward", as: FnEditorUiDeleteForward.self)
        editorUiAddStyleFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_add_style", as: FnEditorUiAddStyle.self)
        editorUiRemoveStyleFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_remove_style", as: FnEditorUiRemoveStyle.self)
        editorUiUndoFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_undo", as: FnEditorUiUndo.self)
        editorUiRedoFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_redo", as: FnEditorUiRedo.self)
        editorUiMoveVisualByRowsFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_move_visual_by_rows", as: FnEditorUiMoveVisualByRows.self)
        editorUiMoveGraphemeLeftFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_move_grapheme_left", as: FnEditorUiMoveGraphemeLeft.self)
        editorUiMoveGraphemeRightFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_move_grapheme_right", as: FnEditorUiMoveGraphemeRight.self)
        editorUiMoveGraphemeLeftAndModifySelectionFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_move_grapheme_left_and_modify_selection", as: FnEditorUiMoveGraphemeLeftAndModifySelection.self)
        editorUiMoveGraphemeRightAndModifySelectionFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_move_grapheme_right_and_modify_selection", as: FnEditorUiMoveGraphemeRightAndModifySelection.self)
        editorUiMoveVisualByRowsAndModifySelectionFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_move_visual_by_rows_and_modify_selection", as: FnEditorUiMoveVisualByRowsAndModifySelection.self)
        editorUiSetMarkedTextFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_set_marked_text", as: FnEditorUiSetMarkedText.self)
        editorUiSetMarkedTextExFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_set_marked_text_ex", as: FnEditorUiSetMarkedTextEx.self)
        editorUiUnmarkTextFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_unmark_text", as: FnEditorUiUnmarkText.self)
        editorUiCommitTextFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_commit_text", as: FnEditorUiCommitText.self)
        editorUiMouseDownFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_mouse_down", as: FnEditorUiMouseDown.self)
        editorUiMouseDraggedFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_mouse_dragged", as: FnEditorUiMouseDragged.self)
        editorUiMouseUpFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_mouse_up", as: FnEditorUiMouseUp.self)
        editorUiRenderRGBAFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_render_rgba", as: FnEditorUiRenderRGBA.self)
        editorUiGetTextFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_get_text", as: FnEditorUiGetText.self)

        editorUiGetSelectionOffsetsFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_get_selection_offsets", as: FnEditorUiGetSelectionOffsets.self)
        editorUiGetSelectionsFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_get_selections", as: FnEditorUiGetSelections.self)
        editorUiSetSelectionsFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_set_selections", as: FnEditorUiSetSelections.self)
        editorUiSetRectSelectionFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_set_rect_selection", as: FnEditorUiSetRectSelection.self)

        editorUiClearSecondarySelectionsFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_clear_secondary_selections", as: FnEditorUiClearSecondarySelections.self)
        editorUiAddCursorAboveFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_add_cursor_above", as: FnEditorUiAddCursorAbove.self)
        editorUiAddCursorBelowFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_add_cursor_below", as: FnEditorUiAddCursorBelow.self)
        editorUiAddNextOccurrenceFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_add_next_occurrence", as: FnEditorUiAddNextOccurrence.self)
        editorUiAddAllOccurrencesFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_add_all_occurrences", as: FnEditorUiAddAllOccurrences.self)
        editorUiSelectWordFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_select_word", as: FnEditorUiSelectWord.self)
        editorUiSelectLineFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_select_line", as: FnEditorUiSelectLine.self)
        editorUiSetLineSelectionOffsetsFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_set_line_selection_offsets", as: FnEditorUiSetLineSelectionOffsets.self)
        editorUiSelectParagraphAtCharOffsetFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_select_paragraph_at_char_offset", as: FnEditorUiSelectParagraphAtCharOffset.self)
        editorUiSetParagraphSelectionOffsetsFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_set_paragraph_selection_offsets", as: FnEditorUiSetParagraphSelectionOffsets.self)
        editorUiExpandSelectionFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_expand_selection", as: FnEditorUiExpandSelection.self)
        editorUiAddCaretAtCharOffsetFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_add_caret_at_char_offset", as: FnEditorUiAddCaretAtCharOffset.self)

        editorUiGetMarkedRangeFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_get_marked_range", as: FnEditorUiGetMarkedRange.self)
        editorUiCharOffsetToViewPointFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_char_offset_to_view_point", as: FnEditorUiCharOffsetToViewPoint.self)
        editorUiViewPointToCharOffsetFn = try dylib.loadSymbol("editor_core_ui_ffi_editor_ui_view_point_to_char_offset", as: FnEditorUiViewPointToCharOffset.self)
    }

    public func versionString() -> String {
        guard let ptr = versionFn() else { return "" }
        defer { stringFreeFn(ptr) }
        return String(cString: ptr)
    }

    func lastErrorMessageString() -> String {
        guard let ptr = lastErrorMessageFn() else { return "" }
        defer { stringFreeFn(ptr) }
        return String(cString: ptr)
    }

    func ensureStatus(_ status: Int32, context: String) throws {
        guard let code = EcuStatus(rawValue: status) else {
            throw EditorCoreUIFFIError.ffiStatus(code: .internal, context: context, message: "unknown status \(status); last_error=\(lastErrorMessageString())")
        }
        guard code == .ok else {
            throw EditorCoreUIFFIError.ffiStatus(code: code, context: context, message: lastErrorMessageString())
        }
    }

    static func defaultLibraryFileName() -> String {
        #if os(macOS)
        return "libeditor_core_ui_ffi.dylib"
        #elseif os(Linux)
        return "libeditor_core_ui_ffi.so"
        #elseif os(Windows)
        return "editor_core_ui_ffi.dll"
        #else
        return "libeditor_core_ui_ffi.dylib"
        #endif
    }

    private static func candidateLibraryPaths(explicitPath: String?) -> [String] {
        if let explicitPath, !explicitPath.isEmpty {
            return [explicitPath]
        }

        let env = ProcessInfo.processInfo.environment
        var candidates: [String] = []

        if let envPath = env["EDITOR_CORE_UI_FFI_DYLIB_PATH"], !envPath.isEmpty {
            candidates.append(envPath)
        }
        if let root = env["EDITOR_CORE_REPO_ROOT"], !root.isEmpty {
            candidates.append((root as NSString).appendingPathComponent("target/debug/\(defaultLibraryFileName())"))
            candidates.append((root as NSString).appendingPathComponent("target/release/\(defaultLibraryFileName())"))
        }

        if let repoRoot = locateRepoRoot() {
            candidates.append((repoRoot as NSString).appendingPathComponent("target/debug/\(defaultLibraryFileName())"))
            candidates.append((repoRoot as NSString).appendingPathComponent("target/release/\(defaultLibraryFileName())"))
        }

        let cwd = FileManager.default.currentDirectoryPath
        candidates.append((cwd as NSString).appendingPathComponent("../target/debug/\(defaultLibraryFileName())"))
        candidates.append((cwd as NSString).appendingPathComponent("../target/release/\(defaultLibraryFileName())"))
        candidates.append((cwd as NSString).appendingPathComponent("target/debug/\(defaultLibraryFileName())"))
        candidates.append((cwd as NSString).appendingPathComponent("target/release/\(defaultLibraryFileName())"))
        candidates.append(defaultLibraryFileName())
        return candidates
    }

    private static func locateRepoRoot() -> String? {
        var current = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
        for _ in 0..<10 {
            let probe = current.appendingPathComponent("crates/editor-core-ui-ffi/Cargo.toml").path
            if FileManager.default.fileExists(atPath: probe) {
                return current.path
            }
            let parent = current.deletingLastPathComponent()
            if parent.path == current.path {
                break
            }
            current = parent
        }
        return nil
    }
}
