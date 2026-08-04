use super::*;

impl EditorUi {
    pub fn unmark_text(&mut self) {
        self.marked = None;
        let _ = self.apply_processing_edits([ProcessingEdit::ClearStyleLayer {
            layer: StyleLayerId::IME_MARKED_TEXT,
        }]);
    }

    pub fn commit_text(&mut self, text: &str) -> Result<(), UiError> {
        if let Some(marked) = self.marked.take() {
            self.exec_core(Command::Edit(EditCommand::ReplaceCoalescingUndo {
                start: marked.start,
                length: marked.len,
                text: text.to_string(),
            }))?;
            self.refresh_processing()?;

            let end = marked.start + text.chars().count();
            let (line, column) = self.char_offset_to_logical_position(end);
            self.exec_core(Command::Cursor(CursorCommand::MoveTo { line, column }))?;

            let _ = self.apply_processing_edits([ProcessingEdit::ClearStyleLayer {
                layer: StyleLayerId::IME_MARKED_TEXT,
            }]);
            // Commit ends the composition undo group.
            let _ = self.exec_core(Command::Edit(EditCommand::EndUndoGroup));
            self.ensure_primary_caret_visible_after_edit();
            Ok(())
        } else {
            self.insert_text(text)
        }
    }
}
