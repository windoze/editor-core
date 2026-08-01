use super::super::super::super::*;
use super::EventOutcome;

pub(super) fn handle_lsp_derived_state_response(
    doc: &mut EditorUiDoc,
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
                    doc.lsp_fail("LSP buffer line index unavailable");
                    return Ok(EventOutcome::Abort);
                }
            };
            *applied |= doc.apply_lsp_processing_edits([edit])?;
            Ok(EventOutcome::Handled)
        }
        "textDocument/codeLens" => {
            doc.lsp_code_lens_in_flight = false;
            let result = resp.result.clone().unwrap_or(serde_json::Value::Null);
            let edit = match doc.ws.buffer_line_index(doc.buffer_id) {
                Ok(line_index) => lsp_code_lens_to_processing_edit(line_index, &result),
                Err(_) => {
                    doc.lsp_fail("LSP buffer line index unavailable");
                    return Ok(EventOutcome::Abort);
                }
            };
            *applied |= doc.apply_lsp_processing_edits([edit])?;
            Ok(EventOutcome::Handled)
        }
        "textDocument/documentLink" => {
            doc.lsp_document_links_in_flight = false;
            let result = resp.result.clone().unwrap_or(serde_json::Value::Null);
            let edits = match doc.ws.buffer_line_index(doc.buffer_id) {
                Ok(line_index) => lsp_document_links_to_processing_edits(line_index, &result),
                Err(_) => {
                    doc.lsp_fail("LSP buffer line index unavailable");
                    return Ok(EventOutcome::Abort);
                }
            };
            *applied |= doc.apply_lsp_processing_edits(edits)?;
            Ok(EventOutcome::Handled)
        }
        _ => Ok(EventOutcome::Unhandled),
    }
}
