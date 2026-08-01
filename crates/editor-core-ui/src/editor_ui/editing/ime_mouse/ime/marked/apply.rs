use super::*;

impl EditorUi {
    pub(super) fn replace_marked_text(
        &mut self,
        text: &str,
        selected_start: usize,
        selected_len: usize,
        replacement: MarkedReplacement,
        new_len: usize,
    ) -> Result<(), UiError> {
        // Start of composition: do not merge with the current typing group.
        if self.marked.is_none() {
            let _ = self.exec_core(Command::Edit(EditCommand::EndUndoGroup));
        }

        // Honor selection inside marked text (preedit caret / selection).
        //
        // Important: this must happen *within* the same edit command so it doesn't break
        // undo grouping (CommandExecutor ends the coalescing group on non-edit commands).
        let sel_start = selected_start.min(new_len);
        let sel_end = selected_start.saturating_add(selected_len).min(new_len);
        let a_off = replacement.start.saturating_add(sel_start);
        let b_off = replacement.start.saturating_add(sel_end);

        self.exec_core(Command::Edit(
            EditCommand::ReplaceCoalescingUndoWithSelection {
                start: replacement.start,
                length: replacement.replace_len,
                text: text.to_string(),
                selection_start: a_off,
                selection_end: b_off,
            },
        ))?;
        self.refresh_processing()?;

        self.marked = Some(MarkedRange {
            start: replacement.start,
            len: new_len,
            original_text: replacement.original_text,
            original_len: replacement.original_len,
        });

        // Apply a dedicated style layer so the renderer can draw preedit (underline/background).
        self.apply_processing_edits([ProcessingEdit::ReplaceStyleLayer {
            layer: StyleLayerId::IME_MARKED_TEXT,
            intervals: vec![Interval::new(
                replacement.start,
                replacement.start.saturating_add(new_len),
                IME_MARKED_TEXT_STYLE_ID,
            )],
        }])?;
        Ok(())
    }
}
