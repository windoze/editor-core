use super::super::super::super::*;

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_expand_selection(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.expand_selection().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_expand_selection_by(
    ui: *mut EditorUi,
    unit: u32,
    count: u32,
    direction: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;

        let unit = match unit {
            0 => ExpandSelectionUnit::Character,
            1 => ExpandSelectionUnit::Word,
            2 => ExpandSelectionUnit::Line,
            _ => {
                return Err(invalid_argument(format!(
                    "invalid expand selection unit {unit} (expected 0=character, 1=word, 2=line)"
                )));
            }
        };

        let direction = match direction {
            0 => ExpandSelectionDirection::Backward,
            1 => ExpandSelectionDirection::Forward,
            _ => {
                return Err(invalid_argument(format!(
                    "invalid expand selection direction {direction} (expected 0=backward, 1=forward)"
                )));
            }
        };

        ui.expand_selection_by(unit, u32_to_usize(count, "count")?, direction)
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
