use super::*;

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_execute_command(
    ui: *mut EditorUi,
    command_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let command_json = require_cstr(command_json_utf8, "command_json_utf8")?
            .to_str()
            .map_err(|_| "command_json_utf8 is not valid UTF-8".to_string())?;
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }
        let id = ui
            .lsp_request_execute_command(command_json)
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
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_execute_command_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_execute_command_result_json()
    })
}
