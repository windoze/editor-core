use super::*;

impl EditorUi {
    pub(super) fn clear_marked_text(
        &mut self,
        replacement: MarkedReplacement,
    ) -> Result<(), UiError> {
        if replacement.replace_len > 0 || !replacement.original_text.is_empty() {
            self.exec_core(Command::Edit(EditCommand::ReplaceCoalescingUndo {
                start: replacement.start,
                length: replacement.replace_len,
                text: replacement.original_text.clone(),
            }))?;
            self.refresh_processing()?;
        }

        self.marked = None;
        let _ = self.apply_processing_edits([ProcessingEdit::ClearStyleLayer {
            layer: StyleLayerId::IME_MARKED_TEXT,
        }]);
        // Do not let IME composition edits coalesce into subsequent typing.
        let _ = self.exec_core(Command::Edit(EditCommand::EndUndoGroup));

        // Restore selection to the original range (best-effort).
        let a_off = replacement.start;
        let b_off = replacement.start.saturating_add(replacement.original_len);
        let (a_line, a_col, b_line, b_col) = self.with_line_index(|line_index| {
            let (a_line, a_col) = line_index.char_offset_to_position(a_off);
            let (b_line, b_col) = line_index.char_offset_to_position(b_off);
            (a_line, a_col, b_line, b_col)
        })?;

        if replacement.original_len > 0 {
            self.exec_core(Command::Cursor(CursorCommand::SetSelection {
                start: Position::new(a_line, a_col),
                end: Position::new(b_line, b_col),
            }))?;
        } else {
            self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                line: a_line,
                column: a_col,
            }))?;
            let _ = self.exec_core(Command::Cursor(CursorCommand::ClearSelection));
        }
        Ok(())
    }
}
