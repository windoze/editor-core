use super::*;

impl EditorUi {
    pub fn primary_selection_offsets(&self) -> (usize, usize) {
        let cursor = self.cursor_state();
        let doc = self.lock_doc();
        let Ok(line_index) = doc.ws.buffer_line_index(self.buffer_id) else {
            return (cursor.offset, cursor.offset);
        };
        if let Some(sel) = cursor.selection {
            let a = line_index.position_to_char_offset(sel.start.line, sel.start.column);
            let b = line_index.position_to_char_offset(sel.end.line, sel.end.column);
            if a <= b { (a, b) } else { (b, a) }
        } else {
            (cursor.offset, cursor.offset)
        }
    }

    /// Get the selected text (primary + secondary selections), joined with `'\n'`.
    ///
    /// Notes:
    /// - Empty selections (carets) are ignored.
    /// - The primary selection is placed first, followed by secondary selections in their
    ///   current order.
    pub fn selected_text(&self) -> String {
        let cursor = self.cursor_state();
        let doc = self.lock_doc();
        let Ok(line_index) = doc.ws.buffer_line_index(self.buffer_id) else {
            return String::new();
        };

        let mut order: Vec<usize> = Vec::with_capacity(cursor.selections.len());
        if cursor.primary_selection_index < cursor.selections.len() {
            order.push(cursor.primary_selection_index);
        }
        for idx in 0..cursor.selections.len() {
            if idx != cursor.primary_selection_index {
                order.push(idx);
            }
        }

        let mut parts: Vec<String> = Vec::new();
        for idx in order {
            let sel = match cursor.selections.get(idx) {
                Some(s) => s,
                None => continue,
            };
            if sel.start == sel.end {
                continue;
            }

            let a = line_index.position_to_char_offset(sel.start.line, sel.start.column);
            let b = line_index.position_to_char_offset(sel.end.line, sel.end.column);
            let (start, end) = if a <= b { (a, b) } else { (b, a) };
            let len = end.saturating_sub(start);
            if len == 0 {
                continue;
            }
            if let Ok(text) = doc.ws.buffer_text_range(doc.buffer_id, start, len) {
                parts.push(text);
            }
        }

        if parts.len() == 1 {
            parts.remove(0)
        } else {
            parts.join("\n")
        }
    }

    /// Get lightweight minimap snapshot as JSON.
    ///
    /// This mirrors the JSON shape from `editor-core-ffi` (`value_minimap_grid`) so hosts can reuse
    /// the same decoding logic.
    pub fn minimap_json(&mut self, start_visual_row: usize, count: usize) -> String {
        let view_version = {
            let doc = self.lock_doc();
            doc.ws.view_version(self.view_id).unwrap_or(0)
        };
        if let Some(cache) = self.minimap_cache.as_ref()
            && cache.view_version == view_version
            && cache.start_visual_row == start_visual_row
            && cache.count == count
        {
            return cache.json.clone();
        }

        let grid = {
            let mut doc = self.lock_doc();
            doc.ws
                .get_minimap_content(self.view_id, start_visual_row, count)
                .ok()
        };
        let Some(grid) = grid else {
            self.minimap_cache = None;
            return "{}".to_string();
        };
        let value = serde_json::json!({
            "start_visual_row": grid.start_visual_row,
            "count": grid.count,
            "actual_line_count": grid.actual_line_count(),
            "lines": grid.lines.iter().map(|line| {
                serde_json::json!({
                    "logical_line_index": line.logical_line_index,
                    "visual_in_logical": line.visual_in_logical,
                    "char_offset_start": line.char_offset_start,
                    "char_offset_end": line.char_offset_end,
                    "total_cells": line.total_cells,
                    "non_whitespace_cells": line.non_whitespace_cells,
                    "dominant_style": line.dominant_style,
                    "is_fold_placeholder_appended": line.is_fold_placeholder_appended,
                })
            }).collect::<Vec<_>>(),
        });
        let json = serde_json::to_string(&value).unwrap_or_else(|_| "{}".to_string());
        self.minimap_cache = Some(MinimapCache {
            view_version,
            start_visual_row,
            count,
            json: json.clone(),
        });
        json
    }

    /// Return all selections (including primary) as character-offset ranges, plus the primary index.
    ///
    /// Each range is inclusive-exclusive in Unicode scalar indices.
    pub fn selections_offsets(&self) -> (Vec<(usize, usize)>, usize) {
        let cursor = self.cursor_state();
        let doc = self.lock_doc();
        let Ok(line_index) = doc.ws.buffer_line_index(self.buffer_id) else {
            return (Vec::new(), 0);
        };

        let mut out = Vec::with_capacity(cursor.selections.len());
        for sel in cursor.selections {
            let a = line_index.position_to_char_offset(sel.start.line, sel.start.column);
            let b = line_index.position_to_char_offset(sel.end.line, sel.end.column);
            if a <= b {
                out.push((a, b));
            } else {
                out.push((b, a));
            }
        }
        (out, cursor.primary_selection_index)
    }

    /// Delete only non-empty selections (primary + secondary), keeping empty carets intact.
    ///
    /// This is intended for clipboard "cut" behavior.
    pub fn delete_selections_only(&mut self) -> Result<(), UiError> {
        // 复用 core 的 `InsertText` 逻辑：用空字符串替换各个 selection，
        // 对空 caret 则是 no-op，从而实现“只删选区不动 caret”的 cut 语义。
        self.exec_core(Command::Edit(EditCommand::InsertText {
            text: String::new(),
        }))?;
        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(())
    }

    /// Replace the current selection set (including primary) from character-offset ranges.
    ///
    /// Notes:
    /// - Ranges are inclusive-exclusive, in Unicode scalar indices.
    /// - Empty ranges represent carets.
    pub fn set_selections_offsets(
        &mut self,
        ranges: &[(usize, usize)],
        primary_index: usize,
    ) -> Result<(), UiError> {
        if ranges.is_empty() {
            return Err(UiError::Processor(
                "set_selections_offsets requires a non-empty selection list".to_string(),
            ));
        }

        let selections = self.with_line_index(|line_index| {
            let mut selections: Vec<Selection> = Vec::with_capacity(ranges.len());
            for (start, end) in ranges {
                let (start_line, start_col) = line_index.char_offset_to_position(*start);
                let (end_line, end_col) = line_index.char_offset_to_position(*end);
                let start_pos = Position::new(start_line, start_col);
                let end_pos = Position::new(end_line, end_col);
                selections.push(Selection {
                    start: start_pos,
                    end: end_pos,
                    direction: SelectionDirection::Forward,
                });
            }
            selections
        })?;

        self.exec_core(Command::Cursor(CursorCommand::SetSelections {
            selections,
            primary_index,
        }))?;
        Ok(())
    }

    pub fn clear_secondary_selections(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::ClearSecondarySelections))?;
        Ok(())
    }

    pub fn add_cursor_above(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::AddCursorAbove))?;
        Ok(())
    }

    pub fn add_cursor_below(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::AddCursorBelow))?;
        Ok(())
    }

    pub fn add_next_occurrence(&mut self, options: SearchOptions) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::AddNextOccurrence {
            options,
        }))?;
        Ok(())
    }

    pub fn add_all_occurrences(&mut self, options: SearchOptions) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::AddAllOccurrences {
            options,
        }))?;
        Ok(())
    }

    pub fn select_word(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::SelectWord))?;
        Ok(())
    }

    pub(super) fn word_unit_range_at_char_offset(
        &mut self,
        char_offset: usize,
    ) -> Result<(usize, usize), UiError> {
        let (line, column) = self.char_offset_to_logical_position(char_offset);
        self.exec_core(Command::Cursor(CursorCommand::MoveTo { line, column }))?;
        self.exec_core(Command::Cursor(CursorCommand::ClearSelection))?;
        self.select_word()?;
        Ok(self.primary_selection_offsets())
    }

    pub fn select_line(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::SelectLine))?;
        Ok(())
    }

    /// 按行扩展选择：给定 anchor/active 两个 char offset，选择覆盖它们所在行的并集。
    ///
    /// 语义类似 “三击选中行后拖拽按行扩展”：
    /// - start 为最上面一行的行首
    /// - end 尽量包含最下面一行的换行（若存在下一行）
    pub fn set_line_selection_offsets(
        &mut self,
        anchor_offset: usize,
        active_offset: usize,
    ) -> Result<(), UiError> {
        let (line_count, a_line, b_line) = self.with_line_index(|line_index| {
            let line_count = line_index.line_count();
            let (a_line, _a_col) = line_index.char_offset_to_position(anchor_offset);
            let (b_line, _b_col) = line_index.char_offset_to_position(active_offset);
            (line_count, a_line, b_line)
        })?;
        if line_count == 0 {
            return Ok(());
        }

        let start_line = a_line.min(b_line);
        let end_line = a_line.max(b_line);
        let (start, end) = self.paragraph_offsets_for_line_range(start_line, end_line);
        self.set_selections_offsets(&[(start, end)], 0)?;
        Ok(())
    }

    /// 选择一个“段落”（以空行分隔的连续行块）。
    ///
    /// - 段落定义：连续的“空行”或连续的“非空行”构成一个段落。
    /// - 选区行为：类似 `SelectLine`，会尽量包含段落末尾的换行（若存在下一行）。
    pub fn select_paragraph_at_char_offset(&mut self, char_offset: usize) -> Result<(), UiError> {
        let (line_count, line) = self.with_line_index(|line_index| {
            let line_count = line_index.line_count();
            let (line, _col) = line_index.char_offset_to_position(char_offset);
            (line_count, line)
        })?;
        if line_count == 0 {
            return Ok(());
        }
        let (start_line, end_line) = self.paragraph_line_range_for_line(line);
        let (start, end) = self.paragraph_offsets_for_line_range(start_line, end_line);
        self.set_selections_offsets(&[(start, end)], 0)?;
        Ok(())
    }

    /// 按段落扩展选择：给定 anchor/active 两个 char offset，选择覆盖它们所在段落的并集。
    pub fn set_paragraph_selection_offsets(
        &mut self,
        anchor_offset: usize,
        active_offset: usize,
    ) -> Result<(), UiError> {
        let (line_count, a_line, b_line) = self.with_line_index(|line_index| {
            let line_count = line_index.line_count();
            let (a_line, _a_col) = line_index.char_offset_to_position(anchor_offset);
            let (b_line, _b_col) = line_index.char_offset_to_position(active_offset);
            (line_count, a_line, b_line)
        })?;
        if line_count == 0 {
            return Ok(());
        }

        let (a_start, a_end) = self.paragraph_line_range_for_line(a_line);
        let (b_start, b_end) = self.paragraph_line_range_for_line(b_line);

        let start_line = a_start.min(b_start);
        let end_line = a_end.max(b_end);
        let (start, end) = self.paragraph_offsets_for_line_range(start_line, end_line);
        self.set_selections_offsets(&[(start, end)], 0)?;
        Ok(())
    }

    pub fn expand_selection(&mut self) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::ExpandSelection))?;
        Ok(())
    }

    pub fn expand_selection_by(
        &mut self,
        unit: ExpandSelectionUnit,
        count: usize,
        direction: ExpandSelectionDirection,
    ) -> Result<(), UiError> {
        self.exec_core(Command::Cursor(CursorCommand::ExpandSelectionBy {
            unit,
            count,
            direction,
        }))?;
        Ok(())
    }

    pub fn set_rect_selection_offsets(
        &mut self,
        anchor_offset: usize,
        active_offset: usize,
    ) -> Result<(), UiError> {
        let (a_line, a_col, b_line, b_col) = self.with_line_index(|line_index| {
            let (a_line, a_col) = line_index.char_offset_to_position(anchor_offset);
            let (b_line, b_col) = line_index.char_offset_to_position(active_offset);
            (a_line, a_col, b_line, b_col)
        })?;
        self.exec_core(Command::Cursor(CursorCommand::SetRectSelection {
            anchor: Position::new(a_line, a_col),
            active: Position::new(b_line, b_col),
        }))?;
        Ok(())
    }

    pub fn add_caret_at_char_offset(
        &mut self,
        char_offset: usize,
        make_primary: bool,
    ) -> Result<(), UiError> {
        let (line, column) =
            self.with_line_index(|line_index| line_index.char_offset_to_position(char_offset))?;
        let pos = Position::new(line, column);

        let cursor = self.cursor_state();
        let mut selections = cursor.selections;
        selections.push(Selection {
            start: pos,
            end: pos,
            direction: SelectionDirection::Forward,
        });

        let primary_index = if make_primary {
            selections.len().saturating_sub(1)
        } else {
            cursor.primary_selection_index
        };

        self.exec_core(Command::Cursor(CursorCommand::SetSelections {
            selections,
            primary_index,
        }))?;
        Ok(())
    }

    #[allow(dead_code)]
    fn is_blank_line(&self, line: usize) -> bool {
        self.with_line_index(|idx| {
            idx.get_line_text(line)
                .unwrap_or_default()
                .trim()
                .is_empty()
        })
        .unwrap_or(true)
    }

    fn paragraph_line_range_for_line(&self, line: usize) -> (usize, usize) {
        self.with_line_index(|line_index| {
            let line_count = line_index.line_count();
            if line_count == 0 {
                return (0, 0);
            }

            let mut start = line.min(line_count.saturating_sub(1));
            let mut end = start;

            let want_blank = line_index
                .get_line_text(start)
                .unwrap_or_default()
                .trim()
                .is_empty();

            while start > 0
                && line_index
                    .get_line_text(start - 1)
                    .unwrap_or_default()
                    .trim()
                    .is_empty()
                    == want_blank
            {
                start -= 1;
            }

            while end + 1 < line_count
                && line_index
                    .get_line_text(end + 1)
                    .unwrap_or_default()
                    .trim()
                    .is_empty()
                    == want_blank
            {
                end += 1;
            }

            (start, end)
        })
        .unwrap_or((0, 0))
    }

    fn paragraph_offsets_for_line_range(
        &self,
        start_line: usize,
        end_line: usize,
    ) -> (usize, usize) {
        self.with_line_index(|line_index| {
            let line_count = line_index.line_count();
            if line_count == 0 {
                return (0, 0);
            }

            let start_line = start_line.min(line_count.saturating_sub(1));
            let end_line = end_line.min(line_count.saturating_sub(1));

            let start = line_index.position_to_char_offset(start_line, 0);
            let end = if end_line + 1 < line_count {
                line_index.position_to_char_offset(end_line + 1, 0)
            } else {
                let line_text = line_index.get_line_text(end_line).unwrap_or_default();
                line_index.position_to_char_offset(end_line, line_text.chars().count())
            };

            (start, end)
        })
        .unwrap_or((0, 0))
    }

    /// Return the current IME marked text range as `(start, len)` in character offsets.
    pub fn marked_range(&self) -> Option<(usize, usize)> {
        self.marked.as_ref().map(|m| (m.start, m.len))
    }
}
