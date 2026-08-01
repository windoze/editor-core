use super::*;

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_json(
    ui: *mut EditorUi,
    workspace_edit_json_utf8: *const c_char,
    document_uri_utf8: *const c_char,
) -> *mut c_char {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let workspace_edit_json =
            require_cstr(workspace_edit_json_utf8, "workspace_edit_json_utf8")?
                .to_str()
                .map_err(|_| "workspace_edit_json_utf8 is not valid UTF-8".to_string())?;
        let document_uri = if document_uri_utf8.is_null() {
            None
        } else {
            Some(
                require_cstr(document_uri_utf8, "document_uri_utf8")?
                    .to_str()
                    .map_err(|_| "document_uri_utf8 is not valid UTF-8".to_string())?,
            )
        };
        ui.lsp_apply_workspace_edit_json(workspace_edit_json, document_uri)
            .map(make_c_string_ptr)
            .map_err(map_ui_error)
    }) {
        Ok(ptr) => {
            clear_last_error();
            ptr
        }
        Err(err) => {
            set_last_error(err);
            ptr::null_mut()
        }
    }
}
