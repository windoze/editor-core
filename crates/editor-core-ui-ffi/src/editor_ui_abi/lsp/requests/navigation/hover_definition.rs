use super::super::super::super::super::*;

/// Request LSP hover for a logical position (0-based line/column in Unicode scalars).
///
/// This is non-blocking: the result arrives asynchronously and can be read via
/// `editor_core_ui_ffi_editor_ui_lsp_take_last_hover_json` after polling processing.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_request_id` must be a valid pointer to a `u64`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_hover(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }

        let id = ui
            .lsp_request_hover(u32_to_usize(line, "line")?, u32_to_usize(column, "column")?)
            .map_err(map_ui_error)?;
        unsafe {
            *out_request_id = id;
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

/// Take the last LSP hover result payload as JSON (`Hover | null`).
///
/// - On success, returns `ECU_OK` and sets:
///   - `out_has_result = 1` and `out_result_json_utf8` to a newly allocated string, or
///   - `out_has_result = 0` and `out_result_json_utf8 = NULL` when there is no new result.
///
/// Caller must free the returned string with `editor_core_ui_ffi_string_free`.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_has_result` and `out_result_json_utf8` must be valid pointers.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_hover_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_has_result.is_null() {
            return Err(invalid_argument("out_has_result is null"));
        }
        if out_result_json_utf8.is_null() {
            return Err(invalid_argument("out_result_json_utf8 is null"));
        }

        let json = ui.lsp_take_last_hover_result_json();
        unsafe {
            if let Some(json) = json {
                *out_has_result = 1;
                *out_result_json_utf8 = make_c_string_ptr(json);
            } else {
                *out_has_result = 0;
                *out_result_json_utf8 = ptr::null_mut();
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

/// Request LSP go-to-definition for a logical position (0-based line/column in Unicode scalars).
///
/// This is non-blocking: the result arrives asynchronously and can be read via
/// `editor_core_ui_ffi_editor_ui_lsp_take_last_definition_json` after polling processing.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_request_id` must be a valid pointer to a `u64`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_definition(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }

        let id = ui
            .lsp_request_definition(u32_to_usize(line, "line")?, u32_to_usize(column, "column")?)
            .map_err(map_ui_error)?;
        unsafe {
            *out_request_id = id;
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

/// Take the last LSP go-to-definition result payload as JSON (`Definition | null`).
///
/// - On success, returns `ECU_OK` and sets:
///   - `out_has_result = 1` and `out_result_json_utf8` to a newly allocated string, or
///   - `out_has_result = 0` and `out_result_json_utf8 = NULL` when there is no new result.
///
/// Caller must free the returned string with `editor_core_ui_ffi_string_free`.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_has_result` and `out_result_json_utf8` must be valid pointers.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_definition_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_has_result.is_null() {
            return Err(invalid_argument("out_has_result is null"));
        }
        if out_result_json_utf8.is_null() {
            return Err(invalid_argument("out_result_json_utf8 is null"));
        }

        let json = ui.lsp_take_last_definition_result_json();
        unsafe {
            if let Some(json) = json {
                *out_has_result = 1;
                *out_result_json_utf8 = make_c_string_ptr(json);
            } else {
                *out_has_result = 0;
                *out_result_json_utf8 = ptr::null_mut();
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
