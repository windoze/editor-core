use super::*;

impl EditorUi {
    pub(crate) fn begin_char_mouse_drag(
        &mut self,
        pos: Position,
        off: usize,
        modifiers: Modifiers,
        mode: MouseSelectionMode,
    ) -> Result<(), UiError> {
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

            let anchor_offset = self
                .with_line_index(|idx| idx.position_to_char_offset(anchor.line, anchor.column))?;
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
        Ok(())
    }

    pub(crate) fn begin_rect_mouse_drag(
        &mut self,
        pos: Position,
        off: usize,
        mode: MouseSelectionMode,
    ) -> Result<(), UiError> {
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
        Ok(())
    }
}
