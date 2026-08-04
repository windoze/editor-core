use super::*;

fn parse_recent_uris(
    uris_json_utf8: *const c_char,
    parameter_name: &'static str,
) -> Result<Vec<String>, String> {
    let uris_json = require_str(uris_json_utf8, parameter_name)?;
    serde_json::from_str::<Vec<String>>(uris_json).map_err(|err| {
        invalid_argument(format!(
            "{parameter_name} must be a JSON string array: {err}"
        ))
    })
}

fn parse_recent_file_uris(uris_json_utf8: *const c_char) -> Result<Vec<String>, String> {
    parse_recent_uris(uris_json_utf8, "uris_json_utf8")
}

fn parse_recent_project_uris(uris_json_utf8: *const c_char) -> Result<Vec<String>, String> {
    parse_recent_uris(uris_json_utf8, "uris_json_utf8")
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_remember_recent_file_uri(
    multi: *mut MultiDocumentEditorUi,
    uri_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let uri = require_str(uri_utf8, "uri_utf8")?;
        multi.remember_recent_file_uri(uri);
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
pub extern "C" fn editor_core_ui_ffi_multi_document_restore_recent_files_json(
    multi: *mut MultiDocumentEditorUi,
    uris_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let uris = parse_recent_file_uris(uris_json_utf8)?;
        multi.restore_recent_file_uris(uris);
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
pub extern "C" fn editor_core_ui_ffi_multi_document_clear_recent_files(
    multi: *mut MultiDocumentEditorUi,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi.clear_recent_file_uris();
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
pub extern "C" fn editor_core_ui_ffi_multi_document_recent_files_json(
    multi: *mut MultiDocumentEditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        serde_json::to_string(&multi.recent_file_entries())
            .map_err(|err| format!("failed to encode recent files: {err}"))
    }) {
        Ok(json) => {
            clear_last_error();
            make_c_string_ptr(json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_remember_recent_project_uri(
    multi: *mut MultiDocumentEditorUi,
    uri_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let uri = require_str(uri_utf8, "uri_utf8")?;
        multi.remember_recent_project_uri(uri);
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
pub extern "C" fn editor_core_ui_ffi_multi_document_restore_recent_projects_json(
    multi: *mut MultiDocumentEditorUi,
    uris_json_utf8: *const c_char,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let uris = parse_recent_project_uris(uris_json_utf8)?;
        multi.restore_recent_project_uris(uris);
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
pub extern "C" fn editor_core_ui_ffi_multi_document_clear_recent_projects(
    multi: *mut MultiDocumentEditorUi,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi.clear_recent_project_uris();
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
pub extern "C" fn editor_core_ui_ffi_multi_document_recent_projects_json(
    multi: *mut MultiDocumentEditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        serde_json::to_string(&multi.recent_project_entries())
            .map_err(|err| format!("failed to encode recent projects: {err}"))
    }) {
        Ok(json) => {
            clear_last_error();
            make_c_string_ptr(json)
        }
        Err(err) => {
            set_last_error_from_error(err);
            ptr::null_mut()
        }
    }
}
