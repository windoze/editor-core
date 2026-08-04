use super::super::*;

/// Export current diagnostics for the active buffer as JSON.
///
/// Caller owns the returned string and must free it with `editor_core_ui_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_diagnostics_json(ui: *mut EditorUi) -> *mut c_char {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.diagnostics_json().map_err(map_ui_error)
    }) {
        Ok(result_json) => {
            clear_last_error();
            make_c_string_ptr(result_json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}
