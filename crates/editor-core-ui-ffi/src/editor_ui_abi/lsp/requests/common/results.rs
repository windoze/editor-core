use super::*;
use serde_json::{Value, json};
use std::ffi::CStr;

pub(crate) fn lsp_take_result_json_ffi(
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
pub extern "C" fn editor_core_ui_ffi_editor_ui_lsp_take_last_result_envelope_json(
    ui: *mut EditorUi,
    slot_utf8: *const c_char,
) -> *mut c_char {
    let slot_for_error = best_effort_slot(slot_utf8);
    let envelope = match ffi_catch(|| {
        let slot = require_str(slot_utf8, "slot_utf8")?;
        let ui = require_mut(ui, "ui")?;
        let result_json = take_lsp_result_slot_json(ui, slot)?;
        lsp_result_envelope_success(slot, result_json)
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            lsp_result_envelope_error(slot_for_error.as_deref(), status, message)
        }
    };
    make_c_string_ptr(envelope)
}

fn best_effort_slot(slot_utf8: *const c_char) -> Option<String> {
    if slot_utf8.is_null() {
        return None;
    }
    Some(
        unsafe { CStr::from_ptr(slot_utf8) }
            .to_string_lossy()
            .into_owned(),
    )
}

fn take_lsp_result_slot_json(ui: &mut EditorUi, slot: &str) -> Result<Option<String>, String> {
    let result = match slot {
        "hover" => ui.lsp_take_last_hover_result_json(),
        "definition" => ui.lsp_take_last_definition_result_json(),
        "declaration" => ui.lsp_take_last_declaration_result_json(),
        "type_definition" => ui.lsp_take_last_type_definition_result_json(),
        "implementation" => ui.lsp_take_last_implementation_result_json(),
        "references" => ui.lsp_take_last_references_result_json(),
        "completion" => ui.lsp_take_last_completion_result_json(),
        "completion_resolve" => ui.lsp_take_last_completion_item_resolve_result_json(),
        "signature_help" => ui.lsp_take_last_signature_help_result_json(),
        "prepare_rename" => ui.lsp_take_last_prepare_rename_result_json(),
        "rename" => ui.lsp_take_last_rename_result_json(),
        "code_action" => ui.lsp_take_last_code_action_result_json(),
        "code_action_resolve" => ui.lsp_take_last_code_action_resolve_result_json(),
        "execute_command" => ui.lsp_take_last_execute_command_result_json(),
        "code_lens" => ui.lsp_take_last_code_lens_result_json(),
        "code_lens_resolve" => ui.lsp_take_last_code_lens_resolve_result_json(),
        "inlay_hints" => ui.lsp_take_last_inlay_hints_result_json(),
        "inlay_hint_resolve" => ui.lsp_take_last_inlay_hint_resolve_result_json(),
        "document_links" => ui.lsp_take_last_document_links_result_json(),
        "document_link_resolve" => ui.lsp_take_last_document_link_resolve_result_json(),
        "semantic_tokens_full" => ui.lsp_take_last_semantic_tokens_full_result_json(),
        "semantic_tokens_delta" => ui.lsp_take_last_semantic_tokens_delta_result_json(),
        "semantic_tokens_range" => ui.lsp_take_last_semantic_tokens_range_result_json(),
        "document_symbols" => ui.lsp_take_last_document_symbols_result_json(),
        "workspace_symbols" => ui.lsp_take_last_workspace_symbols_result_json(),
        "folding_ranges" => ui.lsp_take_last_folding_ranges_result_json(),
        "selection_range" => ui.lsp_take_last_selection_range_result_json(),
        "linked_editing_range" => ui.lsp_take_last_linked_editing_range_result_json(),
        "document_diagnostic" => ui.lsp_take_last_document_diagnostic_result_json(),
        "workspace_diagnostic" => ui.lsp_take_last_workspace_diagnostic_result_json(),
        "formatting" => ui.lsp_take_last_formatting_result_json(),
        "range_formatting" => ui.lsp_take_last_range_formatting_result_json(),
        "document_color" => ui.lsp_take_last_document_color_result_json(),
        "color_presentation" => ui.lsp_take_last_color_presentation_result_json(),
        "prepare_call_hierarchy" => ui.lsp_take_last_prepare_call_hierarchy_result_json(),
        "call_hierarchy_incoming" => ui.lsp_take_last_call_hierarchy_incoming_calls_result_json(),
        "call_hierarchy_outgoing" => ui.lsp_take_last_call_hierarchy_outgoing_calls_result_json(),
        "prepare_type_hierarchy" => ui.lsp_take_last_prepare_type_hierarchy_result_json(),
        "type_hierarchy_supertypes" => ui.lsp_take_last_type_hierarchy_supertypes_result_json(),
        "type_hierarchy_subtypes" => ui.lsp_take_last_type_hierarchy_subtypes_result_json(),
        "publish_diagnostics" | "on_type_formatting" => {
            return Err(invalid_argument(format!(
                "lsp result slot {slot:?} does not expose a take-last result buffer"
            )));
        }
        _ => {
            return Err(invalid_argument(format!(
                "unknown lsp result slot {slot:?}"
            )));
        }
    };
    Ok(result)
}

fn lsp_result_envelope_success(slot: &str, result_json: Option<String>) -> Result<String, String> {
    let has_result = result_json.is_some();
    let value = match result_json {
        Some(json_text) => serde_json::from_str::<Value>(&json_text)
            .map_err(|err| format!("stored LSP result JSON for slot {slot:?} is invalid: {err}"))?,
        None => Value::Null,
    };
    Ok(json!({
        "ok": true,
        "slot": slot,
        "status": if has_result { "success" } else { "empty" },
        "has_result": has_result,
        "value": value,
        "error": Value::Null,
        "version": ECU_ABI_VERSION,
    })
    .to_string())
}

fn lsp_result_envelope_error(slot: Option<&str>, status: c_int, message: String) -> String {
    json!({
        "ok": false,
        "slot": slot,
        "status": "error",
        "has_result": false,
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
