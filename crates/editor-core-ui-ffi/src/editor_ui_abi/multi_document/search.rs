use super::*;
use editor_core::SearchOptions;
use serde_json::{Value, json};

fn search_all_tabs_value(
    multi: &mut MultiDocumentEditorUi,
    query: &str,
    options: SearchOptions,
) -> Result<Value, String> {
    let results = multi
        .search_all_tabs(query, options)
        .map_err(|err| format!("search failed: {err}"))?;
    Ok(json!({
        "results": results
            .iter()
            .map(|result| json!({
                "tab_id": result.tab_id.get(),
                "matches": result
                    .matches
                    .iter()
                    .map(|m| json!({ "start": m.start, "end": m.end }))
                    .collect::<Vec<_>>(),
            }))
            .collect::<Vec<_>>(),
    }))
}

/// Search all open tabs and return JSON results.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_search_all_tabs_json(
    multi: *mut MultiDocumentEditorUi,
    query_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let options = SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        Ok(search_all_tabs_value(multi, query, options)?.to_string())
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

/// Search all open tabs and return results through a structured envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_search_all_tabs_envelope_json(
    multi: *mut MultiDocumentEditorUi,
    query_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
) -> *mut c_char {
    let envelope = match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let options = SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        let value = search_all_tabs_value(multi, query, options)?;
        Ok(multi_document_search_envelope_success(value))
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            multi_document_search_envelope_error(status, message)
        }
    };
    make_c_string_ptr(envelope)
}

fn multi_document_search_envelope_success(value: Value) -> String {
    json!({
        "ok": true,
        "status": "success",
        "value": value,
        "error": Value::Null,
        "version": ECU_ABI_VERSION,
    })
    .to_string()
}

fn multi_document_search_envelope_error(status: c_int, message: String) -> String {
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
