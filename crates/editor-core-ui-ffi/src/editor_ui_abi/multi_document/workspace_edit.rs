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
