use super::*;

impl EditorUi {
    pub fn lsp_request_code_lens(&mut self) -> Result<u64, UiError> {
        let id = self
            .lsp_request_document_result(LspResultSlot::CodeLens, |lsp| lsp.request_code_lens())?;
        let mut doc = self.lock_doc();
        doc.lsp_code_lens_in_flight = true;
        doc.lsp_aux_refresh_due = None;
        Ok(id)
    }

    pub fn lsp_take_last_code_lens_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CodeLens)
    }

    pub fn lsp_request_code_lens_resolve(&mut self, lens_json: &str) -> Result<u64, UiError> {
        let lens: serde_json::Value =
            serde_json::from_str(lens_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::CodeLensResolve, |lsp| {
            lsp.request_code_lens_resolve(lens)
        })
    }

    pub fn lsp_take_last_code_lens_resolve_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CodeLensResolve)
    }
}
