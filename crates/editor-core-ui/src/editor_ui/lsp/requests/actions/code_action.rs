use super::*;

impl EditorUi {
    pub fn lsp_request_code_action(
        &mut self,
        start_offset: usize,
        end_offset: usize,
        context_json: &str,
    ) -> Result<u64, UiError> {
        self.flush_lsp_did_change_from_delta();

        let context: serde_json::Value = if context_json.trim().is_empty() {
            serde_json::json!({ "diagnostics": [] })
        } else {
            serde_json::from_str(context_json).map_err(|e| UiError::Processor(e.to_string()))?
        };

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
        let start = start_offset.min(end_offset);
        let end = start_offset.max(end_offset);
        let id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri)?;
                lsp.request_code_action(line_index, start, end, context)
            })
            .map_err(UiError::Processor)?;

        doc.lsp_client_requests.insert(
            id,
            LspClientRequest::Result {
                view: self.view_id,
                slot: LspResultSlot::CodeAction,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((self.view_id, LspResultSlot::CodeAction), id);
        doc.lsp_last_result_json
            .remove(&(self.view_id, LspResultSlot::CodeAction));
        Ok(id)
    }

    pub fn lsp_take_last_code_action_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CodeAction)
    }

    pub fn lsp_request_code_action_resolve(&mut self, action_json: &str) -> Result<u64, UiError> {
        let action: serde_json::Value =
            serde_json::from_str(action_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::CodeActionResolve, |lsp| {
            lsp.request_code_action_resolve(action)
        })
    }

    pub fn lsp_take_last_code_action_resolve_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CodeActionResolve)
    }
}
