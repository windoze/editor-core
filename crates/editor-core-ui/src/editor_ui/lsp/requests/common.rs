mod document;
mod line_index;
mod position;
mod result;

use super::super::*;

fn record_lsp_result_request(doc: &mut EditorUiDoc, view: ViewId, slot: LspResultSlot, id: u64) {
    doc.track_lsp_result_request(view, slot, id);
}
