//! Helpers for parsing LSP hover payloads (`textDocument/hover`).
//!
//! This module intentionally stays dependency-light and operates on `serde_json::Value`.

use crate::lsp_sync::LspRange;
use serde_json::Value;

/// LSP `MarkupKind`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LspMarkupKind {
    /// Plain text.
    PlainText,
    /// Markdown.
    Markdown,
}

/// LSP `MarkupContent`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LspMarkupContent {
    /// Content kind.
    pub kind: LspMarkupKind,
    /// Content value (plain text or markdown string).
    pub value: String,
}

/// Normalized hover contents.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LspHoverContents {
    /// A single `MarkupContent`.
    Markup(LspMarkupContent),
    /// A single string (LSP `MarkedString` simplified form).
    String(String),
    /// Multiple items (LSP `MarkedString[]` / `MarkupContent[]`).
    Many(Vec<LspHoverContents>),
}

/// Normalized hover result.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LspHover {
    /// Hover contents.
    pub contents: LspHoverContents,
    /// Optional range the hover applies to.
    pub range: Option<LspRange>,
}

fn range_from_value(v: &Value) -> Option<LspRange> {
    LspRange::from_value(v)
}

fn markup_kind_from_str(s: &str) -> Option<LspMarkupKind> {
    match s {
        "plaintext" => Some(LspMarkupKind::PlainText),
        "markdown" => Some(LspMarkupKind::Markdown),
        _ => None,
    }
}

fn markup_content_from_value(v: &Value) -> Option<LspMarkupContent> {
    let kind = v
        .get("kind")
        .and_then(Value::as_str)
        .and_then(markup_kind_from_str)?;
    let value = v.get("value").and_then(Value::as_str)?.to_string();
    Some(LspMarkupContent { kind, value })
}

fn marked_string_from_value(v: &Value) -> Option<String> {
    // MarkedString = string | { language, value }
    if let Some(s) = v.as_str() {
        return Some(s.to_string());
    }
    let value = v.get("value").and_then(Value::as_str)?;
    let language = v.get("language").and_then(Value::as_str);
    if let Some(lang) = language {
        // Render as fenced code block (markdown), preserving language id.
        return Some(format!("```{lang}\n{value}\n```"));
    }
    Some(value.to_string())
}

fn hover_contents_from_value(v: &Value) -> Option<LspHoverContents> {
    // MarkupContent
    if let Some(obj) = v.as_object()
        && obj.contains_key("kind")
        && obj.contains_key("value")
        && let Some(mc) = markup_content_from_value(v)
    {
        return Some(LspHoverContents::Markup(mc));
    }

    // MarkedString
    if let Some(ms) = marked_string_from_value(v) {
        return Some(LspHoverContents::String(ms));
    }

    // Array
    if let Some(arr) = v.as_array() {
        let items = arr
            .iter()
            .filter_map(hover_contents_from_value)
            .collect::<Vec<_>>();
        return Some(LspHoverContents::Many(items));
    }

    None
}

/// Parse a `Hover | null` JSON value into a normalized representation.
pub fn hover_from_value(value: &Value) -> Option<LspHover> {
    if value.is_null() {
        return None;
    }
    let contents = hover_contents_from_value(value.get("contents")?)?;
    let range = value.get("range").and_then(range_from_value);
    Some(LspHover { contents, range })
}

impl LspHoverContents {
    /// Render hover contents into a single markdown-ish string.
    ///
    /// Notes:
    /// - `plaintext` content is returned as-is.
    /// - Multiple entries are joined with double newlines.
    pub fn to_markdown_string(&self) -> String {
        match self {
            Self::Markup(mc) => mc.value.clone(),
            Self::String(s) => s.clone(),
            Self::Many(items) => items
                .iter()
                .map(|x| x.to_markdown_string())
                .filter(|s| !s.trim().is_empty())
                .collect::<Vec<_>>()
                .join("\n\n"),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn hover_parses_markup_content() {
        let v = json!({
            "contents": { "kind": "markdown", "value": "**hi**" },
            "range": { "start": { "line": 1, "character": 2 }, "end": { "line": 1, "character": 3 } }
        });
        let h = hover_from_value(&v).expect("hover");
        assert_eq!(h.contents.to_markdown_string(), "**hi**");
        assert_eq!(h.range.unwrap().start.line, 1);
    }

    #[test]
    fn hover_parses_marked_string_object_as_fenced_block() {
        let v = json!({
            "contents": { "language": "rust", "value": "fn main() {}" }
        });
        let h = hover_from_value(&v).expect("hover");
        let s = h.contents.to_markdown_string();
        assert!(s.contains("```rust"));
        assert!(s.contains("fn main() {}"));
    }

    #[test]
    fn hover_parses_array_contents() {
        let v = json!({
            "contents": [
                { "kind": "plaintext", "value": "a" },
                { "kind": "markdown", "value": "b" }
            ]
        });
        let h = hover_from_value(&v).expect("hover");
        assert_eq!(h.contents.to_markdown_string(), "a\n\nb");
    }
}
