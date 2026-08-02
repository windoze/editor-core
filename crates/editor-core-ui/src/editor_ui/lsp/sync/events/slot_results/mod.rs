mod apply;
mod record;

use super::super::super::super::*;
use super::EventOutcome;
use apply::apply_slot_result_edits;
use record::{record_slot_error_result, record_slot_success_result};

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
        doc.clear_lsp_in_flight_for_slot(request_slot);
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
        doc.clear_lsp_in_flight_for_slot(slot);
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
        record_slot_error_result(doc, view, slot, resp.id, error);
        return Ok(EventOutcome::Handled);
    }

    let result = resp.result.clone().unwrap_or(serde_json::Value::Null);
    match apply_slot_result_edits(doc, slot, &result, applied)? {
        EventOutcome::Abort => Ok(EventOutcome::Abort),
        _ => {
            record_slot_success_result(doc, view, slot, resp.id, result);
            Ok(EventOutcome::Handled)
        }
    }
}
