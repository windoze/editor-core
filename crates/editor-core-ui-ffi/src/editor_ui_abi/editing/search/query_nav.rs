use super::*;

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `query_utf8` must be a valid null-terminated UTF-8 C string pointer.
/// `out_match_count` must be a valid pointer to a `u32`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_search_set_query(
    ui: *mut EditorUi,
    query_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
    out_match_count: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let options = editor_core::SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        let count = ui.search_set_query(query, options).map_err(map_ui_error)?;
        if !out_match_count.is_null() {
            unsafe {
                *out_match_count = usize_to_u32(count, "match count")?;
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_search_clear(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.search_clear();
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
/// `query_utf8` must be a valid null-terminated UTF-8 C string pointer.
/// `out_found` must be a valid pointer to a `u8`, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_find_next(
    ui: *mut EditorUi,
    query_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
    out_found: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let options = editor_core::SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        let found = ui.find_next(query, options).map_err(map_ui_error)?;
        if !out_found.is_null() {
            unsafe {
                *out_found = if found { 1 } else { 0 };
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
/// `query_utf8` must be a valid null-terminated UTF-8 C string pointer.
/// `out_found` must be a valid pointer to a `u8`, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_find_prev(
    ui: *mut EditorUi,
    query_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
    out_found: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let options = editor_core::SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        let found = ui.find_prev(query, options).map_err(map_ui_error)?;
        if !out_found.is_null() {
            unsafe {
                *out_found = if found { 1 } else { 0 };
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
