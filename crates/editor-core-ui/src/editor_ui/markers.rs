use super::*;

impl EditorUi {
    /// Toggle a bookmark at the current cursor line.
    ///
    /// Returns `true` if a bookmark was added, or `false` if an existing bookmark on that line was
    /// removed.
    pub fn toggle_bookmark_at_cursor_line(&mut self) -> Result<bool, UiError> {
        let added = {
            let mut doc = self.lock_doc();
            doc.ws
                .toggle_bookmark_at_cursor_line(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
        };
        Ok(added)
    }

    /// Return all bookmark line numbers (0-based) for the current document buffer.
    pub fn bookmark_lines(&self) -> Result<Vec<usize>, UiError> {
        let doc = self.lock_doc();
        doc.ws
            .bookmark_lines(self.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))
    }

    /// Clear all bookmarks for the current document buffer.
    pub fn clear_bookmarks(&mut self) -> Result<(), UiError> {
        {
            let mut doc = self.lock_doc();
            doc.ws
                .clear_bookmarks(self.buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        }
        Ok(())
    }

    /// Move the cursor to the next bookmark (wrapping to the first bookmark).
    ///
    /// Returns the new cursor position, or `None` if there are no bookmarks.
    pub fn goto_next_bookmark(&mut self) -> Result<Option<Position>, UiError> {
        let pos = {
            let mut doc = self.lock_doc();
            let pos = doc
                .ws
                .goto_next_bookmark(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            if pos.is_some() && self.bracket_match_highlights_enabled {
                let _ = doc.exec_core(
                    self.view_id,
                    Command::Style(StyleCommand::UpdateBracketMatchHighlights),
                );
            }
            pos
        };
        if pos.is_some() {
            self.ensure_primary_caret_visible_after_navigation();
        }
        Ok(pos)
    }

    /// Move the cursor to the previous bookmark (wrapping to the last bookmark).
    ///
    /// Returns the new cursor position, or `None` if there are no bookmarks.
    pub fn goto_prev_bookmark(&mut self) -> Result<Option<Position>, UiError> {
        let pos = {
            let mut doc = self.lock_doc();
            let pos = doc
                .ws
                .goto_prev_bookmark(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            if pos.is_some() && self.bracket_match_highlights_enabled {
                let _ = doc.exec_core(
                    self.view_id,
                    Command::Style(StyleCommand::UpdateBracketMatchHighlights),
                );
            }
            pos
        };
        if pos.is_some() {
            self.ensure_primary_caret_visible_after_navigation();
        }
        Ok(pos)
    }

    /// Set (or replace) a named mark at the current cursor position.
    pub fn set_mark_at_cursor(&mut self, name: String) -> Result<(), UiError> {
        {
            let mut doc = self.lock_doc();
            doc.ws
                .set_mark_at_cursor(self.view_id, name)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        }
        Ok(())
    }

    /// Move the cursor to a named mark (if present).
    ///
    /// Returns the new cursor position, or `None` if the mark does not exist.
    pub fn goto_mark(&mut self, name: &str) -> Result<Option<Position>, UiError> {
        let pos = {
            let mut doc = self.lock_doc();
            let pos = doc
                .ws
                .goto_mark(self.view_id, name)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            if pos.is_some() && self.bracket_match_highlights_enabled {
                let _ = doc.exec_core(
                    self.view_id,
                    Command::Style(StyleCommand::UpdateBracketMatchHighlights),
                );
            }
            pos
        };
        if pos.is_some() {
            self.ensure_primary_caret_visible_after_navigation();
        }
        Ok(pos)
    }

    /// Remove a named mark from the current document buffer.
    ///
    /// Returns `true` if the mark existed.
    pub fn clear_mark(&mut self, name: &str) -> Result<bool, UiError> {
        let existed = {
            let mut doc = self.lock_doc();
            doc.ws
                .clear_mark(self.buffer_id, name)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
        };
        Ok(existed)
    }

    /// Return all mark names for the current document buffer (deterministic order).
    pub fn mark_names(&self) -> Result<Vec<String>, UiError> {
        let doc = self.lock_doc();
        doc.ws
            .mark_names(self.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))
    }

    /// Record the current cursor position as a jump-list location.
    pub fn push_jump_location(&mut self) -> Result<(), UiError> {
        {
            let mut doc = self.lock_doc();
            doc.ws
                .push_jump_location(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        }
        Ok(())
    }

    /// Jump back in the view's jump list.
    ///
    /// Returns the navigation target (including buffer id). In the single-buffer UI wrapper,
    /// this always also moves the caret.
    pub fn jump_back(&mut self) -> Result<Option<editor_core::JumpTarget>, UiError> {
        let target = {
            let mut doc = self.lock_doc();
            let target = doc
                .ws
                .jump_back(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            if target.is_some() && self.bracket_match_highlights_enabled {
                let _ = doc.exec_core(
                    self.view_id,
                    Command::Style(StyleCommand::UpdateBracketMatchHighlights),
                );
            }
            target
        };
        if target.is_some() {
            self.ensure_primary_caret_visible_after_navigation();
        }
        Ok(target)
    }

    /// Jump forward in the view's jump list.
    ///
    /// Returns the navigation target (including buffer id). In the single-buffer UI wrapper,
    /// this always also moves the caret.
    pub fn jump_forward(&mut self) -> Result<Option<editor_core::JumpTarget>, UiError> {
        let target = {
            let mut doc = self.lock_doc();
            let target = doc
                .ws
                .jump_forward(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            if target.is_some() && self.bracket_match_highlights_enabled {
                let _ = doc.exec_core(
                    self.view_id,
                    Command::Style(StyleCommand::UpdateBracketMatchHighlights),
                );
            }
            target
        };
        if target.is_some() {
            self.ensure_primary_caret_visible_after_navigation();
        }
        Ok(target)
    }
}
