use super::*;

impl EditorUi {
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

    pub(crate) fn lsp_apply_lsp_text_edits(
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
}
