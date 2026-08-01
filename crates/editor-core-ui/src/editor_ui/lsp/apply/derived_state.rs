use super::*;

impl EditorUi {
    pub fn lsp_apply_publish_diagnostics_json(&mut self, params_json: &str) -> Result<(), UiError> {
        let params_value: serde_json::Value =
            serde_json::from_str(params_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let notif = LspNotification::from_method_and_params(
            "textDocument/publishDiagnostics",
            &params_value,
        )
        .ok_or_else(|| UiError::Processor("invalid publishDiagnostics params".to_string()))?;

        let LspNotification::PublishDiagnostics(params) = notif else {
            return Err(UiError::Processor(
                "failed to parse publishDiagnostics params".to_string(),
            ));
        };

        let edits = self.with_line_index(|line_index| {
            lsp_diagnostics_to_processing_edits(line_index, &params)
        })?;
        self.apply_processing_edits(edits)?;
        Ok(())
    }

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

    /// Apply LSP document highlight result payload (`DocumentHighlight[] | null`) as a style layer.
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/documentHighlight`.
    pub fn lsp_apply_document_highlights_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edit = self.with_line_index(|line_index| {
            lsp_document_highlights_to_processing_edit(line_index, &result_value)
        })?;
        self.apply_processing_edits([edit])?;
        Ok(())
    }

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

    /// Apply LSP inlay hints result payload (`InlayHint[] | null`) as decorations.
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/inlayHint`.
    pub fn lsp_apply_inlay_hints_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edit = self.with_line_index(|line_index| {
            lsp_inlay_hints_to_processing_edit(line_index, &result_value)
        })?;
        self.apply_processing_edits([edit])?;
        Ok(())
    }

    /// Apply LSP code lens result payload (`CodeLens[] | null`) as decorations.
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/codeLens`.
    pub fn lsp_apply_code_lens_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edit = self.with_line_index(|line_index| {
            lsp_code_lens_to_processing_edit(line_index, &result_value)
        })?;
        self.apply_processing_edits([edit])?;
        Ok(())
    }

    /// Apply LSP document links result payload (`DocumentLink[] | null`) as:
    /// - decorations (payload / click targets)
    /// - style intervals (rendering underline)
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/documentLink`.
    pub fn lsp_apply_document_links_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edits = self.with_line_index(|line_index| {
            lsp_document_links_to_processing_edits(line_index, &result_value)
        })?;
        self.apply_processing_edits(edits)?;
        Ok(())
    }
}
