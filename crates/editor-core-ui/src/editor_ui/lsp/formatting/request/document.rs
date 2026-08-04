use super::*;

impl EditorUi {
    /// Format the active document via LSP (`textDocument/formatting`) and apply edits locally.
    ///
    /// This is a "turnkey" helper intended for editor commands (explicit user actions).
    /// It blocks for up to `timeout_ms` while waiting for the response.
    ///
    /// Returns `true` if any text edits were applied.
    pub fn lsp_format_document(
        &mut self,
        formatting_options_json: &str,
        timeout_ms: u32,
    ) -> Result<bool, UiError> {
        self.flush_lsp_did_change_from_delta();
        let options = parse_lsp_formatting_options(formatting_options_json)?;

        let (shared, doc_uri, buffer_id) = {
            let doc = self.lock_doc();
            let Some(shared) = doc.lsp.clone() else {
                return Err(UiError::Processor("LSP is not enabled".to_string()));
            };
            let Some(doc_uri) = doc.lsp_document_uri.clone() else {
                return Err(UiError::Processor("LSP document URI missing".to_string()));
            };
            (shared, doc_uri, doc.buffer_id)
        };

        let request_id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri.as_str())?;
                lsp.request_formatting(options)
            })
            .map_err(UiError::Processor)?;

        self.wait_lsp_text_edit_response_and_apply(
            &shared,
            request_id,
            timeout_ms,
            "LSP formatting",
            buffer_id,
        )
    }
}
