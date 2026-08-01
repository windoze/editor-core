use super::super::super::*;

impl EditorUi {
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
