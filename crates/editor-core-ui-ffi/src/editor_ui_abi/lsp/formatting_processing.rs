use super::super::super::*;

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_format_document(
    ui: *mut EditorUi,
    formatting_options_json_utf8: *const c_char,
    timeout_ms: u32,
    out_applied: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_applied.is_null() {
            return Err(invalid_argument("out_applied is null"));
        }

        let options = if formatting_options_json_utf8.is_null() {
            ""
        } else {
            require_cstr(formatting_options_json_utf8, "formatting_options_json_utf8")?
                .to_str()
                .map_err(|_| "formatting_options_json_utf8 is not valid UTF-8".to_string())?
        };

        let applied = ui
            .lsp_format_document(options, timeout_ms)
            .map_err(map_ui_error)?;
        unsafe {
            *out_applied = if applied { 1 } else { 0 };
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

/// Format a range via LSP (`textDocument/rangeFormatting`) and apply edits locally.
///
/// - `start_offset` / `end_offset`: editor-core char offsets.
/// - `formatting_options_json_utf8`: optional JSON `FormattingOptions` object; pass `NULL` or an
///   empty string to use a small default.
/// - `timeout_ms`: maximum time to wait for the response.
/// - `out_applied`: set to 1 if any edits were applied.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_applied` must be a valid pointer to `u8`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_format_range(
    ui: *mut EditorUi,
    start_offset: u32,
    end_offset: u32,
    formatting_options_json_utf8: *const c_char,
    timeout_ms: u32,
    out_applied: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_applied.is_null() {
            return Err(invalid_argument("out_applied is null"));
        }

        let options = if formatting_options_json_utf8.is_null() {
            ""
        } else {
            require_cstr(formatting_options_json_utf8, "formatting_options_json_utf8")?
                .to_str()
                .map_err(|_| "formatting_options_json_utf8 is not valid UTF-8".to_string())?
        };

        let applied = ui
            .lsp_format_range(
                start_offset as usize,
                end_offset as usize,
                options,
                timeout_ms,
            )
            .map_err(map_ui_error)?;
        unsafe {
            *out_applied = if applied { 1 } else { 0 };
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

/// Request on-type formatting via LSP (`textDocument/onTypeFormatting`) and apply edits locally.
///
/// - `logical_line` / `logical_column`: logical editor position after the trigger character.
/// - `trigger_utf8`: LSP trigger character string.
/// - `formatting_options_json_utf8`: optional JSON `FormattingOptions` object; pass `NULL` or an
///   empty string to use a small default.
/// - `timeout_ms`: maximum time to wait for the response.
/// - `out_applied`: set to 1 if any edits were applied.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `trigger_utf8` must be a valid NUL-terminated UTF-8 string.
/// `out_applied` must be a valid pointer to `u8`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_format_on_type(
    ui: *mut EditorUi,
    logical_line: u32,
    logical_column: u32,
    trigger_utf8: *const c_char,
    formatting_options_json_utf8: *const c_char,
    timeout_ms: u32,
    out_applied: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_applied.is_null() {
            return Err(invalid_argument("out_applied is null"));
        }
        let trigger = require_cstr(trigger_utf8, "trigger_utf8")?
            .to_str()
            .map_err(|_| "trigger_utf8 is not valid UTF-8".to_string())?;
        let options = if formatting_options_json_utf8.is_null() {
            ""
        } else {
            require_cstr(formatting_options_json_utf8, "formatting_options_json_utf8")?
                .to_str()
                .map_err(|_| "formatting_options_json_utf8 is not valid UTF-8".to_string())?
        };

        let applied = ui
            .lsp_format_on_type(
                logical_line as usize,
                logical_column as usize,
                trigger,
                options,
                timeout_ms,
            )
            .map_err(map_ui_error)?;
        unsafe {
            *out_applied = if applied { 1 } else { 0 };
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

/// Poll and apply any completed async processing (Tree-sitter highlighting/folding).
///
/// This is non-blocking: it never waits for the worker thread.
///
/// - `out_applied`: set to 1 if new edits were applied.
/// - `out_pending`: set to 1 if there is still pending work.
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

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `capture_utf8` must be a valid null-terminated UTF-8 C string pointer.
/// `out_style_id` must be a valid pointer to a `u32`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_treesitter_style_id_for_capture(
    ui: *mut EditorUi,
    capture_utf8: *const c_char,
    out_style_id: *mut u32,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_style_id.is_null() {
            return Err(invalid_argument("out_style_id is null"));
        }
        let capture = require_cstr(capture_utf8, "capture_utf8")?
            .to_str()
            .map_err(|_| "capture_utf8 is not valid UTF-8".to_string())?;
        let style_id = ui.treesitter_style_id_for_capture(capture);
        unsafe {
            *out_style_id = style_id;
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

/// Map a Tree-sitter capture style id to its capture name.
///
/// Returns an allocated C string. Caller must free with [`editor_core_ui_ffi_string_free`].
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_treesitter_capture_for_style_id(
    ui: *mut EditorUi,
    style_id: u32,
) -> *mut c_char {
    let default = ptr::null_mut();
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let name = ui
            .treesitter_capture_for_style_id(style_id)
            .ok_or_else(|| "unknown style_id".to_string())?;
        Ok(make_c_string_ptr(name.to_string()))
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
