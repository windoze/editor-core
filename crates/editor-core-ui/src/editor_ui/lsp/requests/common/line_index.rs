use super::*;

impl EditorUi {
    pub(crate) fn lsp_request_with_line_index_result(
        &mut self,
        slot: LspResultSlot,
        request: impl FnOnce(&mut LspSession, &editor_core::LineIndex) -> Result<u64, String>,
    ) -> Result<u64, UiError> {
        self.flush_lsp_did_change_from_delta();

        let mut doc = self.lock_doc();
        let Some(shared) = doc.lsp.as_ref() else {
            return Err(UiError::Processor("LSP is not enabled".to_string()));
        };
        let Some(doc_uri) = doc.lsp_document_uri.as_deref() else {
            return Err(UiError::Processor("LSP document URI missing".to_string()));
        };

        let line_index = doc
            .ws
            .buffer_line_index(doc.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri)?;
                request(lsp, line_index)
            })
            .map_err(UiError::Processor)?;

        record_lsp_result_request(&mut doc, self.view_id, slot, id);
        Ok(id)
    }
}
