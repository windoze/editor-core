use super::*;

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_inlay_hints(
    ui: *mut EditorUi,
    start_offset: u32,
    end_offset: u32,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }
        let id = ui
            .lsp_request_inlay_hints(
                u32_to_usize(start_offset, "start_offset")?,
                u32_to_usize(end_offset, "end_offset")?,
            )
            .map_err(map_ui_error)?;
        unsafe {
            *out_request_id = id;
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

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_inlay_hints_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_inlay_hints_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_inlay_hint_resolve(
    ui: *mut EditorUi,
    hint_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_json_ffi(
        ui,
        hint_json_utf8,
        "hint_json_utf8",
        out_request_id,
        |ui, json| ui.lsp_request_inlay_hint_resolve(json),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_inlay_hint_resolve_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_inlay_hint_resolve_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_document_links(
    ui: *mut EditorUi,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_no_position_ffi(ui, out_request_id, |ui| ui.lsp_request_document_links())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_document_links_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_document_links_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_document_link_resolve(
    ui: *mut EditorUi,
    link_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_json_ffi(
        ui,
        link_json_utf8,
        "link_json_utf8",
        out_request_id,
        |ui, json| ui.lsp_request_document_link_resolve(json),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_document_link_resolve_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_document_link_resolve_result_json()
    })
}
