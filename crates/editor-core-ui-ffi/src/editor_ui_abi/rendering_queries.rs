use super::super::*;

/// Render the current visible viewport into an RGBA buffer.
///
/// - The caller provides an output buffer and capacity.
/// - If capacity is insufficient, returns `ECU_ERR_BUFFER_TOO_SMALL` and writes the required size to `out_len`.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_len` must be a valid pointer to a `u32`.
/// `out_buf` must be a valid pointer to a buffer with at least `out_cap` bytes, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_render_rgba(
    ui: *mut EditorUi,
    out_buf: *mut u8,
    out_cap: u32,
    out_len: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out_len = require_out_mut(out_len, "out_len")?;

        let required = usize_to_u32(ui.required_rgba_len(), "rgba buffer required length")?;
        *out_len = required;

        if out_buf.is_null() {
            // Two-call pattern: allow caller to query required size.
            return Ok(ECU_ERR_BUFFER_TOO_SMALL);
        }

        if out_cap < required {
            return Ok(ECU_ERR_BUFFER_TOO_SMALL);
        }

        let dst = unsafe {
            ffi_slice_from_raw_parts_mut(out_buf, required, "out_buf", "required rgba length")?
        };
        ui.render_rgba_visible_into(dst)
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

/// Enable Skia Metal backend for this editor instance (macOS only).
///
/// - `metal_device`: `id<MTLDevice>`
/// - `metal_command_queue`: `id<MTLCommandQueue>`
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_enable_metal(
    ui: *mut EditorUi,
    metal_device: *mut c_void,
    metal_command_queue: *mut c_void,
) -> c_int {
    if metal_device.is_null() {
        return status_from_invalid_argument("metal_device is null".to_string());
    }
    if metal_command_queue.is_null() {
        return status_from_invalid_argument("metal_command_queue is null".to_string());
    }

    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.enable_metal(metal_device, metal_command_queue)
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

/// Render the current visible viewport into a Metal texture (macOS only).
///
/// - `metal_texture`: `id<MTLTexture>`
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_render_metal(
    ui: *mut EditorUi,
    metal_texture: *mut c_void,
) -> c_int {
    if metal_texture.is_null() {
        return status_from_invalid_argument("metal_texture is null".to_string());
    }

    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.render_metal_visible_into_texture(metal_texture)
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

/// Get the full document text as UTF-8.
///
/// Returns an allocated C string. Caller must free with [`editor_core_ui_ffi_string_free`].
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_get_text(ui: *mut EditorUi) -> *mut c_char {
    let default = ptr::null_mut();
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        Ok(make_c_string_ptr(ui.text()))
    }) {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => {
            set_last_error_from_error(err);
            default
        }
    }
}

/// Check whether the document is modified (dirty) relative to the last `mark_saved` / clean state.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_modified` must be a valid pointer to a `u8`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_is_modified(
    ui: *mut EditorUi,
    out_modified: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_modified.is_null() {
            return Err(invalid_argument("out_modified is null"));
        }
        unsafe {
            *out_modified = if ui.is_modified() { 1 } else { 0 };
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

/// Mark the current document state as saved (clean), resetting dirty tracking.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_mark_saved(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.mark_saved();
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Get selected text (primary + secondary selections) as UTF-8, joined with `'\n'`.
///
/// Returns an allocated C string. Caller must free with [`editor_core_ui_ffi_string_free`].
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_get_selected_text(ui: *mut EditorUi) -> *mut c_char {
    let default = ptr::null_mut();
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        Ok(make_c_string_ptr(ui.selected_text()))
    }) {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => {
            set_last_error_from_error(err);
            default
        }
    }
}

/// Get minimap snapshot as JSON.
///
/// Returns an allocated C string. Caller must free with [`editor_core_ui_ffi_string_free`].
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_minimap_json(
    ui: *mut EditorUi,
    start_visual_row: u32,
    count: u32,
) -> *mut c_char {
    let default = ptr::null_mut();
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        Ok(make_c_string_ptr(ui.minimap_json(
            u32_to_usize(start_visual_row, "start_visual_row")?,
            u32_to_usize(count, "count")?,
        )))
    }) {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => {
            set_last_error_from_error(err);
            default
        }
    }
}

/// Get primary selection offsets (character offsets).
///
/// Writes `start` and `end` (inclusive-exclusive) offsets.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_start` and `out_end` must be valid pointers to `u32`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_get_selection_offsets(
    ui: *mut EditorUi,
    out_start: *mut u32,
    out_end: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out_start = require_out_mut(out_start, "out_start")?;
        let out_end = require_out_mut(out_end, "out_end")?;
        let (start, end) = ui.primary_selection_offsets();
        *out_start = usize_to_u32(start, "selection start")?;
        *out_end = usize_to_u32(end, "selection end")?;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Delete only non-empty selections (primary + secondary), keeping empty carets intact.
///
/// This is intended for clipboard "cut" behavior.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_delete_selections_only(ui: *mut EditorUi) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.delete_selections_only()
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

/// Get all selections (including primary) as character-offset ranges.
///
/// - `out_len` receives the required number of ranges.
/// - `out_primary_index` receives the primary selection index.
/// - If `out_ranges` is null or `out_cap` is insufficient, returns `ECU_ERR_BUFFER_TOO_SMALL`.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_len` and `out_primary_index` must be valid pointers to `u32`.
/// `out_ranges` must be a valid pointer to a buffer with at least `out_cap` elements, or null.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_get_selections(
    ui: *mut EditorUi,
    out_ranges: *mut EcuSelectionRange,
    out_cap: u32,
    out_len: *mut u32,
    out_primary_index: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out_len = require_out_mut(out_len, "out_len")?;
        let out_primary_index = require_out_mut(out_primary_index, "out_primary_index")?;

        let (ranges, primary) = ui.selections_offsets();
        let required = usize_to_u32(ranges.len(), "selection range count")?;
        let primary = usize_to_u32(primary, "primary selection index")?;
        let converted = ranges
            .into_iter()
            .map(|(start, end)| {
                Ok(EcuSelectionRange {
                    start: usize_to_u32(start, "selection range start")?,
                    end: usize_to_u32(end, "selection range end")?,
                })
            })
            .collect::<Result<Vec<_>, String>>()?;
        *out_len = required;
        *out_primary_index = primary;

        if out_ranges.is_null() {
            return Ok(ECU_ERR_BUFFER_TOO_SMALL);
        }
        if out_cap < required {
            return Ok(ECU_ERR_BUFFER_TOO_SMALL);
        }

        let dst = unsafe {
            ffi_slice_from_raw_parts_mut(
                out_ranges,
                required,
                "out_ranges",
                "selection range count",
            )?
        };
        dst.copy_from_slice(&converted);
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Set the full selection set (including primary) from character-offset ranges.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `ranges` must be a valid pointer to an array of `EcuSelectionRange` with at least `range_count` elements.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_set_selections(
    ui: *mut EditorUi,
    ranges: *const EcuSelectionRange,
    range_count: u32,
    primary_index: u32,
) -> c_int {
    if range_count == 0 {
        return status_from_invalid_argument("range_count must be > 0".to_string());
    }
    if ranges.is_null() {
        return status_from_invalid_argument("ranges is null".to_string());
    }

    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;

        let slice =
            unsafe { ffi_slice_from_raw_parts(ranges, range_count, "ranges", "range_count")? };
        let mut vec = Vec::with_capacity(slice.len());
        for r in slice {
            vec.push((
                u32_to_usize(r.start, "range start")?,
                u32_to_usize(r.end, "range end")?,
            ));
        }

        ui.set_selections_offsets(
            vec.as_slice(),
            u32_to_usize(primary_index, "primary_index")?,
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

/// Set a rectangular (box) selection from two character offsets.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_set_rect_selection(
    ui: *mut EditorUi,
    anchor_offset: u32,
    active_offset: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.set_rect_selection_offsets(
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

/// Get IME marked text range.
///
/// If there is no marked text, writes `has_marked = 0` and `out_start/out_len = 0`.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_has_marked` must be a valid pointer to a `u8`.
/// `out_start` and `out_len` must be valid pointers to `u32`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_get_marked_range(
    ui: *mut EditorUi,
    out_has_marked: *mut u8,
    out_start: *mut u32,
    out_len: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let out_has_marked = require_out_mut(out_has_marked, "out_has_marked")?;
        let out_start = require_out_mut(out_start, "out_start")?;
        let out_len = require_out_mut(out_len, "out_len")?;

        let (has, start, len) = match ui.marked_range() {
            Some((s, l)) => (
                1u8,
                usize_to_u32(s, "marked range start")?,
                usize_to_u32(l, "marked range length")?,
            ),
            None => (0u8, 0u32, 0u32),
        };
        *out_has_marked = has;
        *out_start = start;
        *out_len = len;
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

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
