use super::*;
use serde_json::{Value, json};

fn multi_document_snapshot_value(
    multi: &MultiDocumentEditorUi,
) -> Result<serde_json::Value, String> {
    let tabs = multi
        .tab_ids()
        .into_iter()
        .map(|tab_id| {
            let view_count = multi
                .view_count(tab_id)
                .ok_or_else(|| format!("unknown tab id {}", tab_id.get()))?;
            let active_view_index = multi
                .active_view_index(tab_id)
                .ok_or_else(|| format!("unknown tab id {}", tab_id.get()))?;
            Ok(json!({
                "id": tab_id.get(),
                "title": multi.tab_title(tab_id),
                "document_uri": multi.tab_document_uri(tab_id),
                "language_id": multi.tab_language_id(tab_id),
                "is_preview": multi.is_preview_tab(tab_id).unwrap_or(false),
                "is_active": multi.active_tab_id() == Some(tab_id),
                "is_modified": multi
                    .is_tab_modified(tab_id)
                    .map_err(|err| err.to_string())?,
                "view_count": view_count,
                "active_view_index": active_view_index,
            }))
        })
        .collect::<Result<Vec<_>, String>>()?;

    Ok(json!({
        "active_tab_id": multi.active_tab_id().map(|id| id.get()),
        "workspace_roots": multi.workspace_roots(),
        "project_lsp_servers": multi.project_lsp_server_configs(),
        "tabs": tabs,
    }))
}

fn multi_document_snapshot_json(multi: &MultiDocumentEditorUi) -> Result<String, String> {
    Ok(multi_document_snapshot_value(multi)?.to_string())
}

/// Return the active tab id, if any.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_active_tab_id(
    multi: *mut MultiDocumentEditorUi,
    out_has_active: *mut u8,
    out_tab_id: *mut u64,
) -> c_int {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let out_has_active = require_out_mut(out_has_active, "out_has_active")?;
        let out_tab_id = require_out_mut(out_tab_id, "out_tab_id")?;
        if let Some(tab_id) = multi.active_tab_id() {
            *out_has_active = 1;
            *out_tab_id = tab_id.get();
        } else {
            *out_has_active = 0;
            *out_tab_id = 0;
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

/// Return a JSON snapshot of tabs and active state.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_snapshot_json(
    multi: *mut MultiDocumentEditorUi,
) -> *mut c_char {
    match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        multi_document_snapshot_json(multi)
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

/// Return a JSON snapshot of tabs and active state through a structured envelope.
#[unsafe(no_mangle)]
pub extern "C" fn editor_core_ui_ffi_multi_document_snapshot_envelope_json(
    multi: *mut MultiDocumentEditorUi,
) -> *mut c_char {
    let envelope = match ffi_catch(|| {
        let multi = require_mut(multi, "multi")?;
        let value = multi_document_snapshot_value(multi)?;
        Ok(multi_document_snapshot_envelope_success(value))
    }) {
        Ok(envelope) => {
            clear_last_error();
            envelope
        }
        Err(err) => {
            let (status, message) = classify_error(err);
            set_last_error(message.clone());
            multi_document_snapshot_envelope_error(status, message)
        }
    };
    make_c_string_ptr(envelope)
}

fn multi_document_snapshot_envelope_success(value: Value) -> String {
    json!({
        "ok": true,
        "status": "success",
        "value": value,
        "error": Value::Null,
        "version": ECU_ABI_VERSION,
    })
    .to_string()
}

fn multi_document_snapshot_envelope_error(status: c_int, message: String) -> String {
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
