use super::*;
use serde_json::{Value, json};
use std::ffi::CStr;

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

/// Apply, read, or project workspace diagnostics and return a structured envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_workspace_diagnostics_envelope_json(
    multi: *mut MultiDocumentEditorUi,
    operation_utf8: *const c_char,
    result_json_utf8: *const c_char,
) -> *mut c_char {
    let operation_for_error = best_effort_workspace_diagnostics_operation(operation_utf8);
    let envelope = match ffi_catch(|| {
        let operation = require_str(operation_utf8, "operation_utf8")?;
        let multi = require_mut(multi, "multi")?;
        let result_json = workspace_diagnostics_operation_json(multi, operation, result_json_utf8)?;
        workspace_diagnostics_envelope_success(operation, result_json)
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            workspace_diagnostics_envelope_error(operation_for_error.as_deref(), status, message)
        }
    };
    make_c_string_ptr(envelope)
}

fn best_effort_workspace_diagnostics_operation(operation_utf8: *const c_char) -> Option<String> {
    if operation_utf8.is_null() {
        return None;
    }
    Some(
        unsafe { CStr::from_ptr(operation_utf8) }
            .to_string_lossy()
            .into_owned(),
    )
}

fn workspace_diagnostics_operation_json(
    multi: &mut MultiDocumentEditorUi,
    operation: &str,
    result_json_utf8: *const c_char,
) -> Result<String, String> {
    match operation {
        "apply" => {
            let result_json = require_str(result_json_utf8, "result_json_utf8")?;
            multi
                .apply_workspace_diagnostics_json(result_json)
                .map_err(map_ui_error)?;
            multi
                .workspace_diagnostics_snapshot_json()
                .map_err(map_ui_error)
        }
        "snapshot" => multi
            .workspace_diagnostics_snapshot_json()
            .map_err(map_ui_error),
        "markers" => multi
            .workspace_diagnostic_markers_json()
            .map_err(map_ui_error),
        "previous_result_ids" => multi
            .workspace_diagnostics_previous_result_ids_json()
            .map_err(map_ui_error),
        _ => Err(invalid_argument(format!(
            "unknown workspace diagnostics operation {operation:?}"
        ))),
    }
}

fn workspace_diagnostics_envelope_success(
    operation: &str,
    result_json: String,
) -> Result<String, String> {
    let value = serde_json::from_str::<Value>(&result_json).map_err(|err| {
        format!("stored workspace diagnostics JSON for operation {operation:?} is invalid: {err}")
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

fn workspace_diagnostics_envelope_error(
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
