use super::*;

impl EditorUi {
    pub fn backspace(&mut self) -> Result<(), UiError> {
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
}
