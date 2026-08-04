import CEditorCoreUIFFI
import Foundation
import Metal

extension EditorUI {
    // MARK: - Bookmarks / marks / jump list

    /// Toggle a bookmark at the current cursor line.
    ///
    /// Returns `true` if a bookmark was added, or `false` if an existing bookmark on that line was removed.
    @discardableResult
    public func toggleBookmarkAtCursorLine() throws -> Bool {
        var out: UInt8 = 0
        let status = editor_core_ui_ffi_editor_ui_toggle_bookmark_at_cursor_line(handle, &out)
        try library.ensureStatus(status, context: "editor_ui_toggle_bookmark_at_cursor_line")
        return out != 0
    }

    /// Move the caret to the next bookmark (wraps to the first bookmark).
    public func goToNextBookmark() throws {
        let status = editor_core_ui_ffi_editor_ui_goto_next_bookmark(handle)
        try library.ensureStatus(status, context: "editor_ui_goto_next_bookmark")
    }

    /// Move the caret to the previous bookmark (wraps to the last bookmark).
    public func goToPrevBookmark() throws {
        let status = editor_core_ui_ffi_editor_ui_goto_prev_bookmark(handle)
        try library.ensureStatus(status, context: "editor_ui_goto_prev_bookmark")
    }

    /// Set (or replace) a named mark at the current caret position.
    public func setMarkAtCursor(_ name: String) throws {
        let status: Int32 = name.withCString { cstr in
            editor_core_ui_ffi_editor_ui_set_mark_at_cursor(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_set_mark_at_cursor")
    }

    /// Move the caret to a named mark (if present).
    public func goToMark(_ name: String) throws {
        let status: Int32 = name.withCString { cstr in
            editor_core_ui_ffi_editor_ui_goto_mark(handle, cstr)
        }
        try library.ensureStatus(status, context: "editor_ui_goto_mark")
    }

    /// Record the current caret location into the jump list.
    public func pushJumpLocation() throws {
        let status = editor_core_ui_ffi_editor_ui_push_jump_location(handle)
        try library.ensureStatus(status, context: "editor_ui_push_jump_location")
    }

    /// Jump back in the jump list (no-op when empty).
    public func jumpBack() throws {
        let status = editor_core_ui_ffi_editor_ui_jump_back(handle)
        try library.ensureStatus(status, context: "editor_ui_jump_back")
    }

    /// Jump forward in the jump list (no-op when empty).
    public func jumpForward() throws {
        let status = editor_core_ui_ffi_editor_ui_jump_forward(handle)
        try library.ensureStatus(status, context: "editor_ui_jump_forward")
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
}
