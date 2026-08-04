use crate::*;
use serde_json::{Value, json};

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_diagnostics_envelope_json(
    ui: *mut EditorUi,
    publish_diagnostics_json_utf8: *const c_char,
) -> *mut c_char {
    lsp_derived_state_apply_envelope_json_ptr(
        ui,
        publish_diagnostics_json_utf8,
        "publish_diagnostics_json_utf8",
        "apply_diagnostics",
        |ui, json| {
            ui.lsp_apply_publish_diagnostics_json(json)
                .map_err(map_ui_error)
        },
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_inlay_hints_envelope_json(
    ui: *mut EditorUi,
    inlay_hints_result_json_utf8: *const c_char,
) -> *mut c_char {
    lsp_derived_state_apply_envelope_json_ptr(
        ui,
        inlay_hints_result_json_utf8,
        "inlay_hints_result_json_utf8",
        "apply_inlay_hints",
        |ui, json| ui.lsp_apply_inlay_hints_json(json).map_err(map_ui_error),
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_code_lens_envelope_json(
    ui: *mut EditorUi,
    code_lens_result_json_utf8: *const c_char,
) -> *mut c_char {
    lsp_derived_state_apply_envelope_json_ptr(
        ui,
        code_lens_result_json_utf8,
        "code_lens_result_json_utf8",
        "apply_code_lens",
        |ui, json| ui.lsp_apply_code_lens_json(json).map_err(map_ui_error),
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_document_links_envelope_json(
    ui: *mut EditorUi,
    document_links_result_json_utf8: *const c_char,
) -> *mut c_char {
    lsp_derived_state_apply_envelope_json_ptr(
        ui,
        document_links_result_json_utf8,
        "document_links_result_json_utf8",
        "apply_document_links",
        |ui, json| ui.lsp_apply_document_links_json(json).map_err(map_ui_error),
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_document_highlights_envelope_json(
    ui: *mut EditorUi,
    document_highlights_result_json_utf8: *const c_char,
) -> *mut c_char {
    lsp_derived_state_apply_envelope_json_ptr(
        ui,
        document_highlights_result_json_utf8,
        "document_highlights_result_json_utf8",
        "apply_document_highlights",
        |ui, json| {
            ui.lsp_apply_document_highlights_json(json)
                .map_err(map_ui_error)
        },
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_document_symbols_envelope_json(
    ui: *mut EditorUi,
    document_symbols_result_json_utf8: *const c_char,
) -> *mut c_char {
    lsp_derived_state_apply_envelope_json_ptr(
        ui,
        document_symbols_result_json_utf8,
        "document_symbols_result_json_utf8",
        "apply_document_symbols",
        |ui, json| {
            ui.lsp_apply_document_symbols_json(json)
                .map_err(map_ui_error)
        },
    )
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_folding_ranges_envelope_json(
    ui: *mut EditorUi,
    folding_ranges_result_json_utf8: *const c_char,
) -> *mut c_char {
    lsp_derived_state_apply_envelope_json_ptr(
        ui,
        folding_ranges_result_json_utf8,
        "folding_ranges_result_json_utf8",
        "apply_folding_ranges",
        |ui, json| ui.lsp_apply_folding_ranges_json(json).map_err(map_ui_error),
    )
}

fn lsp_derived_state_apply_envelope_json_ptr<F>(
    ui: *mut EditorUi,
    result_json_utf8: *const c_char,
    result_json_name: &'static str,
    operation: &'static str,
    apply: F,
) -> *mut c_char
where
    F: FnOnce(&mut EditorUi, &str) -> Result<(), String>,
{
    let envelope = match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let result_json = require_str(result_json_utf8, result_json_name)?;
        apply(ui, result_json)?;
        Ok(lsp_derived_state_apply_envelope_success(operation))
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            lsp_derived_state_apply_envelope_error(operation, status, message)
        }
    };
    make_c_string_ptr(envelope)
}

fn lsp_derived_state_apply_envelope_success(operation: &'static str) -> String {
    json!({
        "ok": true,
        "operation": operation,
        "status": "success",
        "value": {
            "applied": true,
        },
        "error": Value::Null,
        "version": ECU_ABI_VERSION,
    })
    .to_string()
}

fn lsp_derived_state_apply_envelope_error(
    operation: &'static str,
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
