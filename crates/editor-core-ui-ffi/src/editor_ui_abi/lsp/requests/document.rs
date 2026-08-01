use super::super::super::super::*;
use super::common::*;

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_document_symbols(
    ui: *mut EditorUi,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_no_position_ffi(ui, out_request_id, |ui| ui.lsp_request_document_symbols())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_document_symbols_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_document_symbols_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_folding_ranges(
    ui: *mut EditorUi,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_no_position_ffi(ui, out_request_id, |ui| ui.lsp_request_folding_ranges())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_folding_ranges_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_folding_ranges_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_selection_range(
    ui: *mut EditorUi,
    positions_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_json_ffi(
        ui,
        positions_json_utf8,
        "positions_json_utf8",
        out_request_id,
        |ui, json| ui.lsp_request_selection_range(json),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_selection_range_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_selection_range_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_linked_editing_range(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_position_ffi(ui, line, column, out_request_id, |ui, line, column| {
        ui.lsp_request_linked_editing_range(line, column)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_linked_editing_range_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_linked_editing_range_result_json()
    })
}
