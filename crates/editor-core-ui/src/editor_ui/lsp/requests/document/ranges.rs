use super::*;

impl EditorUi {
    pub fn lsp_request_folding_ranges(&mut self) -> Result<u64, UiError> {
        self.lsp_request_document_result(LspResultSlot::FoldingRanges, |lsp| {
            lsp.request_folding_ranges()
        })
    }

    pub fn lsp_take_last_folding_ranges_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::FoldingRanges)
    }

    pub fn lsp_request_selection_range(&mut self, positions_json: &str) -> Result<u64, UiError> {
        let positions = parse_lsp_position_list_json(positions_json)?;
        self.lsp_request_with_line_index_result(LspResultSlot::SelectionRange, |lsp, line_index| {
            lsp.request_selection_range(line_index, &positions)
        })
    }

    pub fn lsp_take_last_selection_range_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::SelectionRange)
    }

    pub fn lsp_request_linked_editing_range(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::LinkedEditingRange,
            line,
            column,
            |lsp, line_index, line, column| {
                lsp.request_linked_editing_range(line_index, line, column)
            },
        )
    }

    pub fn lsp_take_last_linked_editing_range_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::LinkedEditingRange)
    }
}
