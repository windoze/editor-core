use super::super::*;

impl EditorUi {
    /// Apply LSP document symbol result payload (`DocumentSymbol[] | SymbolInformation[] | null`).
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/documentSymbol`.
    pub fn lsp_apply_document_symbols_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edit = self.with_line_index(|line_index| {
            lsp_document_symbols_to_processing_edit(line_index, &result_value)
        })?;
        self.apply_processing_edits([edit])?;
        Ok(())
    }

    /// Apply LSP folding range result payload (`FoldingRange[] | null`) to core fold regions.
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/foldingRange`.
    pub fn lsp_apply_folding_ranges_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edit = folding_ranges_result_to_processing_edit(&result_value);
        self.apply_processing_edits([edit])?;
        Ok(())
    }
}
