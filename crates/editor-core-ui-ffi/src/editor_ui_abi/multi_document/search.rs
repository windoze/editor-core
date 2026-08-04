use super::*;
use editor_core::SearchOptions;
use editor_core_ui::{
    WorkspaceFileListOptions, WorkspaceFileReplacementOptions, WorkspaceFileSearchOptions,
};
use serde_json::{Value, json};

fn search_all_tabs_value(
    multi: &mut MultiDocumentEditorUi,
    query: &str,
    options: SearchOptions,
) -> Result<Value, String> {
    let results = multi
        .search_all_tabs(query, options)
        .map_err(|err| format!("search failed: {err}"))?;
    Ok(json!({
        "results": results
            .iter()
            .map(|result| json!({
                "tab_id": result.tab_id.get(),
                "matches": result
                    .matches
                    .iter()
                    .map(|m| json!({ "start": m.start, "end": m.end }))
                    .collect::<Vec<_>>(),
            }))
            .collect::<Vec<_>>(),
    }))
}

fn workspace_file_search_value(
    multi: &mut MultiDocumentEditorUi,
    query: &str,
    options: SearchOptions,
    include_globs: Vec<String>,
    exclude_globs: Vec<String>,
    max_results: u32,
) -> Result<Value, String> {
    let results = multi
        .search_workspace_files(
            query,
            options,
            WorkspaceFileSearchOptions {
                include_globs,
                exclude_globs,
                max_results: max_results as usize,
            },
        )
        .map_err(|err| format!("workspace file search failed: {err}"))?;
    Ok(json!({ "results": results }))
}

fn workspace_file_list_value(
    multi: &mut MultiDocumentEditorUi,
    include_globs: Vec<String>,
    exclude_globs: Vec<String>,
    max_results: u32,
) -> Result<Value, String> {
    let files = multi
        .list_workspace_files(WorkspaceFileListOptions {
            include_globs,
            exclude_globs,
            max_results: max_results as usize,
        })
        .map_err(|err| format!("workspace file list failed: {err}"))?;
    Ok(json!({ "files": files }))
}

fn project_file_index_snapshot_value(multi: &MultiDocumentEditorUi) -> Value {
    json!(multi.project_file_index_snapshot())
}

fn project_file_index_query_value(
    multi: &MultiDocumentEditorUi,
    query: &str,
    max_results: u32,
) -> Value {
    json!({
        "results": multi.query_project_file_index(query, max_results as usize),
    })
}

fn refresh_project_file_index_value(
    multi: &mut MultiDocumentEditorUi,
    max_results: u32,
) -> Result<Value, String> {
    let snapshot = multi
        .refresh_project_file_index(WorkspaceFileListOptions {
            include_globs: Vec::new(),
            exclude_globs: Vec::new(),
            max_results: max_results as usize,
        })
        .map_err(|err| format!("project file index refresh failed: {err}"))?;
    serde_json::to_value(snapshot)
        .map_err(|err| format!("failed to encode project file index: {err}"))
}

fn parse_globs_json(ptr: *const c_char, name: &'static str) -> Result<Vec<String>, String> {
    if ptr.is_null() {
        return Ok(Vec::new());
    }
    let json = require_str(ptr, name)?;
    if json.trim().is_empty() {
        return Ok(Vec::new());
    }
    serde_json::from_str::<Vec<String>>(json)
        .map_err(|err| invalid_argument(format!("{name} must be a JSON string array: {err}")))
}

fn parse_apply_mode(ptr: *const c_char) -> Result<String, String> {
    if ptr.is_null() {
        return Ok("atomic".to_string());
    }
    let mode = require_str(ptr, "apply_mode_utf8")?.trim();
    if mode.is_empty() {
        return Ok("atomic".to_string());
    }
    match mode {
        "partial" | "atomic" => Ok(mode.to_string()),
        other => Err(invalid_argument(format!(
            "apply_mode_utf8 must be partial or atomic, got {other}"
        ))),
    }
}

fn workspace_file_replacement_workspace_edit_value(
    multi: &mut MultiDocumentEditorUi,
    query: &str,
    replacement: &str,
    options: SearchOptions,
    include_globs: Vec<String>,
    exclude_globs: Vec<String>,
    apply_mode: String,
    max_results: u32,
) -> Result<Value, String> {
    let workspace_edit_json = multi
        .workspace_file_replacement_workspace_edit_json(
            query,
            replacement,
            options,
            WorkspaceFileReplacementOptions {
                include_globs,
                exclude_globs,
                max_results: max_results as usize,
                apply_mode,
            },
        )
        .map_err(|err| format!("workspace file replacement failed: {err}"))?;
    serde_json::from_str(&workspace_edit_json)
        .map_err(|err| format!("workspace file replacement returned invalid JSON: {err}"))
}

/// Search all open tabs and return JSON results.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_search_all_tabs_json(
    multi: *mut MultiDocumentEditorUi,
    query_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let options = SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        Ok(search_all_tabs_value(multi, query, options)?.to_string())
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

/// Search all open tabs and return results through a structured envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_search_all_tabs_envelope_json(
    multi: *mut MultiDocumentEditorUi,
    query_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
) -> *mut c_char {
    let envelope = match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let options = SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        let value = search_all_tabs_value(multi, query, options)?;
        Ok(multi_document_json_envelope_success(value))
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            multi_document_json_envelope_error(status, message)
        }
    };
    make_c_string_ptr(envelope)
}

/// Search local files under the configured workspace roots and return JSON results.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_search_workspace_files_json(
    multi: *mut MultiDocumentEditorUi,
    query_utf8: *const c_char,
    include_globs_json_utf8: *const c_char,
    exclude_globs_json_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
    max_results: u32,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let include_globs = parse_globs_json(include_globs_json_utf8, "include_globs_json_utf8")?;
        let exclude_globs = parse_globs_json(exclude_globs_json_utf8, "exclude_globs_json_utf8")?;
        let options = SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        Ok(workspace_file_search_value(
            multi,
            query,
            options,
            include_globs,
            exclude_globs,
            max_results,
        )?
        .to_string())
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

/// List local files under the configured workspace roots and return JSON results.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_list_workspace_files_json(
    multi: *mut MultiDocumentEditorUi,
    include_globs_json_utf8: *const c_char,
    exclude_globs_json_utf8: *const c_char,
    max_results: u32,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let include_globs = parse_globs_json(include_globs_json_utf8, "include_globs_json_utf8")?;
        let exclude_globs = parse_globs_json(exclude_globs_json_utf8, "exclude_globs_json_utf8")?;
        Ok(
            workspace_file_list_value(multi, include_globs, exclude_globs, max_results)?
                .to_string(),
        )
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

/// List local files under the configured workspace roots and return a structured envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_list_workspace_files_envelope_json(
    multi: *mut MultiDocumentEditorUi,
    include_globs_json_utf8: *const c_char,
    exclude_globs_json_utf8: *const c_char,
    max_results: u32,
) -> *mut c_char {
    let envelope = match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let include_globs = parse_globs_json(include_globs_json_utf8, "include_globs_json_utf8")?;
        let exclude_globs = parse_globs_json(exclude_globs_json_utf8, "exclude_globs_json_utf8")?;
        let value = workspace_file_list_value(multi, include_globs, exclude_globs, max_results)?;
        Ok(multi_document_json_envelope_success(value))
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            multi_document_json_envelope_error(status, message)
        }
    };
    make_c_string_ptr(envelope)
}

/// Refresh the core-owned project file index and return its JSON snapshot.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_refresh_project_file_index_json(
    multi: *mut MultiDocumentEditorUi,
    max_results: u32,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        Ok(refresh_project_file_index_value(multi, max_results)?.to_string())
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

/// Refresh the core-owned project file index and return a structured envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_refresh_project_file_index_envelope_json(
    multi: *mut MultiDocumentEditorUi,
    max_results: u32,
) -> *mut c_char {
    let envelope = match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let value = refresh_project_file_index_value(multi, max_results)?;
        Ok(multi_document_json_envelope_success(value))
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            multi_document_json_envelope_error(status, message)
        }
    };
    make_c_string_ptr(envelope)
}

/// Return the last core-owned project file index JSON snapshot.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_project_file_index_snapshot_json(
    multi: *mut MultiDocumentEditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        Ok(project_file_index_snapshot_value(multi).to_string())
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

/// Return the last core-owned project file index snapshot through a structured envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_project_file_index_snapshot_envelope_json(
    multi: *mut MultiDocumentEditorUi,
) -> *mut c_char {
    let envelope = match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        Ok(multi_document_json_envelope_success(
            project_file_index_snapshot_value(multi),
        ))
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            multi_document_json_envelope_error(status, message)
        }
    };
    make_c_string_ptr(envelope)
}

/// Clear the core-owned project file index snapshot.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_clear_project_file_index(
    multi: *mut MultiDocumentEditorUi,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi.clear_project_file_index();
        Ok(ECU_OK)
    }) {
        Ok(code) => {
            clear_last_error();
            code
        }
        Err(err) => status_from_error(err),
    }
}

/// Query the last core-owned project file index snapshot with fuzzy path matching.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_query_project_file_index_json(
    multi: *mut MultiDocumentEditorUi,
    query_utf8: *const c_char,
    max_results: u32,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let query = require_str(query_utf8, "query_utf8")?;
        Ok(project_file_index_query_value(multi, query, max_results).to_string())
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

/// Query the last core-owned project file index snapshot through a structured envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_query_project_file_index_envelope_json(
    multi: *mut MultiDocumentEditorUi,
    query_utf8: *const c_char,
    max_results: u32,
) -> *mut c_char {
    let envelope = match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let query = require_str(query_utf8, "query_utf8")?;
        Ok(multi_document_json_envelope_success(
            project_file_index_query_value(multi, query, max_results),
        ))
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            multi_document_json_envelope_error(status, message)
        }
    };
    make_c_string_ptr(envelope)
}

/// Search local files under the configured workspace roots and return a structured envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_search_workspace_files_envelope_json(
    multi: *mut MultiDocumentEditorUi,
    query_utf8: *const c_char,
    include_globs_json_utf8: *const c_char,
    exclude_globs_json_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
    max_results: u32,
) -> *mut c_char {
    let envelope = match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let include_globs = parse_globs_json(include_globs_json_utf8, "include_globs_json_utf8")?;
        let exclude_globs = parse_globs_json(exclude_globs_json_utf8, "exclude_globs_json_utf8")?;
        let options = SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        let value = workspace_file_search_value(
            multi,
            query,
            options,
            include_globs,
            exclude_globs,
            max_results,
        )?;
        Ok(multi_document_json_envelope_success(value))
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            multi_document_json_envelope_error(status, message)
        }
    };
    make_c_string_ptr(envelope)
}

/// Build a WorkspaceEdit JSON payload that replaces local file search matches.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_workspace_file_replacement_workspace_edit_json(
    multi: *mut MultiDocumentEditorUi,
    query_utf8: *const c_char,
    replacement_utf8: *const c_char,
    include_globs_json_utf8: *const c_char,
    exclude_globs_json_utf8: *const c_char,
    apply_mode_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
    max_results: u32,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let replacement = require_str(replacement_utf8, "replacement_utf8")?;
        let include_globs = parse_globs_json(include_globs_json_utf8, "include_globs_json_utf8")?;
        let exclude_globs = parse_globs_json(exclude_globs_json_utf8, "exclude_globs_json_utf8")?;
        let apply_mode = parse_apply_mode(apply_mode_utf8)?;
        let options = SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        multi
            .workspace_file_replacement_workspace_edit_json(
                query,
                replacement,
                options,
                WorkspaceFileReplacementOptions {
                    include_globs,
                    exclude_globs,
                    max_results: max_results as usize,
                    apply_mode,
                },
            )
            .map_err(|err| format!("workspace file replacement failed: {err}"))
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

/// Build a WorkspaceEdit JSON payload for replacements and return it through a structured envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_workspace_file_replacement_workspace_edit_envelope_json(
    multi: *mut MultiDocumentEditorUi,
    query_utf8: *const c_char,
    replacement_utf8: *const c_char,
    include_globs_json_utf8: *const c_char,
    exclude_globs_json_utf8: *const c_char,
    apply_mode_utf8: *const c_char,
    case_sensitive: u8,
    whole_word: u8,
    regex: u8,
    max_results: u32,
) -> *mut c_char {
    let envelope = match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let query = require_str(query_utf8, "query_utf8")?;
        let replacement = require_str(replacement_utf8, "replacement_utf8")?;
        let include_globs = parse_globs_json(include_globs_json_utf8, "include_globs_json_utf8")?;
        let exclude_globs = parse_globs_json(exclude_globs_json_utf8, "exclude_globs_json_utf8")?;
        let apply_mode = parse_apply_mode(apply_mode_utf8)?;
        let options = SearchOptions {
            case_sensitive: case_sensitive != 0,
            whole_word: whole_word != 0,
            regex: regex != 0,
        };
        let value = workspace_file_replacement_workspace_edit_value(
            multi,
            query,
            replacement,
            options,
            include_globs,
            exclude_globs,
            apply_mode,
            max_results,
        )?;
        Ok(multi_document_json_envelope_success(value))
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            multi_document_json_envelope_error(status, message)
        }
    };
    make_c_string_ptr(envelope)
}

fn multi_document_json_envelope_success(value: Value) -> String {
    json!({
        "ok": true,
        "status": "success",
        "value": value,
        "error": Value::Null,
        "version": ECU_ABI_VERSION,
    })
    .to_string()
}

fn multi_document_json_envelope_error(status: c_int, message: String) -> String {
    json!({
        "ok": false,
        "status": "error",
        "value": Value::Null,
        "error": {
            "code": status_code_name(status),
            "status": status,
            "message": message,
        },
        "version": ECU_ABI_VERSION,
    })
    .to_string()
}
