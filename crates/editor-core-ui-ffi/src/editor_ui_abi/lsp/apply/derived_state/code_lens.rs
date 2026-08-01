use crate::*;

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_code_lens_json(
    ui: *mut EditorUi,
    code_lens_result_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let json = require_cstr(code_lens_result_json_utf8, "code_lens_result_json_utf8")?
            .to_str()
            .map_err(|_| "code_lens_result_json_utf8 is not valid UTF-8".to_string())?;
        ui.lsp_apply_code_lens_json(json)
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
