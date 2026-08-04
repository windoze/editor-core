use super::*;

/// Request on-type formatting via LSP (`textDocument/onTypeFormatting`) and apply edits locally.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `trigger_utf8` must be a valid NUL-terminated UTF-8 string.
/// `out_applied` must be a valid pointer to `u8`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_format_on_type(
    ui: *mut EditorUi,
    logical_line: u32,
    logical_column: u32,
    trigger_utf8: *const c_char,
    formatting_options_json_utf8: *const c_char,
    timeout_ms: u32,
    out_applied: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_applied.is_null() {
            return Err(invalid_argument("out_applied is null"));
        }
        let trigger = require_cstr(trigger_utf8, "trigger_utf8")?
            .to_str()
            .map_err(|_| "trigger_utf8 is not valid UTF-8".to_string())?;
        let options = if formatting_options_json_utf8.is_null() {
            ""
        } else {
            require_cstr(formatting_options_json_utf8, "formatting_options_json_utf8")?
                .to_str()
                .map_err(|_| "formatting_options_json_utf8 is not valid UTF-8".to_string())?
        };

        let applied = ui
            .lsp_format_on_type(
                logical_line as usize,
                logical_column as usize,
                trigger,
                options,
                timeout_ms,
            )
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
