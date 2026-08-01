use super::super::super::super::*;
use super::common::*;

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_document_diagnostic(
    ui: *mut EditorUi,
    previous_result_id_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let previous_result_id = if previous_result_id_utf8.is_null() {
            None
        } else {
            Some(
                require_cstr(previous_result_id_utf8, "previous_result_id_utf8")?
                    .to_str()
                    .map_err(|_| "previous_result_id_utf8 is not valid UTF-8".to_string())?,
            )
        };
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }
        let id = ui
            .lsp_request_document_diagnostic(previous_result_id)
            .map_err(map_ui_error)?;
        unsafe {
            *out_request_id = id;
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
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_document_diagnostic_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_document_diagnostic_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_workspace_diagnostic(
    ui: *mut EditorUi,
    previous_result_ids_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_json_ffi(
        ui,
        previous_result_ids_json_utf8,
        "previous_result_ids_json_utf8",
        out_request_id,
        |ui, json| ui.lsp_request_workspace_diagnostic(json),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_workspace_diagnostic_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_workspace_diagnostic_result_json()
    })
}
