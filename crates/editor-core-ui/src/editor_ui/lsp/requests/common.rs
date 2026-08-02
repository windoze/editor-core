mod document;
mod line_index;
mod position;
mod result;

use super::super::*;

fn record_lsp_result_request(doc: &mut EditorUiDoc, view: ViewId, slot: LspResultSlot, id: u64) {
    doc.lsp_client_requests
        .insert(id, LspClientRequest::Result { view, slot });
    doc.lsp_latest_result_request_id.insert((view, slot), id);
    doc.lsp_last_result_json.remove(&(view, slot));
}
