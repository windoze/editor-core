use super::*;

pub(super) fn record_slot_error_result(
    doc: &mut EditorUiDoc,
    view: ViewId,
    slot: LspResultSlot,
    request_id: u64,
    error: LspResponseError,
) {
    if slot == LspResultSlot::CodeLens {
        doc.lsp_code_lens_in_flight = false;
    }

    let stored_json = stored_lsp_error_result_json(slot, error.clone());
    let result_json_len = stored_json.as_ref().map_or(0, String::len);
    store_last_result_json(doc, view, slot, stored_json);

    let result_sequence = doc.record_lsp_result_event(
        view,
        slot,
        request_id,
        EditorLspResultEventStatus::Error,
        result_json_len,
        Some(&error),
    );
    doc.record_lsp_request_completed(
        view,
        slot,
        request_id,
        EditorLspRequestEventStatus::Error,
        Some(result_sequence),
        Some(&error),
    );
}

pub(super) fn record_slot_success_result(
    doc: &mut EditorUiDoc,
    view: ViewId,
    slot: LspResultSlot,
    request_id: u64,
    result: serde_json::Value,
) {
    let stored_json = stored_lsp_success_result_json(slot, result);
    let result_json_len = stored_json.as_ref().map_or(0, String::len);
    let status = if result_json_len == 0 {
        EditorLspResultEventStatus::Empty
    } else {
        EditorLspResultEventStatus::Success
    };
    store_last_result_json(doc, view, slot, stored_json);

    let result_sequence =
        doc.record_lsp_result_event(view, slot, request_id, status, result_json_len, None);
    doc.record_lsp_request_completed(
        view,
        slot,
        request_id,
        EditorLspRequestEventStatus::from_result_status(status),
        Some(result_sequence),
        None,
    );
}

fn store_last_result_json(
    doc: &mut EditorUiDoc,
    view: ViewId,
    slot: LspResultSlot,
    stored_json: Option<String>,
) {
    if let Some(json) = stored_json {
        doc.lsp_last_result_json.insert((view, slot), json);
    } else {
        doc.lsp_last_result_json.remove(&(view, slot));
    }
}
