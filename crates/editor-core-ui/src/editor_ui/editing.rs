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

    /// Set IME marked text (composition).
    ///
    /// This is UI-layer behavior (not editor-core kernel): we represent the marked string
    /// as a replaceable range in the document, tracking its `(start, len)` in char offsets.
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

    pub fn mouse_down(&mut self, x_px: f32, y_px: f32) -> Result<(), UiError> {
        self.mouse_down_with_modifiers_and_click_count(x_px, y_px, Modifiers::NONE, 1)
    }

    /// 鼠标按下（扩展版）：支持 modifiers + click count。
    ///
    /// 约定（尽量对齐主流编辑器的“鼠标策略”）：
    /// - `click_count == 1`：放置 caret；拖拽为字符级选择
    /// - `click_count == 2`：选中单词；拖拽按“单词”扩展
    /// - `click_count == 3`：选中整行；拖拽按“行”扩展
    /// - `click_count >= 4`：选中段落；拖拽按“段落”扩展
    /// - `ALT`：开始矩形选择（box/column selection），拖拽为矩形扩展
    /// - `SHIFT`：单击时从现有 selection anchor 扩展到点击位置
    /// - `CTRL`/`META`：单击添加一个额外 caret（multi-cursor）
    ///
    /// 注意：
    /// - 这是 UI 层行为（`editor-core-ui`），不会影响内核命令语义。
    pub fn mouse_down_with_modifiers_and_click_count(
        &mut self,
        x_px: f32,
        y_px: f32,
        modifiers: Modifiers,
        click_count: u8,
    ) -> Result<(), UiError> {
        // Gutter interaction: click-to-toggle fold state for a fold start line.
        if self.render_config.gutter_width_cells > 0 {
            let gutter_px =
                self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
            let gutter_end_x = self.render_config.padding_x_px + gutter_px;
            if x_px < gutter_end_x {
                if self.has_virtual_text_decorations() {
                    let (_start_composed, _row_count, grid) = self.composed_viewport_grid();
                    let (local_row, _x_cells) = self.pixel_to_local_row_col(x_px, y_px);
                    if let Some(line) = grid.lines.get(local_row)
                        && let editor_core::ComposedLineKind::Document { logical_line, .. } =
                            line.kind
                    {
                        let fold_regions = {
                            let doc = self.lock_doc();
                            doc.ws
                                .folding_regions_for_buffer(self.buffer_id)
                                .unwrap_or_default()
                        };
                        if let Some(region) = fold_regions
                            .iter()
                            .filter(|r| r.start_line == logical_line)
                            .min_by_key(|r| r.end_line)
                            .cloned()
                        {
                            if region.is_collapsed {
                                self.exec_core(Command::Style(StyleCommand::Unfold {
                                    start_line: region.start_line,
                                }))?;
                            } else {
                                self.exec_core(Command::Style(StyleCommand::Fold {
                                    start_line: region.start_line,
                                    end_line: region.end_line,
                                }))?;
                            }
                            self.mouse_drag = None;
                            return Ok(());
                        }
                    }
                } else {
                    let (row, _x_cells) = self.pixel_to_visual(x_px, y_px);
                    let pos = {
                        let mut doc = self.lock_doc();
                        doc.ws
                            .visual_position_to_logical_for_view(self.view_id, row, 0)
                            .ok()
                            .flatten()
                    };
                    if let Some(pos) = pos {
                        let fold_regions = {
                            let doc = self.lock_doc();
                            doc.ws
                                .folding_regions_for_buffer(self.buffer_id)
                                .unwrap_or_default()
                        };
                        if let Some(region) = fold_regions
                            .iter()
                            .filter(|r| r.start_line == pos.line)
                            .min_by_key(|r| r.end_line)
                            .cloned()
                        {
                            if region.is_collapsed {
                                self.exec_core(Command::Style(StyleCommand::Unfold {
                                    start_line: region.start_line,
                                }))?;
                            } else {
                                self.exec_core(Command::Style(StyleCommand::Fold {
                                    start_line: region.start_line,
                                    end_line: region.end_line,
                                }))?;
                            }
                            self.mouse_drag = None;
                            return Ok(());
                        }
                    }
                }
            }
        }

        let Some(off) = self.view_point_to_char_offset(x_px, y_px) else {
            return Ok(());
        };
        let (line, column) = self.char_offset_to_logical_position(off);
        let pos = Position::new(line, column);

        let click_count = click_count.max(1) as usize;

        // Single-click + Ctrl/Cmd: multi-cursor add caret.
        let wants_add_caret = click_count == 1
            && !modifiers.contains(Modifiers::SHIFT)
            && (modifiers.contains(Modifiers::CTRL) || modifiers.contains(Modifiers::META));
        if wants_add_caret {
            self.add_caret_at_char_offset(off, true)?;
            self.mouse_drag = None;
            return Ok(());
        }

        let mode = if modifiers.contains(Modifiers::ALT) {
            MouseSelectionMode::Rect
        } else {
            match click_count {
                1 => MouseSelectionMode::Char,
                2 => MouseSelectionMode::Word,
                3 => MouseSelectionMode::Line,
                _ => MouseSelectionMode::Paragraph,
            }
        };

        match mode {
            MouseSelectionMode::Char => {
                if modifiers.contains(Modifiers::SHIFT) {
                    let cursor = self.cursor_state();
                    let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);

                    self.exec_core(Command::Cursor(CursorCommand::SetSelection {
                        start: anchor,
                        end: pos,
                    }))?;
                    // 让 caret 跟随 active end。
                    self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                        line: pos.line,
                        column: pos.column,
                    }))?;

                    let anchor_offset = self.with_line_index(|idx| {
                        idx.position_to_char_offset(anchor.line, anchor.column)
                    })?;
                    self.mouse_drag = Some(MouseDragState {
                        mode,
                        anchor_pos: anchor,
                        anchor_offset,
                        anchor_unit_range: None,
                    });
                } else {
                    self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                        line: pos.line,
                        column: pos.column,
                    }))?;
                    self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
                    self.mouse_drag = Some(MouseDragState {
                        mode,
                        anchor_pos: pos,
                        anchor_offset: off,
                        anchor_unit_range: None,
                    });
                }
            }
            MouseSelectionMode::Rect => {
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: pos.line,
                    column: pos.column,
                }))?;
                self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
                self.set_rect_selection_offsets(off, off)?;
                self.mouse_drag = Some(MouseDragState {
                    mode,
                    anchor_pos: pos,
                    anchor_offset: off,
                    anchor_unit_range: None,
                });
            }
            MouseSelectionMode::Word => {
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: pos.line,
                    column: pos.column,
                }))?;
                self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
                self.select_word()?;
                let (start, end) = self.primary_selection_offsets();
                let (end_line, end_col) = self.char_offset_to_logical_position(end);
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: end_line,
                    column: end_col,
                }))?;
                self.mouse_drag = Some(MouseDragState {
                    mode,
                    anchor_pos: pos,
                    anchor_offset: off,
                    anchor_unit_range: Some((start, end)),
                });
            }
            MouseSelectionMode::Line => {
                self.set_line_selection_offsets(off, off)?;
                let (_start, end) = self.primary_selection_offsets();
                let (end_line, end_col) = self.char_offset_to_logical_position(end);
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: end_line,
                    column: end_col,
                }))?;
                self.mouse_drag = Some(MouseDragState {
                    mode,
                    anchor_pos: pos,
                    anchor_offset: off,
                    anchor_unit_range: None,
                });
            }
            MouseSelectionMode::Paragraph => {
                self.select_paragraph_at_char_offset(off)?;
                let (_start, end) = self.primary_selection_offsets();
                let (end_line, end_col) = self.char_offset_to_logical_position(end);
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: end_line,
                    column: end_col,
                }))?;
                self.mouse_drag = Some(MouseDragState {
                    mode,
                    anchor_pos: pos,
                    anchor_offset: off,
                    anchor_unit_range: None,
                });
            }
        }
        Ok(())
    }

    pub fn mouse_dragged(&mut self, x_px: f32, y_px: f32) -> Result<(), UiError> {
        let Some(state) = self.mouse_drag.clone() else {
            return Ok(());
        };
        let Some(off) = self.view_point_to_char_offset(x_px, y_px) else {
            return Ok(());
        };

        match state.mode {
            MouseSelectionMode::Char => {
                let (to_line, to_col) = self.char_offset_to_logical_position(off);
                let to = Position::new(to_line, to_col);

                self.exec_core(Command::Cursor(CursorCommand::SetSelection {
                    start: state.anchor_pos,
                    end: to,
                }))?;
                // Keep cursor_position synced to active end.
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: to.line,
                    column: to.column,
                }))?;
            }
            MouseSelectionMode::Word => {
                let (a_start, a_end) = state
                    .anchor_unit_range
                    .unwrap_or((state.anchor_offset, state.anchor_offset));
                let (b_start, b_end) = self.word_unit_range_at_char_offset(off)?;
                let start = a_start.min(b_start);
                let end = a_end.max(b_end);
                self.set_selections_offsets(&[(start, end)], 0)?;

                // caret 位于 active 方向的边界（尽量贴近常见编辑器体验）。
                let caret_off = if off >= state.anchor_offset {
                    end
                } else {
                    start
                };
                let (caret_line, caret_col) = self.char_offset_to_logical_position(caret_off);
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: caret_line,
                    column: caret_col,
                }))?;
            }
            MouseSelectionMode::Line => {
                self.set_line_selection_offsets(state.anchor_offset, off)?;
                let (start, end) = self.primary_selection_offsets();
                let (a_line, _a_col, b_line, _b_col) = self.with_line_index(|idx| {
                    let (a_line, a_col) = idx.char_offset_to_position(state.anchor_offset);
                    let (b_line, b_col) = idx.char_offset_to_position(off);
                    (a_line, a_col, b_line, b_col)
                })?;
                let caret_off = if b_line >= a_line { end } else { start };
                let (caret_line, caret_col) = self.char_offset_to_logical_position(caret_off);
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: caret_line,
                    column: caret_col,
                }))?;
            }
            MouseSelectionMode::Paragraph => {
                self.set_paragraph_selection_offsets(state.anchor_offset, off)?;
                let (start, end) = self.primary_selection_offsets();
                let caret_off = if off >= state.anchor_offset {
                    end
                } else {
                    start
                };
                let (caret_line, caret_col) = self.char_offset_to_logical_position(caret_off);
                self.exec_core(Command::Cursor(CursorCommand::MoveTo {
                    line: caret_line,
                    column: caret_col,
                }))?;
            }
            MouseSelectionMode::Rect => {
                self.set_rect_selection_offsets(state.anchor_offset, off)?;
                // 注意：这里不要再执行 `MoveTo`。
                //
                // `SetRectSelection` 会产生多选区（multi-cursor）。某些 `MoveTo` 变体会把多选区
                // 折叠成单 caret，导致矩形选择在拖拽时“丢行”。
            }
        }
        Ok(())
    }

    pub fn mouse_up(&mut self) {
        self.mouse_drag = None;
    }
}
