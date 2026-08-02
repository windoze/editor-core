use super::*;

impl EditorUi {
    /// Request LSP hover information for a given logical position (0-based line/column in Unicode scalars).
    ///
    /// The result is delivered asynchronously via `poll_processing` and can be read by calling
    /// [`Self::lsp_take_last_hover_result_json`].
    pub fn lsp_request_hover(&mut self, line: usize, column: usize) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::Hover,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_hover(line_index, line, column),
        )
    }

    pub fn lsp_take_last_hover_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::Hover)
    }
}
