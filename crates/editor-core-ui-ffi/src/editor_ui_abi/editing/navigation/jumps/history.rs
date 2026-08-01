use super::super::super::super::super::*;

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_push_jump_location(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.push_jump_location().map_err(map_ui_error)?;
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_jump_back(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let _ = ui.jump_back().map_err(map_ui_error)?;
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_jump_forward(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let _ = ui.jump_forward().map_err(map_ui_error)?;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}
