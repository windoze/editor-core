//! Stage 2: Logical Line Index
//!
//! Provides efficient line indexing using Rope data structure, supporting O(log N) access and editing.

use crate::storage::Piece;
use ropey::Rope;

/// Metadata for a logical line
#[derive(Debug, Clone)]
pub struct LineMetadata {
    /// List of Pieces referenced by this line (fragments may span multiple pieces)
    pub pieces: Vec<Piece>,
    /// Fast path flag: whether this is pure ASCII
    pub is_pure_ascii: bool,
    /// Byte length of this line
    pub byte_length: usize,
    /// Character count of this line
    pub char_count: usize,
}

impl LineMetadata {
    /// Create an empty line metadata record.
    pub fn new() -> Self {
        Self {
            pieces: Vec::new(),
            is_pure_ascii: true,
            byte_length: 0,
            char_count: 0,
        }
    }

    /// Build line metadata for a single logical line (no trailing `\n`).
    pub fn from_text(text: &str) -> Self {
        let is_pure_ascii = text.is_ascii();
        Self {
            pieces: Vec::new(),
            is_pure_ascii,
            byte_length: text.len(),
            char_count: text.chars().count(),
        }
    }
}

impl Default for LineMetadata {
    fn default() -> Self {
        Self::new()
    }
}

/// Logical line index - implemented using Rope data structure
///
/// Rope provides O(log N) line access, insertion, and deletion performance, suitable for large file editing
pub struct LineIndex {
    /// Rope data structure that automatically manages line indexing
    rope: Rope,
}

impl LineIndex {
    /// Create a new line index
    pub fn new() -> Self {
        Self { rope: Rope::new() }
    }

    /// Build line index from text
    pub fn from_text(text: &str) -> Self {
        Self {
            rope: Rope::from_str(text),
        }
    }

    /// Append a new line
    pub fn append_line(&mut self, line: LineMetadata) {
        // Reconstruct text from LineMetadata and append
        let current_len = self.rope.len_chars();

        // If not the first line, add a newline first
        if current_len > 0 {
            self.rope.insert(current_len, "\n");
        }

        // Add line content (LineMetadata doesn't store actual text, using placeholder here)
        // Note: This is for backward compatibility, in actual use should call insert() directly
        let placeholder = "x".repeat(line.char_count);
        self.rope.insert(self.rope.len_chars(), &placeholder);
    }

    /// Insert a line at the specified position
    pub fn insert_line(&mut self, line_number: usize, line: LineMetadata) {
        if line_number >= self.rope.len_lines() {
            self.append_line(line);
            return;
        }

        // Get character offset at insertion position
        let insert_pos = self.rope.line_to_char(line_number);

        // Insert new line content
        let placeholder = "x".repeat(line.char_count);
        self.rope.insert(insert_pos, &placeholder);
        self.rope.insert(insert_pos + line.char_count, "\n");
    }

    /// Delete the specified line
    pub fn delete_line(&mut self, line_number: usize) {
        if line_number >= self.rope.len_lines() {
            return;
        }

        let start_char = self.rope.line_to_char(line_number);
        let end_char = if line_number + 1 < self.rope.len_lines() {
            self.rope.line_to_char(line_number + 1)
        } else {
            self.rope.len_chars()
        };

        self.rope.remove(start_char..end_char);
    }

    /// Get metadata for the specified line number (simulated)
    pub fn get_line(&self, line_number: usize) -> Option<LineMetadata> {
        if line_number >= self.rope.len_lines() {
            return None;
        }

        let line = self.rope.line(line_number);
        let mut text = line.to_string();

        // Remove trailing newline (Rope's line() includes newline)
        if text.ends_with('\n') {
            text.pop();
        }
        if text.ends_with('\r') {
            text.pop();
        }

        Some(LineMetadata::from_text(&text))
    }

    /// Get mutable reference (Rope doesn't need this method, kept for compatibility)
    pub fn get_line_mut(&mut self, line_number: usize) -> Option<&mut LineMetadata> {
        // Rope doesn't support getting mutable references directly, return None
        let _line_num = line_number;
        None
    }

    /// Get byte offset for line number (excluding newlines of previous lines)
    pub fn line_to_offset(&self, line_number: usize) -> usize {
        if line_number == 0 {
            return 0;
        }

        if line_number >= self.rope.len_lines() {
            // Return total bytes minus newline count
            let newline_count = self.rope.len_lines().saturating_sub(1);
            return self.rope.len_bytes().saturating_sub(newline_count);
        }

        // Rope's line_to_byte includes all newlines from previous lines
        // Subtract line_number newlines to match old behavior
        self.rope
            .line_to_byte(line_number)
            .saturating_sub(line_number)
    }

    /// Get line number from byte offset (offset excludes newlines)
    pub fn offset_to_line(&self, offset: usize) -> usize {
        if offset == 0 {
            return 0;
        }

        // Need to add back newline count to get actual Rope byte offset
        // Binary search to find the correct line
        let mut low = 0;
        let mut high = self.rope.len_lines();

        while low < high {
            let mid = (low + high) / 2;
            let mid_offset = self.line_to_offset(mid);

            if mid_offset < offset {
                low = mid + 1;
            } else if mid_offset > offset {
                high = mid;
            } else {
                return mid;
            }
        }

        low.saturating_sub(1)
            .min(self.rope.len_lines().saturating_sub(1))
    }

    /// Get line number and offset within line from character offset
    pub fn char_offset_to_position(&self, char_offset: usize) -> (usize, usize) {
        let char_offset = char_offset.min(self.rope.len_chars());

        let line_idx = self.rope.char_to_line(char_offset);
        let line_start_char = self.rope.line_to_char(line_idx);
        let char_in_line = char_offset - line_start_char;

        (line_idx, char_in_line)
    }

    /// Get character offset from line number and column number
    pub fn position_to_char_offset(&self, line: usize, column: usize) -> usize {
        if line >= self.rope.len_lines() {
            return self.rope.len_chars();
        }

        let line_start_char = self.rope.line_to_char(line);
        let line_len = if line + 1 < self.rope.len_lines() {
            self.rope.line_to_char(line + 1) - line_start_char - 1 // -1 for newline
        } else {
            self.rope.len_chars() - line_start_char
        };

        line_start_char + column.min(line_len)
    }

    /// Get total line count
    pub fn line_count(&self) -> usize {
        self.rope.len_lines()
    }

    /// Get total byte count
    pub fn byte_count(&self) -> usize {
        self.rope.len_bytes()
    }

    /// Get total character count
    pub fn char_count(&self) -> usize {
        self.rope.len_chars()
    }

    /// Insert text (at specified character offset)
    pub fn insert(&mut self, char_offset: usize, text: &str) {
        let char_offset = char_offset.min(self.rope.len_chars());
        self.rope.insert(char_offset, text);
    }

    /// Delete text range (character offset)
    pub fn delete(&mut self, start_char: usize, len_chars: usize) {
        let start_char = start_char.min(self.rope.len_chars());
        let end_char = (start_char + len_chars).min(self.rope.len_chars());

        if start_char < end_char {
            self.rope.remove(start_char..end_char);
        }
    }

    /// Get complete text
    pub fn get_text(&self) -> String {
        self.rope.to_string()
    }

    /// Get text of the specified line (excluding newline)
    pub fn get_line_text(&self, line_number: usize) -> Option<String> {
        if line_number >= self.rope.len_lines() {
            return None;
        }

        let mut text = self.rope.line(line_number).to_string();

        // Remove trailing newline
        if text.ends_with('\n') {
            text.pop();
        }

        Some(text)
    }
}

impl Default for LineIndex {
    fn default() -> Self {
        Self::new()
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_line_index() {
        let index = LineIndex::new();
        assert_eq!(index.line_count(), 1); // Rope empty document has 1 line
        assert_eq!(index.byte_count(), 0);
        assert_eq!(index.char_count(), 0);
    }

    #[test]
    fn test_from_text() {
        let text = "Line 1\nLine 2\nLine 3";
        let index = LineIndex::from_text(text);

        assert_eq!(index.line_count(), 3);
        assert_eq!(index.byte_count(), text.len());
        assert_eq!(index.char_count(), text.chars().count());
    }

    #[test]
    fn test_line_to_offset() {
        let text = "First line\nSecond line\nThird line";
        let index = LineIndex::from_text(text);

        assert_eq!(index.line_to_offset(0), 0);
        assert_eq!(index.line_to_offset(1), 10); // "First line" (excluding \n)
        assert_eq!(index.line_to_offset(2), 21); // "First line" (10) + "Second line" (11) = 21
    }

    #[test]
    fn test_offset_to_line() {
        let text = "First line\nSecond line\nThird line";
        let index = LineIndex::from_text(text);

        assert_eq!(index.offset_to_line(0), 0);
        assert_eq!(index.offset_to_line(5), 0);
        assert_eq!(index.offset_to_line(11), 1);
        assert_eq!(index.offset_to_line(23), 2);
    }

    #[test]
    fn test_char_offset_to_position() {
        let text = "ABC\nDEF\nGHI";
        let index = LineIndex::from_text(text);

        assert_eq!(index.char_offset_to_position(0), (0, 0)); // A
        assert_eq!(index.char_offset_to_position(2), (0, 2)); // C
        assert_eq!(index.char_offset_to_position(4), (1, 0)); // D
        assert_eq!(index.char_offset_to_position(8), (2, 0)); // G
    }

    #[test]
    fn test_position_to_char_offset() {
        let text = "ABC\nDEF\nGHI";
        let index = LineIndex::from_text(text);

        assert_eq!(index.position_to_char_offset(0, 0), 0); // A
        assert_eq!(index.position_to_char_offset(0, 2), 2); // C
        assert_eq!(index.position_to_char_offset(1, 0), 4); // D
        assert_eq!(index.position_to_char_offset(2, 0), 8); // G
    }

    #[test]
    fn test_utf8_cjk() {
        let text = "你好\n世界";
        let index = LineIndex::from_text(text);

        assert_eq!(index.line_count(), 2);
        assert_eq!(index.byte_count(), text.len());
        assert_eq!(index.char_count(), 5); // 5 characters (你好\n世界)

        // First line: "你好"
        assert_eq!(index.char_offset_to_position(0), (0, 0));
        assert_eq!(index.char_offset_to_position(1), (0, 1));
        // Second line: "世界" (newline at character offset 2)
        assert_eq!(index.char_offset_to_position(3), (1, 0));
    }

    #[test]
    fn test_get_line() {
        let text = "Line 1\nLine 2\nLine 3";
        let index = LineIndex::from_text(text);

        let line0 = index.get_line(0);
        assert!(line0.is_some());
        let meta = line0.unwrap();
        assert!(meta.is_pure_ascii);

        let line_none = index.get_line(10);
        assert!(line_none.is_none());
    }

    #[test]
    fn test_insert_delete_lines() {
        let mut index = LineIndex::from_text("Line 1\nLine 2");
        assert_eq!(index.line_count(), 2);

        index.delete_line(0);
        assert_eq!(index.line_count(), 1);
    }

    #[test]
    fn test_mixed_ascii_cjk() {
        let text = "Hello 你好\nWorld 世界";
        let index = LineIndex::from_text(text);

        assert_eq!(index.line_count(), 2);
        assert!(index.byte_count() > index.char_count());
    }

    #[test]
    fn test_large_document() {
        let mut lines = Vec::new();
        for i in 0..10000 {
            lines.push(format!("Line {}", i));
        }
        let text = lines.join("\n");

        let index = LineIndex::from_text(&text);
        assert_eq!(index.line_count(), 10000);

        // Test accessing middle line
        let line_5000 = index.get_line(5000);
        assert!(line_5000.is_some());
    }

    #[test]
    fn test_insert_text() {
        let mut index = LineIndex::from_text("Hello World");

        index.insert(6, "Beautiful ");
        assert_eq!(index.get_text(), "Hello Beautiful World");
    }

    #[test]
    fn test_delete_text() {
        let mut index = LineIndex::from_text("Hello Beautiful World");

        index.delete(6, 10); // Delete "Beautiful "
        assert_eq!(index.get_text(), "Hello World");
    }
}
