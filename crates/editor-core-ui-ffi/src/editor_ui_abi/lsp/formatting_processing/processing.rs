use super::*;

/// Poll and apply any completed async processing (Tree-sitter highlighting/folding).
///
/// This is non-blocking: it never waits for the worker thread.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_applied` and `out_pending` must be valid pointers to `u8`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_poll_processing(
    ui: *mut EditorUi,
    out_applied: *mut u8,
    out_pending: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_applied.is_null() {
            return Err(invalid_argument("out_applied is null"));
        }
        if out_pending.is_null() {
            return Err(invalid_argument("out_pending is null"));
        }

        let result = ui.poll_processing().map_err(map_ui_error)?;
        unsafe {
            *out_applied = if result.applied { 1 } else { 0 };
            *out_pending = if result.pending { 1 } else { 0 };
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
