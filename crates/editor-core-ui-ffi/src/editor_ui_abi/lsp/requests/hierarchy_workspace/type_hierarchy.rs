use super::*;

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_prepare_type_hierarchy(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_position_ffi(ui, line, column, out_request_id, |ui, line, column| {
        ui.lsp_request_prepare_type_hierarchy(line, column)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_prepare_type_hierarchy_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_prepare_type_hierarchy_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_type_hierarchy_supertypes(
    ui: *mut EditorUi,
    item_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_json_ffi(
        ui,
        item_json_utf8,
        "item_json_utf8",
        out_request_id,
        |ui, json| ui.lsp_request_type_hierarchy_supertypes(json),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_type_hierarchy_supertypes_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_type_hierarchy_supertypes_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_type_hierarchy_subtypes(
    ui: *mut EditorUi,
    item_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_json_ffi(
        ui,
        item_json_utf8,
        "item_json_utf8",
        out_request_id,
        |ui, json| ui.lsp_request_type_hierarchy_subtypes(json),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_type_hierarchy_subtypes_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_type_hierarchy_subtypes_result_json()
    })
}
