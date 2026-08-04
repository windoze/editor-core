use super::*;

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
