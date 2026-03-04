//! UI composition layer for `editor-core`.
//!
//! This crate owns editor state, performs input-event mapping, and uses a renderer
//! implementation (Skia in `editor-core-render-skia`) to draw the viewport.

use editor_core::{
    Command, CommandResult, CursorCommand, EditCommand, EditorStateManager,
    ExpandSelectionDirection, ExpandSelectionUnit, Position, IME_MARKED_TEXT_STYLE_ID,
    ProcessingEdit, SearchOptions, Selection, SelectionDirection, StyleCommand, StyleLayerId,
    ViewCommand,
};
use editor_core::intervals::Interval;
use editor_core_lsp::{
    LspNotification, encode_semantic_style_id, lsp_diagnostics_to_processing_edits,
    semantic_tokens_to_intervals,
};
use editor_core_render_skia::{
    FoldMarker, RenderConfig, RenderError, RenderTheme, SkiaRenderer, StyleColors, VisualCaret,
    VisualSelection,
};
use editor_core_sublime::{SublimeProcessor, SublimeSyntaxSet};
use editor_core_treesitter::{TreeSitterProcessor, TreeSitterProcessorConfig};
use std::collections::{BTreeMap, HashMap};
use thiserror::Error;

#[derive(Debug, Error)]
pub enum UiError {
    #[error("command error: {0}")]
    Command(#[from] editor_core::CommandError),
    #[error("render error: {0}")]
    Render(#[from] RenderError),
    #[error("processor error: {0}")]
    Processor(String),
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct MarkedRange {
    start: usize,
    len: usize,
    /// Text that was replaced when the IME composition started.
    ///
    /// Needed to support "cancel composition" without losing the original selection.
    original_text: String,
    original_len: usize,
}

#[derive(Debug, Default)]
struct TreeSitterCaptureMapper {
    capture_to_id: HashMap<String, u32>,
    id_to_capture: Vec<String>,
}

impl TreeSitterCaptureMapper {
    /// Base prefix for Tree-sitter highlight capture `StyleId`s.
    pub const BASE: u32 = 0x0500_0000;

    pub fn style_id_for_capture(&mut self, capture_name: &str) -> u32 {
        if let Some(&id) = self.capture_to_id.get(capture_name) {
            return id;
        }
        let idx = self.id_to_capture.len() as u32 + 1;
        let id = Self::BASE | idx;
        self.id_to_capture.push(capture_name.to_string());
        self.capture_to_id.insert(capture_name.to_string(), id);
        id
    }

    pub fn capture_for_style_id(&self, style_id: u32) -> Option<&str> {
        if style_id & 0xFF00_0000 != Self::BASE {
            return None;
        }
        let raw = style_id & 0x00FF_FFFF;
        if raw == 0 {
            return None;
        }
        let idx = raw.saturating_sub(1) as usize;
        self.id_to_capture.get(idx).map(|s| s.as_str())
    }
}

/// A minimal "single buffer, single view" UI wrapper.
///
/// Later we can add a `Workspace`-backed version for tabs/splits.
pub struct EditorUi {
    state: EditorStateManager,
    renderer: SkiaRenderer,
    theme: RenderTheme,
    render_config: RenderConfig,
    sublime: Option<SublimeProcessor>,
    treesitter: Option<TreeSitterProcessor>,
    treesitter_capture_mapper: TreeSitterCaptureMapper,
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
            sublime: None,
            treesitter: None,
            treesitter_capture_mapper: TreeSitterCaptureMapper::default(),
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

    /// Return all selections (including primary) as character-offset ranges, plus the primary index.
    ///
    /// Each range is inclusive-exclusive in Unicode scalar indices.
    pub fn selections_offsets(&self) -> (Vec<(usize, usize)>, usize) {
        let cursor = self.state.get_cursor_state();
        let line_index = &self.state.editor().line_index;

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

        let line_index = &self.state.editor().line_index;
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

        self.state.execute(Command::Cursor(CursorCommand::SetSelections {
            selections,
            primary_index,
        }))?;
        Ok(())
    }

    pub fn clear_secondary_selections(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Cursor(CursorCommand::ClearSecondarySelections))?;
        Ok(())
    }

    pub fn add_cursor_above(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Cursor(CursorCommand::AddCursorAbove))?;
        Ok(())
    }

    pub fn add_cursor_below(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Cursor(CursorCommand::AddCursorBelow))?;
        Ok(())
    }

    pub fn add_next_occurrence(&mut self, options: SearchOptions) -> Result<(), UiError> {
        self.state.execute(Command::Cursor(CursorCommand::AddNextOccurrence {
            options,
        }))?;
        Ok(())
    }

    pub fn add_all_occurrences(&mut self, options: SearchOptions) -> Result<(), UiError> {
        self.state.execute(Command::Cursor(CursorCommand::AddAllOccurrences {
            options,
        }))?;
        Ok(())
    }

    pub fn select_word(&mut self) -> Result<(), UiError> {
        self.state.execute(Command::Cursor(CursorCommand::SelectWord))?;
        Ok(())
    }

    pub fn select_line(&mut self) -> Result<(), UiError> {
        self.state.execute(Command::Cursor(CursorCommand::SelectLine))?;
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
        let line_index = &self.state.editor().line_index;
        let line_count = line_index.line_count();
        if line_count == 0 {
            return Ok(());
        }

        let (a_line, _a_col) = line_index.char_offset_to_position(anchor_offset);
        let (b_line, _b_col) = line_index.char_offset_to_position(active_offset);

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
        let line_index = &self.state.editor().line_index;
        let line_count = line_index.line_count();
        if line_count == 0 {
            return Ok(());
        }

        let (line, _col) = line_index.char_offset_to_position(char_offset);
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
        let line_index = &self.state.editor().line_index;
        let line_count = line_index.line_count();
        if line_count == 0 {
            return Ok(());
        }

        let (a_line, _a_col) = line_index.char_offset_to_position(anchor_offset);
        let (b_line, _b_col) = line_index.char_offset_to_position(active_offset);

        let (a_start, a_end) = self.paragraph_line_range_for_line(a_line);
        let (b_start, b_end) = self.paragraph_line_range_for_line(b_line);

        let start_line = a_start.min(b_start);
        let end_line = a_end.max(b_end);
        let (start, end) = self.paragraph_offsets_for_line_range(start_line, end_line);
        self.set_selections_offsets(&[(start, end)], 0)?;
        Ok(())
    }

    pub fn expand_selection(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Cursor(CursorCommand::ExpandSelection))?;
        Ok(())
    }

    pub fn expand_selection_by(
        &mut self,
        unit: ExpandSelectionUnit,
        count: usize,
        direction: ExpandSelectionDirection,
    ) -> Result<(), UiError> {
        self.state
            .execute(Command::Cursor(CursorCommand::ExpandSelectionBy {
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
        let line_index = &self.state.editor().line_index;
        let (a_line, a_col) = line_index.char_offset_to_position(anchor_offset);
        let (b_line, b_col) = line_index.char_offset_to_position(active_offset);
        self.state.execute(Command::Cursor(CursorCommand::SetRectSelection {
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
        let line_index = &self.state.editor().line_index;
        let (line, column) = line_index.char_offset_to_position(char_offset);
        let pos = Position::new(line, column);

        let cursor = self.state.get_cursor_state();
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

        self.state.execute(Command::Cursor(CursorCommand::SetSelections {
            selections,
            primary_index,
        }))?;
        Ok(())
    }

    fn is_blank_line(&self, line: usize) -> bool {
        self.state
            .editor()
            .line_index
            .get_line_text(line)
            .unwrap_or_default()
            .trim()
            .is_empty()
    }

    fn paragraph_line_range_for_line(&self, line: usize) -> (usize, usize) {
        let line_index = &self.state.editor().line_index;
        let line_count = line_index.line_count();
        if line_count == 0 {
            return (0, 0);
        }

        let mut start = line.min(line_count.saturating_sub(1));
        let mut end = start;

        let want_blank = self.is_blank_line(start);

        while start > 0 && self.is_blank_line(start - 1) == want_blank {
            start -= 1;
        }
        while end + 1 < line_count && self.is_blank_line(end + 1) == want_blank {
            end += 1;
        }

        (start, end)
    }

    fn paragraph_offsets_for_line_range(&self, start_line: usize, end_line: usize) -> (usize, usize) {
        let line_index = &self.state.editor().line_index;
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
    }

    /// Return the current IME marked text range as `(start, len)` in character offsets.
    pub fn marked_range(&self) -> Option<(usize, usize)> {
        self.marked.as_ref().map(|m| (m.start, m.len))
    }

    /// Map a character offset (Unicode scalar index) to visual `(row, x_cells)`.
    pub fn char_offset_to_visual(&self, char_offset: usize) -> Option<(usize, usize)> {
        let (line, column) = self
            .state
            .editor()
            .line_index
            .char_offset_to_position(char_offset);
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

        let gutter_px =
            self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
        let x_px = self.render_config.padding_x_px
            + gutter_px
            + x_cells as f32 * self.render_config.cell_width_px;
        let y_px =
            self.render_config.padding_y_px + local_row as f32 * self.render_config.line_height_px;
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

    pub fn set_style_colors(&mut self, styles: BTreeMap<u32, StyleColors>) {
        self.theme.styles = styles;
    }

    pub fn clear_style_colors(&mut self) {
        self.theme.styles.clear();
    }

    pub fn set_sublime_syntax_yaml(&mut self, yaml: &str) -> Result<(), UiError> {
        let mut set = SublimeSyntaxSet::new();
        let syntax = set
            .load_from_str(yaml)
            .map_err(|e| UiError::Processor(e.to_string()))?;
        self.sublime = Some(SublimeProcessor::new(syntax, set));
        self.refresh_processing()
    }

    pub fn set_sublime_syntax_path(&mut self, path: &std::path::Path) -> Result<(), UiError> {
        let mut set = SublimeSyntaxSet::new();
        let syntax = set
            .load_from_path(path)
            .map_err(|e| UiError::Processor(e.to_string()))?;
        self.sublime = Some(SublimeProcessor::new(syntax, set));
        self.refresh_processing()
    }

    pub fn disable_sublime_syntax(&mut self) {
        self.sublime = None;
    }

    pub fn sublime_scope_for_style_id(&self, style_id: u32) -> Option<&str> {
        self.sublime
            .as_ref()
            .and_then(|p| p.scope_mapper.scope_for_style_id(style_id))
    }

    pub fn sublime_style_id_for_scope(&mut self, scope: &str) -> Result<u32, UiError> {
        let Some(proc) = self.sublime.as_mut() else {
            return Err(UiError::Processor(
                "sublime syntax processor is not enabled".to_string(),
            ));
        };
        Ok(proc.scope_mapper.style_id_for_scope(scope))
    }

    pub fn set_treesitter_rust_default(&mut self) -> Result<(), UiError> {
        self.set_treesitter_rust_with_queries(
            tree_sitter_rust::HIGHLIGHTS_QUERY,
            Some(
                r#"
                (function_item) @fold
                (impl_item) @fold
                (struct_item) @fold
                (enum_item) @fold
                (mod_item) @fold
                (block) @fold
                "#,
            ),
        )
    }

    pub fn set_treesitter_rust_with_queries(
        &mut self,
        highlights_query: &str,
        folds_query: Option<&str>,
    ) -> Result<(), UiError> {
        let language: tree_sitter::Language = tree_sitter_rust::LANGUAGE.into();

        let query = tree_sitter::Query::new(&language, highlights_query)
            .map_err(|e| UiError::Processor(e.to_string()))?;

        let mut capture_styles = BTreeMap::<String, u32>::new();
        for name in query.capture_names() {
            let style_id = self.treesitter_capture_mapper.style_id_for_capture(name);
            capture_styles.insert(name.to_string(), style_id);
        }

        let mut config = TreeSitterProcessorConfig::new(language, highlights_query.to_string());
        if let Some(folds_query) = folds_query {
            config = config.with_folds_query(folds_query.to_string());
        }
        config.capture_styles = capture_styles;

        self.treesitter =
            Some(TreeSitterProcessor::new(config).map_err(|e| UiError::Processor(e.to_string()))?);
        self.refresh_processing()
    }

    pub fn disable_treesitter(&mut self) {
        self.treesitter = None;
    }

    pub fn treesitter_capture_for_style_id(&self, style_id: u32) -> Option<&str> {
        self.treesitter_capture_mapper
            .capture_for_style_id(style_id)
    }

    pub fn treesitter_style_id_for_capture(&mut self, capture_name: &str) -> u32 {
        self.treesitter_capture_mapper
            .style_id_for_capture(capture_name)
    }

    pub fn lsp_apply_publish_diagnostics_json(&mut self, params_json: &str) -> Result<(), UiError> {
        let params_value: serde_json::Value =
            serde_json::from_str(params_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let notif = LspNotification::from_method_and_params(
            "textDocument/publishDiagnostics",
            &params_value,
        )
        .ok_or_else(|| UiError::Processor("invalid publishDiagnostics params".to_string()))?;

        let LspNotification::PublishDiagnostics(params) = notif else {
            return Err(UiError::Processor(
                "failed to parse publishDiagnostics params".to_string(),
            ));
        };

        let line_index = &self.state.editor().line_index;
        let edits = lsp_diagnostics_to_processing_edits(line_index, &params);
        self.state.apply_processing_edits(edits);
        Ok(())
    }

    pub fn lsp_apply_semantic_tokens(&mut self, data: &[u32]) -> Result<(), UiError> {
        let line_index = &self.state.editor().line_index;
        let intervals = semantic_tokens_to_intervals(data, line_index, encode_semantic_style_id)
            .map_err(|e| UiError::Processor(e.to_string()))?;
        self.state
            .apply_processing_edits(vec![ProcessingEdit::ReplaceStyleLayer {
                layer: StyleLayerId::SEMANTIC_TOKENS,
                intervals,
            }]);
        Ok(())
    }

    pub fn set_render_config(&mut self, config: RenderConfig) {
        self.render_config = config;
    }

    pub fn set_render_metrics(
        &mut self,
        font_size: f32,
        line_height_px: f32,
        cell_width_px: f32,
        padding_x_px: f32,
        padding_y_px: f32,
    ) {
        self.render_config.font_size = font_size;
        self.render_config.line_height_px = line_height_px;
        self.render_config.cell_width_px = cell_width_px;
        self.render_config.padding_x_px = padding_x_px;
        self.render_config.padding_y_px = padding_y_px;
    }

    /// Configure font fallback list for rendering (comma-separated family names).
    ///
    /// This mirrors how VS Code allows configuring `editor.fontFamily` as a list.
    ///
    /// Notes:
    /// - This does not affect layout metrics; the editor remains monospace-grid based.
    /// - The renderer will pick the first font that contains a glyph for each character.
    pub fn set_font_families_csv(&mut self, families_csv: &str) {
        let families: Vec<String> = families_csv
            .split(',')
            .map(|s| s.trim().to_string())
            .collect();
        self.renderer.set_font_families(families);
    }

    /// Enable/disable font ligatures in the renderer (visual-only).
    pub fn set_font_ligatures_enabled(&mut self, enabled: bool) {
        self.render_config.enable_ligatures = enabled;
    }

    /// Override the ASCII word-boundary character set used by editor-friendly "word" operations.
    ///
    /// This is similar in spirit to VSCode's `wordSeparators`.
    pub fn set_word_boundary_ascii_boundary_chars(&mut self, boundary_chars: &str) -> Result<(), UiError> {
        self.state
            .execute(Command::View(ViewCommand::SetWordBoundaryAsciiBoundaryChars {
                boundary_chars: boundary_chars.to_string(),
            }))?;
        Ok(())
    }

    /// Reset word-boundary configuration to the default (ASCII identifier-like words).
    pub fn reset_word_boundary_defaults(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::View(ViewCommand::ResetWordBoundaryDefaults))?;
        Ok(())
    }

    pub fn set_gutter_width_cells(&mut self, width_cells: u32) -> Result<(), UiError> {
        self.render_config.gutter_width_cells = width_cells;
        // Keep wrap width in sync with the available text area.
        self.set_viewport_px(
            self.render_config.width_px,
            self.render_config.height_px,
            self.render_config.scale,
        )?;
        Ok(())
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

        let gutter_px =
            self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
        let usable_w =
            (width_px as f32 - self.render_config.padding_x_px * 2.0 - gutter_px).max(1.0);
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
        self.refresh_processing()?;
        Ok(())
    }

    pub fn backspace(&mut self) -> Result<(), UiError> {
        self.state.execute(Command::Edit(EditCommand::Backspace))?;
        self.refresh_processing()?;
        Ok(())
    }

    pub fn delete_forward(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Edit(EditCommand::DeleteForward))?;
        self.refresh_processing()?;
        Ok(())
    }

    pub fn add_style(&mut self, start: usize, end: usize, style_id: u32) -> Result<(), UiError> {
        self.state.execute(Command::Style(StyleCommand::AddStyle {
            start,
            end,
            style_id,
        }))?;
        self.refresh_processing()?;
        Ok(())
    }

    pub fn remove_style(&mut self, start: usize, end: usize, style_id: u32) -> Result<(), UiError> {
        self.state
            .execute(Command::Style(StyleCommand::RemoveStyle {
                start,
                end,
                style_id,
            }))?;
        self.refresh_processing()?;
        Ok(())
    }

    pub fn undo(&mut self) -> Result<(), UiError> {
        self.state.execute(Command::Edit(EditCommand::Undo))?;
        Ok(())
    }

    pub fn redo(&mut self) -> Result<(), UiError> {
        self.state.execute(Command::Edit(EditCommand::Redo))?;
        Ok(())
    }

    pub fn end_undo_group(&mut self) -> Result<(), UiError> {
        self.state
            .execute(Command::Edit(EditCommand::EndUndoGroup))?;
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

    pub fn move_grapheme_left_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.state.get_cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        // Move the internal caret to the active end, clear selection so movement applies, then restore.
        self.state.execute(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.state
            .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        self.state
            .execute(Command::Cursor(CursorCommand::MoveGraphemeLeft))?;

        let new_active = self.state.editor().cursor_position();
        self.state.execute(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        Ok(())
    }

    pub fn move_grapheme_right_and_modify_selection(&mut self) -> Result<(), UiError> {
        let cursor = self.state.get_cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.state.execute(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.state
            .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        self.state
            .execute(Command::Cursor(CursorCommand::MoveGraphemeRight))?;

        let new_active = self.state.editor().cursor_position();
        self.state.execute(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
        Ok(())
    }

    pub fn move_visual_by_rows_and_modify_selection(
        &mut self,
        delta_rows: isize,
    ) -> Result<(), UiError> {
        let cursor = self.state.get_cursor_state();
        let anchor = cursor.selection.map(|s| s.start).unwrap_or(cursor.position);
        let active = cursor.position;

        self.state.execute(Command::Cursor(CursorCommand::MoveTo {
            line: active.line,
            column: active.column,
        }))?;
        self.state
            .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        self.state
            .execute(Command::Cursor(CursorCommand::MoveVisualBy { delta_rows }))?;

        let new_active = self.state.editor().cursor_position();
        self.state.execute(Command::Cursor(CursorCommand::SetSelection {
            start: anchor,
            end: new_active,
        }))?;
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
        let (start, replace_len, original_text, original_len) =
            if let Some((start, len)) = replace_range {
                let original = self.state.editor().piece_table.get_range(start, len);
                (start, len, original, len)
            } else if let Some(marked) = self.marked.as_ref() {
                (
                    marked.start,
                    marked.len,
                    marked.original_text.clone(),
                    marked.original_len,
                )
            } else {
                let cursor = self.state.get_cursor_state();
                let line_index = &self.state.editor().line_index;
                if let Some(sel) = cursor.selection {
                    let a = line_index.position_to_char_offset(sel.start.line, sel.start.column);
                    let b = line_index.position_to_char_offset(sel.end.line, sel.end.column);
                    let (start, end) = if a <= b { (a, b) } else { (b, a) };
                    let len = end.saturating_sub(start);
                    let original = self.state.editor().piece_table.get_range(start, len);
                    (start, len, original, len)
                } else {
                    (cursor.offset, 0, String::new(), 0)
                }
            };

        // Empty marked text means "cancel/clear composition": restore original replaced text.
        if new_len == 0 {
            if replace_len > 0 || !original_text.is_empty() {
                self.state.execute(Command::Edit(EditCommand::Replace {
                    start,
                    length: replace_len,
                    text: original_text.clone(),
                }))?;
                self.refresh_processing()?;
            }

            self.marked = None;
            self.state
                .apply_processing_edits([ProcessingEdit::ClearStyleLayer {
                    layer: StyleLayerId::IME_MARKED_TEXT,
                }]);

            // Restore selection to the original range (best-effort).
            let a_off = start;
            let b_off = start.saturating_add(original_len);
            let line_index = &self.state.editor().line_index;
            let (a_line, a_col) = line_index.char_offset_to_position(a_off);
            let (b_line, b_col) = line_index.char_offset_to_position(b_off);

            if original_len > 0 {
                self.state.execute(Command::Cursor(CursorCommand::SetSelection {
                    start: Position::new(a_line, a_col),
                    end: Position::new(b_line, b_col),
                }))?;
            } else {
                self.state.execute(Command::Cursor(CursorCommand::MoveTo {
                    line: a_line,
                    column: a_col,
                }))?;
                self.state
                    .execute(Command::Cursor(CursorCommand::ClearSelection))?;
            }
            return Ok(());
        }

        self.state.execute(Command::Edit(EditCommand::Replace {
            start,
            length: replace_len,
            text: text.to_string(),
        }))?;
        self.refresh_processing()?;

        self.marked = Some(MarkedRange {
            start,
            len: new_len,
            original_text,
            original_len,
        });

        // Apply a dedicated style layer so the renderer can draw preedit (underline/background).
        self.state
            .apply_processing_edits([ProcessingEdit::ReplaceStyleLayer {
                layer: StyleLayerId::IME_MARKED_TEXT,
                intervals: vec![Interval::new(
                    start,
                    start.saturating_add(new_len),
                    IME_MARKED_TEXT_STYLE_ID,
                )],
            }]);

        // Honor selection inside marked text (preedit caret / selection).
        let sel_start = selected_start.min(new_len);
        let sel_end = selected_start
            .saturating_add(selected_len)
            .min(new_len);

        let a_off = start.saturating_add(sel_start);
        let b_off = start.saturating_add(sel_end);

        let line_index = &self.state.editor().line_index;
        let (a_line, a_col) = line_index.char_offset_to_position(a_off);
        let (b_line, b_col) = line_index.char_offset_to_position(b_off);

        if sel_end > sel_start {
            self.state.execute(Command::Cursor(CursorCommand::SetSelection {
                start: Position::new(a_line, a_col),
                end: Position::new(b_line, b_col),
            }))?;
        } else {
            self.state.execute(Command::Cursor(CursorCommand::MoveTo {
                line: b_line,
                column: b_col,
            }))?;
            self.state
                .execute(Command::Cursor(CursorCommand::ClearSelection))?;
        }
        Ok(())
    }

    pub fn unmark_text(&mut self) {
        self.marked = None;
        self.state
            .apply_processing_edits([ProcessingEdit::ClearStyleLayer {
                layer: StyleLayerId::IME_MARKED_TEXT,
            }]);
    }

    pub fn commit_text(&mut self, text: &str) -> Result<(), UiError> {
        if let Some(marked) = self.marked.take() {
            self.state.execute(Command::Edit(EditCommand::Replace {
                start: marked.start,
                length: marked.len,
                text: text.to_string(),
            }))?;
            self.refresh_processing()?;

            let end = marked.start + text.chars().count();
            let (line, column) = self.state.editor().line_index.char_offset_to_position(end);
            self.state
                .execute(Command::Cursor(CursorCommand::MoveTo { line, column }))?;

            self.state
                .apply_processing_edits([ProcessingEdit::ClearStyleLayer {
                    layer: StyleLayerId::IME_MARKED_TEXT,
                }]);
            Ok(())
        } else {
            self.insert_text(text)
        }
    }

    pub fn mouse_down(&mut self, x_px: f32, y_px: f32) -> Result<(), UiError> {
        // Gutter interaction: click-to-toggle fold state for a fold start line.
        if self.render_config.gutter_width_cells > 0 {
            let gutter_px =
                self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
            let gutter_end_x = self.render_config.padding_x_px + gutter_px;
            if x_px < gutter_end_x {
                let (row, _x_cells) = self.pixel_to_visual(x_px, y_px);
                if let Some(pos) = self.state.visual_position_to_logical(row, 0) {
                    if let Some(region) = self
                        .state
                        .get_folding_state()
                        .regions
                        .iter()
                        .filter(|r| r.start_line == pos.line)
                        .min_by_key(|r| r.end_line)
                        .cloned()
                    {
                        if region.is_collapsed {
                            self.state.execute(Command::Style(StyleCommand::Unfold {
                                start_line: region.start_line,
                            }))?;
                        } else {
                            self.state.execute(Command::Style(StyleCommand::Fold {
                                start_line: region.start_line,
                                end_line: region.end_line,
                            }))?;
                        }
                        self.mouse_anchor = None;
                        return Ok(());
                    }
                }
            }
        }

        let (row, x_cells) = self.pixel_to_visual(x_px, y_px);
        if let Some(pos) = self.state.visual_position_to_logical(row, x_cells) {
            self.state.execute(Command::Cursor(CursorCommand::MoveTo {
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
        let required = SkiaRenderer::required_rgba_len(self.render_config)?;
        let mut out = vec![0u8; required];
        self.render_rgba_visible_into(out.as_mut_slice())?;
        Ok(out)
    }

    pub fn required_rgba_len(&self) -> usize {
        (self.render_config.width_px as usize)
            .saturating_mul(self.render_config.height_px as usize)
            .saturating_mul(4)
    }

    pub fn render_rgba_visible_into(&mut self, out_rgba: &mut [u8]) -> Result<usize, UiError> {
        let viewport = self.state.get_viewport_state();
        let start_row = viewport.scroll_top;
        let row_count = viewport
            .height
            .unwrap_or(viewport.total_visual_lines.saturating_sub(start_row));

        let grid = self.state.get_viewport_content_styled(start_row, row_count);
        let selections = self.all_selections_visual();
        let carets = self.all_carets_visual();

        let mut fold_markers = Vec::<FoldMarker>::new();
        for region in &self.state.get_folding_state().regions {
            if region.end_line <= region.start_line {
                continue;
            }
            fold_markers.push(FoldMarker {
                logical_line: region.start_line as u32,
                is_collapsed: region.is_collapsed,
            });
        }
        let required = SkiaRenderer::required_rgba_len(self.render_config)?;
        self.renderer.render_rgba_into(
            &grid,
            carets.as_slice(),
            selections.as_slice(),
            fold_markers.as_slice(),
            self.render_config,
            &self.theme,
            out_rgba,
        )?;
        Ok(required)
    }

    fn refresh_processing(&mut self) -> Result<(), UiError> {
        if let Some(proc) = self.sublime.as_mut() {
            self.state
                .apply_processor(proc)
                .map_err(|e| UiError::Processor(e.to_string()))?;
        }
        if let Some(proc) = self.treesitter.as_mut() {
            self.state
                .apply_processor(proc)
                .map_err(|e| UiError::Processor(e.to_string()))?;
        }
        Ok(())
    }

    fn all_selections_visual(&self) -> Vec<VisualSelection> {
        let cursor = self.state.get_cursor_state();
        let mut out = Vec::new();

        for sel in cursor.selections {
            if sel.start == sel.end {
                continue;
            }
            let Some((a_row, a_x)) = self
                .state
                .logical_position_to_visual(sel.start.line, sel.start.column)
            else {
                continue;
            };
            let Some((b_row, b_x)) = self
                .state
                .logical_position_to_visual(sel.end.line, sel.end.column)
            else {
                continue;
            };
            out.push(VisualSelection {
                start_row: a_row as u32,
                start_x_cells: a_x as u32,
                end_row: b_row as u32,
                end_x_cells: b_x as u32,
            });
        }

        out
    }

    fn all_carets_visual(&self) -> Vec<VisualCaret> {
        let cursor = self.state.get_cursor_state();
        let primary_idx = cursor.primary_selection_index;

        let mut secondary = Vec::new();
        let mut primary = Vec::new();
        for (idx, sel) in cursor.selections.iter().enumerate() {
            let Some((row, x_cells)) = self
                .state
                .logical_position_to_visual(sel.end.line, sel.end.column)
            else {
                continue;
            };

            // Draw primary caret last so it wins in overlaps.
            let caret = VisualCaret {
                row: row as u32,
                x_cells: x_cells as u32,
            };
            if idx == primary_idx {
                primary.push(caret);
            } else {
                secondary.push(caret);
            }
        }
        secondary.extend(primary);
        secondary
    }

    fn pixel_to_visual(&self, x_px: f32, y_px: f32) -> (usize, usize) {
        let gutter_px =
            self.render_config.gutter_width_cells as f32 * self.render_config.cell_width_px;
        let x = (x_px - self.render_config.padding_x_px - gutter_px).max(0.0);
        let y = (y_px - self.render_config.padding_y_px).max(0.0);

        let col = (x / self.render_config.cell_width_px.max(1.0))
            .floor()
            .max(0.0) as usize;
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
    use editor_core_treesitter::TreeSitterUpdateMode;

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
	    fn ui_undo_redo_roundtrip() {
	        let mut ui = EditorUi::new("", 80);
	        ui.insert_text("a").unwrap();
	        ui.end_undo_group().unwrap();
	        ui.insert_text("b").unwrap();
	        assert_eq!(ui.text(), "ab");
	        ui.undo().unwrap();
	        assert_eq!(ui.text(), "a");
	        ui.redo().unwrap();
	        assert_eq!(ui.text(), "ab");
	    }

	    #[test]
	    fn ui_expand_selection_by_word_is_expand_only() {
	        let mut ui = EditorUi::new("one two three", 80);
	        ui.execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 4 }))
	            .unwrap(); // at "two"

	        ui.expand_selection_by(
	            ExpandSelectionUnit::Word,
	            1,
	            ExpandSelectionDirection::Forward,
	        )
	        .unwrap();
	        assert_eq!(ui.primary_selection_offsets(), (4, 7)); // "two"

	        ui.expand_selection_by(
	            ExpandSelectionUnit::Word,
	            1,
	            ExpandSelectionDirection::Forward,
	        )
	        .unwrap();
	        assert_eq!(ui.primary_selection_offsets(), (4, 13)); // "two three"

	        ui.expand_selection_by(
	            ExpandSelectionUnit::Word,
	            1,
	            ExpandSelectionDirection::Backward,
	        )
	        .unwrap();
	        assert_eq!(ui.primary_selection_offsets(), (0, 13)); // "one two three"
	    }

    #[test]
    fn ui_word_boundary_config_affects_select_word() {
        let mut ui = EditorUi::new("foo-bar", 80);
        ui.execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }))
            .unwrap();
        ui.select_word().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (0, 3)); // "foo"

        ui.set_word_boundary_ascii_boundary_chars(".").unwrap();
        ui.execute(Command::Cursor(CursorCommand::ClearSelection)).unwrap();
        ui.execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }))
            .unwrap();
        ui.select_word().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (0, 7)); // "foo-bar"

        ui.reset_word_boundary_defaults().unwrap();
        ui.execute(Command::Cursor(CursorCommand::ClearSelection)).unwrap();
        ui.execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }))
            .unwrap();
        ui.select_word().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (0, 3)); // "foo"
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
    fn ui_marked_text_empty_cancels_and_restores_original_text_and_selection() {
        // Start composition by replacing a selection, then cancel it by setting empty marked text.
        let mut ui = EditorUi::new("abcXYZdef", 80);
        ui.set_marked_text_with_selection("你", 1, 0, Some((3, 3)))
            .unwrap();
        assert_eq!(ui.text(), "abc你def");

        // Cancel: empty marked text should restore the original "XYZ" and selection.
        ui.set_marked_text_with_selection("", 0, 0, None).unwrap();
        assert_eq!(ui.text(), "abcXYZdef");
        assert_eq!(ui.primary_selection_offsets(), (3, 6));

        // Also cover the common case: composition started at a caret (no selection).
        let mut ui2 = EditorUi::new("abc", 80);
        ui2.execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 3 }))
            .unwrap();
        ui2.set_marked_text("你").unwrap();
        assert_eq!(ui2.text(), "abc你");
        ui2.set_marked_text("").unwrap();
        assert_eq!(ui2.text(), "abc");
        assert_eq!(ui2.primary_selection_offsets(), (3, 3));
    }

    #[test]
    fn ui_marked_text_honors_selection_and_applies_style_layer() {
        let mut ui = EditorUi::new("", 80);

        // Marked text = "你好", caret inside composition after the first char.
        ui.set_marked_text_with_selection("你好", 1, 0, None).unwrap();
        assert_eq!(ui.text(), "你好");

        // Cursor is at offset 1 => (line 0, column 1).
        assert_eq!(ui.cursor_state().position, Position::new(0, 1));

        let grid = ui.state.get_viewport_content_styled(0, 1);
        assert_eq!(grid.lines.len(), 1);
        assert_eq!(grid.lines[0].cells.len(), 2);
        assert!(grid.lines[0].cells[0]
            .styles
            .iter()
            .any(|&id| id == IME_MARKED_TEXT_STYLE_ID));
        assert!(grid.lines[0].cells[1]
            .styles
            .iter()
            .any(|&id| id == IME_MARKED_TEXT_STYLE_ID));

        // Committing clears the marked style layer.
        ui.commit_text("你好!").unwrap();
        let grid2 = ui.state.get_viewport_content_styled(0, 1);
        assert!(
            grid2.lines[0]
                .cells
                .iter()
                .all(|c| !c.styles.iter().any(|&id| id == IME_MARKED_TEXT_STYLE_ID)),
            "expected IME marked text style to be cleared after commit"
        );
    }

    #[test]
    fn ui_marked_text_replacement_range_overrides_current_selection() {
        // Replacement range should allow host IME to replace an arbitrary document slice
        // (e.g. when the input method decides to replace a previously inserted segment).
        let mut ui = EditorUi::new("abcXYZdef", 80);

        // Replace "XYZ" with IME marked text "你" (selection at end of marked text).
        ui.set_marked_text_with_selection("你", 1, 0, Some((3, 3)))
            .unwrap();
        assert_eq!(ui.text(), "abc你def");

        let marked = ui.marked_range().unwrap();
        assert_eq!(marked, (3, 1));

        // Commit should replace the marked range (not insert).
        ui.commit_text("你好").unwrap();
        assert_eq!(ui.text(), "abc你好def");
        assert!(ui.marked_range().is_none());
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
            styles: std::collections::BTreeMap::new(),
        });
        ui.set_viewport_px(80, 40, 1.0).unwrap();

        // Put caret after 'c' (x=3).
        ui.execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 3,
        }))
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

    #[test]
    fn ui_gutter_shifts_view_point_mapping() {
        let mut ui = EditorUi::new("abc\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 40,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(200, 40, 1.0).unwrap();
        ui.set_gutter_width_cells(2).unwrap(); // gutter = 20px

        let (x_px, y_px) = ui.char_offset_to_view_point_px(0).unwrap();
        assert_eq!((x_px, y_px), (20.0, 0.0));

        // Hit-testing inside gutter should clamp to column 0.
        assert_eq!(ui.view_point_to_char_offset(5.0, 10.0).unwrap(), 0);
    }

    #[test]
    fn ui_gutter_click_toggles_fold_state() {
        let text = "fn main() {\n  let x = 1;\n}\n";
        let mut ui = EditorUi::new(text, 80);
        ui.set_treesitter_rust_default().unwrap();
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 80,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(200, 80, 1.0).unwrap();
        ui.set_gutter_width_cells(2).unwrap();

        assert!(
            ui.state
                .get_folding_state()
                .regions
                .iter()
                .any(|r| r.start_line == 0 && !r.is_collapsed),
            "expected a fold region starting at line 0"
        );

        // Click in gutter at visual row 0.
        ui.mouse_down(5.0, 10.0).unwrap();
        assert!(
            ui.state
                .get_folding_state()
                .regions
                .iter()
                .any(|r| r.start_line == 0 && r.is_collapsed),
            "expected fold region to become collapsed after gutter click"
        );

        ui.mouse_down(5.0, 10.0).unwrap();
        assert!(
            ui.state
                .get_folding_state()
                .regions
                .iter()
                .any(|r| r.start_line == 0 && !r.is_collapsed),
            "expected fold region to expand after second gutter click"
        );
    }

    #[test]
    fn ui_nested_fold_unfold_sequence_keeps_inner_toggleable() {
        // Regression for: fold inner -> fold outer -> unfold outer -> inner must still unfold.
        let text = "fn main() {\n  if true {\n    if true {\n      println!(\"hi\");\n    }\n  }\n}\n";
        let mut ui = EditorUi::new(text, 80);
        ui.set_treesitter_rust_default().unwrap();
        ui.set_render_config(RenderConfig {
            width_px: 260,
            height_px: 200,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        ui.set_viewport_px(260, 200, 1.0).unwrap();
        ui.set_gutter_width_cells(2).unwrap();

        let regions = ui.state.get_folding_state().regions;
        assert!(regions.len() >= 2, "expected nested fold regions from Tree-sitter");

        // Pick an innermost region and its closest outer region.
        let inner = regions
            .iter()
            .filter(|r| r.end_line > r.start_line)
            .min_by_key(|r| r.end_line - r.start_line)
            .cloned()
            .expect("expected at least one fold region");
        let outer = regions
            .iter()
            .filter(|r| r.start_line < inner.start_line && r.end_line >= inner.end_line)
            .min_by_key(|r| r.end_line - r.start_line)
            .cloned()
            .expect("expected an outer region containing inner");

        let click_gutter_at_start_line = |ui: &mut EditorUi, start_line: usize| {
            let (row, _x_cells) = ui
                .state
                .logical_position_to_visual(start_line, 0)
                .expect("start line should be visible");
            let y = row as f32 * ui.render_config.line_height_px + ui.render_config.line_height_px * 0.5;
            ui.mouse_down(5.0, y).unwrap();
            ui.mouse_up();
        };

        // 1) Fold inner.
        click_gutter_at_start_line(&mut ui, inner.start_line);
        assert!(
            ui.state
                .get_folding_state()
                .regions
                .iter()
                .any(|r| r.start_line == inner.start_line && r.end_line == inner.end_line && r.is_collapsed),
            "expected inner region to be collapsed"
        );

        // 2) Fold outer.
        click_gutter_at_start_line(&mut ui, outer.start_line);
        assert!(
            ui.state
                .get_folding_state()
                .regions
                .iter()
                .any(|r| r.start_line == outer.start_line && r.end_line == outer.end_line && r.is_collapsed),
            "expected outer region to be collapsed"
        );

        // 3) Unfold outer.
        click_gutter_at_start_line(&mut ui, outer.start_line);
        assert!(
            ui.state
                .get_folding_state()
                .regions
                .iter()
                .any(|r| r.start_line == outer.start_line && r.end_line == outer.end_line && !r.is_collapsed),
            "expected outer region to be expanded"
        );

        // 4) Unfold inner (must still be toggleable).
        click_gutter_at_start_line(&mut ui, inner.start_line);
        assert!(
            ui.state
                .get_folding_state()
                .regions
                .iter()
                .any(|r| r.start_line == inner.start_line && r.end_line == inner.end_line && !r.is_collapsed),
            "expected inner region to be expanded after outer unfolded"
        );
    }

    #[test]
    fn ui_set_selections_offsets_and_insert_text_applies_to_all_carets() {
        let mut ui = EditorUi::new("abc\ndef\n", 80);

        // Two carets: start of line 0 (offset 0) and start of line 1 (offset 4).
        ui.set_selections_offsets(&[(0, 0), (4, 4)], 0).unwrap();
        let (ranges, primary) = ui.selections_offsets();
        assert_eq!(ranges, vec![(0, 0), (4, 4)]);
        assert_eq!(primary, 0);

        ui.insert_text("X").unwrap();
        assert_eq!(ui.text(), "Xabc\nXdef\n");
    }

    #[test]
    fn ui_rect_selection_replaces_each_line_range() {
        let mut ui = EditorUi::new("abc\ndef\nghi\n", 80);

        // Box select column 1..2 across lines 0..2.
        // anchor: line0 col1 => offset 1 ('b')
        // active:  line2 col2 => offset 10 ('i')
        ui.set_rect_selection_offsets(1, 10).unwrap();

        let (ranges, _primary) = ui.selections_offsets();
        assert_eq!(ranges.len(), 3);
        assert_eq!(ranges[0], (1, 2));
        assert_eq!(ranges[1], (5, 6));
        assert_eq!(ranges[2], (9, 10));

        ui.insert_text("X").unwrap();
        assert_eq!(ui.text(), "aXc\ndXf\ngXi\n");
    }

    #[test]
    fn ui_add_all_occurrences_selects_all_matches() {
        let mut ui = EditorUi::new("foo foo foo\n", 80);

        // Put caret at start.
        ui.execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 0 }))
            .unwrap();
        ui.select_word().unwrap();
        ui.add_all_occurrences(SearchOptions::default()).unwrap();

        let (ranges, _primary) = ui.selections_offsets();
        assert_eq!(ranges.len(), 3);

        ui.insert_text("X").unwrap();
        assert_eq!(ui.text(), "X X X\n");
    }

    #[test]
    fn ui_add_cursor_above_and_clear_secondary() {
        let mut ui = EditorUi::new("aa\naa\naa\n", 80);
        ui.execute(Command::Cursor(CursorCommand::MoveTo { line: 1, column: 1 }))
            .unwrap();

        ui.add_cursor_above().unwrap();
        let (ranges, _primary) = ui.selections_offsets();
        assert_eq!(ranges.len(), 2);

        ui.insert_text("X").unwrap();
        assert_eq!(ui.text(), "aXa\naXa\naa\n");

        ui.clear_secondary_selections().unwrap();
        let (ranges, _primary) = ui.selections_offsets();
        assert_eq!(ranges.len(), 1);
    }

    #[test]
    fn ui_move_and_modify_selection_extends_from_anchor() {
        let mut ui = EditorUi::new("abc\n", 80);
        ui.set_selections_offsets(&[(2, 2)], 0).unwrap(); // caret at offset 2

        ui.move_grapheme_left_and_modify_selection().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (1, 2));

        ui.move_grapheme_left_and_modify_selection().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (0, 2));

        ui.move_grapheme_right_and_modify_selection().unwrap();
        assert_eq!(ui.primary_selection_offsets(), (1, 2));
    }

    fn pixel(buf: &[u8], width_px: u32, x: u32, y: u32) -> [u8; 4] {
        let idx = ((y * width_px + x) * 4) as usize;
        [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
    }

    #[test]
    fn ui_sublime_highlight_and_folding_roundtrip() {
        let yaml = include_str!("../../editor-core-sublime/tests/fixtures/TOML.sublime-syntax");
        let text = r#"title = "TOML Example" # comment
numbers = [
  1,
  2,
  3,
]
multiline = """
hello
world
"""
"#;

        let mut ui = EditorUi::new(text, 80);
        ui.set_sublime_syntax_yaml(yaml).unwrap();

        let comment_style = ui
            .sublime_style_id_for_scope("comment.line.number-sign.toml")
            .unwrap();
        assert_eq!(
            ui.sublime_scope_for_style_id(comment_style),
            Some("comment.line.number-sign.toml")
        );

        let grid = ui.state.get_viewport_content_styled(0, 8);
        assert!(
            grid.lines
                .iter()
                .flat_map(|l| l.cells.iter())
                .any(|c| c.styles.contains(&comment_style)),
            "expected at least one comment-styled cell"
        );

        let regions = ui.state.get_folding_state().regions;
        assert!(
            regions.iter().any(|r| r.start_line == 1 && r.end_line == 5),
            "expected fold region for multi-line array (lines 1..=5)"
        );
        assert!(
            regions.iter().any(|r| r.start_line == 6 && r.end_line == 9),
            "expected fold region for multi-line basic string (lines 6..=9)"
        );
    }

    #[test]
    fn ui_sublime_refreshes_after_edit() {
        let yaml = include_str!("../../editor-core-sublime/tests/fixtures/TOML.sublime-syntax");
        let mut ui = EditorUi::new("title = 1\n", 80);
        ui.set_sublime_syntax_yaml(yaml).unwrap();

        // Insert a comment; `insert_text` should auto-refresh processors.
        ui.insert_text("# comment\n").unwrap();

        let comment_style = ui
            .sublime_style_id_for_scope("comment.line.number-sign.toml")
            .unwrap();
        let grid = ui.state.get_viewport_content_styled(0, 2);
        assert!(
            grid.lines
                .iter()
                .flat_map(|l| l.cells.iter())
                .any(|c| c.styles.contains(&comment_style)),
            "expected comment style after edit"
        );
    }

    #[test]
    fn ui_treesitter_highlight_and_folding_roundtrip() {
        let highlights = r#"
        (line_comment) @comment
        (string_literal) @string
        "#;
        let folds = r#"
        (function_item) @fold
        "#;

        let text = r#"// hi
fn main() {
  let s = "x";
}
"#;

        let mut ui = EditorUi::new(text, 80);
        ui.set_treesitter_rust_with_queries(highlights, Some(folds))
            .unwrap();

        let comment_style = ui.treesitter_style_id_for_capture("comment");
        let string_style = ui.treesitter_style_id_for_capture("string");
        assert_eq!(
            ui.treesitter_capture_for_style_id(comment_style),
            Some("comment")
        );
        assert_eq!(
            ui.treesitter_capture_for_style_id(string_style),
            Some("string")
        );

        let grid = ui.state.get_viewport_content_styled(0, 4);
        assert!(
            grid.lines
                .iter()
                .flat_map(|l| l.cells.iter())
                .any(|c| c.styles.contains(&comment_style)),
            "expected at least one comment-styled cell"
        );
        assert!(
            grid.lines
                .iter()
                .flat_map(|l| l.cells.iter())
                .any(|c| c.styles.contains(&string_style)),
            "expected at least one string-styled cell"
        );

        let regions = ui.state.get_folding_state().regions;
        assert!(
            regions.iter().any(|r| r.start_line == 1 && r.end_line == 3),
            "expected fold region for multi-line function"
        );
    }

    #[test]
    fn ui_treesitter_uses_incremental_updates_when_deltas_available() {
        let highlights = r#"(line_comment) @comment"#;
        let mut ui = EditorUi::new("// a\n", 80);
        ui.set_treesitter_rust_with_queries(highlights, None)
            .unwrap();
        assert_eq!(
            ui.treesitter.as_ref().unwrap().last_update_mode(),
            TreeSitterUpdateMode::Initial
        );

        ui.insert_text("// b\n").unwrap();
        assert_eq!(
            ui.treesitter.as_ref().unwrap().last_update_mode(),
            TreeSitterUpdateMode::Incremental
        );
    }

    #[test]
    fn ui_lsp_diagnostics_apply_style_layer() {
        // Use a space at the highlighted location so glyph rasterization does not affect the pixel sample.
        let mut ui = EditorUi::new("a c\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 200,
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
            styles: {
                let mut m = std::collections::BTreeMap::new();
                // LSP diagnostics style id encoding: 0x0400_0100 | severity
                m.insert(
                    0x0400_0100 | 1,
                    editor_core_render_skia::StyleColors::new(
                        None,
                        Some(editor_core_render_skia::Rgba8::new(1, 200, 2, 255)),
                    ),
                );
                m
            },
        });
        ui.set_viewport_px(200, 40, 1.0).unwrap();

        let params_json = r#"{
          "uri": "file:///test",
          "diagnostics": [
            {
              "range": {
                "start": { "line": 0, "character": 1 },
                "end": { "line": 0, "character": 2 }
              },
              "severity": 1,
              "message": "unit"
            }
          ],
          "version": 1
        }"#;
        ui.lsp_apply_publish_diagnostics_json(params_json).unwrap();

        let rgba = ui.render_rgba_visible().unwrap();
        // Highlighted cell at col=1 => x in [10..20]
        assert_eq!(pixel(&rgba, 200, 15, 10), [1, 200, 2, 255]);
    }

    #[test]
    fn ui_lsp_semantic_tokens_apply_style_layer() {
        // Use a space at the highlighted location so glyph rasterization does not affect the pixel sample.
        let mut ui = EditorUi::new("a c\n", 80);
        ui.set_render_config(RenderConfig {
            width_px: 200,
            height_px: 40,
            cell_width_px: 10.0,
            line_height_px: 20.0,
            padding_x_px: 0.0,
            padding_y_px: 0.0,
            ..RenderConfig::default()
        });
        let style_id = (7u32 << 16) | 0u32;
        ui.set_theme(RenderTheme {
            background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
            foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
            selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
            caret: editor_core_render_skia::Rgba8::new(0, 0, 200, 255),
            styles: {
                let mut m = std::collections::BTreeMap::new();
                m.insert(
                    style_id,
                    editor_core_render_skia::StyleColors::new(
                        None,
                        Some(editor_core_render_skia::Rgba8::new(1, 200, 2, 255)),
                    ),
                );
                m
            },
        });
        ui.set_viewport_px(200, 40, 1.0).unwrap();

        // Highlight the 'b' as a semantic token:
        // (deltaLine=0, deltaStart=1, length=1, tokenType=7, tokenModifiers=0)
        ui.lsp_apply_semantic_tokens(&[0, 1, 1, 7, 0]).unwrap();

        let rgba = ui.render_rgba_visible().unwrap();
        assert_eq!(pixel(&rgba, 200, 15, 10), [1, 200, 2, 255]);
    }
}
