use super::*;

impl EditorUi {
    pub fn lsp_request_inlay_hints(
        &mut self,
        start_offset: usize,
        end_offset: usize,
    ) -> Result<u64, UiError> {
        let id = self
            .lsp_request_with_line_index_result(LspResultSlot::InlayHints, |lsp, line_index| {
                lsp.request_inlay_hints(line_index, start_offset, end_offset)
            })?;
        let mut doc = self.lock_doc();
        doc.lsp_inlay_in_flight = true;
        doc.lsp_aux_refresh_due = None;
        Ok(id)
    }

    pub fn lsp_take_last_inlay_hints_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::InlayHints)
    }

    pub fn lsp_request_document_links(&mut self) -> Result<u64, UiError> {
        let id = self.lsp_request_document_result(LspResultSlot::DocumentLinks, |lsp| {
            lsp.request_document_links()
        })?;
        let mut doc = self.lock_doc();
        doc.lsp_document_links_in_flight = true;
        doc.lsp_aux_refresh_due = None;
        Ok(id)
    }

    pub fn lsp_take_last_document_links_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::DocumentLinks)
    }
}
