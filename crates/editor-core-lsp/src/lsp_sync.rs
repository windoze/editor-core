//! LSP Sync Layer (Language Server Protocol Sync)
//!
//! Translates editor changes into standard LSP JSON-RPC messages and handles UTF-16 coordinate conversions and semantic token parsing.

use editor_core::LineIndex;
use editor_core::intervals::{Interval, StyleId};

fn split_lines_preserve_trailing(text: &str) -> Vec<String> {
    // Keep consistent editor semantics:
    // - N newlines => N+1 lines
    // - Treat CRLF by stripping trailing '\r'
    text.split('\n')
        .map(|line| line.strip_suffix('\r').unwrap_or(line).to_string())
        .collect()
}

/// LSP Position (based on UTF-16 code units)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LspPosition {
    /// Line number (0-based)
    pub line: u32,
    /// Character offset (UTF-16 code units, 0-based)
    pub character: u32,
}

impl LspPosition {
    /// Create a new LSP position (UTF-16 based).
    pub fn new(line: u32, character: u32) -> Self {
        Self { line, character }
    }
}

/// LSP Range
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct LspRange {
    /// Range start position (inclusive).
    pub start: LspPosition,
    /// Range end position (exclusive).
    pub end: LspPosition,
}

impl LspRange {
    /// Create a new LSP range.
    pub fn new(start: LspPosition, end: LspPosition) -> Self {
        Self { start, end }
    }
}

/// Text change event
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TextChange {
    /// Range of the change
    pub range: LspRange,
    /// New text content
    pub text: String,
}

/// LSP coordinate converter
///
/// Handles conversions between byte offsets, character offsets, and LSP Position (UTF-16)
pub struct LspCoordinateConverter;

impl LspCoordinateConverter {
    /// Convert UTF-8 string to UTF-16 code unit count
    pub fn utf8_to_utf16_len(text: &str) -> usize {
        text.encode_utf16().count()
    }

    /// Convert character offset to UTF-16 code unit offset
    pub fn char_offset_to_utf16(text: &str, char_offset: usize) -> usize {
        text.chars().take(char_offset).map(|c| c.len_utf16()).sum()
    }

    /// Convert UTF-16 code unit offset to character offset
    pub fn utf16_to_char_offset(text: &str, utf16_offset: usize) -> usize {
        let mut current_utf16 = 0;
        let mut char_count = 0;

        for ch in text.chars() {
            if current_utf16 >= utf16_offset {
                break;
            }
            current_utf16 += ch.len_utf16();
            char_count += 1;
        }

        char_count
    }

    /// Convert line and column (character offset) to LSP Position
    pub fn position_to_lsp(line_text: &str, line: usize, char_in_line: usize) -> LspPosition {
        let utf16_offset = Self::char_offset_to_utf16(line_text, char_in_line);
        LspPosition::new(line as u32, utf16_offset as u32)
    }

    /// Convert LSP Position to character offset
    pub fn lsp_to_char_offset(line_text: &str, character: u32) -> usize {
        Self::utf16_to_char_offset(line_text, character as usize)
    }
}

/// Incremental change calculator
///
/// Generates LSP didChange messages based on edit operations
pub struct DeltaCalculator {
    /// Document line contents (for coordinate conversion)
    lines: Vec<String>,
}

impl DeltaCalculator {
    /// Create an empty calculator (no lines).
    pub fn new() -> Self {
        Self { lines: Vec::new() }
    }

    /// Initialize from text
    pub fn from_text(text: &str) -> Self {
        let lines = split_lines_preserve_trailing(text);
        Self { lines }
    }

    /// Update line contents
    pub fn set_lines(&mut self, lines: Vec<String>) {
        self.lines = lines;
    }

    /// Get text of specified line
    pub fn get_line(&self, line: usize) -> Option<&str> {
        self.lines.get(line).map(|s| s.as_str())
    }

    /// Calculate change for insert operation
    pub fn calculate_insert_change(
        &self,
        line: usize,
        char_in_line: usize,
        inserted_text: &str,
    ) -> TextChange {
        let line_text = self.get_line(line).unwrap_or("");
        let start_pos = LspCoordinateConverter::position_to_lsp(line_text, line, char_in_line);

        // Insert operation range is zero-width
        let range = LspRange::new(start_pos, start_pos);

        TextChange {
            range,
            text: inserted_text.to_string(),
        }
    }

    /// Calculate change for delete operation
    pub fn calculate_delete_change(
        &self,
        start_line: usize,
        start_char: usize,
        end_line: usize,
        end_char: usize,
    ) -> TextChange {
        let start_line_text = self.get_line(start_line).unwrap_or("");
        let end_line_text = self.get_line(end_line).unwrap_or("");

        let start_pos =
            LspCoordinateConverter::position_to_lsp(start_line_text, start_line, start_char);
        let end_pos = LspCoordinateConverter::position_to_lsp(end_line_text, end_line, end_char);

        let range = LspRange::new(start_pos, end_pos);

        TextChange {
            range,
            text: String::new(), // Delete operation has empty text
        }
    }

    /// Calculate change for replace operation
    pub fn calculate_replace_change(
        &self,
        start_line: usize,
        start_char: usize,
        end_line: usize,
        end_char: usize,
        new_text: &str,
    ) -> TextChange {
        let start_line_text = self.get_line(start_line).unwrap_or("");
        let end_line_text = self.get_line(end_line).unwrap_or("");

        let start_pos =
            LspCoordinateConverter::position_to_lsp(start_line_text, start_line, start_char);
        let end_pos = LspCoordinateConverter::position_to_lsp(end_line_text, end_line, end_char);

        let range = LspRange::new(start_pos, end_pos);

        TextChange {
            range,
            text: new_text.to_string(),
        }
    }

    /// Apply change and update internal state
    pub fn apply_change(&mut self, change: &TextChange) {
        fn char_index_to_byte_offset(text: &str, char_index: usize) -> usize {
            if char_index == 0 {
                return 0;
            }

            text.char_indices()
                .nth(char_index)
                .map(|(byte_idx, _)| byte_idx)
                .unwrap_or(text.len())
        }

        let start_line = change.range.start.line as usize;
        let end_line = change.range.end.line as usize;

        // Maintain consistency with editor semantics: at least 1 line.
        if self.lines.is_empty() {
            self.lines.push(String::new());
        }

        if start_line >= self.lines.len() {
            self.lines.resize(start_line + 1, String::new());
        }
        if end_line >= self.lines.len() {
            self.lines.resize(end_line + 1, String::new());
        }

        let start_line_text = self.lines[start_line].clone();
        let end_line_text = self.lines[end_line].clone();

        let start_char = LspCoordinateConverter::utf16_to_char_offset(
            &start_line_text,
            change.range.start.character as usize,
        );
        let end_char = LspCoordinateConverter::utf16_to_char_offset(
            &end_line_text,
            change.range.end.character as usize,
        );

        let start_byte = char_index_to_byte_offset(&start_line_text, start_char);
        let end_byte = char_index_to_byte_offset(&end_line_text, end_char);

        let prefix = &start_line_text[..start_byte];
        let suffix = &end_line_text[end_byte..];

        let mut replacement =
            String::with_capacity(prefix.len() + change.text.len() + suffix.len());
        replacement.push_str(prefix);
        replacement.push_str(&change.text);
        replacement.push_str(suffix);

        let new_lines = split_lines_preserve_trailing(&replacement);

        // Replace affected line range: use splice uniformly for single-line/multi-line.
        self.lines.splice(start_line..=end_line, new_lines);

        if self.lines.is_empty() {
            self.lines.push(String::new());
        }
    }
}

impl Default for DeltaCalculator {
    fn default() -> Self {
        Self::new()
    }
}

/// Semantic token type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SemanticTokenType {
    /// Namespace symbols.
    Namespace = 0,
    /// Type symbols (built-in or user defined).
    Type = 1,
    /// Class symbols.
    Class = 2,
    /// Enum symbols.
    Enum = 3,
    /// Interface symbols.
    Interface = 4,
    /// Struct symbols.
    Struct = 5,
    /// Type parameter symbols.
    TypeParameter = 6,
    /// Parameter symbols.
    Parameter = 7,
    /// Variable symbols.
    Variable = 8,
    /// Property symbols.
    Property = 9,
    /// Enum member symbols.
    EnumMember = 10,
    /// Event symbols.
    Event = 11,
    /// Function symbols.
    Function = 12,
    /// Method symbols.
    Method = 13,
    /// Macro symbols.
    Macro = 14,
    /// Keyword tokens.
    Keyword = 15,
    /// Modifier tokens.
    Modifier = 16,
    /// Comment tokens.
    Comment = 17,
    /// String literal tokens.
    String = 18,
    /// Number literal tokens.
    Number = 19,
    /// Regular expression literal tokens.
    Regexp = 20,
    /// Operator tokens.
    Operator = 21,
}

/// Semantic token
#[derive(Debug, Clone)]
pub struct SemanticToken {
    /// Line offset relative to previous token
    pub delta_line: u32,
    /// Character offset relative to previous token (same line) or absolute offset (different line)
    pub delta_start: u32,
    /// Token length
    pub length: u32,
    /// Token type
    pub token_type: u32,
    /// Token modifiers (bit flags)
    pub token_modifiers: u32,
}

impl SemanticToken {
    /// Create a semantic token in LSP's relative encoding.
    pub fn new(
        delta_line: u32,
        delta_start: u32,
        length: u32,
        token_type: u32,
        token_modifiers: u32,
    ) -> Self {
        Self {
            delta_line,
            delta_start,
            length,
            token_type,
            token_modifiers,
        }
    }
}

/// Semantic tokens manager
///
/// Converts semantic tokens returned by LSP into a format usable by Interval Tree
pub struct SemanticTokensManager {
    /// Current tokens
    tokens: Vec<SemanticToken>,
}

impl SemanticTokensManager {
    /// Create an empty semantic tokens manager.
    pub fn new() -> Self {
        Self { tokens: Vec::new() }
    }

    /// Update tokens
    pub fn update_tokens(&mut self, tokens: Vec<SemanticToken>) {
        self.tokens = tokens;
    }

    /// Convert relative offset tokens to absolute positions
    ///
    /// Returns a list of (line, start_char, length, token_type)
    pub fn to_absolute_positions(&self) -> Vec<(u32, u32, u32, u32)> {
        let mut result = Vec::new();
        let mut current_line = 0;
        let mut current_start = 0;

        for token in &self.tokens {
            if token.delta_line > 0 {
                current_line += token.delta_line;
                current_start = token.delta_start;
            } else {
                current_start += token.delta_start;
            }

            result.push((current_line, current_start, token.length, token.token_type));
        }

        result
    }

    /// Clear tokens
    pub fn clear(&mut self) {
        self.tokens.clear();
    }
}

impl Default for SemanticTokensManager {
    fn default() -> Self {
        Self::new()
    }
}

/// LSP semantic tokens conversion error
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum SemanticTokensError {
    /// `data` length must be a multiple of 5 (deltaLine, deltaStart, length, tokenType, tokenModifiers)
    InvalidDataLength(usize),
    /// Token points to a non-existent line number
    InvalidLine(u32),
    /// Token UTF-16 range calculation overflow
    Utf16Overflow,
}

impl std::fmt::Display for SemanticTokensError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            SemanticTokensError::InvalidDataLength(len) => {
                write!(
                    f,
                    "Semantic tokens data length must be a multiple of 5 (got {})",
                    len
                )
            }
            SemanticTokensError::InvalidLine(line) => {
                write!(f, "Semantic token line out of range: {}", line)
            }
            SemanticTokensError::Utf16Overflow => write!(f, "Semantic token UTF-16 range overflow"),
        }
    }
}

impl std::error::Error for SemanticTokensError {}

/// Default semantic token -> StyleId encoding.
///
/// Semantic tokens do not carry color information, so it's recommended to encode
/// `(token_type, token_modifiers)` as `StyleId`, then have the UI/theme layer
/// do the `StyleId -> color/style` mapping.
///
/// Encoding format:
/// - High 16 bits: token_type
/// - Low 16 bits: token_modifiers (truncated to 16 bits)
pub fn encode_semantic_style_id(token_type: u32, token_modifiers: u32) -> StyleId {
    ((token_type & 0xFFFF) << 16) | (token_modifiers & 0xFFFF)
}

/// Decode default semantic StyleId encoding, returns `(token_type, token_modifiers_low16)`.
pub fn decode_semantic_style_id(style_id: StyleId) -> (u32, u32) {
    (style_id >> 16, style_id & 0xFFFF)
}

/// Convert LSP `semanticTokens` raw `data` (u32 sequence) to `Interval` list.
///
/// - `data` uses LSP standard delta encoding, with each group of 5 u32s:
///   `(deltaLine, deltaStart, length, tokenType, tokenModifiers)`
/// - `deltaStart`/`length` units are UTF-16 code units.
///
/// The returned intervals use **character offset (char offset)**, consistent with `LineIndex` / `PieceTable` / `IntervalTree`.
pub fn semantic_tokens_to_intervals<F>(
    data: &[u32],
    line_index: &LineIndex,
    style_resolver: F,
) -> Result<Vec<Interval>, SemanticTokensError>
where
    F: Fn(u32, u32) -> StyleId,
{
    if !data.len().is_multiple_of(5) {
        return Err(SemanticTokensError::InvalidDataLength(data.len()));
    }

    let mut intervals = Vec::with_capacity(data.len() / 5);
    let mut current_line: u32 = 0;
    let mut current_start_utf16: u32 = 0;
    let mut cached_line: Option<usize> = None;
    let mut cached_line_text = String::new();

    for chunk in data.chunks_exact(5) {
        let delta_line = chunk[0];
        let delta_start = chunk[1];
        let length = chunk[2];
        let token_type = chunk[3];
        let token_modifiers = chunk[4];

        if delta_line > 0 {
            current_line = current_line.saturating_add(delta_line);
            current_start_utf16 = delta_start;
        } else {
            current_start_utf16 = current_start_utf16.saturating_add(delta_start);
        }

        let end_utf16 = current_start_utf16
            .checked_add(length)
            .ok_or(SemanticTokensError::Utf16Overflow)?;

        let line_usize = current_line as usize;
        if line_usize >= line_index.line_count() {
            return Err(SemanticTokensError::InvalidLine(current_line));
        }

        if cached_line != Some(line_usize) {
            cached_line_text = line_index.get_line_text(line_usize).unwrap_or_default();
            cached_line = Some(line_usize);
        }

        let line_text = cached_line_text.as_str();
        let start_char =
            LspCoordinateConverter::utf16_to_char_offset(line_text, current_start_utf16 as usize);
        let end_char = LspCoordinateConverter::utf16_to_char_offset(line_text, end_utf16 as usize);

        if start_char == end_char {
            continue;
        }

        let start = line_index.position_to_char_offset(line_usize, start_char);
        let end = line_index.position_to_char_offset(line_usize, end_char);
        if start >= end {
            continue;
        }

        intervals.push(Interval::new(
            start,
            end,
            style_resolver(token_type, token_modifiers),
        ));
    }

    Ok(intervals)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_utf8_to_utf16_len() {
        assert_eq!(LspCoordinateConverter::utf8_to_utf16_len("hello"), 5);
        assert_eq!(LspCoordinateConverter::utf8_to_utf16_len("你好"), 2);
        // Emoji may be 1 or 2 UTF-16 code units
        assert_eq!(LspCoordinateConverter::utf8_to_utf16_len("👋"), 2);
    }

    #[test]
    fn test_char_offset_to_utf16() {
        let text = "hello你好👋";

        // "hello" = 5 个字符，5 个 UTF-16 units
        assert_eq!(LspCoordinateConverter::char_offset_to_utf16(text, 5), 5);

        // "hello你" = 6 个字符，6 个 UTF-16 units
        assert_eq!(LspCoordinateConverter::char_offset_to_utf16(text, 6), 6);

        // "hello你好" = 7 个字符，7 个 UTF-16 units
        assert_eq!(LspCoordinateConverter::char_offset_to_utf16(text, 7), 7);

        // "hello你好👋" = 8 个字符，9 个 UTF-16 units（👋 = 2 units）
        assert_eq!(LspCoordinateConverter::utf8_to_utf16_len(text), 9);
    }

    #[test]
    fn test_utf16_to_char_offset() {
        let text = "hello你好👋";

        assert_eq!(LspCoordinateConverter::utf16_to_char_offset(text, 5), 5);
        assert_eq!(LspCoordinateConverter::utf16_to_char_offset(text, 6), 6);
        assert_eq!(LspCoordinateConverter::utf16_to_char_offset(text, 7), 7);
    }

    #[test]
    fn test_position_to_lsp() {
        let line_text = "hello world";
        let pos = LspCoordinateConverter::position_to_lsp(line_text, 0, 6);
        assert_eq!(pos.line, 0);
        assert_eq!(pos.character, 6);
    }

    #[test]
    fn test_position_to_lsp_with_emoji() {
        let line_text = "hello 👋 world";
        // "hello " = 6 个字符，6 个 UTF-16 units
        let pos1 = LspCoordinateConverter::position_to_lsp(line_text, 0, 6);
        assert_eq!(pos1.character, 6);

        // "hello 👋" = 7 个字符，8 个 UTF-16 units
        let pos2 = LspCoordinateConverter::position_to_lsp(line_text, 0, 7);
        assert_eq!(pos2.character, 8);
    }

    #[test]
    fn test_delta_calculator_insert() {
        let text = "line 1\nline 2\nline 3";
        let calc = DeltaCalculator::from_text(text);

        let change = calc.calculate_insert_change(1, 5, " inserted");
        assert_eq!(change.range.start.line, 1);
        assert_eq!(change.range.start.character, 5);
        assert_eq!(change.range.end, change.range.start);
        assert_eq!(change.text, " inserted");
    }

    #[test]
    fn test_delta_calculator_delete() {
        let text = "line 1\nline 2\nline 3";
        let calc = DeltaCalculator::from_text(text);

        let change = calc.calculate_delete_change(0, 5, 1, 5);
        assert_eq!(change.range.start.line, 0);
        assert_eq!(change.range.start.character, 5);
        assert_eq!(change.range.end.line, 1);
        assert_eq!(change.range.end.character, 5);
        assert_eq!(change.text, "");
    }

    #[test]
    fn test_delta_calculator_apply_change_single_line_insert_with_newline() {
        let mut calc = DeltaCalculator::from_text("hello\nworld");

        // 在第 0 行末尾插入 "\n!"，应当拆分成新行。
        let change = calc.calculate_insert_change(0, 5, "\n!");
        calc.apply_change(&change);

        assert_eq!(calc.get_line(0), Some("hello"));
        assert_eq!(calc.get_line(1), Some("!"));
        assert_eq!(calc.get_line(2), Some("world"));
    }

    #[test]
    fn test_delta_calculator_apply_change_multi_line_delete() {
        let mut calc = DeltaCalculator::from_text("aa\nbb\ncc");

        // 删除从 (0,1) 到 (2,1) 的范围：保留 "a" + "c" => "ac"
        let change = calc.calculate_delete_change(0, 1, 2, 1);
        calc.apply_change(&change);

        assert_eq!(calc.get_line(0), Some("ac"));
        assert_eq!(calc.get_line(1), None);
    }

    #[test]
    fn test_delta_calculator_apply_change_multi_line_replace_with_newlines() {
        let mut calc = DeltaCalculator::from_text("one\ntwo\nthree");

        // 替换跨行范围，并插入两行。
        let change = calc.calculate_replace_change(0, 1, 1, 1, "X\nY");
        calc.apply_change(&change);

        // 原文本： "o|ne" + "\n" + "|two" + ...
        // 替换后应为：
        //  line0: "oX"
        //  line1: "Ywo"
        //  line2: "three"
        assert_eq!(calc.get_line(0), Some("oX"));
        assert_eq!(calc.get_line(1), Some("Ywo"));
        assert_eq!(calc.get_line(2), Some("three"));
    }

    #[test]
    fn test_semantic_tokens_absolute_positions() {
        let mut manager = SemanticTokensManager::new();

        let tokens = vec![
            SemanticToken::new(0, 0, 5, 12, 0), // 第 0 行，位置 0，长度 5
            SemanticToken::new(0, 6, 5, 8, 0),  // 第 0 行，位置 6，长度 5
            SemanticToken::new(1, 0, 6, 12, 0), // 第 1 行，位置 0，长度 6
        ];

        manager.update_tokens(tokens);

        let abs_positions = manager.to_absolute_positions();
        assert_eq!(abs_positions.len(), 3);
        assert_eq!(abs_positions[0], (0, 0, 5, 12));
        assert_eq!(abs_positions[1], (0, 6, 5, 8));
        assert_eq!(abs_positions[2], (1, 0, 6, 12));
    }

    #[test]
    fn test_roundtrip_conversion() {
        let text = "hello 你好 👋 world";

        // Test roundtrip conversion
        for char_offset in 0..text.chars().count() {
            let utf16_offset = LspCoordinateConverter::char_offset_to_utf16(text, char_offset);
            let back_to_char = LspCoordinateConverter::utf16_to_char_offset(text, utf16_offset);
            assert_eq!(
                back_to_char, char_offset,
                "Roundtrip conversion failed: char_offset={}",
                char_offset
            );
        }
    }

    #[test]
    fn test_encode_decode_semantic_style_id() {
        let style_id = encode_semantic_style_id(42, 0xBEEF);
        assert_eq!(decode_semantic_style_id(style_id), (42, 0xBEEF));
    }

    #[test]
    fn test_semantic_tokens_to_intervals_basic() {
        let text = "Hello\nWorld";
        let line_index = LineIndex::from_text(text);

        // token #1: line 0, start 0, len 5 ("Hello")
        // token #2: line 1, start 0, len 5 ("World")
        //
        // LSP delta encoding:
        //  - first token: deltaLine=0, deltaStart=0
        //  - second token: deltaLine=1 => new line, deltaStart is absolute in that line
        let data = vec![0, 0, 5, 1, 2, 1, 0, 5, 3, 0];

        let intervals =
            semantic_tokens_to_intervals(&data, &line_index, encode_semantic_style_id).unwrap();

        assert_eq!(intervals.len(), 2);
        assert_eq!(
            intervals[0],
            Interval::new(0, 5, encode_semantic_style_id(1, 2))
        );
        // line 1 starts after "Hello\n" => char offset 6
        assert_eq!(
            intervals[1],
            Interval::new(6, 11, encode_semantic_style_id(3, 0))
        );
    }
}
