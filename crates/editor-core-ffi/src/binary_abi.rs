use super::*;

/// Encode semantic `(token_type, token_modifiers)` pair into default style id.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_encode_semantic_style_id(
    token_type: u32,
    token_modifiers: u32,
) -> u32 {
    match ffi_catch(|| Ok(encode_semantic_style_id(token_type, token_modifiers))) {
        Ok(v) => {
            clear_last_error();
            v
        }
        Err(err) => {
            set_last_error(err);
            0
        }
    }
}

/// Return ABI version for typed/binary APIs.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_abi_version() -> u32 {
    ECF_ABI_VERSION
}

/// Fill basic document stats.
///
/// # Safety
///
/// `state` must be a valid pointer to an `EcfEditorState`.
/// `out_stats` must be a valid pointer to an `EcfDocumentStats` struct.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_editor_get_document_stats(
    state: *const EcfEditorState,
    out_stats: *mut EcfDocumentStats,
) -> i32 {
    status_result(|| {
        let state =
            require_ref(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        if out_stats.is_null() {
            return Err((EcfStatus::InvalidArgument, "out_stats is null".to_string()));
        }

        let doc = state.inner.get_document_state();
        let stats = EcfDocumentStats {
            abi_version: ECF_ABI_VERSION,
            struct_size: size_of::<EcfDocumentStats>() as u32,
            line_count: doc.line_count as u64,
            char_count: doc.char_count as u64,
            byte_count: doc.byte_count as u64,
            is_modified: if doc.is_modified { 1 } else { 0 },
            reserved0: [0; 7],
            version: doc.version,
        };

        // SAFETY: non-null checked; caller provides writable memory for output struct.
        unsafe {
            *out_stats = stats;
        }
        Ok(())
    })
}

/// Insert UTF-8 text at current selection/cursor(s).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_insert_text_utf8(
    state: *mut EcfEditorState,
    bytes: *const u8,
    len: u32,
) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let text = require_utf8_bytes(bytes, len, "bytes")?.to_string();
        state
            .inner
            .execute(Command::Edit(EditCommand::InsertText { text }))
            .map_err(|err| {
                (
                    EcfStatus::CommandFailed,
                    format!("insert_text failed: {err}"),
                )
            })?;
        Ok(())
    })
}

/// Backspace at current selection/cursor(s).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_backspace(state: *mut EcfEditorState) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        state
            .inner
            .execute(Command::Edit(EditCommand::Backspace))
            .map_err(|err| (EcfStatus::CommandFailed, format!("backspace failed: {err}")))?;
        Ok(())
    })
}

/// Delete forward at current selection/cursor(s).
///
/// # Safety
///
/// `state` must be a valid pointer to an `EcfEditorState`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ffi_editor_delete_forward(state: *mut EcfEditorState) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        state
            .inner
            .execute(Command::Edit(EditCommand::DeleteForward))
            .map_err(|err| {
                (
                    EcfStatus::CommandFailed,
                    format!("delete_forward failed: {err}"),
                )
            })?;
        Ok(())
    })
}

/// Undo one change group.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_undo(state: *mut EcfEditorState) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        state
            .inner
            .execute(Command::Edit(EditCommand::Undo))
            .map_err(|err| (EcfStatus::CommandFailed, format!("undo failed: {err}")))?;
        Ok(())
    })
}

/// Redo one change group.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_redo(state: *mut EcfEditorState) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        state
            .inner
            .execute(Command::Edit(EditCommand::Redo))
            .map_err(|err| (EcfStatus::CommandFailed, format!("redo failed: {err}")))?;
        Ok(())
    })
}

/// Move cursor to a logical `(line, column)` position.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_move_to(
    state: *mut EcfEditorState,
    line: u32,
    column: u32,
) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let line = status_usize_from_u32(line, "line")?;
        let column = status_usize_from_u32(column, "column")?;
        state
            .inner
            .execute(Command::Cursor(CursorCommand::MoveTo { line, column }))
            .map_err(|err| (EcfStatus::CommandFailed, format!("move_to failed: {err}")))?;
        Ok(())
    })
}

/// Move cursor by deltas in logical line/column space.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_move_by(
    state: *mut EcfEditorState,
    delta_line: i32,
    delta_column: i32,
) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        state
            .inner
            .execute(Command::Cursor(CursorCommand::MoveBy {
                delta_line: delta_line as isize,
                delta_column: delta_column as isize,
            }))
            .map_err(|err| (EcfStatus::CommandFailed, format!("move_by failed: {err}")))?;
        Ok(())
    })
}

/// Set primary selection with explicit direction (`0=forward`, `1=backward`).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_set_selection(
    state: *mut EcfEditorState,
    start_line: u32,
    start_column: u32,
    end_line: u32,
    end_column: u32,
    direction: u8,
) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let start_line = status_usize_from_u32(start_line, "start_line")?;
        let start_column = status_usize_from_u32(start_column, "start_column")?;
        let end_line = status_usize_from_u32(end_line, "end_line")?;
        let end_column = status_usize_from_u32(end_column, "end_column")?;
        let direction = match direction {
            0 => SelectionDirection::Forward,
            1 => SelectionDirection::Backward,
            _ => {
                return Err((
                    EcfStatus::InvalidArgument,
                    "direction must be 0 (forward) or 1 (backward)".to_string(),
                ));
            }
        };

        let selection = Selection {
            start: Position::new(start_line, start_column),
            end: Position::new(end_line, end_column),
            direction,
        };

        state
            .inner
            .execute(Command::Cursor(CursorCommand::SetSelections {
                selections: vec![selection],
                primary_index: 0,
            }))
            .map_err(|err| {
                (
                    EcfStatus::CommandFailed,
                    format!("set_selection failed: {err}"),
                )
            })?;
        Ok(())
    })
}

/// Clear selection (collapse to caret).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_clear_selection(state: *mut EcfEditorState) -> i32 {
    status_result(|| {
        let state =
            require_mut(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        state
            .inner
            .execute(Command::Cursor(CursorCommand::ClearSelection))
            .map_err(|err| {
                (
                    EcfStatus::CommandFailed,
                    format!("clear_selection failed: {err}"),
                )
            })?;
        Ok(())
    })
}

/// Workspace variant: insert UTF-8 text in a specific view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_insert_text_utf8(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    bytes: *const u8,
    len: u32,
) -> i32 {
    status_result(|| {
        let workspace = require_mut(workspace, "workspace")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let text = require_utf8_bytes(bytes, len, "bytes")?.to_string();
        workspace
            .inner
            .execute(
                ViewId::from_raw(view_id),
                Command::Edit(EditCommand::InsertText { text }),
            )
            .map_err(|err| {
                (
                    EcfStatus::CommandFailed,
                    format!("workspace insert_text failed: {err:?}"),
                )
            })?;
        Ok(())
    })
}

/// Workspace variant: move cursor in a specific view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_move_to(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    line: u32,
    column: u32,
) -> i32 {
    status_result(|| {
        let workspace = require_mut(workspace, "workspace")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let line = status_usize_from_u32(line, "line")?;
        let column = status_usize_from_u32(column, "column")?;
        workspace
            .inner
            .execute(
                ViewId::from_raw(view_id),
                Command::Cursor(CursorCommand::MoveTo { line, column }),
            )
            .map_err(|err| {
                (
                    EcfStatus::CommandFailed,
                    format!("workspace move_to failed: {err:?}"),
                )
            })?;
        Ok(())
    })
}

/// Workspace variant: backspace in a specific view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_backspace(
    workspace: *mut EcfWorkspace,
    view_id: u64,
) -> i32 {
    status_result(|| {
        let workspace = require_mut(workspace, "workspace")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        workspace
            .inner
            .execute(
                ViewId::from_raw(view_id),
                Command::Edit(EditCommand::Backspace),
            )
            .map_err(|err| {
                (
                    EcfStatus::CommandFailed,
                    format!("workspace backspace failed: {err:?}"),
                )
            })?;
        Ok(())
    })
}

/// Retrieve styled viewport snapshot as ABI-v1 binary blob.
///
/// Returns `ECF_ERR_BUFFER_TOO_SMALL` and writes required size to `out_len` when `out_cap` is
/// insufficient (or `out_buf` is null).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_editor_get_viewport_blob(
    state: *const EcfEditorState,
    start_visual_row: u32,
    row_count: u32,
    out_buf: *mut u8,
    out_cap: u32,
    out_len: *mut u32,
) -> i32 {
    status_result(|| {
        let state =
            require_ref(state, "state").map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let start_visual_row = status_usize_from_u32(start_visual_row, "start_visual_row")?;
        let row_count = status_usize_from_u32(row_count, "row_count")?;
        let grid = state
            .inner
            .get_viewport_content_styled(start_visual_row, row_count);
        let blob = build_viewport_blob(&grid)?;
        copy_blob_to_output(&blob, out_buf, out_cap, out_len)
    })
}

/// Workspace variant of `editor_core_ffi_editor_get_viewport_blob`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_workspace_get_viewport_blob(
    workspace: *mut EcfWorkspace,
    view_id: u64,
    start_visual_row: u32,
    row_count: u32,
    out_buf: *mut u8,
    out_cap: u32,
    out_len: *mut u32,
) -> i32 {
    status_result(|| {
        let workspace = require_mut(workspace, "workspace")
            .map_err(|e| (EcfStatus::InvalidArgument, e.to_string()))?;
        let start_visual_row = status_usize_from_u32(start_visual_row, "start_visual_row")?;
        let row_count = status_usize_from_u32(row_count, "row_count")?;
        let grid = workspace
            .inner
            .get_viewport_content_styled(ViewId::from_raw(view_id), start_visual_row, row_count)
            .map_err(|err| {
                (
                    EcfStatus::NotFound,
                    format!("get_viewport_content_styled failed: {err:?}"),
                )
            })?;
        let blob = build_viewport_blob(&grid)?;
        copy_blob_to_output(&blob, out_buf, out_cap, out_len)
    })
}

/// ABI-v1 alias: see `editor_core_ffi_abi_version`.
#[unsafe(no_mangle)]
pub extern "C" fn ecf_abi_version() -> u32 {
    editor_core_ffi_abi_version()
}

/// ABI-v1 alias: see `editor_core_ffi_editor_insert_text_utf8`.
#[unsafe(no_mangle)]
pub extern "C" fn ecf_editor_insert_text_utf8(
    state: *mut EcfEditorState,
    bytes: *const u8,
    len: u32,
) -> i32 {
    editor_core_ffi_editor_insert_text_utf8(state, bytes, len)
}

/// ABI-v1 alias: see `editor_core_ffi_editor_move_to`.
#[unsafe(no_mangle)]
pub extern "C" fn ecf_editor_move_to(state: *mut EcfEditorState, line: u32, column: u32) -> i32 {
    editor_core_ffi_editor_move_to(state, line, column)
}

/// ABI-v1 alias: see `editor_core_ffi_editor_backspace`.
#[unsafe(no_mangle)]
pub extern "C" fn ecf_editor_backspace(state: *mut EcfEditorState) -> i32 {
    editor_core_ffi_editor_backspace(state)
}

/// ABI-v1 alias: see `editor_core_ffi_editor_get_viewport_blob`.
#[unsafe(no_mangle)]
pub extern "C" fn ecf_editor_get_viewport_blob(
    state: *const EcfEditorState,
    start_visual_row: u32,
    row_count: u32,
    out_buf: *mut u8,
    out_cap: u32,
    out_len: *mut u32,
) -> i32 {
    editor_core_ffi_editor_get_viewport_blob(
        state,
        start_visual_row,
        row_count,
        out_buf,
        out_cap,
        out_len,
    )
}
