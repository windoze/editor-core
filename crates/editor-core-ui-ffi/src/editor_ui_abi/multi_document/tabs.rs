use super::*;

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

/// Return the document URI associated with a tab, if any.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_tab_document_uri(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
    out_uri_utf8: *mut *mut c_char,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let out_uri = require_out_mut(out_uri_utf8, "out_uri_utf8")?;
        let tab_id = tab_id_from_raw(tab_id);
        if multi.is_preview_tab(tab_id).is_none() {
            return Err(format!("unknown tab id {}", tab_id.get()));
        }
        *out_uri = multi
            .tab_document_uri(tab_id)
            .map(|uri| make_c_string_ptr(uri.to_string()))
            .unwrap_or(ptr::null_mut());
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Set or clear the document URI associated with a tab.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_set_tab_document_uri(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
    document_uri_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let document_uri = if document_uri_utf8.is_null() {
            None
        } else {
            Some(require_str(document_uri_utf8, "document_uri_utf8")?.to_string())
        };
        multi
            .set_tab_document_uri(tab_id_from_raw(tab_id), document_uri)
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
