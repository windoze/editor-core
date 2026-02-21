//! Helpers for converting LSP payloads into `editor-core` decorations.
//!
//! This module intentionally avoids pulling in `lsp-types`. It parses the small subset needed
//! to bridge common LSP "virtual text" features into `editor-core`'s decoration model.

use crate::lsp_sync::{LspCoordinateConverter, LspPosition};
use editor_core::processing::ProcessingEdit;
use editor_core::{
    Decoration, DecorationKind, DecorationLayerId, DecorationPlacement, DecorationRange, LineIndex,
};
use serde_json::Value;

fn char_offset_for_lsp_position(line_index: &LineIndex, pos: LspPosition) -> usize {
    let line = pos.line as usize;
    let line_text = line_index.get_line_text(line).unwrap_or_default();
    let char_in_line =
        LspCoordinateConverter::utf16_to_char_offset(&line_text, pos.character as usize);
    line_index.position_to_char_offset(line, char_in_line)
}

fn parse_lsp_position(value: &Value) -> Option<LspPosition> {
    Some(LspPosition {
        line: value.get("line")?.as_u64()? as u32,
        character: value.get("character")?.as_u64()? as u32,
    })
}

fn parse_inlay_hint_label(value: &Value) -> String {
    if let Some(s) = value.as_str() {
        return s.to_string();
    }

    if let Some(arr) = value.as_array() {
        let mut out = String::new();
        for part in arr {
            if let Some(value) = part.get("value").and_then(Value::as_str) {
                out.push_str(value);
            }
        }
        return out;
    }

    String::new()
}

fn parse_inlay_hint_tooltip(value: &Value) -> Option<String> {
    if let Some(s) = value.as_str() {
        return Some(s.to_string());
    }

    // MarkupContent: { kind: "...", value: "..." }
    value
        .get("value")
        .and_then(Value::as_str)
        .map(|s| s.to_string())
}

/// Convert an LSP `textDocument/inlayHint` result payload (`InlayHint[] | null`) into decorations.
pub fn lsp_inlay_hints_to_decorations(line_index: &LineIndex, result: &Value) -> Vec<Decoration> {
    let Some(hints) = result.as_array() else {
        return Vec::new();
    };

    let mut out = Vec::<Decoration>::with_capacity(hints.len());
    for hint in hints {
        let Some(pos_value) = hint.get("position") else {
            continue;
        };
        let Some(pos) = parse_lsp_position(pos_value) else {
            continue;
        };
        let offset = char_offset_for_lsp_position(line_index, pos);

        let mut label = hint
            .get("label")
            .map(parse_inlay_hint_label)
            .unwrap_or_default();

        let padding_left = hint
            .get("paddingLeft")
            .and_then(Value::as_bool)
            .unwrap_or(false);
        let padding_right = hint
            .get("paddingRight")
            .and_then(Value::as_bool)
            .unwrap_or(false);

        if padding_left && !label.starts_with(' ') {
            label.insert(0, ' ');
        }
        if padding_right && !label.ends_with(' ') {
            label.push(' ');
        }

        let tooltip = hint.get("tooltip").and_then(parse_inlay_hint_tooltip);

        out.push(Decoration {
            range: DecorationRange::new(offset, offset),
            placement: DecorationPlacement::After,
            kind: DecorationKind::InlayHint,
            text: if label.is_empty() { None } else { Some(label) },
            styles: Vec::new(),
            tooltip,
            data_json: Some(hint.to_string()),
        });
    }

    out
}

/// Convert inlay hints into a single processing edit that replaces the `INLAY_HINTS` layer.
pub fn lsp_inlay_hints_to_processing_edit(
    line_index: &LineIndex,
    result: &Value,
) -> ProcessingEdit {
    ProcessingEdit::ReplaceDecorations {
        layer: DecorationLayerId::INLAY_HINTS,
        decorations: lsp_inlay_hints_to_decorations(line_index, result),
    }
}
