use super::*;

impl EditorUi {
    pub fn lsp_request_document_color(&mut self) -> Result<u64, UiError> {
        self.lsp_request_document_result(LspResultSlot::DocumentColor, |lsp| {
            lsp.request_document_color()
        })
    }

    pub fn lsp_take_last_document_color_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::DocumentColor)
    }

    pub fn lsp_request_color_presentation(
        &mut self,
        start_offset: usize,
        end_offset: usize,
        color_json: &str,
    ) -> Result<u64, UiError> {
        let color: serde_json::Value =
            serde_json::from_str(color_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_with_line_index_result(
            LspResultSlot::ColorPresentation,
            |lsp, line_index| {
                let range = lsp.lsp_range_for_editor_offsets(line_index, start_offset, end_offset);
                lsp.request_color_presentation(&range, color)
            },
        )
    }

    pub fn lsp_take_last_color_presentation_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::ColorPresentation)
    }
}
