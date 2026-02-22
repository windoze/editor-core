//! Helpers for converting LSP "document highlight" payloads into `editor-core` style intervals.
//!
//! This module intentionally avoids pulling in `lsp-types`. It parses the small subset needed
//! to bridge `textDocument/documentHighlight` results into a dedicated `StyleLayerId`.

use crate::lsp_sync::{LspCoordinateConverter, LspPosition, LspRange};
use editor_core::intervals::{Interval, StyleId};
use editor_core::processing::ProcessingEdit;
use editor_core::{
    DOCUMENT_HIGHLIGHT_READ_STYLE_ID, DOCUMENT_HIGHLIGHT_TEXT_STYLE_ID,
    DOCUMENT_HIGHLIGHT_WRITE_STYLE_ID, LineIndex, StyleLayerId,
};
use serde_json::Value;

fn parse_lsp_position(value: &Value) -> Option<LspPosition> {
    Some(LspPosition {
        line: value.get("line")?.as_u64()? as u32,
        character: value.get("character")?.as_u64()? as u32,
    })
}

fn parse_lsp_range(value: &Value) -> Option<LspRange> {
    let start = parse_lsp_position(value.get("start")?)?;
    let end = parse_lsp_position(value.get("end")?)?;
    Some(LspRange::new(start, end))
}

fn char_offset_for_lsp_position(line_index: &LineIndex, pos: LspPosition) -> usize {
    let line = pos.line as usize;
    let line_text = line_index.get_line_text(line).unwrap_or_default();
    let char_in_line =
        LspCoordinateConverter::utf16_to_char_offset(&line_text, pos.character as usize);
    line_index.position_to_char_offset(line, char_in_line)
}

fn char_offsets_for_lsp_range(line_index: &LineIndex, range: &LspRange) -> (usize, usize) {
    let start = char_offset_for_lsp_position(line_index, range.start);
    let end = char_offset_for_lsp_position(line_index, range.end);
    (start.min(end), start.max(end))
}

fn style_id_for_document_highlight_kind(kind: Option<u64>) -> StyleId {
    // LSP DocumentHighlightKind:
    // 1 = Text, 2 = Read, 3 = Write
    match kind {
        Some(2) => DOCUMENT_HIGHLIGHT_READ_STYLE_ID,
        Some(3) => DOCUMENT_HIGHLIGHT_WRITE_STYLE_ID,
        _ => DOCUMENT_HIGHLIGHT_TEXT_STYLE_ID,
    }
}

/// Convert an LSP `textDocument/documentHighlight` result payload (`DocumentHighlight[] | null`)
/// into `editor-core` style intervals (character offsets).
pub fn lsp_document_highlights_to_intervals(
    line_index: &LineIndex,
    result: &Value,
) -> Vec<Interval> {
    let Some(highlights) = result.as_array() else {
        return Vec::new();
    };

    let mut out = Vec::<Interval>::with_capacity(highlights.len());
    for highlight in highlights {
        let Some(range_value) = highlight.get("range") else {
            continue;
        };
        let Some(range) = parse_lsp_range(range_value) else {
            continue;
        };

        let (start, end) = char_offsets_for_lsp_range(line_index, &range);
        if start == end {
            continue;
        }

        let style_id =
            style_id_for_document_highlight_kind(highlight.get("kind").and_then(Value::as_u64));
        out.push(Interval::new(start, end, style_id));
    }

    out
}

/// Convert document highlights into a single processing edit that replaces the
/// `StyleLayerId::DOCUMENT_HIGHLIGHTS` layer.
pub fn lsp_document_highlights_to_processing_edit(
    line_index: &LineIndex,
    result: &Value,
) -> ProcessingEdit {
    ProcessingEdit::ReplaceStyleLayer {
        layer: StyleLayerId::DOCUMENT_HIGHLIGHTS,
        intervals: lsp_document_highlights_to_intervals(line_index, result),
    }
}
