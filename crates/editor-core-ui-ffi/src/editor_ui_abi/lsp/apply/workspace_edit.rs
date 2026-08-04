use super::*;
use serde_json::{Value, json};

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_json(
    ui: *mut EditorUi,
    workspace_edit_json_utf8: *const c_char,
    document_uri_utf8: *const c_char,
) -> *mut c_char {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let workspace_edit_json =
            require_cstr(workspace_edit_json_utf8, "workspace_edit_json_utf8")?
                .to_str()
                .map_err(|_| "workspace_edit_json_utf8 is not valid UTF-8".to_string())?;
        let document_uri = if document_uri_utf8.is_null() {
            None
        } else {
            Some(
                require_cstr(document_uri_utf8, "document_uri_utf8")?
                    .to_str()
                    .map_err(|_| "document_uri_utf8 is not valid UTF-8".to_string())?,
            )
        };
        ui.lsp_apply_workspace_edit_json(workspace_edit_json, document_uri)
            .map(make_c_string_ptr)
            .map_err(map_ui_error)
    }) {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => {
            set_last_error(err);
            ptr::null_mut()
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_envelope_json(
    ui: *mut EditorUi,
    workspace_edit_json_utf8: *const c_char,
    document_uri_utf8: *const c_char,
) -> *mut c_char {
    let mut document_uri_value = None;
    let envelope = match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let workspace_edit_json =
            require_str(workspace_edit_json_utf8, "workspace_edit_json_utf8")?;
        let document_uri = optional_document_uri(document_uri_utf8)?;
        document_uri_value = document_uri.map(str::to_string);
        let result_json = ui
            .lsp_apply_workspace_edit_json(workspace_edit_json, document_uri)
            .map_err(map_ui_error)?;
        let value = workspace_edit_application_value(result_json)?;
        Ok(workspace_edit_application_envelope_success(
            document_uri_value.as_deref(),
            value,
        ))
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            workspace_edit_application_envelope_error(
                document_uri_value.as_deref(),
                status,
                message,
            )
        }
    };
    make_c_string_ptr(envelope)
}

fn optional_document_uri<'a>(document_uri_utf8: *const c_char) -> Result<Option<&'a str>, String> {
    if document_uri_utf8.is_null() {
        Ok(None)
    } else {
        require_str(document_uri_utf8, "document_uri_utf8").map(Some)
    }
}

fn workspace_edit_application_value(result_json: String) -> Result<Value, String> {
    serde_json::from_str::<Value>(&result_json)
        .map_err(|err| format!("workspace edit application returned invalid JSON: {err}"))
}

fn workspace_edit_application_envelope_success(document_uri: Option<&str>, value: Value) -> String {
    json!({
        "ok": true,
        "status": "success",
        "document_uri": document_uri,
        "value": value,
        "error": Value::Null,
        "version": ECU_ABI_VERSION,
    })
    .to_string()
}

fn workspace_edit_application_envelope_error(
    document_uri: Option<&str>,
    status: c_int,
    message: String,
) -> String {
    json!({
        "ok": false,
        "status": "error",
        "document_uri": document_uri,
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
