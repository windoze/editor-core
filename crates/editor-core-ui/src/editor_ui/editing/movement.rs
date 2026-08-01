use super::*;

impl EditorUi {
    pub fn move_visual_by_rows(&mut self, delta_rows: isize) -> Result<(), UiError> {
        // UI-friendly behavior: if there is an active selection, moving vertically should
        // collapse it to the current caret before moving (matches common editor behavior).
        //
        // Without this, some hosts may appear "stuck" because the selection remains visible
        // while the caret movement is not obvious (and some cursor movement strategies can
        // also depend on a clear selection).
        if self.cursor_state().selection.is_some() {
            self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        }
        self.exec_core(Command::Cursor(CursorCommand::MoveVisualBy { delta_rows }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_grapheme_left(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::MoveGraphemeLeft))?;
        Ok(())
    }

    pub fn move_grapheme_right(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::MoveGraphemeRight))?;
        Ok(())
    }

    pub fn move_word_left(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::MoveWordLeft))?;
        Ok(())
    }

    pub fn move_word_right(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::MoveWordRight))?;
        Ok(())
    }

    pub fn move_to_visual_line_start(&mut self) -> Result<(), UiError> {
        if self.cursor_state().selection.is_some() {
            self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        }
        self.exec_core(Command::Cursor(CursorCommand::MoveToVisualLineStart))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_visual_line_end(&mut self) -> Result<(), UiError> {
        if self.cursor_state().selection.is_some() {
            self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        }
        self.exec_core(Command::Cursor(CursorCommand::MoveToVisualLineEnd))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_document_start(&mut self) -> Result<(), UiError> {
        if self.cursor_state().selection.is_some() {
            self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        }
        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 0,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_document_end(&mut self) -> Result<(), UiError> {
        if self.cursor_state().selection.is_some() {
            self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        }

        let pos = self.with_line_index(|line_index| {
            let line_count = line_index.line_count();
            if line_count == 0 {
                return None;
            }
            let last_line = line_count.saturating_sub(1);
            let text = line_index.get_line_text(last_line).unwrap_or_default();
            Some((last_line, text.chars().count()))
        })?;
        let Some((last_line, col)) = pos else {
            return Ok(());
        };

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: last_line,
            column: col,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_visual_by_pages(&mut self, delta_pages: isize) -> Result<(), UiError> {
        let height_rows = self.viewport_state().height.unwrap_or(1) as isize;
        let height_rows = height_rows.max(1);
        self.move_visual_by_rows(delta_pages.saturating_mul(height_rows))
    }

    pub fn move_grapheme_left_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        // Move the internal caret to the active end, clear selection so movement applies, then restore.
        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.exec_core(Command::Cursor(CursorCommand::MoveGraphemeLeft))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        Ok(())
    }

    pub fn move_word_left_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.exec_core(Command::Cursor(CursorCommand::MoveWordLeft))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        Ok(())
    }

    pub fn move_grapheme_right_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.exec_core(Command::Cursor(CursorCommand::MoveGraphemeRight))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        Ok(())
    }

    pub fn move_word_right_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.exec_core(Command::Cursor(CursorCommand::MoveWordRight))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        Ok(())
    }

    pub fn move_to_visual_line_start_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.exec_core(Command::Cursor(CursorCommand::MoveToVisualLineStart))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_visual_line_end_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.exec_core(Command::Cursor(CursorCommand::MoveToVisualLineEnd))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_document_start_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 0,
        }))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_to_document_end_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;

        let pos = self.with_line_index(|line_index| {
            let line_count = line_index.line_count();
            if line_count == 0 {
                return None;
            }
            let last_line = line_count.saturating_sub(1);
            let text = line_index.get_line_text(last_line).unwrap_or_default();
            Some((last_line, text.chars().count()))
        })?;
        let Some((last_line, col)) = pos else {
            return Ok(());
        };

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: last_line,
            column: col,
        }))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }

    pub fn move_visual_by_pages_and_modify_selection(
        &mut self,
        delta_pages: isize,
    ) -> Result<(), UiError> {
        let height_rows = self.viewport_state().height.unwrap_or(1) as isize;
        let height_rows = height_rows.max(1);
        self.move_visual_by_rows_and_modify_selection(delta_pages.saturating_mul(height_rows))
    }

    pub fn move_visual_by_rows_and_modify_selection(
        &mut self,
        delta_rows: isize,
    ) -> Result<(), UiError> {
        let cursor = self.cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.exec_core(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.exec_core(Command::Cursor(CursorCommand::MoveVisualBy { delta_rows }))?;

        let new_active = self.cursor_state().position;
        self.exec_core(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        self.ensure_primary_caret_visible_after_navigation();
        Ok(())
    }
}
