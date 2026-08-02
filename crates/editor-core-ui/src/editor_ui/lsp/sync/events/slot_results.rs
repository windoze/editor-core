use super::super::super::super::*;
use super::EventOutcome;

pub(super) fn handle_lsp_result_slot_response(
    doc: &mut EditorUiDoc,
    resp: &editor_core_lsp::LspResponse,
    slot: LspResultSlot,
    applied: &mut bool,
) -> Result<EventOutcome, UiError> {
    let Some(LspClientRequest::Result {
        view,
        slot: request_slot,
    }) = doc.lsp_client_requests.remove(&resp.id)
    else {
        return Ok(EventOutcome::Unhandled);
    };

    if request_slot != slot {
        doc.record_lsp_request_completed(
            view,
            request_slot,
            resp.id,
            EditorLspRequestEventStatus::Mismatched,
            None,
            None,
        );
        return Ok(EventOutcome::Handled);
    }
    if doc.lsp_latest_result_request_id.get(&(view, slot)) != Some(&resp.id) {
        doc.record_lsp_request_completed(
            view,
            slot,
            resp.id,
            EditorLspRequestEventStatus::Stale,
            None,
            None,
        );
        return Ok(EventOutcome::Handled);
    }

    if let Some(error) = resp.error.clone() {
        if slot == LspResultSlot::CodeLens {
            doc.lsp_code_lens_in_flight = false;
        }
        let stored_json = stored_lsp_error_result_json(slot, error.clone());
        let result_json_len = stored_json.as_ref().map_or(0, String::len);
        if let Some(json) = stored_json {
            doc.lsp_last_result_json.insert((view, slot), json);
        } else {
            doc.lsp_last_result_json.remove(&(view, slot));
        }
        let result_sequence = doc.record_lsp_result_event(
            view,
            slot,
            resp.id,
            EditorLspResultEventStatus::Error,
            result_json_len,
            Some(&error),
        );
        doc.record_lsp_request_completed(
            view,
            slot,
            resp.id,
            EditorLspRequestEventStatus::Error,
            Some(result_sequence),
            Some(&error),
        );
        return Ok(EventOutcome::Handled);
    }

    let result = resp.result.clone().unwrap_or(serde_json::Value::Null);
    match slot {
        LspResultSlot::DocumentSymbols => {
            let edit = match doc.ws.buffer_line_index(doc.buffer_id) {
                Ok(line_index) => lsp_document_symbols_to_processing_edit(line_index, &result),
                Err(_) => {
                    doc.lsp_fail("LSP buffer line index unavailable");
                    return Ok(EventOutcome::Abort);
                }
            };
            *applied |= doc.apply_lsp_processing_edits([edit])?;
        }
        LspResultSlot::FoldingRanges => {
            let edit = folding_ranges_result_to_processing_edit(&result);
            *applied |= doc.apply_lsp_processing_edits([edit])?;
        }
        LspResultSlot::CodeLens => {
            doc.lsp_code_lens_in_flight = false;
            let edit = match doc.ws.buffer_line_index(doc.buffer_id) {
                Ok(line_index) => lsp_code_lens_to_processing_edit(line_index, &result),
                Err(_) => {
                    doc.lsp_fail("LSP buffer line index unavailable");
                    return Ok(EventOutcome::Abort);
                }
            };
            *applied |= doc.apply_lsp_processing_edits([edit])?;
        }
        _ => {}
    }

    let stored_json = stored_lsp_success_result_json(slot, result);
    let result_json_len = stored_json.as_ref().map_or(0, String::len);
    let status = if result_json_len == 0 {
        EditorLspResultEventStatus::Empty
    } else {
        EditorLspResultEventStatus::Success
    };
    if let Some(json) = stored_json {
        doc.lsp_last_result_json.insert((view, slot), json);
    } else {
        doc.lsp_last_result_json.remove(&(view, slot));
    }
    let result_sequence =
        doc.record_lsp_result_event(view, slot, resp.id, status, result_json_len, None);
    doc.record_lsp_request_completed(
        view,
        slot,
        resp.id,
        EditorLspRequestEventStatus::from_result_status(status),
        Some(result_sequence),
        None,
    );
    Ok(EventOutcome::Handled)
}
