//! Helpers for parsing LSP code actions (`textDocument/codeAction`).
//!
//! This module parses the common response shapes into a small typed model that higher layers can
//! use for:
//! - listing actions (title/kind/isPreferred)
//! - extracting `WorkspaceEdit` payloads (apply helpers)
//! - extracting optional `Command` payloads (`workspace/executeCommand`)

use serde_json::Value;

/// A minimal representation of an LSP `Command`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LspCommand {
    /// Human-readable title.
    pub title: String,
    /// Command identifier.
    pub command: String,
    /// Optional command arguments.
    pub arguments: Vec<Value>,
}

impl LspCommand {
    /// Parse a `Command`-shaped JSON value.
    pub fn from_value(v: &Value) -> Option<Self> {
        Some(Self {
            title: v.get("title").and_then(Value::as_str)?.to_string(),
            command: v.get("command").and_then(Value::as_str)?.to_string(),
            arguments: v
                .get("arguments")
                .and_then(Value::as_array)
                .cloned()
                .unwrap_or_default(),
        })
    }
}

/// A minimal representation of an LSP `CodeAction`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct LspCodeAction {
    /// Action title.
    pub title: String,
    /// Optional kind (e.g. `"quickfix"`).
    pub kind: Option<String>,
    /// Whether this is marked as preferred by the server.
    pub is_preferred: bool,
    /// Optional `WorkspaceEdit` payload.
    pub edit: Option<Value>,
    /// Optional command payload.
    pub command: Option<LspCommand>,
    /// Optional opaque server data (for resolve).
    pub data: Option<Value>,
}

impl LspCodeAction {
    /// Parse a `CodeAction`-shaped JSON value.
    pub fn from_value(v: &Value) -> Option<Self> {
        Some(Self {
            title: v.get("title").and_then(Value::as_str)?.to_string(),
            kind: v.get("kind").and_then(Value::as_str).map(|s| s.to_string()),
            is_preferred: v
                .get("isPreferred")
                .and_then(Value::as_bool)
                .unwrap_or(false),
            edit: v.get("edit").cloned(),
            command: v.get("command").and_then(LspCommand::from_value),
            data: v.get("data").cloned(),
        })
    }
}

/// A normalized code-action response item (`CodeAction | Command`).
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum LspCodeActionItem {
    /// Full `CodeAction` object.
    CodeAction(LspCodeAction),
    /// Legacy `Command` object.
    Command(LspCommand),
}

/// Parse a `CodeAction[] | null` response payload.
pub fn code_action_items_from_value(value: &Value) -> Vec<LspCodeActionItem> {
    let Some(arr) = value.as_array() else {
        return Vec::new();
    };

    arr.iter()
        .filter_map(|item| {
            // Heuristic: `CodeAction` must have `title`, and usually has `kind` or `edit` or `command`.
            // `Command` must have `title` + `command`.
            if item.get("edit").is_some() || item.get("kind").is_some() || item.get("data").is_some()
            {
                return LspCodeAction::from_value(item).map(LspCodeActionItem::CodeAction);
            }
            LspCommand::from_value(item).map(LspCodeActionItem::Command)
        })
        .collect()
}

/// Plan extracted from a code action item for application.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct ApplyCodeActionPlan {
    /// Optional workspace edit to apply locally.
    pub edit: Option<Value>,
    /// Optional command to execute via `workspace/executeCommand`.
    pub command: Option<LspCommand>,
}

/// Extract an "apply plan" from a code action item.
pub fn apply_plan_for_code_action_item(item: &LspCodeActionItem) -> ApplyCodeActionPlan {
    match item {
        LspCodeActionItem::CodeAction(action) => ApplyCodeActionPlan {
            edit: action.edit.clone(),
            command: action.command.clone(),
        },
        LspCodeActionItem::Command(cmd) => ApplyCodeActionPlan {
            edit: None,
            command: Some(cmd.clone()),
        },
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn parse_code_action_list_with_mixed_items() {
        let v = json!([
            { "title": "Fix", "kind": "quickfix", "isPreferred": true, "edit": { "changes": {} } },
            { "title": "Do", "command": "workspace.do", "arguments": [1] }
        ]);
        let items = code_action_items_from_value(&v);
        assert_eq!(items.len(), 2);

        match &items[0] {
            LspCodeActionItem::CodeAction(a) => {
                assert_eq!(a.title, "Fix");
                assert!(a.is_preferred);
                assert!(a.edit.is_some());
            }
            _ => panic!("expected code action"),
        }

        match &items[1] {
            LspCodeActionItem::Command(c) => {
                assert_eq!(c.command, "workspace.do");
                assert_eq!(c.arguments.len(), 1);
            }
            _ => panic!("expected command"),
        }
    }
}

