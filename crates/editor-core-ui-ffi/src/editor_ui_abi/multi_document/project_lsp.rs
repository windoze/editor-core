use super::*;
use serde_json::{Value, json};

fn project_lsp_servers_value(multi: &MultiDocumentEditorUi) -> Result<Value, String> {
    serde_json::to_value(multi.project_lsp_server_configs()).map_err(|err| err.to_string())
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
