use super::*;
use serde_json::{Value, json};
use std::ffi::CStr;

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

/// Preview, apply, or undo an LSP WorkspaceEdit transaction and return a structured envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_workspace_edit_transaction_envelope_json(
    multi: *mut MultiDocumentEditorUi,
    operation_utf8: *const c_char,
    workspace_edit_json_utf8: *const c_char,
) -> *mut c_char {
    let operation_for_error = best_effort_operation(operation_utf8);
    let envelope = match ffi_catch(|| {
        let operation = require_str(operation_utf8, "operation_utf8")?;
        let multi = require_mut(multi, "multi")?;
        let result_json =
            workspace_edit_transaction_json(multi, operation, workspace_edit_json_utf8)?;
        workspace_edit_transaction_envelope_success(operation, result_json)
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            workspace_edit_transaction_envelope_error(
                operation_for_error.as_deref(),
                status,
                message,
            )
        }
    };
    make_c_string_ptr(envelope)
}

fn best_effort_operation(operation_utf8: *const c_char) -> Option<String> {
    if operation_utf8.is_null() {
        return None;
    }
    Some(
        unsafe { CStr::from_ptr(operation_utf8) }
            .to_string_lossy()
            .into_owned(),
    )
}

fn workspace_edit_transaction_json(
    multi: &mut MultiDocumentEditorUi,
    operation: &str,
    workspace_edit_json_utf8: *const c_char,
) -> Result<String, String> {
    match operation {
        "preview" => {
            let workspace_edit_json =
                require_str(workspace_edit_json_utf8, "workspace_edit_json_utf8")?;
            multi
                .preview_workspace_edit_transaction_json(workspace_edit_json)
                .map_err(map_ui_error)
        }
        "apply" => {
            let workspace_edit_json =
                require_str(workspace_edit_json_utf8, "workspace_edit_json_utf8")?;
            multi
                .apply_workspace_edit_transaction_json(workspace_edit_json)
                .map_err(map_ui_error)
        }
        "undo" => multi
            .undo_last_workspace_edit_transaction_json()
            .map_err(map_ui_error),
        _ => Err(invalid_argument(format!(
            "unknown workspace edit transaction operation {operation:?}"
        ))),
    }
}

fn workspace_edit_transaction_envelope_success(
    operation: &str,
    result_json: String,
) -> Result<String, String> {
    let value = serde_json::from_str::<Value>(&result_json).map_err(|err| {
        format!(
            "stored WorkspaceEdit transaction JSON for operation {operation:?} is invalid: {err}"
        )
    })?;
    Ok(json!({
        "ok": true,
        "operation": operation,
        "status": "success",
        "value": value,
        "error": Value::Null,
        "version": ECU_ABI_VERSION,
    })
    .to_string())
}

fn workspace_edit_transaction_envelope_error(
    operation: Option<&str>,
    status: c_int,
    message: String,
) -> String {
    json!({
        "ok": false,
        "operation": operation,
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
