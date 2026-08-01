use super::*;

impl EditorUi {
    pub fn insert_text(&mut self, text: &str) -> Result<(), UiError> {
        // UI typing entry point:
        // - For single-character typing, route through `TypeChar` so auto-pairs can engage.
        // - For multi-character commits (IME commits, etc), keep the bulk `InsertText` path.
        //
        // Notes:
        // - Keep `'\n'` out of the `TypeChar` path; newline indentation is handled explicitly
        //   via `EditCommand::InsertNewline` (with optional auto-indent).
        // - For clipboard paste (including single-character paste), prefer `paste_text` which
        //   always uses `InsertText` and does not trigger auto-pairs rules.
        if text == "\n" || text == "\r" {
            // Treat newline as a dedicated editor command so core auto-indent can run.
            self.exec_core(Command::Edit(EditCommand::InsertNewline {
                auto_indent: true,
            }))?;
            self.refresh_processing()?;
            // Best-effort: if the LSP server advertises `documentOnTypeFormattingProvider` on
            // newline, request it (async) to improve indentation.
            let requested_lsp = self
                .maybe_request_lsp_on_type_formatting("\n")
                .unwrap_or(false);
            if !requested_lsp {
                // Best-effort fallback: if a Tree-sitter `indents.scm` is available for the
                // current language, use it to compute the desired indentation.
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
        // If an IME marked range is active, treat paste as a commit that replaces the marked
        // text and ends the composition group.
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

    pub fn backspace(&mut self) -> Result<(), UiError> {
        // UI-friendly default: delete the previous grapheme cluster (UAX #29).
        //
        // However, when auto-pairs are enabled, most editors prefer delete-pair behavior
        // when the caret is between matching delimiters.
        let cursor = self.cursor_state();
        let can_try_delete_pair =
            self.auto_pairs.enabled && self.auto_pairs.delete_pair && cursor.selection.is_none();
        if can_try_delete_pair && cursor.multi_cursors.is_empty() {
            let caret_off = cursor.offset;
            if caret_off > 0 {
                let pair = self
                    .with_line_index(|idx| (idx.char_at(caret_off - 1), idx.char_at(caret_off)))?;
                if let (Some(open), Some(close)) = pair
                    && self
                        .auto_pairs
                        .pairs
                        .iter()
                        .any(|p| p.open == open && p.close == close)
                {
                    self.exec_core(Command::Edit(EditCommand::Backspace))?;
                    self.refresh_processing()?;
                    self.ensure_primary_caret_visible_after_edit();
                    return Ok(());
                }
            }
        }

        self.exec_core(Command::Edit(EditCommand::DeleteGraphemeBack))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn delete_forward(&mut self) -> Result<(), UiError> {
        // Mirror `backspace`: keep grapheme-aware deletion, but prefer delete-pair when enabled.
        let cursor = self.cursor_state();
        let can_try_delete_pair =
            self.auto_pairs.enabled && self.auto_pairs.delete_pair && cursor.selection.is_none();
        if can_try_delete_pair && cursor.multi_cursors.is_empty() {
            let caret_off = cursor.offset;
            if caret_off > 0 {
                let pair = self
                    .with_line_index(|idx| (idx.char_at(caret_off - 1), idx.char_at(caret_off)))?;
                if let (Some(open), Some(close)) = pair
                    && self
                        .auto_pairs
                        .pairs
                        .iter()
                        .any(|p| p.open == open && p.close == close)
                {
                    self.exec_core(Command::Edit(EditCommand::DeleteForward))?;
                    self.refresh_processing()?;
                    self.ensure_primary_caret_visible_after_edit();
                    return Ok(());
                }
            }
        }

        self.exec_core(Command::Edit(EditCommand::DeleteGraphemeForward))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn delete_word_back(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Edit(EditCommand::DeleteWordBack))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn delete_word_forward(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Edit(EditCommand::DeleteWordForward))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn add_style(&mut self, start: usize, end: usize, style_id: u32) -> Result<(), UiError> {
        self.exec_core(Command::Style(StyleCommand::AddStyle {
            start,
            end,
            style_id,
        }))?;
        self.refresh_processing()?;
        Ok(())
    }

    pub fn remove_style(&mut self, start: usize, end: usize, style_id: u32) -> Result<(), UiError> {
        self.exec_core(Command::Style(StyleCommand::RemoveStyle {
            start,
            end,
            style_id,
        }))?;
        self.refresh_processing()?;
        Ok(())
    }

    pub fn undo(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Edit(EditCommand::Undo))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn redo(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Edit(EditCommand::Redo))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    pub fn end_undo_group(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Edit(EditCommand::EndUndoGroup))?;
        Ok(())
    }
}
