use super::super::*;
use serde_json::{Value, json};

/// Execute one editor command encoded as JSON and return the command-result JSON.
///
/// The JSON schema matches the headless FFI command plane, with UI additions for snippets,
/// auto-pairs config, and bracket-match highlight commands. Caller owns the returned string and
/// must free it with `editor_core_ui_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_execute_command_json(
    ui: *mut EditorUi,
    command_json_utf8: *const c_char,
) -> *mut c_char {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let command_json = require_str(command_json_utf8, "command_json_utf8")?;
        ui.execute_command_json(command_json).map_err(map_ui_error)
    }) {
        Ok(result_json) => {
            clear_last_error();
            make_c_string_ptr(result_json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Execute one editor command encoded as JSON and return a stable JSON result envelope.
///
/// Unlike `editor_core_ui_ffi_editor_ui_execute_command_json`, command/argument errors are returned
/// as JSON instead of a null pointer:
///
/// `{ "ok": true, "value": <command result>, "error": null, "version": ECU_ABI_VERSION }`
/// `{ "ok": false, "value": null, "error": { ... }, "version": ECU_ABI_VERSION }`
///
/// Caller owns the returned string and must free it with `editor_core_ui_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_execute_command_envelope_json(
    ui: *mut EditorUi,
    command_json_utf8: *const c_char,
) -> *mut c_char {
    let envelope = match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let command_json = require_str(command_json_utf8, "command_json_utf8")?;
        ui.execute_command_json(command_json).map_err(map_ui_error)
    }) {
        Ok(result_json) => {
            clear_last_error();
            command_envelope_success(result_json)
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            command_envelope_error(status, message)
        }
    };
    make_c_string_ptr(envelope)
}

fn command_envelope_success(result_json: String) -> String {
    let value = serde_json::from_str::<Value>(&result_json).unwrap_or(Value::String(result_json));
    json!({
        "ok": true,
        "value": value,
        "error": null,
        "version": ECU_ABI_VERSION,
    })
    .to_string()
}

fn command_envelope_error(status: c_int, message: String) -> String {
    json!({
        "ok": false,
        "value": null,
        "error": {
            "code": status_code_name(status),
            "status": status,
            "message": message,
        },
        "version": ECU_ABI_VERSION,
    })
    .to_string()
}
