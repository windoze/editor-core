use super::*;

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `data` must be a valid pointer to an array of `u32` with at least `data_len` elements,
/// or null if `data_len` is 0.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens(
    ui: *mut EditorUi,
    data: *const u32,
    data_len: u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if data.is_null() && data_len != 0 {
            return Err(invalid_argument("data is null"));
        }
        let slice = unsafe { ffi_slice_from_raw_parts(data, data_len, "data", "data_len")? };
        ui.lsp_apply_semantic_tokens(slice)
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
