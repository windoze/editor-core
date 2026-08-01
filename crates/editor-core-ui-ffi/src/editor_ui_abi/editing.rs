use super::super::*;

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_insert_text(
    ui: *mut EditorUi,
    text_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let text = require_cstr(text_utf8, "text_utf8")?
            .to_str()
            .map_err(|_| "text_utf8 is not valid UTF-8".to_string())?;
        ui.insert_text(text).map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Execute one editor command encoded as JSON and return the command-result JSON.
///
/// The JSON schema matches the headless FFI command plane, with UI additions for snippets,
/// auto-pairs config, and bracket-match highlight commands. Caller owns the returned string and
/// must free it with `editor_core_ui_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_execute_command_json(
    ui: *mut EditorUi,
    command_json_utf8: *const c_char,
) -> *mut c_char {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let command_json = require_str(command_json_utf8, "command_json_utf8")?;
        ui.execute_command_json(command_json).map_err(map_ui_error)
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

/// Export current decoration layers for the active buffer as JSON.
///
/// Caller owns the returned string and must free it with `editor_core_ui_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_decorations_json(ui: *mut EditorUi) -> *mut c_char {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.decorations_json().map_err(map_ui_error)
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

/// Export current document symbols for the active buffer as JSON.
///
/// Caller owns the returned string and must free it with `editor_core_ui_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_document_symbols_json(
    ui: *mut EditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.document_symbols_json().map_err(map_ui_error)
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

/// Export current folding regions for the active buffer as JSON.
///
/// Caller owns the returned string and must free it with `editor_core_ui_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_folding_regions_json(
    ui: *mut EditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.folding_regions_json().map_err(map_ui_error)
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

/// Export current style intervals overlapping `[start, end)` as JSON.
///
/// Caller owns the returned string and must free it with `editor_core_ui_ffi_string_free`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_style_intervals_json(
    ui: *mut EditorUi,
    start: u32,
    end: u32,
) -> *mut c_char {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.style_intervals_json(u32_to_usize(start, "start")?, u32_to_usize(end, "end")?)
            .map_err(map_ui_error)
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_insert_tab(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.insert_tab().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_insert_backtab(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.insert_backtab().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_backspace(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.backspace().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_delete_forward(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.delete_forward().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_delete_word_back(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.delete_word_back().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_delete_word_forward(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.delete_word_forward()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_add_style(
    ui: *mut EditorUi,
    start: u32,
    end: u32,
    style_id: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.add_style(
            u32_to_usize(start, "start")?,
            u32_to_usize(end, "end")?,
            style_id,
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_remove_style(
    ui: *mut EditorUi,
    start: u32,
    end: u32,
    style_id: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.remove_style(
            u32_to_usize(start, "start")?,
            u32_to_usize(end, "end")?,
            style_id,
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

/// Replace match highlight ranges (e.g. search matches) as a style overlay layer.
///
/// - `ranges` are character-offset ranges (inclusive-exclusive).
/// - Passing `range_count = 0` clears the layer (and allows `ranges` to be null).
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `ranges` must be a valid pointer to an array of `EcuSelectionRange` with at least `range_count` elements,
/// or null if `range_count` is 0.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_set_match_highlights(
    ui: *mut EditorUi,
    ranges: *const EcuSelectionRange,
    range_count: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;

        if range_count == 0 {
            ui.set_match_highlights_offsets(&[]);
            return Ok(ECU_OK);
        }
        if ranges.is_null() {
            return Err(invalid_argument("ranges is null"));
        }

        let ranges =
            unsafe { ffi_slice_from_raw_parts(ranges, range_count, "ranges", "range_count")? };
        let mut out: Vec<(usize, usize)> = Vec::with_capacity(ranges.len());
        for r in ranges {
            out.push((
                u32_to_usize(r.start, "range start")?,
                u32_to_usize(r.end, "range end")?,
            ));
        }

        ui.set_match_highlights_offsets(&out);
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_undo(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.undo().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_redo(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.redo().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_visual_by_rows(
    ui: *mut EditorUi,
    delta_rows: c_int,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_visual_by_rows(delta_rows as isize)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_grapheme_left(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_grapheme_left()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_grapheme_right(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_grapheme_right()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_word_left(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_word_left().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_word_right(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_word_right().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_matching_bracket(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_matching_bracket()
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

// MARK: - Bookmarks / marks / jump list

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_toggle_bookmark_at_cursor_line(
    ui: *mut EditorUi,
    out_added: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out_added = require_mut(out_added, "out_added")?;
        let added = ui.toggle_bookmark_at_cursor_line().map_err(map_ui_error)?;
        *out_added = if added { 1 } else { 0 };
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_goto_next_bookmark(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let _ = ui.goto_next_bookmark().map_err(map_ui_error)?;
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_goto_prev_bookmark(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let _ = ui.goto_prev_bookmark().map_err(map_ui_error)?;
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_visual_line_start(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_visual_line_start()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_visual_line_end(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_visual_line_end()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_document_start(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_document_start()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_document_end(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_document_end()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_visual_by_pages(
    ui: *mut EditorUi,
    delta_pages: c_int,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_visual_by_pages(delta_pages as isize)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_grapheme_left_and_modify_selection(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_grapheme_left_and_modify_selection()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_grapheme_right_and_modify_selection(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_grapheme_right_and_modify_selection()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_word_left_and_modify_selection(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_word_left_and_modify_selection()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_word_right_and_modify_selection(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_word_right_and_modify_selection()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_visual_line_start_and_modify_selection(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_visual_line_start_and_modify_selection()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_visual_line_end_and_modify_selection(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_visual_line_end_and_modify_selection()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_document_start_and_modify_selection(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_document_start_and_modify_selection()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_to_document_end_and_modify_selection(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_to_document_end_and_modify_selection()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_visual_by_pages_and_modify_selection(
    ui: *mut EditorUi,
    delta_pages: c_int,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_visual_by_pages_and_modify_selection(delta_pages as isize)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_move_visual_by_rows_and_modify_selection(
    ui: *mut EditorUi,
    delta_rows: c_int,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.move_visual_by_rows_and_modify_selection(delta_rows as isize)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_clear_secondary_selections(
    ui: *mut EditorUi,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.clear_secondary_selections()
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_add_cursor_above(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.add_cursor_above().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_add_cursor_below(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.add_cursor_below().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_add_next_occurrence(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.add_next_occurrence(editor_core::SearchOptions::default())
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_add_all_occurrences(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.add_all_occurrences(editor_core::SearchOptions::default())
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_select_word(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.select_word().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_select_line(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.select_line().map(|_| ECU_OK).map_err(map_ui_error)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_line_selection_offsets(
    ui: *mut EditorUi,
    anchor_offset: u32,
    active_offset: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_line_selection_offsets(
            u32_to_usize(anchor_offset, "anchor_offset")?,
            u32_to_usize(active_offset, "active_offset")?,
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_select_paragraph_at_char_offset(
    ui: *mut EditorUi,
    char_offset: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.select_paragraph_at_char_offset(u32_to_usize(char_offset, "char_offset")?)
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_paragraph_selection_offsets(
    ui: *mut EditorUi,
    anchor_offset: u32,
    active_offset: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_paragraph_selection_offsets(
            u32_to_usize(anchor_offset, "anchor_offset")?,
            u32_to_usize(active_offset, "active_offset")?,
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_add_caret_at_char_offset(
    ui: *mut EditorUi,
    char_offset: u32,
    make_primary: u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.add_caret_at_char_offset(u32_to_usize(char_offset, "char_offset")?, make_primary != 0)
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
