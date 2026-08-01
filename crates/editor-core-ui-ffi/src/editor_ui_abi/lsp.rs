use super::super::*;

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

/// Request LSP hover for a logical position (0-based line/column in Unicode scalars).
///
/// This is non-blocking: the result arrives asynchronously and can be read via
/// `editor_core_ui_ffi_editor_ui_lsp_take_last_hover_json` after polling processing.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_request_id` must be a valid pointer to a `u64`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_hover(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }

        let id = ui
            .lsp_request_hover(u32_to_usize(line, "line")?, u32_to_usize(column, "column")?)
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

/// Take the last LSP hover result payload as JSON (`Hover | null`).
///
/// - On success, returns `ECU_OK` and sets:
///   - `out_has_result = 1` and `out_result_json_utf8` to a newly allocated string, or
///   - `out_has_result = 0` and `out_result_json_utf8 = NULL` when there is no new result.
///
/// Caller must free the returned string with `editor_core_ui_ffi_string_free`.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_has_result` and `out_result_json_utf8` must be valid pointers.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_hover_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_has_result.is_null() {
            return Err(invalid_argument("out_has_result is null"));
        }
        if out_result_json_utf8.is_null() {
            return Err(invalid_argument("out_result_json_utf8 is null"));
        }

        let json = ui.lsp_take_last_hover_result_json();
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

/// Request LSP go-to-definition for a logical position (0-based line/column in Unicode scalars).
///
/// This is non-blocking: the result arrives asynchronously and can be read via
/// `editor_core_ui_ffi_editor_ui_lsp_take_last_definition_json` after polling processing.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_request_id` must be a valid pointer to a `u64`.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_definition(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }

        let id = ui
            .lsp_request_definition(u32_to_usize(line, "line")?, u32_to_usize(column, "column")?)
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

/// Take the last LSP go-to-definition result payload as JSON (`Definition | null`).
///
/// - On success, returns `ECU_OK` and sets:
///   - `out_has_result = 1` and `out_result_json_utf8` to a newly allocated string, or
///   - `out_has_result = 0` and `out_result_json_utf8 = NULL` when there is no new result.
///
/// Caller must free the returned string with `editor_core_ui_ffi_string_free`.
///
/// # Safety
///
/// `ui` must be a valid pointer to an `EditorUi`.
/// `out_has_result` and `out_result_json_utf8` must be valid pointers.
#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_definition_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    match ffi_catch(|| {
        let ui = require_mut(ui, "ui")?;
        if out_has_result.is_null() {
            return Err(invalid_argument("out_has_result is null"));
        }
        if out_result_json_utf8.is_null() {
            return Err(invalid_argument("out_result_json_utf8 is null"));
        }

        let json = ui.lsp_take_last_definition_result_json();
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

fn lsp_request_position_ffi(
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

fn lsp_request_no_position_ffi(
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

fn lsp_request_json_ffi(
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

fn lsp_take_result_json_ffi(
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

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_declaration(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_position_ffi(ui, line, column, out_request_id, |ui, line, column| {
        ui.lsp_request_declaration(line, column)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_declaration_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_declaration_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_type_definition(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_position_ffi(ui, line, column, out_request_id, |ui, line, column| {
        ui.lsp_request_type_definition(line, column)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_type_definition_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_type_definition_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_implementation(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_position_ffi(ui, line, column, out_request_id, |ui, line, column| {
        ui.lsp_request_implementation(line, column)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_implementation_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_implementation_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_references(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    include_declaration: u8,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_position_ffi(ui, line, column, out_request_id, |ui, line, column| {
        ui.lsp_request_references(line, column, include_declaration != 0)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_references_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_references_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_completion(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_position_ffi(ui, line, column, out_request_id, |ui, line, column| {
        ui.lsp_request_completion(line, column)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_completion_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_completion_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_completion_item_resolve(
    ui: *mut EditorUi,
    item_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let item_json = require_cstr(item_json_utf8, "item_json_utf8")?
            .to_str()
            .map_err(|_| "item_json_utf8 is not valid UTF-8".to_string())?;
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }
        let id = ui
            .lsp_request_completion_item_resolve(item_json)
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
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_completion_item_resolve_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_completion_item_resolve_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_signature_help(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_position_ffi(ui, line, column, out_request_id, |ui, line, column| {
        ui.lsp_request_signature_help(line, column)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_signature_help_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_signature_help_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_prepare_rename(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_position_ffi(ui, line, column, out_request_id, |ui, line, column| {
        ui.lsp_request_prepare_rename(line, column)
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_prepare_rename_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_prepare_rename_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_rename(
    ui: *mut EditorUi,
    line: u32,
    column: u32,
    new_name_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let new_name = require_cstr(new_name_utf8, "new_name_utf8")?
            .to_str()
            .map_err(|_| "new_name_utf8 is not valid UTF-8".to_string())?;
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }
        let id = ui
            .lsp_request_rename(
                u32_to_usize(line, "line")?,
                u32_to_usize(column, "column")?,
                new_name,
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
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_rename_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_rename_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_code_action(
    ui: *mut EditorUi,
    start_offset: u32,
    end_offset: u32,
    context_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let context_json = require_cstr(context_json_utf8, "context_json_utf8")?
            .to_str()
            .map_err(|_| "context_json_utf8 is not valid UTF-8".to_string())?;
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }
        let id = ui
            .lsp_request_code_action(
                u32_to_usize(start_offset, "start_offset")?,
                u32_to_usize(end_offset, "end_offset")?,
                context_json,
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
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_code_action_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_code_action_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_code_action_resolve(
    ui: *mut EditorUi,
    action_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let action_json = require_cstr(action_json_utf8, "action_json_utf8")?
            .to_str()
            .map_err(|_| "action_json_utf8 is not valid UTF-8".to_string())?;
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }
        let id = ui
            .lsp_request_code_action_resolve(action_json)
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
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_code_action_resolve_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_code_action_resolve_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_execute_command(
    ui: *mut EditorUi,
    command_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let command_json = require_cstr(command_json_utf8, "command_json_utf8")?
            .to_str()
            .map_err(|_| "command_json_utf8 is not valid UTF-8".to_string())?;
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }
        let id = ui
            .lsp_request_execute_command(command_json)
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
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_execute_command_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_execute_command_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_code_lens(
    ui: *mut EditorUi,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_no_position_ffi(ui, out_request_id, |ui| ui.lsp_request_code_lens())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_code_lens_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_code_lens_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_code_lens_resolve(
    ui: *mut EditorUi,
    lens_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_json_ffi(
        ui,
        lens_json_utf8,
        "lens_json_utf8",
        out_request_id,
        |ui, json| ui.lsp_request_code_lens_resolve(json),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_code_lens_resolve_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_code_lens_resolve_result_json()
    })
}

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

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_document_diagnostic(
    ui: *mut EditorUi,
    previous_result_id_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let previous_result_id = if previous_result_id_utf8.is_null() {
            None
        } else {
            Some(
                require_cstr(previous_result_id_utf8, "previous_result_id_utf8")?
                    .to_str()
                    .map_err(|_| "previous_result_id_utf8 is not valid UTF-8".to_string())?,
            )
        };
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }
        let id = ui
            .lsp_request_document_diagnostic(previous_result_id)
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
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_document_diagnostic_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_document_diagnostic_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_workspace_diagnostic(
    ui: *mut EditorUi,
    previous_result_ids_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_json_ffi(
        ui,
        previous_result_ids_json_utf8,
        "previous_result_ids_json_utf8",
        out_request_id,
        |ui, json| ui.lsp_request_workspace_diagnostic(json),
    )
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_workspace_diagnostic_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_workspace_diagnostic_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_document_color(
    ui: *mut EditorUi,
    out_request_id: *mut u64,
) -> c_int {
    lsp_request_no_position_ffi(ui, out_request_id, |ui| ui.lsp_request_document_color())
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_document_color_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_document_color_result_json()
    })
}

#[unsafe(no_mangle)]
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_request_color_presentation(
    ui: *mut EditorUi,
    start_offset: u32,
    end_offset: u32,
    color_json_utf8: *const c_char,
    out_request_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let color_json = require_cstr(color_json_utf8, "color_json_utf8")?
            .to_str()
            .map_err(|_| "color_json_utf8 is not valid UTF-8".to_string())?;
        let ui = require_mut(ui, "ui")?;
        if out_request_id.is_null() {
            return Err(invalid_argument("out_request_id is null"));
        }
        let id = ui
            .lsp_request_color_presentation(
                u32_to_usize(start_offset, "start_offset")?,
                u32_to_usize(end_offset, "end_offset")?,
                color_json,
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
pub unsafe extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_color_presentation_json(
    ui: *mut EditorUi,
    out_has_result: *mut u8,
    out_result_json_utf8: *mut *mut c_char,
) -> c_int {
    lsp_take_result_json_ffi(ui, out_has_result, out_result_json_utf8, |ui| {
        ui.lsp_take_last_color_presentation_result_json()
    })
}

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

/// Format the current document via LSP (`textDocument/formatting`) and apply edits locally.
///
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
