use super::*;

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
