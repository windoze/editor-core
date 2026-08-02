use super::*;

/// Preview applying an LSP WorkspaceEdit to matching open tabs.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_preview_workspace_edit_transaction_json(
    multi: *mut MultiDocumentEditorUi,
    workspace_edit_json_utf8: *const c_char,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let workspace_edit_json =
            require_str(workspace_edit_json_utf8, "workspace_edit_json_utf8")?;
        multi
            .preview_workspace_edit_transaction_json(workspace_edit_json)
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

/// Apply an LSP WorkspaceEdit to matching open tabs.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_apply_workspace_edit_transaction_json(
    multi: *mut MultiDocumentEditorUi,
    workspace_edit_json_utf8: *const c_char,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let workspace_edit_json =
            require_str(workspace_edit_json_utf8, "workspace_edit_json_utf8")?;
        multi
            .apply_workspace_edit_transaction_json(workspace_edit_json)
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

/// Undo the most recent successful WorkspaceEdit transaction.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_undo_last_workspace_edit_transaction_json(
    multi: *mut MultiDocumentEditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi
            .undo_last_workspace_edit_transaction_json()
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

/// Return latest WorkspaceEdit transaction event sequence.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_multi_document_workspace_edit_transaction_events_latest_sequence(
    multi: *mut MultiDocumentEditorUi,
    out_sequence: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        if out_sequence.is_null() {
            return Err(invalid_argument("out_sequence is null"));
        }
        unsafe {
            *out_sequence = multi.workspace_edit_transaction_events_latest_sequence();
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

/// Return WorkspaceEdit transaction events newer than `after_sequence`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_workspace_edit_transaction_events_json(
    multi: *mut MultiDocumentEditorUi,
    after_sequence: u64,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi
            .workspace_edit_transaction_events_json(after_sequence)
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
