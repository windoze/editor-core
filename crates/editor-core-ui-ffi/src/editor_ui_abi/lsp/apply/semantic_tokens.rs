use super::*;
use serde_json::{Value, json};

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `data` must be a valid pointer to an array of `u32` with at least `data_len` elements,
/// or null if `data_len` is 0.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens(
    ui: *mut EditorUi,
    data: *const u32,
    data_len: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if data.is_null() && data_len != 0 {
            return Err(invalid_argument("data is null"));
        }
        let slice = unsafe { ffi_slice_from_raw_parts(data, data_len, "data", "data_len")? };
        ui.lsp_apply_semantic_tokens(slice)
            .map(|_| ECU_OK)
            .map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `data` must be a valid pointer to an array of `u32` with at least `data_len` elements,
/// or null if `data_len` is 0.
///
/// The returned string is owned by the caller and must be freed with
/// `editor_core_ui_ffi_string_free`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens_envelope_json(
    ui: *mut EditorUi,
    data: *const u32,
    data_len: u32,
) -> *mut c_char {
    let envelope = match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if data.is_null() && data_len != 0 {
            return Err(invalid_argument("data is null"));
        }
        let slice = unsafe { ffi_slice_from_raw_parts(data, data_len, "data", "data_len")? };
        ui.lsp_apply_semantic_tokens(slice).map_err(map_ui_error)?;
        Ok(lsp_semantic_tokens_apply_envelope_success(slice.len()))
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            lsp_semantic_tokens_apply_envelope_error(status, message)
        }
    };
    make_c_string_ptr(envelope)
}

fn lsp_semantic_tokens_apply_envelope_success(data_len: usize) -> String {
    json!({
        "ok": true,
        "operation": "apply_semantic_tokens",
        "status": "success",
        "value": {
            "applied": true,
            "data_len": data_len,
        },
        "error": Value::Null,
        "version": ECU_ABI_VERSION,
    })
    .to_string()
}

fn lsp_semantic_tokens_apply_envelope_error(status: c_int, message: String) -> String {
    json!({
        "ok": false,
        "operation": "apply_semantic_tokens",
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
