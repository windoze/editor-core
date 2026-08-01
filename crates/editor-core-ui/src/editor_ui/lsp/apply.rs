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

    /// Apply an LSP `TextEdit[] | null` payload to the current buffer.
    ///
    /// This is primarily intended for applying LSP formatting results in a UI-friendly way.
    ///
    /// Returns `true` if any edits were applied.
    pub fn lsp_apply_text_edits_json(&mut self, text_edits_json: &str) -> Result<bool, UiError> {
        let value: serde_json::Value =
            serde_json::from_str(text_edits_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let buffer_id = {
            let doc = self.lock_doc();
            doc.buffer_id
        };
        self.lsp_apply_text_edits_value(buffer_id, &value)
    }

    pub(crate) fn lsp_apply_text_edits_value(
        &mut self,
        buffer_id: BufferId,
        value: &serde_json::Value,
    ) -> Result<bool, UiError> {
        let edits = text_edits_from_value(value);
        self.lsp_apply_lsp_text_edits(buffer_id, &edits)
    }

    pub fn lsp_apply_workspace_edit_json(
        &mut self,
        workspace_edit_json: &str,
        document_uri: Option<&str>,
    ) -> Result<String, UiError> {
        let value: serde_json::Value = serde_json::from_str(workspace_edit_json)
            .map_err(|e| UiError::Processor(e.to_string()))?;

        let (buffer_id, current_uri) = {
            let doc = self.lock_doc();
            let uri = document_uri
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_string)
                .or_else(|| doc.lsp_document_uri.clone())
                .ok_or_else(|| UiError::Processor("document URI missing".to_string()))?;
            (doc.buffer_id, uri)
        };

        let by_uri = workspace_edit_text_edits(&value);
        let target_edits = by_uri
            .get(current_uri.as_str())
            .cloned()
            .unwrap_or_default();
        let applied = self.lsp_apply_lsp_text_edits(buffer_id, &target_edits)?;

        let mut skipped_uris = by_uri
            .keys()
            .filter(|uri| uri.as_str() != current_uri.as_str())
            .cloned()
            .collect::<Vec<_>>();
        skipped_uris.sort();

        let summary = summarize_workspace_edit(&value);
        let documents = summary
            .documents
            .into_iter()
            .map(|doc| {
                serde_json::json!({
                    "uri": doc.uri,
                    "edit_count": doc.edit_count,
                    "has_overlapping_edits": doc.has_overlapping_edits,
                })
            })
            .collect::<Vec<_>>();

        Ok(serde_json::json!({
            "applied": applied,
            "applied_uri": current_uri,
            "applied_edit_count": target_edits.len(),
            "skipped_uris": skipped_uris,
            "documents": documents,
        })
        .to_string())
    }

    fn lsp_apply_lsp_text_edits(
        &mut self,
        buffer_id: BufferId,
        edits: &[LspTextEdit],
    ) -> Result<bool, UiError> {
        if edits.is_empty() {
            return Ok(false);
        }

        {
            let mut doc = self.lock_doc();
            let line_index = doc
                .ws
                .buffer_line_index(buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;

            let mut specs = edits
                .iter()
                .map(|edit| {
                    let (start, end) = char_offsets_for_lsp_range(line_index, &edit.range);
                    editor_core::TextEditSpec {
                        start,
                        end,
                        text: edit.new_text.clone(),
                    }
                })
                .collect::<Vec<_>>();

            // Match `Workspace::apply_text_edits` behavior (descending by start).
            specs.sort_by_key(|e| std::cmp::Reverse(e.start));

            doc.ws
                .apply_text_edits(vec![(buffer_id, specs)])
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        }

        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(true)
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
