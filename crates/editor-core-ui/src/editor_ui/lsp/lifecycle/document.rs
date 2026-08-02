use super::*;

impl EditorUi {
    pub fn lsp_did_save_document(
        &mut self,
        document_uri: &str,
        text: Option<String>,
    ) -> Result<(), UiError> {
        let shared = {
            let doc = self.lock_doc();
            doc.lsp.clone()
        };
        let Some(shared) = shared else {
            return Err(UiError::Processor("LSP is not enabled".to_string()));
        };

        shared
            .with_session_mut(|lsp| lsp.did_save_for_uri(document_uri, text))
            .map_err(UiError::Processor)
    }

    pub fn lsp_did_close_document(&mut self, document_uri: &str) -> Result<(), UiError> {
        let shared = {
            let doc = self.lock_doc();
            doc.lsp.clone()
        };
        let Some(shared) = shared else {
            return Err(UiError::Processor("LSP is not enabled".to_string()));
        };

        shared
            .with_session_mut(|lsp| lsp.close_document(document_uri))
            .map_err(UiError::Processor)
    }
}
