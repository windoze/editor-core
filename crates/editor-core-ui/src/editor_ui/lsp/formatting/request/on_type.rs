use super::*;

impl EditorUi {
    /// Request on-type formatting via LSP (`textDocument/onTypeFormatting`) and apply edits.
    ///
    /// `line` and `column` are logical editor positions after the trigger character was inserted.
    pub fn lsp_format_on_type(
        &mut self,
        line: usize,
        column: usize,
        ch: &str,
        formatting_options_json: &str,
        timeout_ms: u32,
    ) -> Result<bool, UiError> {
        if ch.is_empty() {
            return Err(UiError::Processor(
                "LSP on-type formatting trigger is empty".to_string(),
            ));
        }

        self.flush_lsp_did_change_from_delta();
        let options = parse_lsp_formatting_options(formatting_options_json)?;

        let (shared, doc_uri, buffer_id, line_index) = {
            let doc = self.lock_doc();
            let Some(shared) = doc.lsp.clone() else {
                return Err(UiError::Processor("LSP is not enabled".to_string()));
            };
            let Some(doc_uri) = doc.lsp_document_uri.clone() else {
                return Err(UiError::Processor("LSP document URI missing".to_string()));
            };
            let line_index = doc
                .ws
                .buffer_line_index(doc.buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
                .clone();
            (shared, doc_uri, doc.buffer_id, line_index)
        };

        let supports = shared
            .with_session_mut(|lsp| Ok(lsp.supports_on_type_formatting_trigger(ch)))
            .map_err(UiError::Processor)?;
        if !supports {
            return Ok(false);
        }

        let request_id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri.as_str())?;
                lsp.request_on_type_formatting(&line_index, line, column, ch.to_string(), options)
            })
            .map_err(UiError::Processor)?;

        self.wait_lsp_text_edit_response_and_apply(
            &shared,
            request_id,
            timeout_ms,
            "LSP on-type formatting",
            buffer_id,
        )
    }
}
