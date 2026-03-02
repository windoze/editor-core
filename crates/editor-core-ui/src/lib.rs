//! UI composition layer for `editor-core`.
//!
//! This crate owns editor state, performs input-event mapping, and uses a renderer
//! implementation (Skia in `editor-core-render-skia`) to draw the viewport.

use editor_core::{
    Command, CommandResult, CursorCommand, EditCommand, EditorStateManager, Position, ViewCommand,
};
use editor_core_render_skia::{
    RenderConfig, RenderError, RenderTheme, SkiaRenderer, VisualCaret, VisualSelection,
};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum UiError {
    #[error("command error: {0}")]
    Command(#[from] editor_core::CommandError),
    #[error("render error: {0}")]
    Render(#[from] RenderError),
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct MarkedRange {
    start: usize,
    len: usize,
}

/// A minimal "single buffer, single view" UI wrapper.
///
/// Later we can add a `Workspace`-backed version for tabs/splits.
pub struct EditorUi {
    state: EditorStateManager,
    renderer: SkiaRenderer,
    theme: RenderTheme,
    render_config: RenderConfig,
    marked: Option<MarkedRange>,
    mouse_anchor: Option<Position>,
}

impl EditorUi {
    pub fn new(initial_text: &str, viewport_width_cells: usize) -> Self {
        Self {
            state: EditorStateManager::new(initial_text, viewport_width_cells),
            renderer: SkiaRenderer::new(),
            theme: RenderTheme::default(),
            render_config: RenderConfig::default(),
            marked: None,
            mouse_anchor: None,
        }
    }

    pub fn text(&self) -> String {
        self.state.editor().get_text()
    }

    pub fn cursor_state(&self) -> editor_core::CursorState {
        self.state.get_cursor_state()
    }

    /// Return the primary selection range as `(start_offset, end_offset)` in character offsets.
    ///
    /// If there is no selection, `start == end == caret_offset`.
    pub fn primary_selection_offsets(&self) -> (usize, usize) {
        let cursor = self.state.get_cursor_state();
        let line_index = &self.state.editor().line_index;
        if let Some(sel) = cursor.selection {
            let a = line_index.position_to_char_offset(sel.start.line, sel.start.column);
            let b = line_index.position_to_char_offset(sel.end.line, sel.end.column);
            if a <= b { (a, b) } else { (b, a) }
        } else {
            (cursor.offset, cursor.offset)
        }
    }

    /// Return the current IME marked text range as `(start, len)` in character offsets.
    pub fn marked_range(&self) -> Option<(usize, usize)> {
        self.marked.map(|m| (m.start, m.len))
    }

    /// Map a character offset (Unicode scalar index) to visual `(row, x_cells)`.
    pub fn char_offset_to_visual(&self, char_offset: usize) -> Option<(usize, usize)> {
        let (line, column) = self.state.editor().line_index.char_offset_to_position(char_offset);
        self.state.logical_position_to_visual(line, column)
    }

    /// Map a visual `(row, x_cells)` position to a character offset.
    pub fn visual_to_char_offset(&self, row: usize, x_cells: usize) -> Option<usize> {
        let pos = self.state.visual_position_to_logical(row, x_cells)?;
        Some(
            self.state
                .editor()
                .line_index
                .position_to_char_offset(pos.line, pos.column),
        )
    }

    /// Map a character offset to a point in the view coordinate space (pixels).
    ///
    /// - `x_px` is left-to-right (in pixels)
    /// - `y_px` is top-to-bottom (in pixels), aligned to the top of the visual row
    pub fn char_offset_to_view_point_px(&self, char_offset: usize) -> Option<(f32, f32)> {
        let (row, x_cells) = self.char_offset_to_visual(char_offset)?;
        let viewport = self.state.get_viewport_state();
        let local_row = row.saturating_sub(viewport.scroll_top);

        let x_px = self.render_config.padding_x_px + x_cells as f32 * self.render_config.cell_width_px;
        let y_px = self.render_config.padding_y_px + local_row as f32 * self.render_config.line_height_px;
        Some((x_px, y_px))
    }

    /// Hit-test a point in the view coordinate space (pixels, top-left origin) and return the
    /// corresponding character offset (Unicode scalar index).
    pub fn view_point_to_char_offset(&self, x_px: f32, y_px: f32) -> Option<usize> {
        let (row, x_cells) = self.pixel_to_visual(x_px, y_px);
        self.visual_to_char_offset(row, x_cells)
    }

    pub fn line_height_px(&self) -> f32 {
        self.render_config.line_height_px
    }

    pub fn set_theme(&mut self, theme: RenderTheme) {
        self.theme = theme;
    }

    pub fn set_render_config(&mut self, config: RenderConfig) {
        self.render_config = config;
    }

    /// Update pixel viewport size and keep editor-core's viewport width/height in sync.
    ///
    /// This is important for soft-wrapping: editor-core's layout uses "cells", while
    /// the renderer maps "cells" to pixel widths.
    pub fn set_viewport_px(
        &mut self,
        width_px: u32,
        height_px: u32,
        scale: f32,
    ) -> Result<(), UiError> {
        self.render_config.width_px = width_px;
        self.render_config.height_px = height_px;
        self.render_config.scale = scale;

        let usable_w = (width_px as f32 - self.render_config.padding_x_px * 2.0).max(1.0);
        let cell_w = self.render_config.cell_width_px.max(1.0);
        let width_cells = (usable_w / cell_w).floor().max(1.0) as usize;
        self.state
            .execute(Command::View(ViewCommand::SetViewportWidth {
                width: width_cells,
            }))?;

        let usable_h = (height_px as f32 - self.render_config.padding_y_px * 2.0).max(1.0);
        let line_h = self.render_config.line_height_px.max(1.0);
        let height_rows = (usable_h / line_h).floor().max(1.0) as usize;
        self.state.set_viewport_height(height_rows);
        Ok(())
    }

    pub fn scroll_by_rows(&mut self, delta_rows: isize) {
        let total = self.state.total_visual_lines() as isize;
        let old = self.state.get_viewport_state().scroll_top as isize;
        let new_top = (old + delta_rows).clamp(0, total.max(0)) as usize;
        self.state.set_scroll_top(new_top);
    }

    pub fn insert_text(&mut self, text: &str) -> Result<(), UiError> {
        self.state.execute(Command::Edit(EditCommand::InsertText {
            text: text.to_string(),
        }))?;
        Ok(())
    }

    pub fn backspace(&mut self) -> Result<(), UiError> {
        self.state.execute(Command::Edit(EditCommand::Backspace))?;
        Ok(())
    }

    pub fn delete_forward(&mut self) -> Result<(), UiError> {
        self.state.execute(Command::Edit(EditCommand::DeleteForward))?;
        Ok(())
    }

    pub fn move_visual_by_rows(&mut self, delta_rows: isize) -> Result<(), UiError> {
        self.state
            .execute(Command::Cursor(CursorCommand::MoveVisualBy { delta_rows }))?;
        Ok(())
    }

    pub fn move_grapheme_left(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Cursor(CursorCommand::MoveGraphemeLeft))?;
        Ok(())
    }

    pub fn move_grapheme_right(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Cursor(CursorCommand::MoveGraphemeRight))?;
        Ok(())
    }

    /// Set IME marked text (composition).
    ///
    /// This is UI-layer behavior (not editor-core kernel): we represent the marked string
    /// as a replaceable range in the document, tracking its `(start, len)` in char offsets.
    pub fn set_marked_text(&mut self, text: &str) -> Result<(), UiError> {
        let new_len = text.chars().count();

        let (start, len) = if let Some(marked) = self.marked {
            (marked.start, marked.len)
        } else {
            let cursor = self.state.get_cursor_state();
            let line_index = &self.state.editor().line_index;
            if let Some(sel) = cursor.selection {
                let a = line_index.position_to_char_offset(sel.start.line, sel.start.column);
                let b = line_index.position_to_char_offset(sel.end.line, sel.end.column);
                let (start, end) = if a <= b { (a, b) } else { (b, a) };
                (start, end.saturating_sub(start))
            } else {
                (cursor.offset, 0)
            }
        };

        self.state.execute(Command::Edit(EditCommand::Replace {
            start,
            length: len,
            text: text.to_string(),
        }))?;

        self.marked = Some(MarkedRange { start, len: new_len });

        // Place caret at the end of marked text.
        let (line, column) = self
            .state
            .editor()
            .line_index
            .char_offset_to_position(start + new_len);
        self.state
            .execute(Command::Cursor(CursorCommand::MoveTo { line, column }))?;
        Ok(())
    }

    pub fn unmark_text(&mut self) {
        self.marked = None;
    }

    pub fn commit_text(&mut self, text: &str) -> Result<(), UiError> {
        if let Some(marked) = self.marked.take() {
            self.state.execute(Command::Edit(EditCommand::Replace {
                start: marked.start,
                length: marked.len,
                text: text.to_string(),
            }))?;

            let end = marked.start + text.chars().count();
            let (line, column) = self.state.editor().line_index.char_offset_to_position(end);
            self.state
                .execute(Command::Cursor(CursorCommand::MoveTo { line, column }))?;
            Ok(())
        } else {
            self.insert_text(text)
        }
    }

    pub fn mouse_down(&mut self, x_px: f32, y_px: f32) -> Result<(), UiError> {
        let (row, x_cells) = self.pixel_to_visual(x_px, y_px);
        if let Some(pos) = self.state.visual_position_to_logical(row, x_cells) {
            self.state
                .execute(Command::Cursor(CursorCommand::MoveTo {
                    line: pos.line,
                    column: pos.column,
                }))?;
            self.state
                .execute(Command::Cursor(CursorCommand::ClearSelection))?;
            self.mouse_anchor = Some(pos);
        }
        Ok(())
    }

    pub fn mouse_dragged(&mut self, x_px: f32, y_px: f32) -> Result<(), UiError> {
        let (row, x_cells) = self.pixel_to_visual(x_px, y_px);
        let Some(anchor) = self.mouse_anchor else {
            return Ok(());
        };
        let Some(to) = self.state.visual_position_to_logical(row, x_cells) else {
            return Ok(());
        };
        self.state
            .execute(Command::Cursor(CursorCommand::SetSelection {
                start: anchor,
                end: to,
            }))?;
        Ok(())
    }

    pub fn mouse_up(&mut self) {
        self.mouse_anchor = None;
    }

    pub fn execute(&mut self, command: Command) -> Result<CommandResult, UiError> {
        Ok(self.state.execute(command)?)
    }

    pub fn render_rgba_visible(&mut self) -> Result<Vec<u8>, UiError> {
        let viewport = self.state.get_viewport_state();
        let start_row = viewport.scroll_top;
        let row_count = viewport.height.unwrap_or(viewport.total_visual_lines.saturating_sub(start_row));

        let grid = self.state.get_viewport_content_styled(start_row, row_count);
        let caret = self.primary_caret_visual();
        let selection = self.primary_selection_visual();
        Ok(self.renderer.render_rgba(
            &grid,
            caret,
            selection,
            self.render_config,
            &self.theme,
        )?)
    }

    fn primary_caret_visual(&self) -> Option<VisualCaret> {
        let cursor = self.state.get_cursor_state();
        self.state
            .logical_position_to_visual(cursor.position.line, cursor.position.column)
            .map(|(row, x_cells)| VisualCaret {
                row: row as u32,
                x_cells: x_cells as u32,
            })
    }

    fn primary_selection_visual(&self) -> Option<VisualSelection> {
        let cursor = self.state.get_cursor_state();
        let sel = cursor.selection?;
        let (a_row, a_x) =
            self.state
                .logical_position_to_visual(sel.start.line, sel.start.column)?;
        let (b_row, b_x) =
            self.state
                .logical_position_to_visual(sel.end.line, sel.end.column)?;
        Some(VisualSelection {
            start_row: a_row as u32,
            start_x_cells: a_x as u32,
            end_row: b_row as u32,
            end_x_cells: b_x as u32,
        })
    }

    fn pixel_to_visual(&self, x_px: f32, y_px: f32) -> (usize, usize) {
        let x = (x_px - self.render_config.padding_x_px).max(0.0);
        let y = (y_px - self.render_config.padding_y_px).max(0.0);

        let col = (x / self.render_config.cell_width_px.max(1.0)).floor().max(0.0) as usize;
        let local_row = (y / self.render_config.line_height_px.max(1.0))
            .floor()
            .max(0.0) as usize;
        let global_row = self.state.get_viewport_state().scroll_top + local_row;
        (global_row, col)
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use editor_core::CursorCommand;

    #[test]
    fn ui_text_roundtrip() {
        let ui = EditorUi::new("hello", 80);
        assert_eq!(ui.text(), "hello");
    }

    #[test]
    fn ui_insert_and_delete() {
        let mut ui = EditorUi::new("", 80);
        ui.insert_text("abc").unwrap();
        assert_eq!(ui.text(), "abc");
        ui.backspace().unwrap();
        assert_eq!(ui.text(), "ab");
        ui.delete_forward().unwrap(); // no-op at end
        assert_eq!(ui.text(), "ab");
    }

    #[test]
    fn ui_marked_text_replace_and_commit() {
        let mut ui = EditorUi::new("", 80);
        ui.set_marked_text("你").unwrap();
        assert_eq!(ui.text(), "你");
        ui.set_marked_text("你好").unwrap();
        assert_eq!(ui.text(), "你好");
        ui.commit_text("你好!").unwrap();
        assert_eq!(ui.text(), "你好!");
    }

    #[test]
    fn ui_mouse_sets_cursor_and_selection() {
        let mut ui = EditorUi::new("abcd\nefgh\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 60,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(200, 60, 1.0).unwrap();

        // Click near column 2 on first line.
        ui.mouse_down(25.0, 10.0).unwrap();
        assert_eq!(ui.cursor_state().position, Position::new(0, 2));

        // Drag to second line column 1.
        ui.mouse_dragged(15.0, 30.0).unwrap();
        let cursor = ui.cursor_state();
        assert!(cursor.selection.is_some());
        ui.mouse_up();
    }

    #[test]
    fn ui_render_includes_caret_overlay() {
        let mut ui = EditorUi::new("abc", 80);
        ui.set_render_config(RenderConfig {
            width_px: 80,
            height_px: 40,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_theme(RenderTheme {
            background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
            foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
            selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
            caret: editor_core_render_skia::Rgba8::new(0, 0, 200, 255),
        });
        ui.set_viewport_px(80, 40, 1.0).unwrap();

        // Put caret after 'c' (x=3).
        ui.execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 3 }))
            .unwrap();
        let rgba = ui.render_rgba_visible().unwrap();
        assert_eq!(pixel(&rgba, 80, 30, 10), [0, 0, 200, 255]);
        assert_eq!(pixel(&rgba, 80, 70, 30), [10, 20, 30, 255]);
    }

    #[test]
    fn ui_exposes_selection_offsets_and_offset_mapping() {
        let mut ui = EditorUi::new("abcd\nefgh\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 60,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(200, 60, 1.0).unwrap();

        // Select "bc" in first line (offsets 1..3).
        ui.execute(Command::Cursor(CursorCommand::SetSelection {
            start: Position::new(0, 1),
            end: Position::new(0, 3),
        }))
        .unwrap();
        assert_eq!(ui.primary_selection_offsets(), (1, 3));

        // Offset -> visual mapping.
        let (row, x) = ui.char_offset_to_visual(2).unwrap();
        assert_eq!((row, x), (0, 2));
        assert_eq!(ui.visual_to_char_offset(0, 2).unwrap(), 2);

        // Offset -> view point mapping (top-left origin).
        let (x_px, y_px) = ui.char_offset_to_view_point_px(2).unwrap();
        assert_eq!((x_px, y_px), (20.0, 0.0));
        assert_eq!(ui.line_height_px(), 20.0);

        // View hit-test.
        assert_eq!(ui.view_point_to_char_offset(25.0, 10.0).unwrap(), 2);
    }

    fn pixel(buf: &[u8], width_px: u32, x: u32, y: u32) -> [u8; 4] {
        let idx = ((y * width_px + x) * 4) as usize;
        [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
    }
}
