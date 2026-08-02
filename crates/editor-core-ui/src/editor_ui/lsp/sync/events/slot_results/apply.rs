use super::*;

pub(super) fn apply_slot_result_edits(
    doc: &mut EditorUiDoc,
    slot: LspResultSlot,
    result: &serde_json::Value,
    applied: &mut bool,
) -> Result<EventOutcome, UiError> {
    match slot {
        LspResultSlot::DocumentSymbols => {
            let edit = match doc.ws.buffer_line_index(doc.buffer_id) {
                Ok(line_index) => lsp_document_symbols_to_processing_edit(line_index, result),
                Err(_) => {
                    doc.lsp_fail("LSP buffer line index unavailable");
                    return Ok(EventOutcome::Abort);
                }
            };
            *applied |= doc.apply_lsp_processing_edits([edit])?;
        }
        LspResultSlot::FoldingRanges => {
            let edit = folding_ranges_result_to_processing_edit(result);
            *applied |= doc.apply_lsp_processing_edits([edit])?;
        }
        LspResultSlot::CodeLens => {
            doc.lsp_code_lens_in_flight = false;
            let edit = match doc.ws.buffer_line_index(doc.buffer_id) {
                Ok(line_index) => lsp_code_lens_to_processing_edit(line_index, result),
                Err(_) => {
                    doc.lsp_fail("LSP buffer line index unavailable");
                    return Ok(EventOutcome::Abort);
                }
            };
            *applied |= doc.apply_lsp_processing_edits([edit])?;
        }
        _ => {}
    }

    Ok(EventOutcome::Handled)
}
