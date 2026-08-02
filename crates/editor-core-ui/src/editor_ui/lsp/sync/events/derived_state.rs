use super::super::super::super::*;
use super::EventOutcome;

fn derived_request_slot(method: &str) -> Option<LspResultSlot> {
    match method {
        "textDocument/semanticTokens/full" => Some(LspResultSlot::SemanticTokensFull),
        "textDocument/semanticTokens/full/delta" => Some(LspResultSlot::SemanticTokensDelta),
        "textDocument/semanticTokens/range" => Some(LspResultSlot::SemanticTokensRange),
        "textDocument/foldingRange" => Some(LspResultSlot::FoldingRanges),
        "textDocument/publishDiagnostics" => Some(LspResultSlot::PublishDiagnostics),
        _ => None,
    }
}

fn derived_request_status(
    status: editor_core_lsp::LspDerivedRequestStatus,
) -> EditorLspRequestEventStatus {
    match status {
        editor_core_lsp::LspDerivedRequestStatus::Pending => EditorLspRequestEventStatus::Pending,
        editor_core_lsp::LspDerivedRequestStatus::Success => EditorLspRequestEventStatus::Success,
        editor_core_lsp::LspDerivedRequestStatus::Empty => EditorLspRequestEventStatus::Empty,
        editor_core_lsp::LspDerivedRequestStatus::Error => EditorLspRequestEventStatus::Error,
        editor_core_lsp::LspDerivedRequestStatus::Stale => EditorLspRequestEventStatus::Stale,
    }
}

pub(super) fn record_lsp_derived_request_event(
    doc: &mut EditorUiDoc,
    view_id: ViewId,
    event: &editor_core_lsp::LspDerivedRequestEvent,
) -> EventOutcome {
    let Some(slot) = derived_request_slot(event.method.as_str()) else {
        return EventOutcome::Unhandled;
    };
    if let Some(doc_uri) = doc.lsp_document_uri.as_deref() {
        if doc_uri != event.uri {
            return EventOutcome::Unhandled;
        }
    }

    match event.phase {
        editor_core_lsp::LspDerivedRequestPhase::Started => {
            doc.record_lsp_request_started(view_id, slot, event.id);
        }
        editor_core_lsp::LspDerivedRequestPhase::Completed => {
            doc.record_lsp_request_completed(
                view_id,
                slot,
                event.id,
                derived_request_status(event.status),
                None,
                event.error.as_ref(),
            );
        }
    }

    EventOutcome::Handled
}

pub(super) fn handle_lsp_derived_state_response(
    doc: &mut EditorUiDoc,
    view_id: ViewId,
    resp: &editor_core_lsp::LspResponse,
    applied: &mut bool,
) -> Result<EventOutcome, UiError> {
    match resp.method.as_str() {
        "textDocument/inlayHint" => {
            doc.lsp_inlay_in_flight = false;
            let result = resp.result.clone().unwrap_or(serde_json::Value::Null);
            let edit = match doc.ws.buffer_line_index(doc.buffer_id) {
                Ok(line_index) => lsp_inlay_hints_to_processing_edit(line_index, &result),
                Err(_) => {
                    doc.fail_lsp_and_record_status(view_id, "LSP buffer line index unavailable");
                    return Ok(EventOutcome::Abort);
                }
            };
            *applied |= doc.apply_lsp_processing_edits(view_id, [edit])?;
            Ok(EventOutcome::Handled)
        }
        "textDocument/codeLens" => {
            doc.lsp_code_lens_in_flight = false;
            let result = resp.result.clone().unwrap_or(serde_json::Value::Null);
            let edit = match doc.ws.buffer_line_index(doc.buffer_id) {
                Ok(line_index) => lsp_code_lens_to_processing_edit(line_index, &result),
                Err(_) => {
                    doc.fail_lsp_and_record_status(view_id, "LSP buffer line index unavailable");
                    return Ok(EventOutcome::Abort);
                }
            };
            *applied |= doc.apply_lsp_processing_edits(view_id, [edit])?;
            Ok(EventOutcome::Handled)
        }
        "textDocument/documentLink" => {
            doc.lsp_document_links_in_flight = false;
            let result = resp.result.clone().unwrap_or(serde_json::Value::Null);
            let edits = match doc.ws.buffer_line_index(doc.buffer_id) {
                Ok(line_index) => lsp_document_links_to_processing_edits(line_index, &result),
                Err(_) => {
                    doc.fail_lsp_and_record_status(view_id, "LSP buffer line index unavailable");
                    return Ok(EventOutcome::Abort);
                }
            };
            *applied |= doc.apply_lsp_processing_edits(view_id, edits)?;
            Ok(EventOutcome::Handled)
        }
        _ => Ok(EventOutcome::Unhandled),
    }
}
