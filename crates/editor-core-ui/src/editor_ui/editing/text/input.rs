use super::*;

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

    /// Clipboard paste entry point (no auto-pairs).
    ///
    /// This always uses `EditCommand::InsertText`, even for a single character, so that
    /// auto-pairs rules don't engage for clipboard operations.
    pub fn paste_text(&mut self, text: &str) -> Result<(), UiError> {
        if self.marked.is_some() {
            return self.commit_text(text);
        }

        self.exec_core(Command::Edit(EditCommand::InsertText {
            text: text.to_string(),
        }))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn insert_tab(&mut self) -> Result<(), UiError> {
        let has_snippet = {
            let doc = self.lock_doc();
            doc.ws
                .has_active_snippet_session(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
        };

        if has_snippet {
            self.exec_core(Command::Cursor(CursorCommand::SnippetNextPlaceholder))?;
        } else {
            self.exec_core(Command::Edit(EditCommand::InsertTab))?;
        }
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn insert_backtab(&mut self) -> Result<(), UiError> {
        let has_snippet = {
            let doc = self.lock_doc();
            doc.ws
                .has_active_snippet_session(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
        };

        if has_snippet {
            self.exec_core(Command::Cursor(CursorCommand::SnippetPrevPlaceholder))?;
        } else {
            self.exec_core(Command::Edit(EditCommand::Outdent))?;
        }
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn has_active_snippet_session(&self) -> Result<bool, UiError> {
        let doc = self.lock_doc();
        doc.ws
            .has_active_snippet_session(self.view_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))
    }
}
