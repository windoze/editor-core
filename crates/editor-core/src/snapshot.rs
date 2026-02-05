//! Phase 6: Headless Output Snapshot (Headless Snapshot API)
//!
//! Provides data structures needed by UI renderers, simulating "text grid" output.

use crate::intervals::StyleId;
use crate::layout::{DEFAULT_TAB_WIDTH, LayoutEngine, cell_width_at, visual_x_for_column};

/// Cell (character) information
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Cell {
    /// Character content
    pub ch: char,
    /// Visual width (1 or 2 cells)
    pub width: usize,
    /// List of applied style IDs
    pub styles: Vec<StyleId>,
}

impl Cell {
    /// Create a cell without any styles applied.
    pub fn new(ch: char, width: usize) -> Self {
        Self {
            ch,
            width,
            styles: Vec::new(),
        }
    }

    /// Create a cell with an explicit style list.
    pub fn with_styles(ch: char, width: usize, styles: Vec<StyleId>) -> Self {
        Self { ch, width, styles }
    }
}

/// Headless line information
#[derive(Debug, Clone)]
pub struct HeadlessLine {
    /// Corresponding logical line index
    pub logical_line_index: usize,
    /// Whether this is a part created by wrapping (soft wrap)
    pub is_wrapped_part: bool,
    /// List of cells
    pub cells: Vec<Cell>,
}

impl HeadlessLine {
    /// Create an empty headless line.
    pub fn new(logical_line_index: usize, is_wrapped_part: bool) -> Self {
        Self {
            logical_line_index,
            is_wrapped_part,
            cells: Vec::new(),
        }
    }

    /// Append a cell to the line.
    pub fn add_cell(&mut self, cell: Cell) {
        self.cells.push(cell);
    }

    /// Get total visual width of this line
    pub fn visual_width(&self) -> usize {
        self.cells.iter().map(|c| c.width).sum()
    }
}

/// Headless grid snapshot
#[derive(Debug, Clone)]
pub struct HeadlessGrid {
    /// List of visual lines
    pub lines: Vec<HeadlessLine>,
    /// Starting visual row number
    pub start_visual_row: usize,
    /// Number of lines requested
    pub count: usize,
}

impl HeadlessGrid {
    /// Create an empty grid snapshot for a requested visual range.
    pub fn new(start_visual_row: usize, count: usize) -> Self {
        Self {
            lines: Vec::new(),
            start_visual_row,
            count,
        }
    }

    /// Append a visual line to the grid.
    pub fn add_line(&mut self, line: HeadlessLine) {
        self.lines.push(line);
    }

    /// Get actual number of lines returned
    pub fn actual_line_count(&self) -> usize {
        self.lines.len()
    }
}

/// Headless snapshot generator
///
/// Integrates all components to generate snapshots needed for UI rendering
pub struct SnapshotGenerator {
    /// Document content (stored by lines)
    lines: Vec<String>,
    /// Viewport width
    viewport_width: usize,
    /// Tab width (in cells) used to expand `'\t'` during layout/measurement.
    tab_width: usize,
    /// Soft wrap layout engine (for logical line <-> visual line conversion)
    layout_engine: LayoutEngine,
}

impl SnapshotGenerator {
    /// Create a new generator for an empty document.
    pub fn new(viewport_width: usize) -> Self {
        let lines = vec![String::new()];
        let mut layout_engine = LayoutEngine::new(viewport_width);
        let line_refs: Vec<&str> = lines.iter().map(|s| s.as_str()).collect();
        layout_engine.from_lines(&line_refs);

        Self {
            // Maintain consistency with common editor semantics: an empty document also has 1 empty line.
            lines,
            viewport_width,
            tab_width: layout_engine.tab_width(),
            layout_engine,
        }
    }

    /// Initialize from text
    pub fn from_text(text: &str, viewport_width: usize) -> Self {
        Self::from_text_with_tab_width(text, viewport_width, DEFAULT_TAB_WIDTH)
    }

    /// Initialize from text, with explicit `tab_width` (in cells) for expanding `'\t'`.
    pub fn from_text_with_tab_width(text: &str, viewport_width: usize, tab_width: usize) -> Self {
        let lines = crate::text::split_lines_preserve_trailing(text);
        let mut layout_engine = LayoutEngine::new(viewport_width);
        layout_engine.set_tab_width(tab_width);
        let line_refs: Vec<&str> = lines.iter().map(|s| s.as_str()).collect();
        layout_engine.from_lines(&line_refs);
        Self {
            lines,
            viewport_width,
            tab_width: layout_engine.tab_width(),
            layout_engine,
        }
    }

    /// Update document content
    pub fn set_lines(&mut self, lines: Vec<String>) {
        self.lines = if lines.is_empty() {
            vec![String::new()]
        } else {
            lines
        };

        let line_refs: Vec<&str> = self.lines.iter().map(|s| s.as_str()).collect();
        self.layout_engine.from_lines(&line_refs);
    }

    /// Set viewport width
    pub fn set_viewport_width(&mut self, width: usize) {
        self.viewport_width = width;
        self.layout_engine.set_viewport_width(width);
    }

    /// Set tab width (in cells) used for expanding `'\t'`.
    pub fn set_tab_width(&mut self, tab_width: usize) {
        self.tab_width = tab_width.max(1);
        self.layout_engine.set_tab_width(self.tab_width);
    }

    /// Get tab width (in cells).
    pub fn tab_width(&self) -> usize {
        self.tab_width
    }

    /// Get headless grid snapshot
    ///
    /// This is the core API, returning visual line data for the specified range
    pub fn get_headless_grid(&self, start_visual_row: usize, count: usize) -> HeadlessGrid {
        let mut grid = HeadlessGrid::new(start_visual_row, count);

        if count == 0 {
            return grid;
        }

        let total_visual = self.layout_engine.visual_line_count();
        if start_visual_row >= total_visual {
            return grid;
        }

        let end_visual = start_visual_row.saturating_add(count).min(total_visual);
        let mut current_visual = 0usize;

        for logical_line in 0..self.layout_engine.logical_line_count() {
            let Some(layout) = self.layout_engine.get_line_layout(logical_line) else {
                continue;
            };

            let line_text = self
                .lines
                .get(logical_line)
                .map(|s| s.as_str())
                .unwrap_or("");
            let line_char_len = line_text.chars().count();

            for visual_in_line in 0..layout.visual_line_count {
                if current_visual >= end_visual {
                    return grid;
                }

                if current_visual >= start_visual_row {
                    let segment_start_col = if visual_in_line == 0 {
                        0
                    } else {
                        layout
                            .wrap_points
                            .get(visual_in_line - 1)
                            .map(|wp| wp.char_index)
                            .unwrap_or(0)
                            .min(line_char_len)
                    };

                    let segment_end_col = if visual_in_line < layout.wrap_points.len() {
                        layout.wrap_points[visual_in_line]
                            .char_index
                            .min(line_char_len)
                    } else {
                        line_char_len
                    };

                    let mut headless_line = HeadlessLine::new(logical_line, visual_in_line > 0);
                    let seg_start_x_in_line =
                        visual_x_for_column(line_text, segment_start_col, self.tab_width);
                    let mut x_in_line = seg_start_x_in_line;
                    for ch in line_text
                        .chars()
                        .skip(segment_start_col)
                        .take(segment_end_col.saturating_sub(segment_start_col))
                    {
                        let w = cell_width_at(ch, x_in_line, self.tab_width);
                        x_in_line = x_in_line.saturating_add(w);
                        headless_line.add_cell(Cell::new(ch, w));
                    }

                    grid.add_line(headless_line);
                }

                current_visual = current_visual.saturating_add(1);
            }
        }

        grid
    }

    /// Get content of a specific logical line
    pub fn get_line(&self, line_index: usize) -> Option<&str> {
        self.lines.get(line_index).map(|s| s.as_str())
    }

    /// Get total number of logical lines
    pub fn line_count(&self) -> usize {
        self.lines.len()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_cell_creation() {
        let cell = Cell::new('a', 1);
        assert_eq!(cell.ch, 'a');
        assert_eq!(cell.width, 1);
        assert!(cell.styles.is_empty());
    }

    #[test]
    fn test_cell_with_styles() {
        let cell = Cell::with_styles('你', 2, vec![1, 2, 3]);
        assert_eq!(cell.ch, '你');
        assert_eq!(cell.width, 2);
        assert_eq!(cell.styles, vec![1, 2, 3]);
    }

    #[test]
    fn test_headless_line() {
        let mut line = HeadlessLine::new(0, false);
        line.add_cell(Cell::new('H', 1));
        line.add_cell(Cell::new('e', 1));
        line.add_cell(Cell::new('你', 2));

        assert_eq!(line.logical_line_index, 0);
        assert!(!line.is_wrapped_part);
        assert_eq!(line.cells.len(), 3);
        assert_eq!(line.visual_width(), 4); // 1 + 1 + 2
    }

    #[test]
    fn test_snapshot_generator_basic() {
        let text = "Hello\nWorld\nRust";
        let generator = SnapshotGenerator::from_text(text, 80);

        assert_eq!(generator.line_count(), 3);
        assert_eq!(generator.get_line(0), Some("Hello"));
        assert_eq!(generator.get_line(1), Some("World"));
        assert_eq!(generator.get_line(2), Some("Rust"));
    }

    #[test]
    fn test_get_headless_grid() {
        let text = "Line 1\nLine 2\nLine 3\nLine 4";
        let generator = SnapshotGenerator::from_text(text, 80);

        // Get first 2 lines
        let grid = generator.get_headless_grid(0, 2);
        assert_eq!(grid.start_visual_row, 0);
        assert_eq!(grid.count, 2);
        assert_eq!(grid.actual_line_count(), 2);

        // Verify first line
        let line0 = &grid.lines[0];
        assert_eq!(line0.logical_line_index, 0);
        assert!(!line0.is_wrapped_part);
        assert_eq!(line0.cells.len(), 6); // "Line 1"

        // Get middle lines
        let grid2 = generator.get_headless_grid(1, 2);
        assert_eq!(grid2.actual_line_count(), 2);
        assert_eq!(grid2.lines[0].logical_line_index, 1);
        assert_eq!(grid2.lines[1].logical_line_index, 2);
    }

    #[test]
    fn test_get_headless_grid_soft_wrap_single_line() {
        let generator = SnapshotGenerator::from_text("abcd", 2);

        let grid = generator.get_headless_grid(0, 10);
        assert_eq!(grid.actual_line_count(), 2);

        let line0_text: String = grid.lines[0].cells.iter().map(|c| c.ch).collect();
        let line1_text: String = grid.lines[1].cells.iter().map(|c| c.ch).collect();

        assert_eq!(grid.lines[0].logical_line_index, 0);
        assert!(!grid.lines[0].is_wrapped_part);
        assert_eq!(line0_text, "ab");

        assert_eq!(grid.lines[1].logical_line_index, 0);
        assert!(grid.lines[1].is_wrapped_part);
        assert_eq!(line1_text, "cd");

        // Starting from the 2nd visual line, get 1 line, should only return the wrapped part.
        let grid2 = generator.get_headless_grid(1, 1);
        assert_eq!(grid2.actual_line_count(), 1);
        assert_eq!(grid2.lines[0].logical_line_index, 0);
        assert!(grid2.lines[0].is_wrapped_part);
        let text2: String = grid2.lines[0].cells.iter().map(|c| c.ch).collect();
        assert_eq!(text2, "cd");
    }

    #[test]
    fn test_grid_with_cjk() {
        let text = "Hello\n你好世界\nRust";
        let generator = SnapshotGenerator::from_text(text, 80);

        let grid = generator.get_headless_grid(1, 1);
        let line = &grid.lines[0];

        assert_eq!(line.cells.len(), 4); // 4 CJK characters
        assert_eq!(line.visual_width(), 8); // Each CJK character 2 cells

        // Verify width of each character
        assert_eq!(line.cells[0].ch, '你');
        assert_eq!(line.cells[0].width, 2);
        assert_eq!(line.cells[1].ch, '好');
        assert_eq!(line.cells[1].width, 2);
    }

    #[test]
    fn test_grid_with_emoji() {
        let text = "Hello 👋\nWorld 🌍";
        let generator = SnapshotGenerator::from_text(text, 80);

        let grid = generator.get_headless_grid(0, 2);
        assert_eq!(grid.actual_line_count(), 2);

        // First line: "Hello 👋"
        let line0 = &grid.lines[0];
        assert_eq!(line0.cells.len(), 7); // H,e,l,l,o,space,👋
        // "Hello " = 6, "👋" = 2
        assert_eq!(line0.visual_width(), 8);
    }

    #[test]
    fn test_grid_bounds() {
        let text = "Line 1\nLine 2\nLine 3";
        let generator = SnapshotGenerator::from_text(text, 80);

        // Request lines beyond range
        let grid = generator.get_headless_grid(1, 10);
        // Should only return lines that actually exist
        assert_eq!(grid.actual_line_count(), 2); // Only Line 2 and Line 3

        // Completely out of range
        let grid2 = generator.get_headless_grid(10, 5);
        assert_eq!(grid2.actual_line_count(), 0);
    }

    #[test]
    fn test_empty_document() {
        let generator = SnapshotGenerator::new(80);
        let grid = generator.get_headless_grid(0, 10);
        assert_eq!(grid.actual_line_count(), 1);
    }

    #[test]
    fn test_viewport_width_change() {
        let text = "Hello World";
        let mut generator = SnapshotGenerator::from_text(text, 40);

        assert_eq!(generator.viewport_width, 40);

        generator.set_viewport_width(20);
        assert_eq!(generator.viewport_width, 20);
        // Changing width should trigger soft wrap reflow (using a shorter width here to verify wrapping).
        generator.set_viewport_width(5);
        let grid = generator.get_headless_grid(0, 10);
        assert!(grid.actual_line_count() > 1);
    }
}
