use super::*;

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
