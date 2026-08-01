use super::super::super::super::*;
use super::common::*;

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_prepare_call_hierarchy(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_position_ffi(ui, line, column, out_request_id, |ui, line, column| {
        ui.lsp_request_prepare_call_hierarchy(line, column)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_prepare_call_hierarchy_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_prepare_call_hierarchy_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_call_hierarchy_incoming_calls(
    ui: *mut EditorUi,
    item_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_json_ffi(
        ui,
        item_json_utf8,
        "item_json_utf8",
        out_request_id,
        |ui, json| ui.lsp_request_call_hierarchy_incoming_calls(json),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_call_hierarchy_incoming_calls_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_call_hierarchy_incoming_calls_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_call_hierarchy_outgoing_calls(
    ui: *mut EditorUi,
    item_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_json_ffi(
        ui,
        item_json_utf8,
        "item_json_utf8",
        out_request_id,
        |ui, json| ui.lsp_request_call_hierarchy_outgoing_calls(json),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_call_hierarchy_outgoing_calls_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_call_hierarchy_outgoing_calls_result_json()
    })
}

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

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_workspace_symbols(
    ui: *mut EditorUi,
    query_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }
        let query = require_cstr(query_utf8, "query_utf8")?
            .to_str()
            .map_err(|_| "query_utf8 is not valid UTF-8".to_string())?;
        let id = ui
            .lsp_request_workspace_symbols(query)
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
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_workspace_symbols_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_workspace_symbols_result_json()
    })
}
