//! Helpers for converting LSP symbol payloads into `editor-core` symbol models.
//!
//! This module intentionally avoids pulling in `lsp-types`. It parses the subset needed to bridge:
//! - `textDocument/documentSymbol` → `editor_core::DocumentOutline`
//! - `workspace/symbol` → `Vec<editor_core::WorkspaceSymbol>`

use crate::lsp_sync::{LspCoordinateConverter, LspPosition, LspRange};
use editor_core::processing::ProcessingEdit;
use editor_core::{
    DocumentOutline, DocumentSymbol, LineIndex, SymbolKind, SymbolLocation, SymbolRange,
    Utf16Position, Utf16Range, WorkspaceSymbol,
};
use serde_json::Value;

fn parse_lsp_position(value: &Value) -> Option<LspPosition> {
    Some(LspPosition {
        line: value.get("line")?.as_u64()? as u32,
        character: value.get("character")?.as_u64()? as u32,
    })
}

fn parse_lsp_range(value: &Value) -> Option<LspRange> {
    Some(LspRange {
        start: parse_lsp_position(value.get("start")?)?,
        end: parse_lsp_position(value.get("end")?)?,
    })
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

fn parse_document_symbol(line_index: &LineIndex, value: &Value) -> Option<DocumentSymbol> {
    let name = value.get("name")?.as_str()?.to_string();
    let detail = value
        .get("detail")
        .and_then(Value::as_str)
        .map(|s| s.to_string());
    let kind = value.get("kind")?.as_u64()? as u32;

    let range_value = value.get("range")?;
    let selection_range_value = value.get("selectionRange")?;
    let range = parse_lsp_range(range_value)?;
    let selection_range = parse_lsp_range(selection_range_value)?;

    let (start, end) = char_offsets_for_lsp_range(line_index, &range);
    let (sel_start, sel_end) = char_offsets_for_lsp_range(line_index, &selection_range);

    let children = value
        .get("children")
        .and_then(Value::as_array)
        .map(|arr| {
            arr.iter()
                .filter_map(|child| parse_document_symbol(line_index, child))
                .collect::<Vec<_>>()
        })
        .unwrap_or_default();

    Some(DocumentSymbol {
        name,
        detail,
        kind: SymbolKind::from_lsp_kind(kind),
        range: SymbolRange::new(start, end),
        selection_range: SymbolRange::new(sel_start, sel_end),
        children,
        data_json: Some(value.to_string()),
    })
}

fn parse_symbol_information_as_document_symbol(
    line_index: &LineIndex,
    value: &Value,
) -> Option<DocumentSymbol> {
    let name = value.get("name")?.as_str()?.to_string();
    let kind = value.get("kind")?.as_u64()? as u32;

    let location = value.get("location")?;
    let range = parse_lsp_range(location.get("range")?)?;

    let (start, end) = char_offsets_for_lsp_range(line_index, &range);

    Some(DocumentSymbol {
        name,
        detail: None,
        kind: SymbolKind::from_lsp_kind(kind),
        range: SymbolRange::new(start, end),
        selection_range: SymbolRange::new(start, end),
        children: Vec::new(),
        data_json: Some(value.to_string()),
    })
}

/// Convert an LSP `textDocument/documentSymbol` result payload into a document outline.
///
/// Supported shapes:
/// - `DocumentSymbol[]` (hierarchical)
/// - `SymbolInformation[]` (flat)
pub fn lsp_document_symbols_to_outline(line_index: &LineIndex, result: &Value) -> DocumentOutline {
    let Some(arr) = result.as_array() else {
        return DocumentOutline::default();
    };

    let mut symbols = Vec::<DocumentSymbol>::new();
    for item in arr {
        if let Some(sym) = parse_document_symbol(line_index, item) {
            symbols.push(sym);
            continue;
        }
        if let Some(sym) = parse_symbol_information_as_document_symbol(line_index, item) {
            symbols.push(sym);
        }
    }

    DocumentOutline::new(symbols)
}

/// Convert document symbols into a processing edit that replaces the current outline.
pub fn lsp_document_symbols_to_processing_edit(
    line_index: &LineIndex,
    result: &Value,
) -> ProcessingEdit {
    ProcessingEdit::ReplaceDocumentSymbols {
        symbols: lsp_document_symbols_to_outline(line_index, result),
    }
}

fn parse_utf16_position(value: &Value) -> Option<Utf16Position> {
    Some(Utf16Position {
        line: value.get("line")?.as_u64()? as u32,
        character: value.get("character")?.as_u64()? as u32,
    })
}

fn parse_utf16_range(value: &Value) -> Option<Utf16Range> {
    Some(Utf16Range::new(
        parse_utf16_position(value.get("start")?)?,
        parse_utf16_position(value.get("end")?)?,
    ))
}

fn parse_symbol_location(value: &Value) -> Option<SymbolLocation> {
    let uri = value.get("uri")?.as_str()?.to_string();
    let range = parse_utf16_range(value.get("range")?)?;
    Some(SymbolLocation { uri, range })
}

/// Convert an LSP `workspace/symbol` result payload into workspace symbols.
///
/// This supports `SymbolInformation[]` (LSP 3.16) and the newer `WorkspaceSymbol[]`-shaped
/// payloads where `location` is `Location`.
pub fn lsp_workspace_symbols_to_results(result: &Value) -> Vec<WorkspaceSymbol> {
    let Some(arr) = result.as_array() else {
        return Vec::new();
    };

    let mut out = Vec::<WorkspaceSymbol>::with_capacity(arr.len());
    for item in arr {
        let name = item
            .get("name")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();
        if name.is_empty() {
            continue;
        }

        let kind = item.get("kind").and_then(Value::as_u64).unwrap_or(0) as u32;
        let detail = item
            .get("detail")
            .and_then(Value::as_str)
            .map(|s| s.to_string());
        let container_name = item
            .get("containerName")
            .and_then(Value::as_str)
            .map(|s| s.to_string());

        let Some(location_value) = item.get("location") else {
            continue;
        };
        let Some(location) = parse_symbol_location(location_value) else {
            continue;
        };

        out.push(WorkspaceSymbol {
            name,
            detail,
            kind: SymbolKind::from_lsp_kind(kind),
            location,
            container_name,
            data_json: Some(item.to_string()),
        });
    }

    out
}
