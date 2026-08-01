use super::*;

impl EditorUi {
    pub fn set_marked_text(&mut self, text: &str) -> Result<(), UiError> {
        let new_len = text.chars().count();
        self.set_marked_text_with_selection(text, new_len, 0, None)
    }

    /// Set IME marked text (composition) with an explicit selection inside the marked string.
    ///
    /// - `selected_start/selected_len` are **character offsets** (Unicode scalar count) within `text`.
    /// - `replace_range` (when provided) is a document range in **character offsets** to replace.
    ///
    /// This matches how `NSTextInputClient.setMarkedText` communicates selection and replacement.
    pub fn set_marked_text_with_selection(
        &mut self,
        text: &str,
        selected_start: usize,
        selected_len: usize,
        replace_range: Option<(usize, usize)>,
    ) -> Result<(), UiError> {
        let new_len = text.chars().count();

        // Determine which document range is being replaced, and the "original" text
        // (the selection at the moment composition starts) so we can restore it if
        // composition is cancelled (e.g. Escape / IME clears marked text).
        let (start, replace_len, original_text, original_len) = if let Some((start, len)) =
            replace_range
        {
            let original = {
                let doc = self.lock_doc();
                doc.ws
                    .buffer_text_range(self.buffer_id, start, len)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?
            };
            (start, len, original, len)
        } else if let Some(marked) = self.marked.as_ref() {
            (
                marked.start,
                marked.len,
                marked.original_text.clone(),
                marked.original_len,
            )
        } else {
            let cursor = self.cursor_state();
            if let Some(sel) = cursor.selection {
                let (start, end) = self.with_line_index(|line_index| {
                    let a = line_index.position_to_char_offset(sel.start.line, sel.start.column);
                    let b = line_index.position_to_char_offset(sel.end.line, sel.end.column);
                    if a <= b { (a, b) } else { (b, a) }
                })?;
                let len = end.saturating_sub(start);
                let original = {
                    let doc = self.lock_doc();
                    doc.ws
                        .buffer_text_range(self.buffer_id, start, len)
                        .map_err(|e| UiError::Processor(format!("{e:?}")))?
                };
                (start, len, original, len)
            } else {
                (cursor.offset, 0, String::new(), 0)
            }
        };

        // Empty marked text means "cancel/clear composition": restore original replaced text.
        if new_len == 0 {
            if replace_len > 0 || !original_text.is_empty() {
                self.exec_core(Command::Edit(EditCommand::ReplaceCoalescingUndo {
                    start,
                    length: replace_len,
                    text: original_text.clone(),
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
            let a_off = start;
            let b_off = start.saturating_add(original_len);
            let (a_line, a_col, b_line, b_col) = self.with_line_index(|line_index| {
                let (a_line, a_col) = line_index.char_offset_to_position(a_off);
                let (b_line, b_col) = line_index.char_offset_to_position(b_off);
                (a_line, a_col, b_line, b_col)
            })?;

            if original_len > 0 {
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
            return Ok(());
        }

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
        let a_off = start.saturating_add(sel_start);
        let b_off = start.saturating_add(sel_end);

        self.exec_core(Command::Edit(
            EditCommand::ReplaceCoalescingUndoWithSelection {
                start,
                length: replace_len,
                text: text.to_string(),
                selection_start: a_off,
                selection_end: b_off,
            },
        ))?;
        self.refresh_processing()?;

        self.marked = Some(MarkedRange {
            start,
            len: new_len,
            original_text,
            original_len,
        });

        // Apply a dedicated style layer so the renderer can draw preedit (underline/background).
        self.apply_processing_edits([ProcessingEdit::ReplaceStyleLayer {
            layer: StyleLayerId::IME_MARKED_TEXT,
            intervals: vec![Interval::new(
                start,
                start.saturating_add(new_len),
                IME_MARKED_TEXT_STYLE_ID,
            )],
        }])?;
        Ok(())
    }
}
