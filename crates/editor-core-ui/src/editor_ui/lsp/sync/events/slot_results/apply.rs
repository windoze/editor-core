use super::*;

pub(super) fn apply_slot_result_edits(
    doc: &mut EditorUiDoc,
    view_id: ViewId,
    slot: LspResultSlot,
    result: &serde_json::Value,
    applied: &mut bool,
) -> Result<EventOutcome, UiError> {
    match slot {
        LspResultSlot::DocumentSymbols => {
            let edit = match doc.ws.buffer_line_index(doc.buffer_id) {
                Ok(line_index) => lsp_document_symbols_to_processing_edit(line_index, result),
                Err(_) => {
                    doc.fail_lsp_and_record_status(view_id, "LSP buffer line index unavailable");
                    return Ok(EventOutcome::Abort);
                }
            };
            *applied |= doc.apply_lsp_processing_edits(view_id, [edit])?;
        }
        LspResultSlot::FoldingRanges => {
            let edit = folding_ranges_result_to_processing_edit(result);
            *applied |= doc.apply_lsp_processing_edits(view_id, [edit])?;
        }
        LspResultSlot::CodeLens => {
            doc.clear_lsp_in_flight_for_slot(slot);
            let edit = match doc.ws.buffer_line_index(doc.buffer_id) {
                Ok(line_index) => lsp_code_lens_to_processing_edit(line_index, result),
                Err(_) => {
                    doc.fail_lsp_and_record_status(view_id, "LSP buffer line index unavailable");
                    return Ok(EventOutcome::Abort);
                }
            };
            *applied |= doc.apply_lsp_processing_edits(view_id, [edit])?;
        }
        LspResultSlot::InlayHints => {
            doc.clear_lsp_in_flight_for_slot(slot);
            let edit = match doc.ws.buffer_line_index(doc.buffer_id) {
                Ok(line_index) => lsp_inlay_hints_to_processing_edit(line_index, result),
                Err(_) => {
                    doc.fail_lsp_and_record_status(view_id, "LSP buffer line index unavailable");
                    return Ok(EventOutcome::Abort);
                }
            };
            *applied |= doc.apply_lsp_processing_edits(view_id, [edit])?;
        }
        LspResultSlot::DocumentLinks => {
            doc.clear_lsp_in_flight_for_slot(slot);
            let edits = match doc.ws.buffer_line_index(doc.buffer_id) {
                Ok(line_index) => lsp_document_links_to_processing_edits(line_index, result),
                Err(_) => {
                    doc.fail_lsp_and_record_status(view_id, "LSP buffer line index unavailable");
                    return Ok(EventOutcome::Abort);
                }
            };
            *applied |= doc.apply_lsp_processing_edits(view_id, edits)?;
        }
        _ => {}
    }

    Ok(EventOutcome::Handled)
}
