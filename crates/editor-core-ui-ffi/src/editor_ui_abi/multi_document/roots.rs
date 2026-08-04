use super::*;
use serde_json::{Value, json};

fn parse_workspace_roots(roots_json_utf8: *const c_char) -> Result<Vec<String>, String> {
    let roots_json = require_str(roots_json_utf8, "roots_json_utf8")?;
    serde_json::from_str(roots_json).map_err(|err| {
        invalid_argument(format!(
            "roots_json_utf8 must be a JSON string array: {err}"
        ))
    })
}

fn workspace_roots_change_value(
    multi: &mut MultiDocumentEditorUi,
    roots: Vec<String>,
) -> Result<Value, String> {
    serde_json::to_value(multi.set_workspace_roots_with_change(roots))
        .map_err(|err| err.to_string())
}

/// Replace the workspace root URI list owned by the multi-document model.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_set_workspace_roots_json(
    multi: *mut MultiDocumentEditorUi,
    roots_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let roots = parse_workspace_roots(roots_json_utf8)?;
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
        let roots = parse_workspace_roots(roots_json_utf8)?;
        Ok(workspace_roots_change_value(multi, roots)?.to_string())
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

/// Replace the workspace root URI list and return the folder diff through a structured envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_set_workspace_roots_with_change_envelope_json(
    multi: *mut MultiDocumentEditorUi,
    roots_json_utf8: *const c_char,
) -> *mut c_char {
    let envelope = match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let roots = parse_workspace_roots(roots_json_utf8)?;
        let value = workspace_roots_change_value(multi, roots)?;
        Ok(workspace_roots_change_envelope_success(value))
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            workspace_roots_change_envelope_error(status, message)
        }
    };
    make_c_string_ptr(envelope)
}

fn workspace_roots_change_envelope_success(value: Value) -> String {
    json!({
        "ok": true,
        "status": "success",
        "value": value,
        "error": Value::Null,
        "version": ECU_ABI_VERSION,
    })
    .to_string()
}

fn workspace_roots_change_envelope_error(status: c_int, message: String) -> String {
    json!({
        "ok": false,
        "status": "error",
        "value": Value::Null,
        "error": {
            "code": status_code_name(status),
            "status": status,
            "message": message,
        },
        "version": ECU_ABI_VERSION,
    })
    .to_string()
}
