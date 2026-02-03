//! Phase 3: Layout and Soft Wrapping (Headless Layout Engine)
//!
//! Calculates the visual representation of text given a container width.
//! Computes character widths based on UAX #11 and implements headless reflow algorithm.

use unicode_width::UnicodeWidthChar;

/// Wrap point
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct WrapPoint {
    /// Character index where wrapping occurs (within the logical line)
    pub char_index: usize,
    /// Byte offset where wrapping occurs (within the logical line)
    pub byte_offset: usize,
}

/// Visual line information
#[derive(Debug, Clone)]
pub struct VisualLineInfo {
    /// Number of visual lines corresponding to this logical line
    pub visual_line_count: usize,
    /// List of wrap points
    pub wrap_points: Vec<WrapPoint>,
}

impl VisualLineInfo {
    /// Create an empty layout (a single visual line, no wrap points).
    pub fn new() -> Self {
        Self {
            visual_line_count: 1,
            wrap_points: Vec::new(),
        }
    }

    /// Calculate visual line information from text and width constraint
    pub fn from_text(text: &str, viewport_width: usize) -> Self {
        let wrap_points = calculate_wrap_points(text, viewport_width);
        let visual_line_count = wrap_points.len() + 1;

        Self {
            visual_line_count,
            wrap_points,
        }
    }
}

impl Default for VisualLineInfo {
    fn default() -> Self {
        Self::new()
    }
}

/// Calculate visual width of a character (based on UAX #11)
///
/// Return value:
/// - 1: Narrow character (ASCII, etc.)
/// - 2: Wide character (CJK, fullwidth, etc.)
/// - 0: Zero-width character (combining characters, etc.)
pub fn char_width(ch: char) -> usize {
    // Use unicode-width crate to implement UAX #11
    UnicodeWidthChar::width(ch).unwrap_or(1)
}

/// Calculate total visual width of a string
pub fn str_width(s: &str) -> usize {
    s.chars().map(char_width).sum()
}

/// Calculate wrap points for text
///
/// Given a width constraint, calculates where the text needs to wrap
pub fn calculate_wrap_points(text: &str, viewport_width: usize) -> Vec<WrapPoint> {
    if viewport_width == 0 {
        return Vec::new();
    }

    let mut wrap_points = Vec::new();
    let mut current_width = 0;

    for (char_index, (byte_offset, ch)) in text.char_indices().enumerate() {
        let ch_width = char_width(ch);

        // If adding this character would exceed the width limit
        if current_width + ch_width > viewport_width {
            // Double-width characters cannot be split
            // If remaining width cannot accommodate the double-width character, it should wrap intact to the next line
            wrap_points.push(WrapPoint {
                char_index,
                byte_offset,
            });
            current_width = ch_width;
        } else {
            current_width += ch_width;
        }

        // If current width equals viewport width exactly, the next character should wrap
        if current_width == viewport_width {
            // Check if there are more characters
            if byte_offset + ch.len_utf8() < text.len() {
                wrap_points.push(WrapPoint {
                    char_index: char_index + 1,
                    byte_offset: byte_offset + ch.len_utf8(),
                });
                current_width = 0;
            }
        }
    }

    wrap_points
}

/// Layout engine - manages visual representation of all lines
pub struct LayoutEngine {
    /// Viewport width (in character cells)
    viewport_width: usize,
    /// Visual information for each logical line
    line_layouts: Vec<VisualLineInfo>,
    /// Raw text for each logical line (excluding newline characters)
    line_texts: Vec<String>,
}

impl LayoutEngine {
    /// Create a new layout engine
    pub fn new(viewport_width: usize) -> Self {
        Self {
            viewport_width,
            line_layouts: Vec::new(),
            line_texts: Vec::new(),
        }
    }

    /// Set viewport width
    pub fn set_viewport_width(&mut self, width: usize) {
        if self.viewport_width != width {
            self.viewport_width = width;
            self.recalculate_all();
        }
    }

    /// Get viewport width
    pub fn viewport_width(&self) -> usize {
        self.viewport_width
    }

    /// Build layout from list of text lines
    pub fn from_lines(&mut self, lines: &[&str]) {
        self.line_layouts.clear();
        self.line_texts.clear();
        for line in lines {
            self.line_texts.push((*line).to_string());
            self.line_layouts
                .push(VisualLineInfo::from_text(line, self.viewport_width));
        }
    }

    /// Add a line
    pub fn add_line(&mut self, text: &str) {
        self.line_texts.push(text.to_string());
        self.line_layouts
            .push(VisualLineInfo::from_text(text, self.viewport_width));
    }

    /// Update a specific line
    pub fn update_line(&mut self, line_index: usize, text: &str) {
        if line_index < self.line_layouts.len() {
            self.line_texts[line_index] = text.to_string();
            self.line_layouts[line_index] = VisualLineInfo::from_text(text, self.viewport_width);
        }
    }

    /// Insert a line
    pub fn insert_line(&mut self, line_index: usize, text: &str) {
        let pos = line_index.min(self.line_layouts.len());
        self.line_texts.insert(pos, text.to_string());
        self.line_layouts
            .insert(pos, VisualLineInfo::from_text(text, self.viewport_width));
    }

    /// Delete a line
    pub fn delete_line(&mut self, line_index: usize) {
        if line_index < self.line_layouts.len() {
            self.line_texts.remove(line_index);
            self.line_layouts.remove(line_index);
        }
    }

    /// Get visual information for a specific logical line
    pub fn get_line_layout(&self, line_index: usize) -> Option<&VisualLineInfo> {
        self.line_layouts.get(line_index)
    }

    /// Get total number of logical lines
    pub fn logical_line_count(&self) -> usize {
        self.line_layouts.len()
    }

    /// Get total number of visual lines
    pub fn visual_line_count(&self) -> usize {
        self.line_layouts.iter().map(|l| l.visual_line_count).sum()
    }

    /// Convert logical line number to visual line number
    ///
    /// Returns the line number of the first visual line of this logical line
    pub fn logical_to_visual_line(&self, logical_line: usize) -> usize {
        self.line_layouts
            .iter()
            .take(logical_line)
            .map(|l| l.visual_line_count)
            .sum()
    }

    /// Convert visual line number to logical line number and offset within line
    ///
    /// Returns (logical_line, visual_line_in_logical)
    pub fn visual_to_logical_line(&self, visual_line: usize) -> (usize, usize) {
        let mut cumulative_visual = 0;

        for (logical_idx, layout) in self.line_layouts.iter().enumerate() {
            if cumulative_visual + layout.visual_line_count > visual_line {
                let visual_offset = visual_line - cumulative_visual;
                return (logical_idx, visual_offset);
            }
            cumulative_visual += layout.visual_line_count;
        }

        // If out of range, return the last line
        let last_line = self.line_layouts.len().saturating_sub(1);
        let last_visual_offset = self
            .line_layouts
            .last()
            .map(|l| l.visual_line_count.saturating_sub(1))
            .unwrap_or(0);
        (last_line, last_visual_offset)
    }

    /// Recalculate layout for all lines
    fn recalculate_all(&mut self) {
        if self.line_texts.len() != self.line_layouts.len() {
            // Conservative handling: avoid out-of-bounds access. Normally these two should always be consistent.
            self.line_layouts.clear();
            for line in &self.line_texts {
                self.line_layouts
                    .push(VisualLineInfo::from_text(line, self.viewport_width));
            }
            return;
        }

        for (layout, line_text) in self.line_layouts.iter_mut().zip(self.line_texts.iter()) {
            *layout = VisualLineInfo::from_text(line_text, self.viewport_width);
        }
    }

    /// Clear all lines
    pub fn clear(&mut self) {
        self.line_layouts.clear();
        self.line_texts.clear();
    }

    /// Convert logical coordinates (line, column) to visual coordinates (visual row number, x cell offset within row).
    ///
    /// - `logical_line`: Logical line number (0-based)
    /// - `column`: Character column within the logical line (0-based, counted by `char`)
    ///
    /// Return value:
    /// - `Some((visual_row, x))`: `visual_row` is the global visual row number, `x` is the cell offset within that visual row
    /// - `None`: Line number out of range
    pub fn logical_position_to_visual(
        &self,
        logical_line: usize,
        column: usize,
    ) -> Option<(usize, usize)> {
        let layout = self.get_line_layout(logical_line)?;
        let line_text = self.line_texts.get(logical_line)?;

        let line_char_len = line_text.chars().count();
        let column = column.min(line_char_len);

        // Calculate which visual line the cursor belongs to (within this logical line) and the starting character index of that visual line.
        let mut wrapped_offset = 0usize;
        let mut segment_start_col = 0usize;

        // The char_index in wrap_points indicates "where the next segment starts".
        for wrap_point in &layout.wrap_points {
            if column >= wrap_point.char_index {
                wrapped_offset += 1;
                segment_start_col = wrap_point.char_index;
            } else {
                break;
            }
        }

        // Calculate visual width from segment start to column.
        let x_in_segment: usize = line_text
            .chars()
            .skip(segment_start_col)
            .take(column.saturating_sub(segment_start_col))
            .map(char_width)
            .sum();

        let visual_row = self.logical_to_visual_line(logical_line) + wrapped_offset;
        Some((visual_row, x_in_segment))
    }

    /// Convert logical coordinates (line, column) to visual coordinates, allowing column to exceed line end (virtual spaces).
    ///
    /// Difference from [`logical_position_to_visual`](Self::logical_position_to_visual):
    /// - `column` is not clamped to `line_char_len`
    /// - Excess portion is treated as virtual spaces of `' '` (width=1)
    pub fn logical_position_to_visual_allow_virtual(
        &self,
        logical_line: usize,
        column: usize,
    ) -> Option<(usize, usize)> {
        let layout = self.get_line_layout(logical_line)?;
        let line_text = self.line_texts.get(logical_line)?;

        let line_char_len = line_text.chars().count();
        let clamped_column = column.min(line_char_len);

        let mut wrapped_offset = 0usize;
        let mut segment_start_col = 0usize;
        for wrap_point in &layout.wrap_points {
            if clamped_column >= wrap_point.char_index {
                wrapped_offset += 1;
                segment_start_col = wrap_point.char_index;
            } else {
                break;
            }
        }

        let x_in_segment: usize = line_text
            .chars()
            .skip(segment_start_col)
            .take(clamped_column.saturating_sub(segment_start_col))
            .map(char_width)
            .sum();

        let x_in_segment = x_in_segment + column.saturating_sub(line_char_len);
        let visual_row = self.logical_to_visual_line(logical_line) + wrapped_offset;
        Some((visual_row, x_in_segment))
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_char_width() {
        // ASCII characters should have width 1
        assert_eq!(char_width('a'), 1);
        assert_eq!(char_width('A'), 1);
        assert_eq!(char_width(' '), 1);

        // CJK characters should have width 2
        assert_eq!(char_width('你'), 2);
        assert_eq!(char_width('好'), 2);
        assert_eq!(char_width('世'), 2);
        assert_eq!(char_width('界'), 2);

        // Most emojis have width 2
        assert_eq!(char_width('👋'), 2);
        assert_eq!(char_width('🌍'), 2);
        assert_eq!(char_width('🦀'), 2);
    }

    #[test]
    fn test_str_width() {
        assert_eq!(str_width("hello"), 5);
        assert_eq!(str_width("你好"), 4); // 2 CJK characters = 4 cells
        assert_eq!(str_width("hello你好"), 9); // 5 + 4
        assert_eq!(str_width("👋🌍"), 4); // 2 emojis = 4 cells
    }

    #[test]
    fn test_calculate_wrap_points_simple() {
        // Viewport width of 10
        let text = "hello world";
        let wraps = calculate_wrap_points(text, 10);

        // "hello world" = 11 characters, should wrap between "hello" and "world"
        // But actually wraps after the 10th character
        assert!(!wraps.is_empty());
    }

    #[test]
    fn test_calculate_wrap_points_exact_fit() {
        // Exactly 10 characters wide
        let text = "1234567890";
        let wraps = calculate_wrap_points(text, 10);

        // Exactly fills, no wrapping needed
        assert_eq!(wraps.len(), 0);
    }

    #[test]
    fn test_calculate_wrap_points_one_over() {
        // 11 characters, width of 10
        let text = "12345678901";
        let wraps = calculate_wrap_points(text, 10);

        // Should wrap after the 10th character
        assert_eq!(wraps.len(), 1);
        assert_eq!(wraps[0].char_index, 10);
    }

    #[test]
    fn test_calculate_wrap_points_cjk() {
        // 5 CJK characters = 10 cells wide
        let text = "你好世界测";
        let wraps = calculate_wrap_points(text, 10);

        // Exactly fills, no wrapping needed
        assert_eq!(wraps.len(), 0);
    }

    #[test]
    fn test_calculate_wrap_points_cjk_overflow() {
        // 6 CJK characters = 12 cells, viewport width of 10
        let text = "你好世界测试";
        let wraps = calculate_wrap_points(text, 10);

        // Should wrap after the 5th character (first 5 characters = 10 cells)
        assert_eq!(wraps.len(), 1);
        assert_eq!(wraps[0].char_index, 5);
    }

    #[test]
    fn test_wrap_double_width_char() {
        // Viewport has 1 cell remaining, next is a double-width character
        // "Hello" = 5 cells, "你" = 2 cells, viewport width = 6
        let text = "Hello你";
        let wraps = calculate_wrap_points(text, 6);

        // "Hello" takes 5 cells, "你" needs 2 cells but only 1 remains
        // So "你" should wrap intact to the next line
        assert_eq!(wraps.len(), 1);
        assert_eq!(wraps[0].char_index, 5); // Wrap before "你"
    }

    #[test]
    fn test_visual_line_info() {
        let info = VisualLineInfo::from_text("1234567890abc", 10);
        assert_eq!(info.visual_line_count, 2); // Needs 2 visual lines
        assert_eq!(info.wrap_points.len(), 1);
    }

    #[test]
    fn test_layout_engine_basic() {
        let mut engine = LayoutEngine::new(10);
        engine.add_line("hello");
        engine.add_line("1234567890abc");

        assert_eq!(engine.logical_line_count(), 2);
        assert_eq!(engine.visual_line_count(), 3); // 1 + 2
    }

    #[test]
    fn test_layout_engine_viewport_change() {
        let mut engine = LayoutEngine::new(20);
        engine.from_lines(&["hello world", "rust programming"]);

        let initial_visual = engine.visual_line_count();
        assert_eq!(initial_visual, 2); // Both lines don't need wrapping

        // Reduce viewport width
        engine.set_viewport_width(5);
        // Note: Due to our implementation, need to reset lines
        engine.from_lines(&["hello world", "rust programming"]);

        let new_visual = engine.visual_line_count();
        assert!(new_visual > initial_visual); // Should have more visual lines
    }

    #[test]
    fn test_logical_to_visual() {
        let mut engine = LayoutEngine::new(10);
        engine.from_lines(&["12345", "1234567890abc", "hello"]);

        // Line 0 ("12345") doesn't wrap, starts at visual line 0
        assert_eq!(engine.logical_to_visual_line(0), 0);

        // Line 1 ("1234567890abc") needs wrapping, starts at visual line 1
        assert_eq!(engine.logical_to_visual_line(1), 1);

        // Line 2 ("hello") starts at visual line 3 (0 + 1 + 2)
        assert_eq!(engine.logical_to_visual_line(2), 3);
    }

    #[test]
    fn test_visual_to_logical() {
        let mut engine = LayoutEngine::new(10);
        engine.from_lines(&["12345", "1234567890abc", "hello"]);

        // Visual line 0 -> logical line 0
        assert_eq!(engine.visual_to_logical_line(0), (0, 0));

        // Visual line 1 -> logical line 1's 0th visual line
        assert_eq!(engine.visual_to_logical_line(1), (1, 0));

        // Visual line 2 -> logical line 1's 1st visual line
        assert_eq!(engine.visual_to_logical_line(2), (1, 1));

        // Visual line 3 -> logical line 2
        assert_eq!(engine.visual_to_logical_line(3), (2, 0));
    }
}
