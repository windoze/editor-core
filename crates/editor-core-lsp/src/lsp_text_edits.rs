//! Minimal helpers for applying LSP `TextEdit` / `WorkspaceEdit` structures to `editor-core`.
//!
//! This module intentionally avoids pulling in a full `lsp-types` dependency. It parses the
//! small subset needed to:
//! - apply formatting edits
//! - apply rename / code action edits
//! - implement server->client `workspace/applyEdit` in a headless way

use crate::lsp_sync::{LspCoordinateConverter, LspPosition, LspRange};
use editor_core::{Command, EditCommand, EditorStateManager, LineIndex};
use serde_json::Value;
use std::collections::HashMap;

#[derive(Debug, Clone, PartialEq, Eq)]
/// A minimal representation of an LSP `TextEdit`.
pub struct LspTextEdit {
    /// The range to replace (UTF-16 based line/character positions).
    pub range: LspRange,
    /// Replacement text (may contain newlines).
    pub new_text: String,
}

impl LspTextEdit {
    /// Parse a `TextEdit`-shaped JSON value.
    pub fn from_value(value: &Value) -> Option<Self> {
        let range_value = value.get("range")?;
        let start = range_value.get("start")?;
        let end = range_value.get("end")?;

        let start_pos = LspPosition {
            line: start.get("line")?.as_u64()? as u32,
            character: start.get("character")?.as_u64()? as u32,
        };
        let end_pos = LspPosition {
            line: end.get("line")?.as_u64()? as u32,
            character: end.get("character")?.as_u64()? as u32,
        };

        let new_text = value
            .get("newText")
            .and_then(Value::as_str)
            .unwrap_or("")
            .to_string();

        Some(Self {
            range: LspRange {
                start: start_pos,
                end: end_pos,
            },
            new_text,
        })
    }
}

/// Parse a JSON array of `TextEdit` values.
pub fn text_edits_from_value(value: &Value) -> Vec<LspTextEdit> {
    value
        .as_array()
        .map(|arr| {
            arr.iter()
                .filter_map(LspTextEdit::from_value)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

fn char_offset_for_lsp_position(line_index: &LineIndex, pos: LspPosition) -> usize {
    let line = pos.line as usize;
    let line_text = line_index.get_line_text(line).unwrap_or_default();
    let char_in_line =
        LspCoordinateConverter::utf16_to_char_offset(&line_text, pos.character as usize);
    line_index.position_to_char_offset(line, char_in_line)
}

/// Convert an LSP range (UTF-16 positions) into a pair of character offsets in the document.
pub fn char_offsets_for_lsp_range(line_index: &LineIndex, range: &LspRange) -> (usize, usize) {
    let start = char_offset_for_lsp_position(line_index, range.start);
    let end = char_offset_for_lsp_position(line_index, range.end);
    (start.min(end), start.max(end))
}

/// Apply a list of LSP `TextEdit`s to an [`EditorStateManager`].
///
/// Returns the list of changed (start,end) ranges in *pre-edit* char offsets. This is useful for
/// headless "changed ranges" highlighting in UIs.
pub fn apply_text_edits(
    state_manager: &mut EditorStateManager,
    edits: &[LspTextEdit],
) -> Result<Vec<(usize, usize)>, String> {
    let line_index = &state_manager.editor().line_index;

    let mut resolved = edits
        .iter()
        .map(|edit| {
            let (start, end) = char_offsets_for_lsp_range(line_index, &edit.range);
            (start, end, edit.new_text.as_str())
        })
        .collect::<Vec<_>>();

    // Sort descending by start offset so earlier edits don't shift the later ones.
    resolved.sort_by_key(|(start, _, _)| std::cmp::Reverse(*start));

    let mut changed = Vec::with_capacity(resolved.len());
    for (start, end, new_text) in resolved {
        let length = end.saturating_sub(start);
        state_manager
            .execute(Command::Edit(EditCommand::Replace {
                start,
                length,
                text: new_text.to_string(),
            }))
            .map_err(|err| format!("Failed to apply LSP edit at {}..{}: {}", start, end, err))?;
        changed.push((start, end));
    }

    Ok(changed)
}

/// Extract all `TextEdit`s in a `WorkspaceEdit` for the given `uri`.
///
/// Handles both:
/// - `workspaceEdit.changes[uri]`
/// - `workspaceEdit.documentChanges[]` containing `TextDocumentEdit`
pub fn workspace_edit_text_edits_for_uri(workspace_edit: &Value, uri: &str) -> Vec<LspTextEdit> {
    let mut out = Vec::<LspTextEdit>::new();

    if let Some(changes) = workspace_edit.get("changes").and_then(Value::as_object)
        && let Some(edits) = changes.get(uri)
    {
        out.extend(text_edits_from_value(edits));
    }

    if let Some(document_changes) = workspace_edit
        .get("documentChanges")
        .and_then(Value::as_array)
    {
        for change in document_changes {
            // TextDocumentEdit: { textDocument: { uri, version? }, edits: [...] }
            let Some(text_document) = change.get("textDocument") else {
                continue;
            };
            let Some(change_uri) = text_document.get("uri").and_then(Value::as_str) else {
                continue;
            };
            if change_uri != uri {
                continue;
            }

            if let Some(edits) = change.get("edits") {
                out.extend(text_edits_from_value(edits));
            }
        }
    }

    out
}

/// Extract all `TextEdit`s in a `WorkspaceEdit`, grouped by `uri`.
///
/// Handles both:
/// - `workspaceEdit.changes[uri]`
/// - `workspaceEdit.documentChanges[]` containing `TextDocumentEdit`
///
/// Other `documentChanges` operations (`create`, `rename`, `delete`) are ignored.
pub fn workspace_edit_text_edits(workspace_edit: &Value) -> HashMap<String, Vec<LspTextEdit>> {
    let mut out = HashMap::<String, Vec<LspTextEdit>>::new();

    if let Some(changes) = workspace_edit.get("changes").and_then(Value::as_object) {
        for (uri, edits) in changes {
            let entry = out.entry(uri.to_string()).or_default();
            entry.extend(text_edits_from_value(edits));
        }
    }

    if let Some(document_changes) = workspace_edit
        .get("documentChanges")
        .and_then(Value::as_array)
    {
        for change in document_changes {
            // TextDocumentEdit: { textDocument: { uri, version? }, edits: [...] }
            let Some(text_document) = change.get("textDocument") else {
                continue;
            };
            let Some(uri) = text_document.get("uri").and_then(Value::as_str) else {
                continue;
            };
            let Some(edits) = change.get("edits") else {
                continue;
            };

            let entry = out.entry(uri.to_string()).or_default();
            entry.extend(text_edits_from_value(edits));
        }
    }

    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_workspace_edit_text_edits_collects_all_uris() {
        let edit = json!({
            "changes": {
                "file:///a": [
                    { "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } }, "newText": "X" }
                ]
            },
            "documentChanges": [
                {
                    "textDocument": { "uri": "file:///b", "version": 1 },
                    "edits": [
                        { "range": { "start": { "line": 1, "character": 2 }, "end": { "line": 1, "character": 3 } }, "newText": "Y" }
                    ]
                }
            ]
        });

        let by_uri = workspace_edit_text_edits(&edit);
        assert_eq!(by_uri.len(), 2);
        assert_eq!(by_uri.get("file:///a").unwrap().len(), 1);
        assert_eq!(by_uri.get("file:///b").unwrap().len(), 1);
    }
}
