use super::*;

/// Return the current workspace outline snapshot JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_workspace_outline_snapshot_json(
    multi: *mut MultiDocumentEditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi
            .workspace_outline_snapshot_json()
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

/// Apply an LSP textDocument/documentSymbol result JSON payload to a tab document.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_apply_tab_document_symbols_json(
    multi: *mut MultiDocumentEditorUi,
    tab_id: u64,
    result_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let result_json = require_str(result_json_utf8, "result_json_utf8")?;
        multi
            .apply_tab_document_symbols_json(tab_id_from_raw(tab_id), result_json)
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
