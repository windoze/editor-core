use super::*;

/// Map a character offset to logical `(line, column)` (both char-indexed).
///
/// - `char_offset` is a Unicode scalar index.
/// - `out_line/out_column` receive 0-based indices.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_line` and `out_column` must be valid pointers to `u32`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_char_offset_to_logical_position(
    ui: *mut EditorUi,
    char_offset: u32,
    out_line: *mut u32,
    out_column: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out_line = require_out_mut(out_line, "out_line")?;
        let out_column = require_out_mut(out_column, "out_column")?;

        let (line, col) =
            ui.char_offset_to_logical_position(u32_to_usize(char_offset, "char_offset")?);
        *out_line = usize_to_u32(line, "logical line")?;
        *out_column = usize_to_u32(col, "logical column")?;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Map a character offset to a view point (in pixels, top-left origin).
///
/// Writes `out_x/out_y` and `out_line_height_px`.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_x`, `out_y`, and `out_line_height_px` must be valid pointers to `c_float`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_char_offset_to_view_point(
    ui: *mut EditorUi,
    char_offset: u32,
    out_x: *mut c_float,
    out_y: *mut c_float,
    out_line_height_px: *mut c_float,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out_x = require_out_mut(out_x, "out_x")?;
        let out_y = require_out_mut(out_y, "out_y")?;
        let out_line_height_px = require_out_mut(out_line_height_px, "out_line_height_px")?;

        let (x, y) = ui
            .char_offset_to_view_point_px(u32_to_usize(char_offset, "char_offset")?)
            .ok_or_else(|| "failed to map char offset to view point".to_string())?;

        *out_x = x;
        *out_y = y;
        *out_line_height_px = ui.line_height_px();
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Hit-test a view point (pixels, top-left origin) and return the corresponding character offset.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_char_offset` must be a valid pointer to a `u32`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_view_point_to_char_offset(
    ui: *mut EditorUi,
    x_px: c_float,
    y_px: c_float,
    out_char_offset: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out_char_offset = require_out_mut(out_char_offset, "out_char_offset")?;
        let offset = ui
            .view_point_to_char_offset(x_px, y_px)
            .ok_or_else(|| "failed to hit-test view point".to_string())?;
        *out_char_offset = usize_to_u32(offset, "char offset")?;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Hit-test a view point and return the raw LSP `DocumentLink` JSON payload (if present).
///
/// - `out_has_link` is set to 1 when a link is present.
/// - `out_json_utf8` receives a newly allocated string that must be freed with
///   `editor_core_ui_ffi_string_free` (or is set to NULL when no link is present).
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_has_link` must be a valid pointer to a `u8`.
/// `out_json_utf8` must be a valid pointer to a `*mut c_char`, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_get_document_link_json_at_view_point(
    ui: *mut EditorUi,
    x_px: c_float,
    y_px: c_float,
    out_has_link: *mut u8,
    out_json_utf8: *mut *mut c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_has_link.is_null() {
            return Err(invalid_argument("out_has_link is null"));
        }

        unsafe {
            *out_has_link = 0;
        }
        if !out_json_utf8.is_null() {
            unsafe {
                *out_json_utf8 = ptr::null_mut();
            }
        }

        let Some(json) = ui.document_link_json_at_view_point_px(x_px, y_px) else {
            return Ok(ECU_OK);
        };

        unsafe {
            *out_has_link = 1;
        }

        if out_json_utf8.is_null() {
            return Ok(ECU_OK);
        }

        unsafe {
            *out_json_utf8 = make_c_string_ptr(json);
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

/// Hit-test a view point and return the raw LSP `InlayHint` JSON payload (if present).
///
/// - `out_has_hint` is set to 1 when an inlay hint is present.
/// - `out_json_utf8` receives a newly allocated string that must be freed with
///   `editor_core_ui_ffi_string_free` (or is set to NULL when no inlay hint is present).
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_has_hint` must be a valid pointer to a `u8`.
/// `out_json_utf8` must be a valid pointer to a `*mut c_char`, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_get_inlay_hint_json_at_view_point(
    ui: *mut EditorUi,
    x_px: c_float,
    y_px: c_float,
    out_has_hint: *mut u8,
    out_json_utf8: *mut *mut c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_has_hint.is_null() {
            return Err(invalid_argument("out_has_hint is null"));
        }

        unsafe {
            *out_has_hint = 0;
        }
        if !out_json_utf8.is_null() {
            unsafe {
                *out_json_utf8 = ptr::null_mut();
            }
        }

        let Some(json) = ui.inlay_hint_json_at_view_point_px(x_px, y_px) else {
            return Ok(ECU_OK);
        };

        unsafe {
            *out_has_hint = 1;
        }

        if out_json_utf8.is_null() {
            return Ok(ECU_OK);
        }

        unsafe {
            *out_json_utf8 = make_c_string_ptr(json);
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

/// Hit-test a view point and return the raw LSP `CodeLens` JSON payload (if present).
///
/// - `out_has_lens` is set to 1 when a code lens is present.
/// - `out_json_utf8` receives a newly allocated string that must be freed with
///   `editor_core_ui_ffi_string_free` (or is set to NULL when no code lens is present).
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_has_lens` must be a valid pointer to a `u8`.
/// `out_json_utf8` must be a valid pointer to a `*mut c_char`, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_get_code_lens_json_at_view_point(
    ui: *mut EditorUi,
    x_px: c_float,
    y_px: c_float,
    out_has_lens: *mut u8,
    out_json_utf8: *mut *mut c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_has_lens.is_null() {
            return Err(invalid_argument("out_has_lens is null"));
        }

        unsafe {
            *out_has_lens = 0;
        }
        if !out_json_utf8.is_null() {
            unsafe {
                *out_json_utf8 = ptr::null_mut();
            }
        }

        let Some(json) = ui.code_lens_json_at_view_point_px(x_px, y_px) else {
            return Ok(ECU_OK);
        };

        unsafe {
            *out_has_lens = 1;
        }

        if out_json_utf8.is_null() {
            return Ok(ECU_OK);
        }

        unsafe {
            *out_json_utf8 = make_c_string_ptr(json);
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
