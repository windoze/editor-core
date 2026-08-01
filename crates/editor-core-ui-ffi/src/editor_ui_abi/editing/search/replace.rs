use super::*;

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `query_utf8` and `replacement_utf8` must be valid null-terminated UTF-8 C string pointers.
/// `out_replaced` must be a valid pointer to a `u32`, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_replace_current(
    ui: *mut EditorUi,
    query_utf8: *const c_char,
    replacement_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
    out_replaced: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let replacement = require_str(replacement_utf8, "replacement_utf8")?;
        let options = editor_core::SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        let replaced = ui
            .replace_current(query, replacement, options)
            .map_err(map_ui_error)?;
        if !out_replaced.is_null() {
            unsafe {
                *out_replaced = usize_to_u32(replaced, "replace count")?;
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

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `query_utf8` and `replacement_utf8` must be valid null-terminated UTF-8 C string pointers.
/// `out_replaced` must be a valid pointer to a `u32`, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_replace_all(
    ui: *mut EditorUi,
    query_utf8: *const c_char,
    replacement_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
    out_replaced: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let replacement = require_str(replacement_utf8, "replacement_utf8")?;
        let options = editor_core::SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        let replaced = ui
            .replace_all(query, replacement, options)
            .map_err(map_ui_error)?;
        if !out_replaced.is_null() {
            unsafe {
                *out_replaced = usize_to_u32(replaced, "replace count")?;
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
