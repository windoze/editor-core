use super::*;

/// Convert a local path to `file://` URI.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_path_to_file_uri(path: *const c_char) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_path_to_file_uri_value(path).map_err(|(_, message)| message)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_path_to_file_uri_envelope_json(
    path: *const c_char,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("path_to_file_uri", || lsp_path_to_file_uri_value(path))
}

fn lsp_path_to_file_uri_value(path: *const c_char) -> Result<Value, (EcfStatus, String)> {
    let path = require_string_status(path, "path")?;
    let uri = path_to_file_uri(Path::new(&path));
    Ok(json!({ "uri": uri }))
}

/// Convert a `file://` URI to path.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_file_uri_to_path(uri: *const c_char) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_file_uri_to_path_value(uri).map_err(|(_, message)| message)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_file_uri_to_path_envelope_json(
    uri: *const c_char,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("file_uri_to_path", || lsp_file_uri_to_path_value(uri))
}

fn lsp_file_uri_to_path_value(uri: *const c_char) -> Result<Value, (EcfStatus, String)> {
    let uri = require_string_status(uri, "uri")?;
    let path = file_uri_to_path(&uri)
        .map(|p| p.to_string_lossy().to_string())
        .ok_or_else(|| (EcfStatus::InvalidArgument, "invalid file URI".to_string()))?;
    Ok(json!({ "path": path }))
}

/// Percent-encode a path segment.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_percent_encode_path(path: *const c_char) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_percent_encode_path_value(path).map_err(|(_, message)| message)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_percent_encode_path_envelope_json(
    path: *const c_char,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("percent_encode_path", || {
        lsp_percent_encode_path_value(path)
    })
}

fn lsp_percent_encode_path_value(path: *const c_char) -> Result<Value, (EcfStatus, String)> {
    let path = require_string_status(path, "path")?;
    Ok(json!({ "encoded": percent_encode_path(&path) }))
}

/// Percent-decode a path segment.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_percent_decode_path(path: *const c_char) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_percent_decode_path_value(path).map_err(|(_, message)| message)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_percent_decode_path_envelope_json(
    path: *const c_char,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("percent_decode_path", || {
        lsp_percent_decode_path_value(path)
    })
}

fn lsp_percent_decode_path_value(path: *const c_char) -> Result<Value, (EcfStatus, String)> {
    let path = require_string_status(path, "path")?;
    Ok(json!({ "decoded": percent_decode_path(&path) }))
}

/// Convert char offset to UTF-16 code units for one line of text.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_char_offset_to_utf16(
    line_text: *const c_char,
    char_offset: u64,
) -> u64 {
    match ffi_catch(|| {
        let line_text = require_string(line_text, "line_text")?;
        let char_offset = usize_from_u64(char_offset, "char_offset")?;
        let utf16_offset = LspCoordinateConverter::char_offset_to_utf16(&line_text, char_offset);
        u64_from_usize(utf16_offset, "utf16_offset")
    }) {
        Ok(v) => {
            clear_last_error();
            v
        }
        Err(err) => {
            set_last_error(err);
            0
        }
    }
}

/// Convert UTF-16 code units to char offset for one line of text.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_utf16_to_char_offset(
    line_text: *const c_char,
    utf16_offset: u64,
) -> u64 {
    match ffi_catch(|| {
        let line_text = require_string(line_text, "line_text")?;
        let utf16_offset = usize_from_u64(utf16_offset, "utf16_offset")?;
        let char_offset = LspCoordinateConverter::utf16_to_char_offset(&line_text, utf16_offset);
        u64_from_usize(char_offset, "char_offset")
    }) {
        Ok(v) => {
            clear_last_error();
            v
        }
        Err(err) => {
            set_last_error(err);
            0
        }
    }
}

/// Build minimal LSP `FormattingOptions` JSON.
///
/// This is primarily useful for indentation and on-type formatting requests.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_formatting_options_json(
    tab_size: u32,
    insert_spaces: bool,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_formatting_options_value(tab_size, insert_spaces).map_err(|(_, message)| message)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_formatting_options_envelope_json(
    tab_size: u32,
    insert_spaces: bool,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("formatting_options", || {
        lsp_formatting_options_value(tab_size, insert_spaces)
    })
}

fn lsp_formatting_options_value(
    tab_size: u32,
    insert_spaces: bool,
) -> Result<Value, (EcfStatus, String)> {
    let tab_size = status_usize_from_u32(tab_size, "tab_size")?;
    Ok(json!({ "options": lsp_formatting_options(tab_size, insert_spaces) }))
}

/// Build LSP `FormattingOptions` JSON from an `editor-core` indentation config JSON.
///
/// `indentation_config_json` uses the same shape as the JSON command bridge:
///
/// ```json
/// { "style": { "kind": "spaces", "width": 4 } }
/// ```
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_formatting_options_for_indentation_config_json(
    indentation_config_json: *const c_char,
    tab_width: u32,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_formatting_options_for_indentation_config_value(indentation_config_json, tab_width)
            .map_err(|(_, message)| message)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_formatting_options_for_indentation_config_envelope_json(
    indentation_config_json: *const c_char,
    tab_width: u32,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("formatting_options_for_indentation_config", || {
        lsp_formatting_options_for_indentation_config_value(indentation_config_json, tab_width)
    })
}

fn lsp_formatting_options_for_indentation_config_value(
    indentation_config_json: *const c_char,
    tab_width: u32,
) -> Result<Value, (EcfStatus, String)> {
    let json_text = require_string_status(indentation_config_json, "indentation_config_json")?;
    let cfg: FfiIndentationConfig = parse_json(&json_text, "indentation config")
        .map_err(|message| (EcfStatus::Parse, message))?;
    let cfg: IndentationConfig = cfg.into();
    let tab_width = status_usize_from_u32(tab_width, "tab_width")?;
    Ok(json!({
        "options": lsp_formatting_options_for_indentation_config(&cfg, tab_width)
    }))
}

/// Build LSP `textDocument/onTypeFormatting` params JSON for the current cursor position.
///
/// Notes:
/// - `options_json` is optional (nullable). When null, `{}` is used.
/// - The returned payload is the *params object* (not a full JSON-RPC envelope).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_on_type_formatting_params_json(
    state: *const EcfEditorState,
    uri: *const c_char,
    ch: *const c_char,
    options_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_on_type_formatting_params_value(state, uri, ch, options_json)
            .map_err(|(_, message)| message)
    })
}

pub(crate) fn lsp_on_type_formatting_params_value(
    state: *const EcfEditorState,
    uri: *const c_char,
    ch: *const c_char,
    options_json: *const c_char,
) -> Result<Value, (EcfStatus, String)> {
    let state = require_ref_status(state, "state")?;
    let uri = require_string_status(uri, "uri")?;
    let ch = require_string_status(ch, "ch")?;

    let options = if let Some(options_json) = optional_string_status(options_json, "options_json")?
    {
        parse_json_value_status(&options_json, "formatting options")?
    } else {
        json!({})
    };

    let pos = state.inner.editor().cursor_position();
    let line_text = state
        .inner
        .editor()
        .line_index()
        .get_line_text(pos.line)
        .unwrap_or_default();
    let utf16_character = LspCoordinateConverter::char_offset_to_utf16(&line_text, pos.column);

    Ok(json!({
        "params": {
            "textDocument": { "uri": uri },
            "position": { "line": pos.line, "character": utf16_character },
            "ch": ch,
            "options": options,
        }
    }))
}

/// Apply LSP `TextEdit[]` JSON to an editor state.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_apply_text_edits_json(
    state: *mut EcfEditorState,
    edits_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_apply_text_edits_value(state, edits_json).map_err(|(_, message)| message)
    })
}

pub(crate) fn lsp_apply_text_edits_value(
    state: *mut EcfEditorState,
    edits_json: *const c_char,
) -> Result<Value, (EcfStatus, String)> {
    let state = require_mut_status(state, "state")?;
    let edits_json = require_string_status(edits_json, "edits_json")?;
    let value = parse_json_value_status(&edits_json, "LSP text edits")?;
    let edits = text_edits_from_value(&value);
    let changed = apply_text_edits(&mut state.inner, &edits).map_err(|err| {
        (
            EcfStatus::CommandFailed,
            format!("apply LSP text edits failed: {err}"),
        )
    })?;
    Ok(json!({
        "changed_ranges": changed
            .into_iter()
            .map(|(start, end)| value_offset_range(start, end))
            .collect::<Vec<_>>()
    }))
}

/// Convert semantic tokens data (`u32[]`) into style intervals for current state text.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_semantic_tokens_to_intervals_json(
    state: *const EcfEditorState,
    data_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_semantic_tokens_to_intervals_value(state, data_json).map_err(|(_, message)| message)
    })
}

pub(crate) fn lsp_semantic_tokens_to_intervals_value(
    state: *const EcfEditorState,
    data_json: *const c_char,
) -> Result<Value, (EcfStatus, String)> {
    let state = require_ref_status(state, "state")?;
    let data_json = require_string_status(data_json, "data_json")?;
    let data: Vec<u32> = parse_json_status(&data_json, "semantic tokens data")?;
    let intervals = semantic_tokens_to_intervals(
        &data,
        state.inner.editor().line_index(),
        encode_semantic_style_id,
    )
    .map_err(|err| {
        (
            EcfStatus::InvalidArgument,
            format!("semantic_tokens_to_intervals failed: {err}"),
        )
    })?;

    Ok(json!({
        "intervals": intervals.iter().map(value_interval).collect::<Vec<_>>()
    }))
}

/// Decode default semantic style id into `(token_type, token_modifiers)`.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_decode_semantic_style_id(style_id: u32) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_decode_semantic_style_id_value(style_id).map_err(|(_, message)| message)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_decode_semantic_style_id_envelope_json(
    style_id: u32,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("decode_semantic_style_id", || {
        lsp_decode_semantic_style_id_value(style_id)
    })
}

fn lsp_decode_semantic_style_id_value(style_id: u32) -> Result<Value, (EcfStatus, String)> {
    let (token_type, token_modifiers) = decode_semantic_style_id(style_id);
    Ok(json!({
        "token_type": token_type,
        "token_modifiers": token_modifiers,
    }))
}

/// Convert LSP document highlights result JSON into one processing edit JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_document_highlights_to_processing_edit_json(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_document_highlights_processing_edit_value(state, result_json)
            .map_err(|(_, message)| message)
    })
}

pub(crate) fn lsp_document_highlights_processing_edit_value(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> Result<Value, (EcfStatus, String)> {
    lsp_single_processing_edit_from_state_value(state, result_json, |line_index, value| {
        lsp_document_highlights_to_processing_edit(line_index, value)
    })
}

/// Convert LSP inlay hints result JSON into one processing edit JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_inlay_hints_to_processing_edit_json(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_inlay_hints_processing_edit_value(state, result_json).map_err(|(_, message)| message)
    })
}

pub(crate) fn lsp_inlay_hints_processing_edit_value(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> Result<Value, (EcfStatus, String)> {
    lsp_single_processing_edit_from_state_value(state, result_json, |line_index, value| {
        lsp_inlay_hints_to_processing_edit(line_index, value)
    })
}

/// Convert LSP document links result JSON into one processing edit JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_document_links_to_processing_edit_json(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_document_links_processing_edit_value(state, result_json).map_err(|(_, message)| message)
    })
}

pub(crate) fn lsp_document_links_processing_edit_value(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> Result<Value, (EcfStatus, String)> {
    lsp_single_processing_edit_from_state_value(state, result_json, |line_index, value| {
        lsp_document_links_to_processing_edit(line_index, value)
    })
}

/// Convert LSP code lens result JSON into one processing edit JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_code_lens_to_processing_edit_json(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_code_lens_processing_edit_value(state, result_json).map_err(|(_, message)| message)
    })
}

pub(crate) fn lsp_code_lens_processing_edit_value(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> Result<Value, (EcfStatus, String)> {
    lsp_single_processing_edit_from_state_value(state, result_json, |line_index, value| {
        lsp_code_lens_to_processing_edit(line_index, value)
    })
}

/// Convert LSP document symbols result JSON into one processing edit JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_document_symbols_to_processing_edit_json(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_document_symbols_processing_edit_value(state, result_json)
            .map_err(|(_, message)| message)
    })
}

pub(crate) fn lsp_document_symbols_processing_edit_value(
    state: *const EcfEditorState,
    result_json: *const c_char,
) -> Result<Value, (EcfStatus, String)> {
    lsp_single_processing_edit_from_state_value(state, result_json, |line_index, value| {
        lsp_document_symbols_to_processing_edit(line_index, value)
    })
}

/// Convert LSP diagnostics notification params JSON into processing edits JSON array.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_diagnostics_to_processing_edits_json(
    state: *const EcfEditorState,
    publish_diagnostics_params_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_diagnostics_processing_edits_value(state, publish_diagnostics_params_json)
            .map_err(|(_, message)| message)
    })
}

pub(crate) fn lsp_diagnostics_processing_edits_value(
    state: *const EcfEditorState,
    publish_diagnostics_params_json: *const c_char,
) -> Result<Value, (EcfStatus, String)> {
    let state = require_ref_status(state, "state")?;
    let params_json = require_string_status(
        publish_diagnostics_params_json,
        "publish_diagnostics_params_json",
    )?;
    let params_value = parse_json_value_status(&params_json, "publishDiagnostics params")?;

    let notification = editor_core_lsp::LspNotification::from_method_and_params(
        "textDocument/publishDiagnostics",
        &params_value,
    )
    .ok_or_else(|| {
        (
            EcfStatus::InvalidArgument,
            "invalid publishDiagnostics params".to_string(),
        )
    })?;

    let editor_core_lsp::LspNotification::PublishDiagnostics(params) = notification else {
        return Err((
            EcfStatus::InvalidArgument,
            "invalid publishDiagnostics payload".to_string(),
        ));
    };

    let edits = lsp_diagnostics_to_processing_edits(state.inner.editor().line_index(), &params);
    Ok(json!({
        "edits": edits.iter().map(value_processing_edit).collect::<Vec<_>>()
    }))
}

/// Convert LSP workspace symbol result JSON into workspace symbols JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_workspace_symbols_json(
    result_json: *const c_char,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_workspace_symbols_value(result_json).map_err(|(_, message)| message)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_workspace_symbols_envelope_json(
    result_json: *const c_char,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("workspace_symbols", || {
        lsp_workspace_symbols_value(result_json)
    })
}

fn lsp_workspace_symbols_value(result_json: *const c_char) -> Result<Value, (EcfStatus, String)> {
    let result_json = require_string_status(result_json, "result_json")?;
    let value = parse_json_value(&result_json, "workspace symbols")
        .map_err(|message| (EcfStatus::Parse, message))?;
    let symbols = lsp_workspace_symbols_to_results(&value);
    Ok(json!({
        "symbols": symbols.iter().map(value_workspace_symbol).collect::<Vec<_>>()
    }))
}

/// Normalize LSP locations result JSON (`Location|Location[]|LocationLink|LocationLink[]`).
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_locations_json(result_json: *const c_char) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_locations_value(result_json).map_err(|(_, message)| message)
    })
}

#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_locations_envelope_json(
    result_json: *const c_char,
) -> *mut c_char {
    lsp_helper_envelope_json_ptr("locations", || lsp_locations_value(result_json))
}

fn lsp_locations_value(result_json: *const c_char) -> Result<Value, (EcfStatus, String)> {
    let result_json = require_string_status(result_json, "result_json")?;
    let value = parse_json_value(&result_json, "locations")
        .map_err(|message| (EcfStatus::Parse, message))?;
    let locations = locations_from_value(&value);
    Ok(json!({
        "locations": locations
            .iter()
            .map(|loc| {
                json!({
                    "uri": loc.uri,
                    "range": {
                        "start": {
                            "line": loc.range.start.line,
                            "character": loc.range.start.character,
                        },
                        "end": {
                            "line": loc.range.end.line,
                            "character": loc.range.end.character,
                        }
                    }
                })
            })
            .collect::<Vec<_>>()
    }))
}

/// Build completion text edits (`TextEditSpec[]`) from one completion item JSON.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_completion_item_to_text_edits_json(
    state: *const EcfEditorState,
    completion_item_json: *const c_char,
    mode: *const c_char,
    fallback_start: u64,
    fallback_end: u64,
    has_fallback: bool,
) -> *mut c_char {
    result_json_ptr(ptr::null_mut(), || {
        lsp_completion_item_to_text_edits_value(
            state,
            completion_item_json,
            mode,
            fallback_start,
            fallback_end,
            has_fallback,
        )
        .map_err(|(_, message)| message)
    })
}

pub(crate) fn lsp_completion_item_to_text_edits_value(
    state: *const EcfEditorState,
    completion_item_json: *const c_char,
    mode: *const c_char,
    fallback_start: u64,
    fallback_end: u64,
    has_fallback: bool,
) -> Result<Value, (EcfStatus, String)> {
    let state = require_ref_status(state, "state")?;
    let completion_item_json = require_string_status(completion_item_json, "completion_item_json")?;
    let mode = require_string_status(mode, "mode")?;

    let mode = parse_completion_mode_status(&mode)?;
    let item = parse_json_value_status(&completion_item_json, "completion item")?;
    let fallback = if has_fallback {
        Some((
            status_usize_from_u64(fallback_start, "fallback_start")?,
            status_usize_from_u64(fallback_end, "fallback_end")?,
        ))
    } else {
        None
    };

    let edits = completion_item_to_text_edit_specs(
        state.inner.editor().line_index(),
        &item,
        mode,
        fallback,
    );

    Ok(json!({
        "edits": edits
            .into_iter()
            .map(|e| json!({ "start": e.start, "end": e.end, "text": e.text }))
            .collect::<Vec<_>>()
    }))
}

/// Apply one completion item JSON as a single undoable edit.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ffi_lsp_apply_completion_item_json(
    state: *mut EcfEditorState,
    completion_item_json: *const c_char,
    mode: *const c_char,
) -> bool {
    result_bool(false, || {
        let state = require_mut(state, "state")?;
        let completion_item_json = require_string(completion_item_json, "completion_item_json")?;
        let mode = require_string(mode, "mode")?;

        let item = parse_json_value(&completion_item_json, "completion item")?;
        let mode = parse_completion_mode(&mode)?;

        apply_completion_item(&mut state.inner, &item, mode)
            .map_err(|err| format!("apply_completion_item failed: {err}"))?;
        Ok(true)
    })
}

pub(crate) fn lsp_apply_completion_item_value(
    state: *mut EcfEditorState,
    completion_item_json: *const c_char,
    mode: *const c_char,
) -> Result<Value, (EcfStatus, String)> {
    let state = require_mut_status(state, "state")?;
    let completion_item_json = require_string_status(completion_item_json, "completion_item_json")?;
    let mode = require_string_status(mode, "mode")?;

    let item = parse_json_value_status(&completion_item_json, "completion item")?;
    let mode = parse_completion_mode_status(&mode)?;

    apply_completion_item(&mut state.inner, &item, mode).map_err(|err| {
        (
            EcfStatus::CommandFailed,
            format!("apply_completion_item failed: {err}"),
        )
    })?;
    Ok(json!({ "applied": true }))
}

fn parse_completion_mode(mode: &str) -> Result<CompletionTextEditMode, String> {
    parse_completion_mode_status(mode).map_err(|(_, message)| message)
}

fn parse_completion_mode_status(mode: &str) -> Result<CompletionTextEditMode, (EcfStatus, String)> {
    match mode.trim().to_ascii_lowercase().as_str() {
        "insert" => Ok(CompletionTextEditMode::Insert),
        "replace" => Ok(CompletionTextEditMode::Replace),
        other => Err((
            EcfStatus::InvalidArgument,
            format!("invalid completion mode: {other} (expected insert|replace)"),
        )),
    }
}

fn lsp_single_processing_edit_from_state_value<F>(
    state: *const EcfEditorState,
    result_json: *const c_char,
    f: F,
) -> Result<Value, (EcfStatus, String)>
where
    F: Fn(&editor_core::LineIndex, &Value) -> ProcessingEdit,
{
    let state = require_ref_status(state, "state")?;
    let result_json = require_string_status(result_json, "result_json")?;
    let value = parse_json_value_status(&result_json, "LSP result")?;
    let edit = f(state.inner.editor().line_index(), &value);
    Ok(value_processing_edit(&edit))
}

pub(crate) fn lsp_helper_envelope_json_ptr<F>(operation: &'static str, f: F) -> *mut c_char
where
    F: FnOnce() -> Result<Value, (EcfStatus, String)>,
{
    let envelope = match std::panic::catch_unwind(std::panic::AssertUnwindSafe(f)) {
        Ok(Ok(value)) => {
            clear_last_error();
            lsp_helper_envelope_success(operation, value)
        }
        Ok(Err((status, message))) => {
            set_last_error(message.clone());
            lsp_helper_envelope_error(operation, status, message)
        }
        Err(_) => {
            let message = "panic across FFI boundary".to_string();
            set_last_error(message.clone());
            lsp_helper_envelope_error(operation, EcfStatus::Internal, message)
        }
    };
    json_ptr(envelope)
}

fn lsp_helper_envelope_success(operation: &'static str, value: Value) -> Value {
    json!({
        "ok": true,
        "status": "success",
        "operation": operation,
        "value": value,
        "error": Value::Null,
        "version": ECF_ABI_VERSION,
    })
}

fn lsp_helper_envelope_error(operation: &'static str, status: EcfStatus, message: String) -> Value {
    json!({
        "ok": false,
        "status": "error",
        "operation": operation,
        "value": Value::Null,
        "error": {
            "code": ecf_status_label(status),
            "status": status.code(),
            "message": message,
        },
        "version": ECF_ABI_VERSION,
    })
}
