use super::*;

/// Replace the workspace root URI list owned by the multi-document model.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_set_workspace_roots_json(
    multi: *mut MultiDocumentEditorUi,
    roots_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let roots_json = require_str(roots_json_utf8, "roots_json_utf8")?;
        let roots: Vec<String> = serde_json::from_str(roots_json).map_err(|err| {
            invalid_argument(format!(
                "roots_json_utf8 must be a JSON string array: {err}"
            ))
        })?;
        multi.set_workspace_roots(roots);
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Replace the workspace root URI list and return the LSP workspace folder diff as JSON.
///
/// Returns `{ "added": WorkspaceFolder[], "removed": WorkspaceFolder[] }`, where each
/// `WorkspaceFolder` has `{ "uri": string, "name": string }`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_set_workspace_roots_with_change_json(
    multi: *mut MultiDocumentEditorUi,
    roots_json_utf8: *const c_char,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let roots_json = require_str(roots_json_utf8, "roots_json_utf8")?;
        let roots: Vec<String> = serde_json::from_str(roots_json).map_err(|err| {
            invalid_argument(format!(
                "roots_json_utf8 must be a JSON string array: {err}"
            ))
        })?;
        serde_json::to_string(&multi.set_workspace_roots_with_change(roots))
            .map_err(|err| err.to_string())
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
