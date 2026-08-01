use super::super::super::super::*;

pub(super) fn lsp_request_position_ffi(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
    request: impl FnOnce(&mut EditorUi, usize, usize) -> Result<u64, editor_core_ui::UiError>,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }

        let id = request(
            ui,
            u32_to_usize(line, "line")?,
            u32_to_usize(column, "column")?,
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

pub(super) fn lsp_request_no_position_ffi(
    ui: *mut EditorUi,
    out_request_id: *mut u64,
    request: impl FnOnce(&mut EditorUi) -> Result<u64, editor_core_ui::UiError>,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }

        let id = request(ui).map_err(map_ui_error)?;
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

pub(super) fn lsp_request_json_ffi(
    ui: *mut EditorUi,
    json_utf8: *const c_char,
    json_name: &str,
    out_request_id: *mut u64,
    request: impl FnOnce(&mut EditorUi, &str) -> Result<u64, editor_core_ui::UiError>,
) -> c_int {
    match ffi_catch(|| {
        let json = require_cstr(json_utf8, json_name)?
            .to_str()
            .map_err(|_| format!("{json_name} is not valid UTF-8"))?;
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }

        let id = request(ui, json).map_err(map_ui_error)?;
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

pub(super) fn lsp_take_result_json_ffi(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
    take: impl FnOnce(&mut EditorUi) -> Option<String>,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_has_result.is_null() {
            return Err(invalid_argument("out_has_result is null"));
        }
        if out_result_json_utf8.is_null() {
            return Err(invalid_argument("out_result_json_utf8 is null"));
        }

        let json = take(ui);
        unsafe {
            if let Some(json) = json {
                *out_has_result = 1;
                *out_result_json_utf8 = make_c_string_ptr(json);
            } else {
                *out_has_result = 0;
                *out_result_json_utf8 = ptr::null_mut();
            }
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
