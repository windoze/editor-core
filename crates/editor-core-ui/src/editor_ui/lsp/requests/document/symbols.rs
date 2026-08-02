use super::*;

impl EditorUi {
    pub fn lsp_request_document_symbols(&mut self) -> Result<u64, UiError> {
        self.lsp_request_document_result(LspResultSlot::DocumentSymbols, |lsp| {
            lsp.request_document_symbols()
        })
    }

    pub fn lsp_take_last_document_symbols_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::DocumentSymbols)
    }

    pub fn lsp_request_workspace_symbols(&mut self, query: &str) -> Result<u64, UiError> {
        self.lsp_request_document_result(LspResultSlot::WorkspaceSymbols, |lsp| {
            lsp.request_workspace_symbol(query)
        })
    }

    pub fn lsp_take_last_workspace_symbols_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::WorkspaceSymbols)
    }
}
