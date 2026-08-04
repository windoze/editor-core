use super::super::*;

/// Check whether a snippet session (placeholders + tabstop navigation) is currently active.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_active` must be a valid pointer to a `u8`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_has_active_snippet_session(
    ui: *mut EditorUi,
    out_active: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_active.is_null() {
            return Err(invalid_argument("out_active is null"));
        }
        let active = ui.has_active_snippet_session().map_err(map_ui_error)?;
        unsafe {
            *out_active = if active { 1 } else { 0 };
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
