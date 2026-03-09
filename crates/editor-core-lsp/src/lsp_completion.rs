//! Completion apply helpers (LSP → `editor-core` edits).
//!
//! This module is intentionally dependency-light (`serde_json::Value` parsing only).
//!
//! Supported shapes:
//! - `CompletionItem.textEdit` as `TextEdit`
//! - `CompletionItem.textEdit` as `InsertReplaceEdit` (choose insert vs replace)
//! - `CompletionItem.additionalTextEdits`
//! - Snippet-shaped inserts (`insertTextFormat == 2`) are applied via `editor-core`’s snippet
//!   engine (`EditCommand::ApplySnippet`).

use crate::lsp_sync::{LspPosition, LspRange};
use crate::lsp_text_edits::{LspTextEdit, char_offsets_for_lsp_range, text_edits_from_value};
use editor_core::{
    Command, EditCommand, EditorStateManager, LineIndex, TextEditSpec, parse_snippet,
};
use serde_json::Value;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Which range to apply when a completion item uses an LSP `InsertReplaceEdit`.
pub enum CompletionTextEditMode {
    /// Use the `insert` range (usually less destructive).
    Insert,
    /// Use the `replace` range.
    Replace,
}

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

fn completion_item_insert_text_is_snippet(item: &Value) -> bool {
    item.get("insertTextFormat")
        .and_then(Value::as_u64)
        .map(|v| v == 2)
        .unwrap_or(false)
}

fn snippet_to_plain_text(snippet: &str) -> String {
    parse_snippet(snippet).text
}

fn normalize_completion_insert_text(item: &Value, text: &str) -> String {
    if completion_item_insert_text_is_snippet(item) {
        snippet_to_plain_text(text)
    } else {
        text.to_string()
    }
}

fn completion_item_main_text_edit(
    item: &Value,
    mode: CompletionTextEditMode,
) -> Option<LspTextEdit> {
    let text_edit = item.get("textEdit")?;

    // Standard `TextEdit`: { range, newText }
    if text_edit.get("range").is_some() {
        let mut edit = LspTextEdit::from_value(text_edit)?;
        edit.new_text = normalize_completion_insert_text(item, &edit.new_text);
        return Some(edit);
    }

    // `InsertReplaceEdit`: { insert, replace, newText }
    let insert_range = text_edit.get("insert").and_then(parse_lsp_range)?;
    let replace_range = text_edit.get("replace").and_then(parse_lsp_range)?;
    let new_text = text_edit.get("newText").and_then(Value::as_str)?;

    let range = match mode {
        CompletionTextEditMode::Insert => insert_range,
        CompletionTextEditMode::Replace => replace_range,
    };

    Some(LspTextEdit {
        range,
        new_text: normalize_completion_insert_text(item, new_text),
    })
}

fn completion_item_fallback_insert_text(item: &Value) -> Option<String> {
    item.get("insertText")
        .and_then(Value::as_str)
        .or_else(|| item.get("label").and_then(Value::as_str))
        .map(|s| normalize_completion_insert_text(item, s))
        .filter(|s| !s.is_empty())
}

/// Convert an LSP `CompletionItem` value into a batch of `TextEditSpec`s (pre-edit char offsets).
///
/// - Always includes `additionalTextEdits` if present.
/// - Uses `textEdit` if present, otherwise falls back to `insertText`/`label` + `fallback_range`.
pub fn completion_item_to_text_edit_specs(
    line_index: &LineIndex,
    item: &Value,
    mode: CompletionTextEditMode,
    fallback_range: Option<(usize, usize)>,
) -> Vec<TextEditSpec> {
    let mut out = Vec::<TextEditSpec>::new();

    if let Some(edit) = completion_item_main_text_edit(item, mode) {
        let (start, end) = char_offsets_for_lsp_range(line_index, &edit.range);
        out.push(TextEditSpec {
            start,
            end,
            text: edit.new_text,
        });
    } else if let (Some((start, end)), Some(text)) =
        (fallback_range, completion_item_fallback_insert_text(item))
    {
        out.push(TextEditSpec { start, end, text });
    }

    if let Some(additional) = item.get("additionalTextEdits") {
        for edit in text_edits_from_value(additional) {
            let (start, end) = char_offsets_for_lsp_range(line_index, &edit.range);
            out.push(TextEditSpec {
                start,
                end,
                text: edit.new_text,
            });
        }
    }

    out
}

fn primary_selection_char_range(state_manager: &EditorStateManager) -> (usize, usize) {
    let editor = state_manager.editor();
    let line_index = &editor.line_index;

    if let Some(sel) = editor.selection() {
        let a = line_index.position_to_char_offset(sel.start.line, sel.start.column);
        let b = line_index.position_to_char_offset(sel.end.line, sel.end.column);
        return (a.min(b), a.max(b));
    }

    let pos = editor.cursor_position();
    let offset = line_index.position_to_char_offset(pos.line, pos.column);
    (offset, offset)
}

/// Apply a completion item to the editor as a **single undoable step**.
///
/// - For plain-text inserts, uses `EditCommand::ApplyTextEdits`.
/// - For snippet inserts (`insertTextFormat == 2`), uses `EditCommand::ApplySnippet` so the
///   kernel can track placeholders and allow tabstop navigation.
pub fn apply_completion_item(
    state_manager: &mut EditorStateManager,
    item: &Value,
    mode: CompletionTextEditMode,
) -> Result<(), String> {
    let fallback = primary_selection_char_range(state_manager);
    let line_index = &state_manager.editor().line_index;

    if completion_item_insert_text_is_snippet(item) {
        let mut additional_edits: Vec<TextEditSpec> = Vec::new();
        if let Some(additional) = item.get("additionalTextEdits") {
            for edit in text_edits_from_value(additional) {
                let (start, end) = char_offsets_for_lsp_range(line_index, &edit.range);
                additional_edits.push(TextEditSpec {
                    start,
                    end,
                    text: edit.new_text,
                });
            }
        }

        let (start, end, snippet_text) =
            if let Some(edit) = completion_item_main_text_edit_raw(item, mode) {
                let (start, end) = char_offsets_for_lsp_range(line_index, &edit.range);
                (start, end, edit.new_text)
            } else if let Some(text) = completion_item_fallback_insert_text_raw(item) {
                (fallback.0, fallback.1, text)
            } else {
                return Err("completion item 没有可应用的 textEdit / insertText".to_string());
            };

        state_manager
            .execute(Command::Edit(EditCommand::ApplySnippet {
                start,
                end,
                snippet: snippet_text,
                additional_edits,
            }))
            .map(|_| ())
            .map_err(|err| format!("apply completion item 失败: {}", err))
    } else {
        let edits = completion_item_to_text_edit_specs(line_index, item, mode, Some(fallback));

        if edits.is_empty() {
            return Err("completion item 没有可应用的 textEdit / insertText".to_string());
        }

        state_manager
            .execute(Command::Edit(EditCommand::ApplyTextEdits { edits }))
            .map(|_| ())
            .map_err(|err| format!("apply completion item 失败: {}", err))
    }
}

fn completion_item_main_text_edit_raw(
    item: &Value,
    mode: CompletionTextEditMode,
) -> Option<LspTextEdit> {
    let text_edit = item.get("textEdit")?;

    // Standard `TextEdit`: { range, newText }
    if text_edit.get("range").is_some() {
        return LspTextEdit::from_value(text_edit);
    }

    // `InsertReplaceEdit`: { insert, replace, newText }
    let insert_range = text_edit.get("insert").and_then(parse_lsp_range)?;
    let replace_range = text_edit.get("replace").and_then(parse_lsp_range)?;
    let new_text = text_edit.get("newText").and_then(Value::as_str)?;

    let range = match mode {
        CompletionTextEditMode::Insert => insert_range,
        CompletionTextEditMode::Replace => replace_range,
    };

    Some(LspTextEdit {
        range,
        new_text: new_text.to_string(),
    })
}

fn completion_item_fallback_insert_text_raw(item: &Value) -> Option<String> {
    item.get("insertText")
        .and_then(Value::as_str)
        .or_else(|| item.get("label").and_then(Value::as_str))
        .map(str::to_string)
        .filter(|s| !s.is_empty())
}
