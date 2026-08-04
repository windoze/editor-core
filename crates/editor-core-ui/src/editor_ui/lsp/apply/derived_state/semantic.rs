use super::super::*;

impl EditorUi {
    pub fn lsp_apply_semantic_tokens(&mut self, data: &[u32]) -> Result<(), UiError> {
        let intervals = self.with_line_index(|line_index| {
            semantic_tokens_to_intervals(data, line_index, encode_semantic_style_id)
                .map_err(|e| UiError::Processor(e.to_string()))
        })??;
        self.apply_processing_edits([ProcessingEdit::ReplaceStyleLayer {
            layer: StyleLayerId::SEMANTIC_TOKENS,
            intervals,
        }])?;
        Ok(())
    }
}
