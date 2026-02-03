//! `editor-core-highlight-simple` - Simple (regex-based) highlighting helpers for `editor-core`.
//!
//! This crate is intended for lightweight formats (JSON/INI/etc.) where full parsing or LSP
//! integration is unnecessary.

use editor_core::intervals::{Interval, StyleId, StyleLayerId};
use editor_core::processing::{DocumentProcessor, ProcessingEdit};
use editor_core::{EditorStateManager, LineIndex};
use regex::Regex;
use std::convert::Infallible;

/// A single regex highlighting rule.
#[derive(Debug, Clone)]
pub struct RegexRule {
    regex: Regex,
    style_id: StyleId,
    capture_group: Option<usize>,
}

impl RegexRule {
    pub fn new(pattern: &str, style_id: StyleId) -> Result<Self, regex::Error> {
        Ok(Self {
            regex: Regex::new(pattern)?,
            style_id,
            capture_group: None,
        })
    }

    /// Highlight only a capture group of each match.
    ///
    /// Example (INI key):
    /// - pattern: `^\\s*([^=\\s]+)\\s*=`
    /// - capture_group: `1` (the key)
    pub fn with_capture_group(mut self, group: usize) -> Self {
        self.capture_group = Some(group);
        self
    }

    pub fn style_id(&self) -> StyleId {
        self.style_id
    }
}

/// A simple regex-based syntax highlighter.
///
/// Designed for simple formats (JSON/INI/etc.). It is *not* intended to be a full parser.
#[derive(Debug, Clone)]
pub struct RegexHighlighter {
    rules: Vec<RegexRule>,
}

impl RegexHighlighter {
    pub fn new(rules: Vec<RegexRule>) -> Self {
        Self { rules }
    }

    pub fn rules(&self) -> &[RegexRule] {
        &self.rules
    }

    /// Run all rules over the whole document and return style intervals (char offsets).
    pub fn highlight(&self, line_index: &LineIndex) -> Vec<Interval> {
        let mut intervals = Vec::new();
        let line_count = line_index.line_count();

        for line in 0..line_count {
            let Some(line_text) = line_index.get_line_text(line) else {
                continue;
            };
            let line_start = line_index.position_to_char_offset(line, 0);

            for rule in &self.rules {
                if let Some(group) = rule.capture_group {
                    for caps in rule.regex.captures_iter(&line_text) {
                        let Some(m) = caps.get(group) else {
                            continue;
                        };
                        if let Some(interval) = interval_from_match(
                            line_start,
                            &line_text,
                            m.start(),
                            m.end(),
                            rule.style_id,
                        ) {
                            intervals.push(interval);
                        }
                    }
                } else {
                    for m in rule.regex.find_iter(&line_text) {
                        if let Some(interval) = interval_from_match(
                            line_start,
                            &line_text,
                            m.start(),
                            m.end(),
                            rule.style_id,
                        ) {
                            intervals.push(interval);
                        }
                    }
                }
            }
        }

        intervals
    }

    /// A small default JSON grammar (strings, numbers, booleans, null).
    ///
    /// Note: LSP semantic tokens are preferred for real code, but this is handy for simple formats.
    pub fn json_default(styles: SimpleJsonStyles) -> Result<Self, regex::Error> {
        Ok(Self::new(vec![
            // JSON string (single-line, handles escapes)
            RegexRule::new(r#""(?:\\.|[^"\\])*""#, styles.string)?,
            // JSON number
            RegexRule::new(
                r#"-?(?:0|[1-9]\d*)(?:\.\d+)?(?:[eE][+-]?\d+)?"#,
                styles.number,
            )?,
            // JSON boolean / null
            RegexRule::new(r#"\b(?:true|false)\b"#, styles.boolean)?,
            RegexRule::new(r#"\bnull\b"#, styles.null)?,
        ]))
    }

    /// A small default INI grammar (section, key, comment).
    pub fn ini_default(styles: SimpleIniStyles) -> Result<Self, regex::Error> {
        Ok(Self::new(vec![
            // Section header: [section]
            RegexRule::new(r#"^\s*\[([^\]]+)\]\s*$"#, styles.section)?.with_capture_group(1),
            // Key: key = value
            RegexRule::new(r#"^\s*([^=\s]+)\s*="#, styles.key)?.with_capture_group(1),
            // Comment: ;... or #...
            RegexRule::new(r#"^\s*[;#].*$"#, styles.comment)?,
        ]))
    }
}

/// A processor that applies a [`RegexHighlighter`] into a [`StyleLayerId`] via `editor-core`'s
/// generic processing interface.
#[derive(Debug, Clone)]
pub struct RegexHighlightProcessor {
    layer: StyleLayerId,
    highlighter: RegexHighlighter,
}

impl RegexHighlightProcessor {
    pub fn new(layer: StyleLayerId, highlighter: RegexHighlighter) -> Self {
        Self { layer, highlighter }
    }

    pub fn layer(&self) -> StyleLayerId {
        self.layer
    }

    pub fn highlighter(&self) -> &RegexHighlighter {
        &self.highlighter
    }

    pub fn highlighter_mut(&mut self) -> &mut RegexHighlighter {
        &mut self.highlighter
    }

    pub fn json_default(styles: SimpleJsonStyles) -> Result<Self, regex::Error> {
        Ok(Self::new(
            StyleLayerId::SIMPLE_SYNTAX,
            RegexHighlighter::json_default(styles)?,
        ))
    }

    pub fn ini_default(styles: SimpleIniStyles) -> Result<Self, regex::Error> {
        Ok(Self::new(
            StyleLayerId::SIMPLE_SYNTAX,
            RegexHighlighter::ini_default(styles)?,
        ))
    }
}

impl DocumentProcessor for RegexHighlightProcessor {
    type Error = Infallible;

    fn process(&mut self, state: &EditorStateManager) -> Result<Vec<ProcessingEdit>, Self::Error> {
        let intervals = self.highlighter.highlight(&state.editor().line_index);
        Ok(vec![ProcessingEdit::ReplaceStyleLayer {
            layer: self.layer,
            intervals,
        }])
    }
}

#[derive(Debug, Clone, Copy)]
pub struct SimpleJsonStyles {
    pub string: StyleId,
    pub number: StyleId,
    pub boolean: StyleId,
    pub null: StyleId,
}

impl Default for SimpleJsonStyles {
    fn default() -> Self {
        Self {
            string: SIMPLE_STYLE_STRING,
            number: SIMPLE_STYLE_NUMBER,
            boolean: SIMPLE_STYLE_BOOLEAN,
            null: SIMPLE_STYLE_NULL,
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct SimpleIniStyles {
    pub section: StyleId,
    pub key: StyleId,
    pub comment: StyleId,
}

impl Default for SimpleIniStyles {
    fn default() -> Self {
        Self {
            section: SIMPLE_STYLE_SECTION,
            key: SIMPLE_STYLE_KEY,
            comment: SIMPLE_STYLE_COMMENT,
        }
    }
}

/// Default `StyleId` constants for `RegexHighlighter`-based grammars.
///
/// These are only identifiers. UI/theme layer is expected to map them to actual colors.
pub const SIMPLE_STYLE_STRING: StyleId = 0x0200_0001;
pub const SIMPLE_STYLE_NUMBER: StyleId = 0x0200_0002;
pub const SIMPLE_STYLE_BOOLEAN: StyleId = 0x0200_0003;
pub const SIMPLE_STYLE_NULL: StyleId = 0x0200_0004;
pub const SIMPLE_STYLE_SECTION: StyleId = 0x0200_0010;
pub const SIMPLE_STYLE_KEY: StyleId = 0x0200_0011;
pub const SIMPLE_STYLE_COMMENT: StyleId = 0x0200_0012;

fn interval_from_match(
    line_start_offset: usize,
    line_text: &str,
    match_start_byte: usize,
    match_end_byte: usize,
    style_id: StyleId,
) -> Option<Interval> {
    if match_start_byte >= match_end_byte || match_end_byte > line_text.len() {
        return None;
    }

    let start_col = line_text[..match_start_byte].chars().count();
    let end_col = line_text[..match_end_byte].chars().count();
    if start_col >= end_col {
        return None;
    }

    Some(Interval::new(
        line_start_offset + start_col,
        line_start_offset + end_col,
        style_id,
    ))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_regex_highlighter_json_strings() {
        let text = r#"{ "key": "值", "n": 12, "ok": true, "x": null }"#;
        let line_index = LineIndex::from_text(text);

        let highlighter = RegexHighlighter::json_default(SimpleJsonStyles::default()).unwrap();
        let intervals = highlighter.highlight(&line_index);

        // Expect at least the 4 quoted strings and a number/keyword.
        assert!(intervals.len() >= 6);
        assert!(intervals.iter().any(|i| i.style_id == SIMPLE_STYLE_STRING));
        assert!(intervals.iter().any(|i| i.style_id == SIMPLE_STYLE_NUMBER));
    }

    #[test]
    fn test_regex_highlighter_ini_capture_groups() {
        let text = "[core]\nname = editor-core\n;comment\n";
        let line_index = LineIndex::from_text(text);
        let highlighter = RegexHighlighter::ini_default(SimpleIniStyles::default()).unwrap();
        let intervals = highlighter.highlight(&line_index);

        assert!(intervals.iter().any(|i| i.style_id == SIMPLE_STYLE_SECTION));
        assert!(intervals.iter().any(|i| i.style_id == SIMPLE_STYLE_KEY));
        assert!(intervals.iter().any(|i| i.style_id == SIMPLE_STYLE_COMMENT));
    }
}
