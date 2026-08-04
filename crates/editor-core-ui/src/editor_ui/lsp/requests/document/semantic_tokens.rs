use super::*;

impl EditorUi {
    pub fn lsp_request_semantic_tokens_full(&mut self) -> Result<u64, UiError> {
        self.lsp_request_document_result(LspResultSlot::SemanticTokensFull, |lsp| {
            lsp.request_semantic_tokens_full()
        })
    }

    pub fn lsp_take_last_semantic_tokens_full_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::SemanticTokensFull)
    }

    pub fn lsp_request_semantic_tokens_delta(
        &mut self,
        previous_result_id: Option<&str>,
    ) -> Result<u64, UiError> {
        let previous_result_id = previous_result_id.map(str::to_owned);
        self.lsp_request_document_result(LspResultSlot::SemanticTokensDelta, |lsp| {
            lsp.request_semantic_tokens_delta(previous_result_id)
        })
    }

    pub fn lsp_take_last_semantic_tokens_delta_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::SemanticTokensDelta)
    }

    pub fn lsp_request_semantic_tokens_range(
        &mut self,
        start_line: usize,
        start_column: usize,
        end_line: usize,
        end_column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_with_line_index_result(
            LspResultSlot::SemanticTokensRange,
            |lsp, line_index| {
                let start =
                    lsp.lsp_position_for_editor_position(line_index, start_line, start_column);
                let end = lsp.lsp_position_for_editor_position(line_index, end_line, end_column);
                lsp.request_semantic_tokens_range(&editor_core_lsp::LspRange::new(start, end))
            },
        )
    }

    pub fn lsp_take_last_semantic_tokens_range_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::SemanticTokensRange)
    }
}
