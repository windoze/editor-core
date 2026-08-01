use super::super::super::super::*;

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_mouse_down(
    ui: *mut EditorUi,
    x_px: c_float,
    y_px: c_float,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.mouse_down(x_px, y_px)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_mouse_down_ex(
    ui: *mut EditorUi,
    x_px: c_float,
    y_px: c_float,
    modifiers: u32,
    click_count: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;

        // Bit layout mirrors `editor_core_ui::Modifiers`:
        // - bit0: shift
        // - bit1: ctrl
        // - bit2: alt/option
        // - bit3: meta/cmd
        let mut mods = editor_core_ui::Modifiers::NONE;
        if (modifiers & 0b0001) != 0 {
            mods.insert(editor_core_ui::Modifiers::SHIFT);
        }
        if (modifiers & 0b0010) != 0 {
            mods.insert(editor_core_ui::Modifiers::CTRL);
        }
        if (modifiers & 0b0100) != 0 {
            mods.insert(editor_core_ui::Modifiers::ALT);
        }
        if (modifiers & 0b1000) != 0 {
            mods.insert(editor_core_ui::Modifiers::META);
        }

        let click = click_count.min(u8::MAX as u32) as u8;
        ui.mouse_down_with_modifiers_and_click_count(x_px, y_px, mods, click)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_mouse_dragged(
    ui: *mut EditorUi,
    x_px: c_float,
    y_px: c_float,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.mouse_dragged(x_px, y_px)
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

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_mouse_up(ui: *mut EditorUi) {
    ffi_void(|| {
        require_mut(ui, "ui")?.mouse_up();
        Ok(())
    });
}
