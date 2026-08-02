use super::*;

pub(crate) fn lsp_take_result_json_ffi(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
    take: impl FnOnce(&mut EditorUi) -> Option<String>,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_has_result.is_null() {
            return Err(invalid_argument("out_has_result is null"));
        }
        if out_result_json_utf8.is_null() {
            return Err(invalid_argument("out_result_json_utf8 is null"));
        }

        let json = take(ui);
        unsafe {
            if let Some(json) = json {
                *out_has_result = 1;
                *out_result_json_utf8 = make_c_string_ptr(json);
            } else {
                *out_has_result = 0;
                *out_result_json_utf8 = ptr::null_mut();
            }
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
