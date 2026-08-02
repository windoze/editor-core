use super::super::*;
use editor_core::SearchOptions;
use serde_json::json;

fn tab_id_from_raw(tab_id: u64) -> TabId {
    TabId::from_raw(tab_id)
}

fn multi_document_snapshot_value(
    multi: &MultiDocumentEditorUi,
) -> Result<serde_json::Value, String> {
    let tabs = multi
        .tab_ids()
        .into_iter()
        .map(|tab_id| {
            let view_count = multi
                .view_count(tab_id)
                .ok_or_else(|| format!("unknown tab id {}", tab_id.get()))?;
            let active_view_index = multi
                .active_view_index(tab_id)
                .ok_or_else(|| format!("unknown tab id {}", tab_id.get()))?;
            Ok(json!({
                "id": tab_id.get(),
                "title": multi.tab_title(tab_id),
                "is_preview": multi.is_preview_tab(tab_id).unwrap_or(false),
                "is_active": multi.active_tab_id() == Some(tab_id),
                "is_modified": multi
                    .is_tab_modified(tab_id)
                    .map_err(|err| err.to_string())?,
                "view_count": view_count,
                "active_view_index": active_view_index,
            }))
        })
        .collect::<Result<Vec<_>, String>>()?;

    Ok(json!({
        "active_tab_id": multi.active_tab_id().map(|id| id.get()),
        "tabs": tabs,
    }))
}

fn multi_document_snapshot_json(multi: &MultiDocumentEditorUi) -> Result<String, String> {
    Ok(multi_document_snapshot_value(multi)?.to_string())
}

/// Create a new multi-document UI orchestrator handle.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_new() -> *mut MultiDocumentEditorUi {
    match ffi_catch(|| Ok(Box::into_raw(Box::new(MultiDocumentEditorUi::new())))) {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Free a multi-document UI orchestrator handle.
///
/// # Safety
///
/// `multi` must be a valid pointer returned by `editor_core_ui_ffi_multi_document_new`, or null.
/// The pointer must not be used after this call.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_multi_document_free(multi: *mut MultiDocumentEditorUi) {
    if multi.is_null() {
        return;
    }
    unsafe {
        drop(Box::from_raw(multi));
    }
}

/// Open a normal tab.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_open_tab(
    multi: *mut MultiDocumentEditorUi,
    initial_text_utf8: *const c_char,
    viewport_width_cells: u32,
    out_tab_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let initial = require_str(initial_text_utf8, "initial_text_utf8")?;
        let viewport_width_cells = u32_to_usize(viewport_width_cells, "viewport_width_cells")?;
        let out_tab_id = require_out_mut(out_tab_id, "out_tab_id")?;
        let tab_id = multi.open_tab(initial, viewport_width_cells);
        *out_tab_id = tab_id.get();
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Open or reuse a preview tab.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_open_preview_tab(
    multi: *mut MultiDocumentEditorUi,
    initial_text_utf8: *const c_char,
    viewport_width_cells: u32,
    out_tab_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let initial = require_str(initial_text_utf8, "initial_text_utf8")?;
        let viewport_width_cells = u32_to_usize(viewport_width_cells, "viewport_width_cells")?;
        let out_tab_id = require_out_mut(out_tab_id, "out_tab_id")?;
        let tab_id = multi.open_preview_tab(initial, viewport_width_cells);
        *out_tab_id = tab_id.get();
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Return the active tab id, if any.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_active_tab_id(
    multi: *mut MultiDocumentEditorUi,
    out_has_active: *mut u8,
    out_tab_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let out_has_active = require_out_mut(out_has_active, "out_has_active")?;
        let out_tab_id = require_out_mut(out_tab_id, "out_tab_id")?;
        if let Some(tab_id) = multi.active_tab_id() {
            *out_has_active = 1;
            *out_tab_id = tab_id.get();
        } else {
            *out_has_active = 0;
            *out_tab_id = 0;
        }
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Return a JSON snapshot of tabs and active state.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_snapshot_json(
    multi: *mut MultiDocumentEditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi_document_snapshot_json(multi)
    }) {
        Ok(json) => {
            clear_last_error();
            make_c_string_ptr(json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Return the active view text for a tab.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_tab_text(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi
            .tab_text(tab_id_from_raw(tab_id))
            .map_err(map_ui_error)
    }) {
        Ok(text) => {
            clear_last_error();
            make_c_string_ptr(text)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Replace the active view text for a tab.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_replace_tab_text(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
    text_utf8: *const c_char,
    mark_saved: u8,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let text = require_str(text_utf8, "text_utf8")?;
        multi
            .replace_tab_text(tab_id_from_raw(tab_id), text, mark_saved != 0)
            .map_err(map_ui_error)?;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Return whether a tab's active view is modified.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_is_tab_modified(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
    out_modified: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let out_modified = require_out_mut(out_modified, "out_modified")?;
        *out_modified = u8::from(
            multi
                .is_tab_modified(tab_id_from_raw(tab_id))
                .map_err(map_ui_error)?,
        );
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Mark a tab's active view as saved.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_mark_tab_saved(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi
            .mark_tab_saved(tab_id_from_raw(tab_id))
            .map_err(map_ui_error)?;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Set the active tab.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_set_active_tab(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi
            .set_active_tab(tab_id_from_raw(tab_id))
            .map_err(map_ui_error)?;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Set or clear a tab title.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_set_tab_title(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
    title_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let title = if title_utf8.is_null() {
            None
        } else {
            Some(require_str(title_utf8, "title_utf8")?.to_string())
        };
        multi
            .set_tab_title(tab_id_from_raw(tab_id), title)
            .map_err(map_ui_error)?;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Return whether a tab is a preview tab.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_is_preview_tab(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
    out_is_preview: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let out_is_preview = require_out_mut(out_is_preview, "out_is_preview")?;
        let tab_id = tab_id_from_raw(tab_id);
        let is_preview = multi
            .is_preview_tab(tab_id)
            .ok_or_else(|| format!("unknown tab id {}", tab_id.get()))?;
        *out_is_preview = u8::from(is_preview);
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Pin a preview tab.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_pin_tab(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi
            .pin_tab(tab_id_from_raw(tab_id))
            .map_err(map_ui_error)?;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Close a tab.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_close_tab(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
    out_closed: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let out_closed = require_out_mut(out_closed, "out_closed")?;
        *out_closed = u8::from(multi.close_tab(tab_id_from_raw(tab_id)));
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Close all tabs.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_close_all_tabs(
    multi: *mut MultiDocumentEditorUi,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi.close_all_tabs();
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Close all tabs except `tab_id`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_close_other_tabs(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
    out_closed_count: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let out_closed_count = require_out_mut(out_closed_count, "out_closed_count")?;
        let closed = multi
            .close_other_tabs(tab_id_from_raw(tab_id))
            .map_err(map_ui_error)?;
        *out_closed_count = usize_to_u32(closed, "closed_count")?;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Close tabs to the right of `tab_id`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_close_tabs_to_right(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
    out_closed_count: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let out_closed_count = require_out_mut(out_closed_count, "out_closed_count")?;
        let closed = multi
            .close_tabs_to_right(tab_id_from_raw(tab_id))
            .map_err(map_ui_error)?;
        *out_closed_count = usize_to_u32(closed, "closed_count")?;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Move a tab in the current tab order. Returns whether the tab was moved.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_move_tab_index(
    multi: *mut MultiDocumentEditorUi,
    from_tab_index: u32,
    to_tab_index: u32,
    out_moved: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let from_tab_index = u32_to_usize(from_tab_index, "from_tab_index")?;
        let to_tab_index = u32_to_usize(to_tab_index, "to_tab_index")?;
        let out_moved = require_out_mut(out_moved, "out_moved")?;
        let moved = multi
            .move_tab_index(from_tab_index, to_tab_index)
            .map_err(map_ui_error)?;
        *out_moved = u8::from(moved);
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Split a tab by cloning its active view.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_split_tab(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
    viewport_width_cells: u32,
    out_view_index: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let viewport_width_cells = u32_to_usize(viewport_width_cells, "viewport_width_cells")?;
        let out_view_index = require_out_mut(out_view_index, "out_view_index")?;
        let view_index = multi
            .split_tab(tab_id_from_raw(tab_id), viewport_width_cells)
            .map_err(map_ui_error)?;
        *out_view_index = usize_to_u32(view_index, "view_index")?;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Set the active view index for a tab.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_set_active_view_index(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
    view_index: u32,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let view_index = u32_to_usize(view_index, "view_index")?;
        multi
            .set_active_view_index(tab_id_from_raw(tab_id), view_index)
            .map_err(map_ui_error)?;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Close a view in a tab. The last remaining view is kept.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_close_view_index(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
    view_index: u32,
    out_closed: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let view_index = u32_to_usize(view_index, "view_index")?;
        let out_closed = require_out_mut(out_closed, "out_closed")?;
        let closed = multi
            .close_view_index(tab_id_from_raw(tab_id), view_index)
            .map_err(map_ui_error)?;
        *out_closed = u8::from(closed);
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Move a view in a tab. Returns whether the view was moved.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_move_view_index(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
    from_view_index: u32,
    to_view_index: u32,
    out_moved: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let from_view_index = u32_to_usize(from_view_index, "from_view_index")?;
        let to_view_index = u32_to_usize(to_view_index, "to_view_index")?;
        let out_moved = require_out_mut(out_moved, "out_moved")?;
        let moved = multi
            .move_view_index(tab_id_from_raw(tab_id), from_view_index, to_view_index)
            .map_err(map_ui_error)?;
        *out_moved = u8::from(moved);
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Return the number of views in a tab.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_view_count(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
    out_view_count: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let out_view_count = require_out_mut(out_view_count, "out_view_count")?;
        let tab_id = tab_id_from_raw(tab_id);
        let view_count = multi
            .view_count(tab_id)
            .ok_or_else(|| format!("unknown tab id {}", tab_id.get()))?;
        *out_view_count = usize_to_u32(view_count, "view_count")?;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Search all open tabs and return JSON results.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_search_all_tabs_json(
    multi: *mut MultiDocumentEditorUi,
    query_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let options = SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        let results = multi
            .search_all_tabs(query, options)
            .map_err(|err| format!("search failed: {err}"))?;
        let value = json!({
            "results": results
                .iter()
                .map(|result| json!({
                    "tab_id": result.tab_id.get(),
                    "matches": result
                        .matches
                        .iter()
                        .map(|m| json!({ "start": m.start, "end": m.end }))
                        .collect::<Vec<_>>(),
                }))
                .collect::<Vec<_>>(),
        });
        Ok(value.to_string())
    }) {
        Ok(json) => {
            clear_last_error();
            make_c_string_ptr(json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Merge an LSP workspace/diagnostic result JSON payload and return the normalized snapshot JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_apply_workspace_diagnostics_json(
    multi: *mut MultiDocumentEditorUi,
    result_json_utf8: *const c_char,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let result_json = require_str(result_json_utf8, "result_json_utf8")?;
        multi
            .apply_workspace_diagnostics_json(result_json)
            .map_err(map_ui_error)?;
        multi
            .workspace_diagnostics_snapshot_json()
            .map_err(map_ui_error)
    }) {
        Ok(json) => {
            clear_last_error();
            make_c_string_ptr(json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Return the current normalized workspace diagnostics snapshot JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_workspace_diagnostics_snapshot_json(
    multi: *mut MultiDocumentEditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi
            .workspace_diagnostics_snapshot_json()
            .map_err(map_ui_error)
    }) {
        Ok(json) => {
            clear_last_error();
            make_c_string_ptr(json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Return the current workspace diagnostic marker projection JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_workspace_diagnostic_markers_json(
    multi: *mut MultiDocumentEditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi
            .workspace_diagnostic_markers_json()
            .map_err(map_ui_error)
    }) {
        Ok(json) => {
            clear_last_error();
            make_c_string_ptr(json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Return previous-result ids for the next LSP workspace/diagnostic request.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_workspace_diagnostics_previous_result_ids_json(
    multi: *mut MultiDocumentEditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi
            .workspace_diagnostics_previous_result_ids_json()
            .map_err(map_ui_error)
    }) {
        Ok(json) => {
            clear_last_error();
            make_c_string_ptr(json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Return latest core-owned workspace diagnostics event sequence.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_multi_document_workspace_diagnostics_latest_event_sequence(
    multi: *mut MultiDocumentEditorUi,
    out_sequence: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        if out_sequence.is_null() {
            return Err(invalid_argument("out_sequence is null"));
        }
        unsafe {
            *out_sequence = multi.workspace_diagnostics_latest_event_sequence();
        }
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Return core-owned workspace diagnostics events newer than `after_sequence`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_workspace_diagnostics_events_json(
    multi: *mut MultiDocumentEditorUi,
    after_sequence: u64,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi
            .workspace_diagnostics_events_json(after_sequence)
            .map_err(map_ui_error)
    }) {
        Ok(json) => {
            clear_last_error();
            make_c_string_ptr(json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Refresh and return latest multi-document LSP result event sequence.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_multi_document_lsp_result_events_latest_sequence(
    multi: *mut MultiDocumentEditorUi,
    out_sequence: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        if out_sequence.is_null() {
            return Err(invalid_argument("out_sequence is null"));
        }
        unsafe {
            *out_sequence = multi.lsp_result_events_latest_sequence();
        }
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Refresh and return multi-document LSP result events newer than `after_sequence`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_lsp_result_events_json(
    multi: *mut MultiDocumentEditorUi,
    after_sequence: u64,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi
            .lsp_result_events_json(after_sequence)
            .map_err(map_ui_error)
    }) {
        Ok(json) => {
            clear_last_error();
            make_c_string_ptr(json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Refresh and return latest multi-document LSP request event sequence.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_multi_document_lsp_request_events_latest_sequence(
    multi: *mut MultiDocumentEditorUi,
    out_sequence: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        if out_sequence.is_null() {
            return Err(invalid_argument("out_sequence is null"));
        }
        unsafe {
            *out_sequence = multi.lsp_request_events_latest_sequence();
        }
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Refresh and return multi-document LSP request events newer than `after_sequence`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_lsp_request_events_json(
    multi: *mut MultiDocumentEditorUi,
    after_sequence: u64,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi
            .lsp_request_events_json(after_sequence)
            .map_err(map_ui_error)
    }) {
        Ok(json) => {
            clear_last_error();
            make_c_string_ptr(json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Clear the multi-document workspace diagnostics store.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_clear_workspace_diagnostics(
    multi: *mut MultiDocumentEditorUi,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi.clear_workspace_diagnostics();
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}
