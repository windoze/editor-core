use super::super::*;

impl EditorUi {
    pub fn insert_text(&mut self, text: &str) -> Result<(), UiError> {
        if text == "\n" || text == "\r" {
            self.exec_core(Command::Edit(EditCommand::InsertNewline {
                auto_indent: true,
            }))?;
            self.refresh_processing()?;
            let requested_lsp = self
                .maybe_request_lsp_on_type_formatting("\n")
                .unwrap_or(false);
            if !requested_lsp {
                let _ = self.maybe_apply_treesitter_indent_for_primary_caret_line();
            }
            self.ensure_primary_caret_visible_after_edit();
            return Ok(());
        }
        let mut typed_trigger: Option<String> = None;
        if let Some(ch) = (text.chars().count() == 1)
            .then(|| text.chars().next())
            .flatten()
            && ch != '\t'
        {
            self.exec_core(Command::Edit(EditCommand::TypeChar { ch }))?;
            typed_trigger = Some(ch.to_string());
        } else {
            self.exec_core(Command::Edit(EditCommand::InsertText {
                text: text.to_string(),
            }))?;
        }
        self.refresh_processing()?;
        if let Some(trigger) = typed_trigger {
            let _ = self.maybe_request_lsp_on_type_formatting(trigger.as_str());
        }
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }
}
