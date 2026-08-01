use super::super::super::*;

/// Enable an stdio LSP session for the current document.
///
/// Notes:
/// - `args_utf8` may be null or an empty string; when present it is split by whitespace.
/// - `root_uri_utf8` / `doc_uri_utf8` should be `file:///...` URIs for best server behavior.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// All C string parameters must be valid null-terminated UTF-8 pointers or null where allowed.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_enable(
    ui: *mut EditorUi,
    cmd_utf8: *const c_char,
    args_utf8: *const c_char,
    root_uri_utf8: *const c_char,
    doc_uri_utf8: *const c_char,
    language_id_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let cmd = require_cstr(cmd_utf8, "cmd_utf8")?
            .to_str()
            .map_err(|_| "cmd_utf8 is not valid UTF-8".to_string())?;
        let root_uri = require_cstr(root_uri_utf8, "root_uri_utf8")?
            .to_str()
            .map_err(|_| "root_uri_utf8 is not valid UTF-8".to_string())?;
        let doc_uri = require_cstr(doc_uri_utf8, "doc_uri_utf8")?
            .to_str()
            .map_err(|_| "doc_uri_utf8 is not valid UTF-8".to_string())?;
        let language_id = require_cstr(language_id_utf8, "language_id_utf8")?
            .to_str()
            .map_err(|_| "language_id_utf8 is not valid UTF-8".to_string())?;

        let args = if args_utf8.is_null() {
            Vec::<String>::new()
        } else {
            let s = require_cstr(args_utf8, "args_utf8")?
                .to_str()
                .map_err(|_| "args_utf8 is not valid UTF-8".to_string())?;
            s.split_whitespace().map(|p| p.to_string()).collect()
        };

        ui.lsp_enable_stdio(cmd, &args, root_uri, doc_uri, language_id)
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

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_disable(ui: *mut EditorUi) {
    ffi_void(|| {
        require_mut(ui, "ui")?.lsp_disable();
        Ok(())
    });
}

/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_enabled` must be a valid pointer to a `u8`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_is_enabled(
    ui: *mut EditorUi,
    out_enabled: *mut u8,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_enabled.is_null() {
            return Err(invalid_argument("out_enabled is null"));
        }
        unsafe {
            *out_enabled = if ui.lsp_is_enabled() { 1 } else { 0 };
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

/// Return a best-effort LSP status snapshot as JSON.
///
/// - `out_status_json_utf8` receives a newly allocated string that must be freed with
///   `editor_core_ui_ffi_string_free`.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_status_json_utf8` must be a valid pointer to a `*mut c_char`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_status_json(
    ui: *mut EditorUi,
    out_status_json_utf8: *mut *mut c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_status_json_utf8.is_null() {
            return Err(invalid_argument("out_status_json_utf8 is null"));
        }

        unsafe {
            *out_status_json_utf8 = ptr::null_mut();
        }

        let json = ui.lsp_status_json();
        unsafe {
            *out_status_json_utf8 = make_c_string_ptr(json);
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
