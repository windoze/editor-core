use super::super::super::super::*;
use super::EventOutcome;

pub(super) fn collect_on_type_formatting_result(
    doc: &mut EditorUiDoc,
    resp: &editor_core_lsp::LspResponse,
    out: &mut Vec<serde_json::Value>,
) -> Result<EventOutcome, UiError> {
    if resp.method.as_str() != "textDocument/onTypeFormatting" {
        return Ok(EventOutcome::Unhandled);
    }

    if let Some(LspClientRequest::OnTypeFormatting { view, version }) =
        doc.lsp_client_requests.remove(&resp.id)
    {
        if doc.lsp_latest_on_type_formatting_request_id.get(&view) != Some(&resp.id) {
            doc.record_lsp_request_completed(
                view,
                LspResultSlot::OnTypeFormatting,
                resp.id,
                EditorLspRequestEventStatus::Stale,
                None,
                None,
            );
            return Ok(EventOutcome::Handled);
        }
        doc.lsp_latest_on_type_formatting_request_id.remove(&view);
        if doc.text_version != version {
            doc.record_lsp_request_completed(
                view,
                LspResultSlot::OnTypeFormatting,
                resp.id,
                EditorLspRequestEventStatus::Stale,
                None,
                None,
            );
            return Ok(EventOutcome::Handled);
        }
        if let Some(error) = resp.error.clone() {
            doc.record_lsp_request_completed(
                view,
                LspResultSlot::OnTypeFormatting,
                resp.id,
                EditorLspRequestEventStatus::Error,
                None,
                Some(&error),
            );
            doc.lsp_fail(format!(
                "LSP on-type formatting failed: {} (code {})",
                error.message, error.code
            ));
            return Ok(EventOutcome::Abort);
        }

        let result = resp.result.clone().unwrap_or(serde_json::Value::Null);
        if result.is_null() {
            doc.record_lsp_request_completed(
                view,
                LspResultSlot::OnTypeFormatting,
                resp.id,
                EditorLspRequestEventStatus::Empty,
                None,
                None,
            );
        } else {
            doc.record_lsp_request_completed(
                view,
                LspResultSlot::OnTypeFormatting,
                resp.id,
                EditorLspRequestEventStatus::Success,
                None,
                None,
            );
            out.push(result);
        }
    }

    Ok(EventOutcome::Handled)
}

pub(super) fn apply_on_type_formatting_results(
    ui: &mut EditorUi,
    results: Vec<serde_json::Value>,
    applied: &mut bool,
) -> Result<bool, UiError> {
    for result in results {
        match ui.lsp_apply_text_edits_value(ui.buffer_id, &result) {
            Ok(did_apply) => {
                if did_apply {
                    *applied = true;
                }
            }
            Err(err) => {
                let mut doc = ui.lock_doc();
                doc.lsp_fail(err.to_string());
                return Ok(false);
            }
        }
    }
    Ok(true)
}
