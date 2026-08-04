use super::super::*;

impl EditorUi {
    pub fn lsp_request_completion(&mut self, line: usize, column: usize) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::Completion,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_completion(line_index, line, column),
        )
    }

    pub fn lsp_take_last_completion_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::Completion)
    }

    pub fn lsp_request_completion_item_resolve(&mut self, item_json: &str) -> Result<u64, UiError> {
        let item: serde_json::Value =
            serde_json::from_str(item_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::CompletionResolve, |lsp| {
            lsp.request_completion_item_resolve(item)
        })
    }

    pub fn lsp_take_last_completion_item_resolve_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CompletionResolve)
    }

    pub fn lsp_request_signature_help(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::SignatureHelp,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_signature_help(line_index, line, column),
        )
    }

    pub fn lsp_take_last_signature_help_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::SignatureHelp)
    }

    pub fn lsp_request_prepare_rename(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::PrepareRename,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_prepare_rename(line_index, line, column),
        )
    }

    pub fn lsp_take_last_prepare_rename_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::PrepareRename)
    }

    pub fn lsp_request_rename(
        &mut self,
        line: usize,
        column: usize,
        new_name: &str,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::Rename,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_rename(line_index, line, column, new_name),
        )
    }

    pub fn lsp_take_last_rename_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::Rename)
    }
}
