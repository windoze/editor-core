use super::super::*;
use serde_json::{Value, json};
use std::ffi::CStr;

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_event_stream_envelope_json(
    ui: *mut EditorUi,
    stream_utf8: *const c_char,
    after_sequence: u64,
) -> *mut c_char {
    let stream_for_error = best_effort_stream(stream_utf8);
    let envelope = match ffi_catch(|| {
        let stream = require_str(stream_utf8, "stream_utf8")?;
        let ui = require_mut(ui, "ui")?;
        let result_json = editor_ui_event_stream_json(ui, stream, after_sequence)?;
        event_stream_envelope_success("editor_ui", stream, after_sequence, result_json)
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            event_stream_envelope_error(
                "editor_ui",
                stream_for_error.as_deref(),
                after_sequence,
                status,
                message,
            )
        }
    };
    make_c_string_ptr(envelope)
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_event_stream_envelope_json(
    multi: *mut MultiDocumentEditorUi,
    stream_utf8: *const c_char,
    after_sequence: u64,
) -> *mut c_char {
    let stream_for_error = best_effort_stream(stream_utf8);
    let envelope = match ffi_catch(|| {
        let stream = require_str(stream_utf8, "stream_utf8")?;
        let multi = require_mut(multi, "multi")?;
        let result_json = multi_document_event_stream_json(multi, stream, after_sequence)?;
        event_stream_envelope_success("multi_document", stream, after_sequence, result_json)
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            event_stream_envelope_error(
                "multi_document",
                stream_for_error.as_deref(),
                after_sequence,
                status,
                message,
            )
        }
    };
    make_c_string_ptr(envelope)
}

fn best_effort_stream(stream_utf8: *const c_char) -> Option<String> {
    if stream_utf8.is_null() {
        return None;
    }
    Some(
        unsafe { CStr::from_ptr(stream_utf8) }
            .to_string_lossy()
            .into_owned(),
    )
}

fn editor_ui_event_stream_json(
    ui: &mut EditorUi,
    stream: &str,
    after_sequence: u64,
) -> Result<String, String> {
    match stream {
        "state_events" => ui.state_events_json(after_sequence).map_err(map_ui_error),
        "lsp_result_events" => ui
            .lsp_result_events_json(after_sequence)
            .map_err(map_ui_error),
        "lsp_request_events" => ui
            .lsp_request_events_json(after_sequence)
            .map_err(map_ui_error),
        _ => Err(invalid_argument(format!(
            "unknown editor_ui event stream {stream:?}"
        ))),
    }
}

fn multi_document_event_stream_json(
    multi: &mut MultiDocumentEditorUi,
    stream: &str,
    after_sequence: u64,
) -> Result<String, String> {
    match stream {
        "state_events" => multi
            .state_events_json(after_sequence)
            .map_err(map_ui_error),
        "lsp_result_events" => multi
            .lsp_result_events_json(after_sequence)
            .map_err(map_ui_error),
        "lsp_request_events" => multi
            .lsp_request_events_json(after_sequence)
            .map_err(map_ui_error),
        _ => Err(invalid_argument(format!(
            "unknown multi_document event stream {stream:?}"
        ))),
    }
}

fn event_stream_envelope_success(
    owner: &str,
    stream: &str,
    after_sequence: u64,
    result_json: String,
) -> Result<String, String> {
    let value = serde_json::from_str::<Value>(&result_json).map_err(|err| {
        format!("stored event stream JSON for owner {owner:?} stream {stream:?} is invalid: {err}")
    })?;
    Ok(json!({
        "ok": true,
        "owner": owner,
        "stream": stream,
        "status": "success",
        "after_sequence": after_sequence,
        "value": value,
        "error": Value::Null,
        "version": ECU_ABI_VERSION,
    })
    .to_string())
}

fn event_stream_envelope_error(
    owner: &str,
    stream: Option<&str>,
    after_sequence: u64,
    status: c_int,
    message: String,
) -> String {
    json!({
        "ok": false,
        "owner": owner,
        "stream": stream,
        "status": "error",
        "after_sequence": after_sequence,
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
