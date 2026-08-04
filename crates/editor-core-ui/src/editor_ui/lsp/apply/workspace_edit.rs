use super::*;

impl EditorUi {
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
}
