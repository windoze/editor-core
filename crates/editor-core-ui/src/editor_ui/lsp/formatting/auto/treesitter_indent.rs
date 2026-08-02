use super::*;

impl EditorUi {
    pub(crate) fn maybe_apply_treesitter_indent_for_primary_caret_line(
        &mut self,
    ) -> Result<bool, UiError> {
        let applied = {
            let mut doc = self.lock_doc();
            if doc.treesitter_indenter.is_none() {
                return Ok(false);
            }

            let buffer_id = doc.buffer_id;
            let version = doc.text_version;
            let text = doc
                .ws
                .buffer_text(buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;

            let pos = doc
                .ws
                .cursor_position_for_view(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            let indent_config = doc
                .ws
                .indentation_config_for_view(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            let indent_style = indent_config.style;

            let Some(indenter) = doc.treesitter_indenter.as_mut() else {
                return Ok(false);
            };

            indenter
                .sync_to_text(version, text.as_str())
                .map_err(|e| UiError::Processor(e.to_string()))?;

            let Some(edit) = indenter.reindent_text_edit_for_line(pos.line, indent_style) else {
                return Ok(false);
            };

            doc.ws
                .apply_text_edits(vec![(buffer_id, vec![edit])])
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            true
        };

        if applied {
            self.refresh_processing()?;
        }
        Ok(applied)
    }
}
