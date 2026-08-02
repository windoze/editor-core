use super::super::super::*;

/// Return latest per-EditorUi LSP request lifecycle event sequence.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_sequence` must be a valid pointer to a `u64`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_events_latest_sequence(
    ui: *mut EditorUi,
    out_sequence: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_sequence.is_null() {
            return Err(invalid_argument("out_sequence is null"));
        }
        unsafe {
            *out_sequence = ui.lsp_request_events_latest_sequence();
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

/// Return per-EditorUi LSP request lifecycle events newer than `after_sequence`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_events_json(
    ui: *mut EditorUi,
    after_sequence: u64,
) -> *mut c_char {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        ui.lsp_request_events_json(after_sequence)
            .map_err(map_ui_error)
    }) {
        Ok(json) => {
            clear_last_error();
            make_c_string_ptr(json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

/// Send a best-effort LSP `$/cancelRequest` and record a local canceled lifecycle event.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_recorded` must be a valid pointer to a `u8`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_cancel_request(
    ui: *mut EditorUi,
    request_id: u64,
    out_recorded: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_recorded.is_null() {
            return Err(invalid_argument("out_recorded is null"));
        }
        let recorded = ui.lsp_cancel_request(request_id).map_err(map_ui_error)?;
        unsafe {
            *out_recorded = if recorded { 1 } else { 0 };
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

/// Record a local timed-out lifecycle event for a pending LSP result request.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_recorded` must be a valid pointer to a `u8`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_mark_request_timed_out(
    ui: *mut EditorUi,
    request_id: u64,
    out_recorded: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_recorded.is_null() {
            return Err(invalid_argument("out_recorded is null"));
        }
        let recorded = ui.lsp_mark_request_timed_out(request_id);
        unsafe {
            *out_recorded = if recorded { 1 } else { 0 };
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
