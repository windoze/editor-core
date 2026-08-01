use super::super::super::*;

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_diagnostics_json(
    ui: *mut EditorUi,
    publish_diagnostics_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let json = require_cstr(
            publish_diagnostics_json_utf8,
            "publish_diagnostics_json_utf8",
        )?
        .to_str()
        .map_err(|_| "publish_diagnostics_json_utf8 is not valid UTF-8".to_string())?;
        ui.lsp_apply_publish_diagnostics_json(json)
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_inlay_hints_json(
    ui: *mut EditorUi,
    inlay_hints_result_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let json = require_cstr(inlay_hints_result_json_utf8, "inlay_hints_result_json_utf8")?
            .to_str()
            .map_err(|_| "inlay_hints_result_json_utf8 is not valid UTF-8".to_string())?;
        ui.lsp_apply_inlay_hints_json(json)
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_code_lens_json(
    ui: *mut EditorUi,
    code_lens_result_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let json = require_cstr(code_lens_result_json_utf8, "code_lens_result_json_utf8")?
            .to_str()
            .map_err(|_| "code_lens_result_json_utf8 is not valid UTF-8".to_string())?;
        ui.lsp_apply_code_lens_json(json)
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_document_links_json(
    ui: *mut EditorUi,
    document_links_result_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let json = require_cstr(
            document_links_result_json_utf8,
            "document_links_result_json_utf8",
        )?
        .to_str()
        .map_err(|_| "document_links_result_json_utf8 is not valid UTF-8".to_string())?;
        ui.lsp_apply_document_links_json(json)
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_document_highlights_json(
    ui: *mut EditorUi,
    document_highlights_result_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let json = require_cstr(
            document_highlights_result_json_utf8,
            "document_highlights_result_json_utf8",
        )?
        .to_str()
        .map_err(|_| "document_highlights_result_json_utf8 is not valid UTF-8".to_string())?;
        ui.lsp_apply_document_highlights_json(json)
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_document_symbols_json(
    ui: *mut EditorUi,
    document_symbols_result_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let json = require_cstr(
            document_symbols_result_json_utf8,
            "document_symbols_result_json_utf8",
        )?
        .to_str()
        .map_err(|_| "document_symbols_result_json_utf8 is not valid UTF-8".to_string())?;
        ui.lsp_apply_document_symbols_json(json)
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

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_apply_folding_ranges_json(
    ui: *mut EditorUi,
    folding_ranges_result_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        let json = require_cstr(
            folding_ranges_result_json_utf8,
            "folding_ranges_result_json_utf8",
        )?
        .to_str()
        .map_err(|_| "folding_ranges_result_json_utf8 is not valid UTF-8".to_string())?;
        ui.lsp_apply_folding_ranges_json(json)
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
