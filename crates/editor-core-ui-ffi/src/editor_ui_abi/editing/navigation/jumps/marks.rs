use super::super::super::super::super::*;

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_mark_at_cursor(
    ui: *mut EditorUi,
    name_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let name = require_str(name_utf8, "name_utf8")?;
        ui.set_mark_at_cursor(name.to_string())
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_goto_mark(
    ui: *mut EditorUi,
    name_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let name = require_str(name_utf8, "name_utf8")?;
        let _ = ui.goto_mark(name).map_err(map_ui_error)?;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}
