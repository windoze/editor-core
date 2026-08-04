use super::super::*;

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
