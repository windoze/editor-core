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

        let start_pos = crate::lsp_sync::LspPosition::from_value(start)?;
        let end_pos = crate::lsp_sync::LspPosition::from_value(end)?;

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
    LspCoordinateConverter::lsp_position_to_char_offset(line_index, pos)
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
    let line_index = state_manager.editor().line_index();

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

/// Summary of a `WorkspaceEdit` payload for UI previews.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceEditSummary {
    /// Per-document summaries, sorted by URI.
    pub documents: Vec<WorkspaceEditDocumentSummary>,
}

/// Summary of edits for a single document URI within a `WorkspaceEdit`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceEditDocumentSummary {
    /// Document URI.
    pub uri: String,
    /// Number of text edits targeting this URI.
    pub edit_count: usize,
    /// Whether any edits overlap in (line,character) space.
    ///
    /// Overlapping edits are not expected in well-formed LSP `WorkspaceEdit` payloads, but some
    /// servers can emit them. UIs can treat this as a "potential conflict" signal.
    pub has_overlapping_edits: bool,
}

fn pos_key(pos: LspPosition) -> (u32, u32) {
    (pos.line, pos.character)
}

fn range_overlaps(a: &LspRange, b: &LspRange) -> bool {
    let a0 = pos_key(a.start);
    let a1 = pos_key(a.end);
    let b0 = pos_key(b.start);
    let b1 = pos_key(b.end);

    // Treat ranges as half-open [start,end).
    a0 < b1 && b0 < a1
}

fn has_overlapping_edits(edits: &[LspTextEdit]) -> bool {
    if edits.len() < 2 {
        return false;
    }

    let mut sorted = edits.to_vec();
    sorted.sort_by_key(|e| pos_key(e.range.start));

    for i in 1..sorted.len() {
        if range_overlaps(&sorted[i - 1].range, &sorted[i].range) {
            return true;
        }
    }
    false
}

/// Summarize a `WorkspaceEdit` payload (`WorkspaceEdit | null`) for previewing.
pub fn summarize_workspace_edit(workspace_edit: &Value) -> WorkspaceEditSummary {
    let by_uri = workspace_edit_text_edits(workspace_edit);
    let mut documents = by_uri
        .into_iter()
        .map(|(uri, edits)| WorkspaceEditDocumentSummary {
            uri,
            edit_count: edits.len(),
            has_overlapping_edits: has_overlapping_edits(&edits),
        })
        .collect::<Vec<_>>();
    documents.sort_by(|a, b| a.uri.cmp(&b.uri));
    WorkspaceEditSummary { documents }
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

    #[test]
    fn test_summarize_workspace_edit_flags_overlapping_ranges() {
        let edit = json!({
            "changes": {
                "file:///a": [
                    { "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 2 } }, "newText": "X" },
                    { "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 3 } }, "newText": "Y" }
                ]
            }
        });

        let summary = summarize_workspace_edit(&edit);
        assert_eq!(summary.documents.len(), 1);
        assert_eq!(summary.documents[0].uri, "file:///a");
        assert!(summary.documents[0].has_overlapping_edits);
    }
}
