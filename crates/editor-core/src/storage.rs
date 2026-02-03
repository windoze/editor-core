//! Stage 1: Linear Storage Layer
//!
//! Implements efficient insertion and deletion operations using Piece Table,
//! providing O(1) undo capability.

/// Buffer type identifier
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum BufferType {
    /// Read-only original buffer
    Original,
    /// Append-only add buffer
    Add,
}

/// Piece structure: references a fragment in a buffer
#[derive(Debug, Clone)]
pub struct Piece {
    /// Buffer type
    pub buffer_type: BufferType,
    /// Start position in the corresponding buffer (byte offset)
    pub start: usize,
    /// Byte length of the fragment
    pub byte_length: usize,
    /// Character count of the fragment (handles UTF-8 multi-byte characters)
    pub char_count: usize,
}

impl Piece {
    /// Create a new Piece
    pub fn new(
        buffer_type: BufferType,
        start: usize,
        byte_length: usize,
        char_count: usize,
    ) -> Self {
        Self {
            buffer_type,
            start,
            byte_length,
            char_count,
        }
    }
}

/// Piece Table - main storage structure
pub struct PieceTable {
    /// Read-only original buffer
    original_buffer: Vec<u8>,
    /// Append-only add buffer
    add_buffer: Vec<u8>,
    /// List of pieces
    pieces: Vec<Piece>,
    /// Operation counter (for triggering GC)
    operation_count: usize,
    /// GC threshold (trigger GC after every N operations)
    gc_threshold: usize,
}

impl PieceTable {
    /// Create a new Piece Table from original text
    pub fn new(text: &str) -> Self {
        let bytes = text.as_bytes().to_vec();
        let char_count = text.chars().count();
        let byte_length = bytes.len();

        let pieces = if byte_length > 0 {
            vec![Piece::new(BufferType::Original, 0, byte_length, char_count)]
        } else {
            Vec::new()
        };

        Self {
            original_buffer: bytes,
            add_buffer: Vec::new(),
            pieces,
            operation_count: 0,
            gc_threshold: 1000, // Trigger GC after every 1000 operations
        }
    }

    /// Create an empty Piece Table
    pub fn empty() -> Self {
        Self {
            original_buffer: Vec::new(),
            add_buffer: Vec::new(),
            pieces: Vec::new(),
            operation_count: 0,
            gc_threshold: 1000,
        }
    }

    /// Insert text at the specified character offset
    pub fn insert(&mut self, offset: usize, text: &str) {
        if text.is_empty() {
            return;
        }

        let text_bytes = text.as_bytes();
        let text_char_count = text.chars().count();
        let text_byte_length = text_bytes.len();

        // Add new text to add_buffer
        let add_start = self.add_buffer.len();
        self.add_buffer.extend_from_slice(text_bytes);

        // Find the piece at the insertion position
        let (piece_index, char_offset_in_piece) = self.find_piece_at_offset(offset);

        if let Some(piece_idx) = piece_index {
            let piece = &self.pieces[piece_idx];

            if char_offset_in_piece == 0 {
                // Insert at the beginning of the piece
                let new_piece = Piece::new(
                    BufferType::Add,
                    add_start,
                    text_byte_length,
                    text_char_count,
                );
                self.pieces.insert(piece_idx, new_piece);
            } else if char_offset_in_piece == piece.char_count {
                // Insert at the end of the piece
                let new_piece = Piece::new(
                    BufferType::Add,
                    add_start,
                    text_byte_length,
                    text_char_count,
                );
                self.pieces.insert(piece_idx + 1, new_piece);
            } else {
                // Insert in the middle of the piece, need to split
                let (left_piece, right_piece) = self.split_piece(piece, char_offset_in_piece);
                let new_piece = Piece::new(
                    BufferType::Add,
                    add_start,
                    text_byte_length,
                    text_char_count,
                );

                // Replace the original piece with three new pieces
                self.pieces.splice(
                    piece_idx..=piece_idx,
                    vec![left_piece, new_piece, right_piece],
                );
            }
        } else {
            // Empty document or insert at the end
            let new_piece = Piece::new(
                BufferType::Add,
                add_start,
                text_byte_length,
                text_char_count,
            );
            self.pieces.push(new_piece);
        }

        // Try to merge adjacent pieces
        self.try_merge_adjacent_pieces();

        // Check if GC needs to be triggered
        self.check_gc();
    }

    /// Delete characters in the specified range
    pub fn delete(&mut self, start_offset: usize, length: usize) {
        if length == 0 {
            return;
        }

        let end_offset = start_offset + length;

        // Find the pieces at the start and end positions
        let (start_piece_idx, start_char_offset) = self.find_piece_at_offset(start_offset);
        let (end_piece_idx, end_char_offset) = self.find_piece_at_offset(end_offset);

        match (start_piece_idx, end_piece_idx) {
            (Some(start_idx), Some(end_idx)) if start_idx == end_idx => {
                // Delete range is within the same piece
                let piece = &self.pieces[start_idx];

                if start_char_offset == 0 && end_char_offset == piece.char_count {
                    // Delete the entire piece
                    self.pieces.remove(start_idx);
                } else if start_char_offset == 0 {
                    // Delete from the beginning
                    let (_, right) = self.split_piece(piece, end_char_offset);
                    self.pieces[start_idx] = right;
                } else if end_char_offset == piece.char_count {
                    // Delete to the end
                    let (left, _) = self.split_piece(piece, start_char_offset);
                    self.pieces[start_idx] = left;
                } else {
                    // Delete in the middle
                    let (left, temp) = self.split_piece(piece, start_char_offset);
                    let (_, right) = self.split_piece(&temp, end_char_offset - start_char_offset);
                    self.pieces.splice(start_idx..=start_idx, vec![left, right]);
                }
            }
            (Some(start_idx), Some(end_idx)) => {
                // Delete range spans multiple pieces
                let start_piece = &self.pieces[start_idx];
                let end_piece = &self.pieces[end_idx];

                let mut new_pieces = Vec::new();

                // Handle the starting piece
                if start_char_offset > 0 {
                    let (left, _) = self.split_piece(start_piece, start_char_offset);
                    new_pieces.push(left);
                }

                // Handle the ending piece
                if end_char_offset < end_piece.char_count {
                    let (_, right) = self.split_piece(end_piece, end_char_offset);
                    new_pieces.push(right);
                }

                // Replace all pieces in the range
                self.pieces.splice(start_idx..=end_idx, new_pieces);
            }
            (None, None) => {
                // Empty document, no need to delete
            }
            _ => {
                // Only one position is valid, handle edge cases
                if let Some(start_idx) = start_piece_idx {
                    // Delete from start_idx to the end
                    let start_piece = &self.pieces[start_idx];
                    if start_char_offset == 0 {
                        self.pieces.truncate(start_idx);
                    } else {
                        let (left, _) = self.split_piece(start_piece, start_char_offset);
                        self.pieces.truncate(start_idx);
                        self.pieces.push(left);
                    }
                }
            }
        }

        // Check if GC needs to be triggered
        self.check_gc();
    }

    /// Get the entire document content
    pub fn get_text(&self) -> String {
        let mut result = String::new();
        for piece in &self.pieces {
            let buffer = match piece.buffer_type {
                BufferType::Original => &self.original_buffer,
                BufferType::Add => &self.add_buffer,
            };
            let slice = &buffer[piece.start..piece.start + piece.byte_length];
            result.push_str(std::str::from_utf8(slice).unwrap());
        }
        result
    }

    /// Get text in the specified range
    pub fn get_range(&self, start_offset: usize, length: usize) -> String {
        let mut result = String::new();
        let mut current_offset = 0;
        let end_offset = start_offset + length;

        for piece in &self.pieces {
            let piece_end = current_offset + piece.char_count;

            if current_offset >= end_offset {
                break;
            }

            if piece_end > start_offset {
                let buffer = match piece.buffer_type {
                    BufferType::Original => &self.original_buffer,
                    BufferType::Add => &self.add_buffer,
                };

                let piece_text =
                    std::str::from_utf8(&buffer[piece.start..piece.start + piece.byte_length])
                        .unwrap();

                let skip_chars = start_offset.saturating_sub(current_offset);

                let take_chars = if piece_end > end_offset {
                    end_offset - current_offset.max(start_offset)
                } else {
                    piece.char_count - skip_chars
                };

                result.push_str(
                    &piece_text
                        .chars()
                        .skip(skip_chars)
                        .take(take_chars)
                        .collect::<String>(),
                );
            }

            current_offset = piece_end;
        }

        result
    }

    /// Get the total character count of the document
    pub fn char_count(&self) -> usize {
        self.pieces.iter().map(|p| p.char_count).sum()
    }

    /// Get the total byte count of the document
    pub fn byte_count(&self) -> usize {
        self.pieces.iter().map(|p| p.byte_length).sum()
    }

    /// Get the size of add_buffer (for memory testing)
    pub fn add_buffer_size(&self) -> usize {
        self.add_buffer.len()
    }

    /// Find the piece at the specified character offset and the offset within that piece
    /// Returns (piece_index, char_offset_in_piece)
    fn find_piece_at_offset(&self, offset: usize) -> (Option<usize>, usize) {
        let mut current_offset = 0;

        for (idx, piece) in self.pieces.iter().enumerate() {
            let next_offset = current_offset + piece.char_count;
            if offset <= next_offset {
                return (Some(idx), offset - current_offset);
            }
            current_offset = next_offset;
        }

        if self.pieces.is_empty() {
            (None, 0)
        } else {
            (
                Some(self.pieces.len() - 1),
                self.pieces.last().unwrap().char_count,
            )
        }
    }

    /// Split a piece at the specified character position
    /// Returns (left_piece, right_piece)
    fn split_piece(&self, piece: &Piece, char_offset: usize) -> (Piece, Piece) {
        let buffer = match piece.buffer_type {
            BufferType::Original => &self.original_buffer,
            BufferType::Add => &self.add_buffer,
        };

        let piece_text =
            std::str::from_utf8(&buffer[piece.start..piece.start + piece.byte_length]).unwrap();

        // Calculate byte offset (O(n))
        // `char_offset` is the character offset within this piece; convert it to UTF-8 byte offset to complete the split.
        let byte_offset = piece_text
            .char_indices()
            .nth(char_offset)
            .map(|(i, _)| i)
            .unwrap_or(piece.byte_length);

        let left = Piece::new(piece.buffer_type, piece.start, byte_offset, char_offset);

        let right = Piece::new(
            piece.buffer_type,
            piece.start + byte_offset,
            piece.byte_length - byte_offset,
            piece.char_count - char_offset,
        );

        (left, right)
    }

    /// Check if two pieces can be merged (must be from the same buffer and adjacent)
    fn can_merge(&self, p1: &Piece, p2: &Piece) -> bool {
        p1.buffer_type == p2.buffer_type &&
        p1.buffer_type == BufferType::Add && // Only merge pieces in AddBuffer
        p1.start + p1.byte_length == p2.start
    }

    /// Merge two adjacent pieces
    fn merge_pieces(&self, p1: &Piece, p2: &Piece) -> Piece {
        Piece::new(
            p1.buffer_type,
            p1.start,
            p1.byte_length + p2.byte_length,
            p1.char_count + p2.char_count,
        )
    }

    /// Try to merge adjacent pieces after insertion
    fn try_merge_adjacent_pieces(&mut self) {
        let mut i = 0;
        while i + 1 < self.pieces.len() {
            if self.can_merge(&self.pieces[i], &self.pieces[i + 1]) {
                let merged = self.merge_pieces(&self.pieces[i], &self.pieces[i + 1]);
                self.pieces.splice(i..=i + 1, vec![merged]);
            } else {
                i += 1;
            }
        }
    }

    /// Garbage collection: compact add_buffer, remove unreferenced data
    pub fn gc(&mut self) {
        // Collect all referenced fragments in AddBuffer
        let mut referenced_ranges: Vec<(usize, usize)> = self
            .pieces
            .iter()
            .filter(|p| p.buffer_type == BufferType::Add)
            .map(|p| (p.start, p.start + p.byte_length))
            .collect();

        if referenced_ranges.is_empty() {
            // No references, clear add_buffer
            self.add_buffer.clear();
            return;
        }

        // Sort by start position
        referenced_ranges.sort_by_key(|r| r.0);

        // Merge overlapping ranges
        let mut merged_ranges = vec![referenced_ranges[0]];
        for range in referenced_ranges.iter().skip(1) {
            let last_idx = merged_ranges.len() - 1;
            if range.0 <= merged_ranges[last_idx].1 {
                // Overlapping or adjacent, merge
                merged_ranges[last_idx].1 = merged_ranges[last_idx].1.max(range.1);
            } else {
                merged_ranges.push(*range);
            }
        }

        // Build new add_buffer and update piece references
        let mut new_add_buffer = Vec::new();
        let mut mappings: Vec<(usize, usize, usize)> = Vec::new(); // (old_start, old_end, new_start)

        for (old_start, old_end) in merged_ranges {
            let new_start = new_add_buffer.len();
            new_add_buffer.extend_from_slice(&self.add_buffer[old_start..old_end]);
            mappings.push((old_start, old_end, new_start));
        }

        // Update offsets of all AddBuffer pieces (allow piece.start to fall within merged ranges)
        for piece in &mut self.pieces {
            if piece.buffer_type != BufferType::Add {
                continue;
            }

            // Binary search: find the last mapping where old_start <= piece.start
            let idx = match mappings.binary_search_by_key(&piece.start, |(s, _, _)| *s) {
                Ok(exact) => exact,
                Err(insert_pos) => insert_pos.saturating_sub(1),
            };

            if let Some((old_start, old_end, new_start)) = mappings.get(idx).copied()
                && piece.start < old_end
            {
                piece.start = new_start + (piece.start - old_start);
            }
        }

        self.add_buffer = new_add_buffer;
        self.operation_count = 0; // Reset counter
    }

    /// Check if GC needs to be triggered
    fn check_gc(&mut self) {
        self.operation_count += 1;
        if self.operation_count >= self.gc_threshold {
            self.gc();
        }
    }

    /// Set GC threshold
    pub fn set_gc_threshold(&mut self, threshold: usize) {
        self.gc_threshold = threshold;
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_new_piece_table() {
        let pt = PieceTable::new("Hello, World!");
        assert_eq!(pt.get_text(), "Hello, World!");
        assert_eq!(pt.char_count(), 13);
    }

    #[test]
    fn test_empty_piece_table() {
        let pt = PieceTable::empty();
        assert_eq!(pt.get_text(), "");
        assert_eq!(pt.char_count(), 0);
    }

    #[test]
    fn test_insert_at_start() {
        let mut pt = PieceTable::new("World");
        pt.insert(0, "Hello, ");
        assert_eq!(pt.get_text(), "Hello, World");
    }

    #[test]
    fn test_insert_at_end() {
        let mut pt = PieceTable::new("Hello");
        pt.insert(5, ", World");
        assert_eq!(pt.get_text(), "Hello, World");
    }

    #[test]
    fn test_insert_in_middle() {
        let mut pt = PieceTable::new("Hlo");
        pt.insert(1, "el");
        assert_eq!(pt.get_text(), "Hello");
    }

    #[test]
    fn test_delete_at_start() {
        let mut pt = PieceTable::new("Hello, World");
        pt.delete(0, 7);
        assert_eq!(pt.get_text(), "World");
    }

    #[test]
    fn test_delete_at_end() {
        let mut pt = PieceTable::new("Hello, World");
        pt.delete(5, 7);
        assert_eq!(pt.get_text(), "Hello");
    }

    #[test]
    fn test_delete_in_middle() {
        let mut pt = PieceTable::new("Hello, World");
        pt.delete(5, 2);
        assert_eq!(pt.get_text(), "HelloWorld");
    }

    #[test]
    fn test_multiple_operations() {
        let mut pt = PieceTable::new("Hello");
        pt.insert(5, " World");
        pt.insert(5, ",");
        pt.delete(0, 7);
        pt.insert(0, "Hi, ");
        assert_eq!(pt.get_text(), "Hi, World");
    }

    #[test]
    fn test_utf8_chinese() {
        let mut pt = PieceTable::new("你好");
        assert_eq!(pt.char_count(), 2);
        assert_eq!(pt.byte_count(), 6);

        pt.insert(1, "们");
        assert_eq!(pt.get_text(), "你们好");
        assert_eq!(pt.char_count(), 3);
    }

    #[test]
    fn test_utf8_emoji() {
        let mut pt = PieceTable::new("Hello 👋");
        pt.insert(6, "World ");
        assert_eq!(pt.get_text(), "Hello World 👋");
    }

    #[test]
    fn test_get_range() {
        let pt = PieceTable::new("Hello, World!");
        assert_eq!(pt.get_range(0, 5), "Hello");
        assert_eq!(pt.get_range(7, 5), "World");
        assert_eq!(pt.get_range(0, 13), "Hello, World!");
    }

    #[test]
    fn test_piece_merging() {
        let mut pt = PieceTable::new("Hello");

        // 连续插入相邻文本应该被合并
        let initial_pieces = pt.pieces.len();
        pt.insert(5, " ");
        pt.insert(6, "World");

        // 由于合并，pieces 数量应该较少
        assert_eq!(pt.get_text(), "Hello World");
        // 验证合并发生了（应该有2个pieces：原始的 "Hello" 和合并后的 " World"）
        assert!(pt.pieces.len() <= initial_pieces + 1);
    }

    #[test]
    fn test_gc_basic() {
        let mut pt = PieceTable::new("Hello");

        // 插入一些文本
        pt.insert(5, " World");
        pt.insert(11, "!");

        let add_buffer_size_before = pt.add_buffer.len();

        // 删除一些文本，产生未引用的片段
        pt.delete(5, 6); // 删除 " World"

        // 手动触发 GC
        pt.gc();

        // 验证内容不变
        assert_eq!(pt.get_text(), "Hello!");

        // 验证 add_buffer 被压缩了
        assert!(pt.add_buffer.len() < add_buffer_size_before);
    }

    #[test]
    fn test_gc_multiple_references() {
        let mut pt = PieceTable::new("ABC");

        // 创建多个引用到 add_buffer 的 pieces
        pt.insert(1, "1");
        pt.insert(3, "2");
        pt.insert(5, "3");

        assert_eq!(pt.get_text(), "A1B2C3");

        // GC 不应该删除被引用的数据
        pt.gc();

        // 内容应该保持不变
        assert_eq!(pt.get_text(), "A1B2C3");

        // add_buffer 仍然包含所有被引用的数据
        assert!(!pt.add_buffer.is_empty());
    }

    #[test]
    fn test_auto_gc_trigger() {
        let mut pt = PieceTable::new("Test");
        pt.set_gc_threshold(5); // 设置低阈值便于测试

        // 执行多次操作
        for i in 0..6 {
            pt.insert(4 + i, "x");
        }

        // 应该触发了自动 GC（计数器被重置）
        assert!(pt.operation_count < 6);
    }
}
