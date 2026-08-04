use super::*;

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
