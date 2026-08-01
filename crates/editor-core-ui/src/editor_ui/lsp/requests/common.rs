use super::super::*;

impl EditorUi {
    pub(super) fn lsp_request_position_result(
        &mut self,
        slot: LspResultSlot,
        line: usize,
        column: usize,
        request: impl FnOnce(
            &mut LspSession,
            &editor_core::LineIndex,
            usize,
            usize,
        ) -> Result<u64, String>,
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
                request(lsp, line_index, line, column)
            })
            .map_err(UiError::Processor)?;

        doc.lsp_client_requests.insert(
            id,
            LspClientRequest::Result {
                view: self.view_id,
                slot,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((self.view_id, slot), id);
        doc.lsp_last_result_json.remove(&(self.view_id, slot));
        Ok(id)
    }

    pub(super) fn lsp_request_document_result(
        &mut self,
        slot: LspResultSlot,
        request: impl FnOnce(&mut LspSession) -> Result<u64, String>,
    ) -> Result<u64, UiError> {
        self.flush_lsp_did_change_from_delta();

        let mut doc = self.lock_doc();
        let Some(shared) = doc.lsp.as_ref() else {
            return Err(UiError::Processor("LSP is not enabled".to_string()));
        };
        let Some(doc_uri) = doc.lsp_document_uri.as_deref() else {
            return Err(UiError::Processor("LSP document URI missing".to_string()));
        };

        let id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri)?;
                request(lsp)
            })
            .map_err(UiError::Processor)?;

        doc.lsp_client_requests.insert(
            id,
            LspClientRequest::Result {
                view: self.view_id,
                slot,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((self.view_id, slot), id);
        doc.lsp_last_result_json.remove(&(self.view_id, slot));
        Ok(id)
    }

    pub(super) fn lsp_request_with_line_index_result(
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

        doc.lsp_client_requests.insert(
            id,
            LspClientRequest::Result {
                view: self.view_id,
                slot,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((self.view_id, slot), id);
        doc.lsp_last_result_json.remove(&(self.view_id, slot));
        Ok(id)
    }

    pub(super) fn lsp_take_last_result_json(&mut self, slot: LspResultSlot) -> Option<String> {
        let mut doc = self.lock_doc();
        doc.lsp_last_result_json.remove(&(self.view_id, slot))
    }
}
