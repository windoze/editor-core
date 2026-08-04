use super::*;
use serde_json::{Value, json};
use std::ffi::CStr;

fn project_lsp_servers_value(multi: &MultiDocumentEditorUi) -> Result<Value, String> {
    serde_json::to_value(multi.project_lsp_server_configs()).map_err(|err| err.to_string())
}

fn project_lsp_start_plan_value(multi: &MultiDocumentEditorUi) -> Result<Value, String> {
    serde_json::to_value(multi.project_lsp_start_plan()).map_err(|err| err.to_string())
}

fn project_lsp_stop_plan_value(multi: &MultiDocumentEditorUi) -> Result<Value, String> {
    serde_json::to_value(multi.project_lsp_stop_plan()).map_err(|err| err.to_string())
}

fn project_lsp_restart_plan_value(multi: &MultiDocumentEditorUi) -> Result<Value, String> {
    serde_json::to_value(multi.project_lsp_restart_plan()).map_err(|err| err.to_string())
}

fn project_lsp_lifecycle_events_value(
    multi: &MultiDocumentEditorUi,
    after_sequence: u64,
) -> Result<Value, String> {
    serde_json::to_value(multi.project_lsp_lifecycle_events_after(after_sequence))
        .map_err(|err| err.to_string())
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_set_project_lsp_servers_json(
    multi: *mut MultiDocumentEditorUi,
    configs_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let configs_json = require_str(configs_json_utf8, "configs_json_utf8")?;
        let configs: Vec<ProjectLspServerConfig> =
            serde_json::from_str(configs_json).map_err(|err| {
                invalid_argument(format!(
                    "configs_json_utf8 must be a JSON array of project LSP server configs: {err}"
                ))
            })?;
        multi
            .set_project_lsp_server_configs(configs)
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_project_lsp_servers_json(
    multi: *mut MultiDocumentEditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        Ok(project_lsp_servers_value(multi)?.to_string())
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_project_lsp_start_plan_json(
    multi: *mut MultiDocumentEditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        Ok(project_lsp_start_plan_value(multi)?.to_string())
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_project_lsp_stop_plan_json(
    multi: *mut MultiDocumentEditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        Ok(project_lsp_stop_plan_value(multi)?.to_string())
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_project_lsp_restart_plan_json(
    multi: *mut MultiDocumentEditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        Ok(project_lsp_restart_plan_value(multi)?.to_string())
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_record_project_lsp_start_outcome_json(
    multi: *mut MultiDocumentEditorUi,
    outcome_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let outcome_json = require_str(outcome_json_utf8, "outcome_json_utf8")?;
        let outcome: ProjectLspStartOutcome =
            serde_json::from_str(outcome_json).map_err(|err| {
                invalid_argument(format!(
                    "outcome_json_utf8 must be a JSON project LSP start outcome: {err}"
                ))
            })?;
        multi
            .record_project_lsp_start_outcome(outcome)
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

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_multi_document_project_lsp_lifecycle_events_latest_sequence(
    multi: *mut MultiDocumentEditorUi,
    out_sequence: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        if out_sequence.is_null() {
            return Err(invalid_argument("out_sequence is null"));
        }
        unsafe {
            *out_sequence = multi.project_lsp_lifecycle_events_latest_sequence();
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_project_lsp_lifecycle_events_json(
    multi: *mut MultiDocumentEditorUi,
    after_sequence: u64,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        Ok(project_lsp_lifecycle_events_value(multi, after_sequence)?.to_string())
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_project_lsp_lifecycle_envelope_json(
    multi: *mut MultiDocumentEditorUi,
    operation_utf8: *const c_char,
    after_sequence: u64,
) -> *mut c_char {
    let operation_for_error = best_effort_project_lsp_operation(operation_utf8);
    let envelope = match ffi_catch(|| {
        let operation = require_str(operation_utf8, "operation_utf8")?;
        let multi = require_mut(multi, "multi")?;
        let value = project_lsp_lifecycle_operation_value(multi, operation, after_sequence)?;
        Ok(project_lsp_lifecycle_envelope_success(operation, value))
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            project_lsp_lifecycle_envelope_error(operation_for_error.as_deref(), status, message)
        }
    };
    make_c_string_ptr(envelope)
}

fn best_effort_project_lsp_operation(operation_utf8: *const c_char) -> Option<String> {
    if operation_utf8.is_null() {
        return None;
    }
    Some(
        unsafe { CStr::from_ptr(operation_utf8) }
            .to_string_lossy()
            .into_owned(),
    )
}

fn project_lsp_lifecycle_operation_value(
    multi: &MultiDocumentEditorUi,
    operation: &str,
    after_sequence: u64,
) -> Result<Value, String> {
    match operation {
        "start_plan" => project_lsp_start_plan_value(multi),
        "stop_plan" => project_lsp_stop_plan_value(multi),
        "restart_plan" => project_lsp_restart_plan_value(multi),
        "lifecycle_events" => project_lsp_lifecycle_events_value(multi, after_sequence),
        _ => Err(invalid_argument(format!(
            "unknown project LSP lifecycle operation {operation:?}"
        ))),
    }
}

fn project_lsp_lifecycle_envelope_success(operation: &str, value: Value) -> String {
    json!({
        "ok": true,
        "operation": operation,
        "status": "success",
        "value": value,
        "error": Value::Null,
        "version": ECU_ABI_VERSION,
    })
    .to_string()
}

fn project_lsp_lifecycle_envelope_error(
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_project_lsp_servers_envelope_json(
    multi: *mut MultiDocumentEditorUi,
) -> *mut c_char {
    let envelope = match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let value = project_lsp_servers_value(multi)?;
        Ok(project_lsp_servers_envelope_success(value))
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            project_lsp_servers_envelope_error(status, message)
        }
    };
    make_c_string_ptr(envelope)
}

fn project_lsp_servers_envelope_success(value: Value) -> String {
    json!({
        "ok": true,
        "status": "success",
        "value": value,
        "error": Value::Null,
        "version": ECU_ABI_VERSION,
    })
    .to_string()
}

fn project_lsp_servers_envelope_error(status: c_int, message: String) -> String {
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
