use super::super::super::super::*;

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_marked_text(
    ui: *mut EditorUi,
    text_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let text = require_cstr(text_utf8, "text_utf8")?
            .to_str()
            .map_err(|_| "text_utf8 is not valid UTF-8".to_string())?;
        ui.set_marked_text(text)
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

/// Set IME marked text with explicit selection and optional replacement range.
///
/// - `selected_start/selected_len`: selection within `text` (character offsets).
/// - `replace_start/replace_len`: document char-offset range to replace.
///   If `replace_start == UINT32_MAX`, the UI layer will use the current marked range (if any),
///   otherwise it falls back to the current selection/caret.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_marked_text_ex(
    ui: *mut EditorUi,
    text_utf8: *const c_char,
    selected_start: u32,
    selected_len: u32,
    replace_start: u32,
    replace_len: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let text = require_cstr(text_utf8, "text_utf8")?
            .to_str()
            .map_err(|_| "text_utf8 is not valid UTF-8".to_string())?;

        let replace_range = if replace_start == u32::MAX {
            None
        } else {
            Some((
                u32_to_usize(replace_start, "replace_start")?,
                u32_to_usize(replace_len, "replace_len")?,
            ))
        };

        ui.set_marked_text_with_selection(
            text,
            u32_to_usize(selected_start, "selected_start")?,
            u32_to_usize(selected_len, "selected_len")?,
            replace_range,
        )
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
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_unmark_text(ui: *mut EditorUi) {
    ffi_void(|| {
        require_mut(ui, "ui")?.unmark_text();
        Ok(())
    });
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_commit_text(
    ui: *mut EditorUi,
    text_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let text = require_cstr(text_utf8, "text_utf8")?
            .to_str()
            .map_err(|_| "text_utf8 is not valid UTF-8".to_string())?;
        ui.commit_text(text).map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_paste_text(
    ui: *mut EditorUi,
    text_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let text = require_cstr(text_utf8, "text_utf8")?
            .to_str()
            .map_err(|_| "text_utf8 is not valid UTF-8".to_string())?;
        ui.paste_text(text).map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}
