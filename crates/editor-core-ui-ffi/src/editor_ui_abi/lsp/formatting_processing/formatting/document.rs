use super::*;

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_format_document(
    ui: *mut EditorUi,
    formatting_options_json_utf8: *const c_char,
    timeout_ms: u32,
    out_applied: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_applied.is_null() {
            return Err(invalid_argument("out_applied is null"));
        }

        let options = if formatting_options_json_utf8.is_null() {
            ""
        } else {
            require_cstr(formatting_options_json_utf8, "formatting_options_json_utf8")?
                .to_str()
                .map_err(|_| "formatting_options_json_utf8 is not valid UTF-8".to_string())?
        };

        let applied = ui
            .lsp_format_document(options, timeout_ms)
            .map_err(map_ui_error)?;
        unsafe {
            *out_applied = if applied { 1 } else { 0 };
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
