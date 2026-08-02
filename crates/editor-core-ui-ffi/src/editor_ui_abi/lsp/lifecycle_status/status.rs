use super::*;

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_enabled` must be a valid pointer to a `u8`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_is_enabled(
    ui: *mut EditorUi,
    out_enabled: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_enabled.is_null() {
            return Err(invalid_argument("out_enabled is null"));
        }
        unsafe {
            *out_enabled = if ui.lsp_is_enabled() { 1 } else { 0 };
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

/// Return a best-effort LSP status snapshot as JSON.
///
/// - `out_status_json_utf8` receives a newly allocated string that must be freed with
///   `editor_core_ui_ffi_string_free`.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_status_json_utf8` must be a valid pointer to a `*mut c_char`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_status_json(
    ui: *mut EditorUi,
    out_status_json_utf8: *mut *mut c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_status_json_utf8.is_null() {
            return Err(invalid_argument("out_status_json_utf8 is null"));
        }

        unsafe {
            *out_status_json_utf8 = ptr::null_mut();
        }

        let json = ui.lsp_status_json();
        unsafe {
            *out_status_json_utf8 = make_c_string_ptr(json);
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
