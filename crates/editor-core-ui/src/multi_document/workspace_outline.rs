use super::{TabEntry, TabId};
use crate::UiError;
use serde::Serialize;
use serde_json::Value;
use std::collections::BTreeMap;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct WorkspaceOutlineDocument {
    pub tab_id: u64,
    pub view_index: usize,
    pub document_uri: Option<String>,
    pub title: Option<String>,
    pub symbol_count: usize,
    pub symbols: Vec<Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct WorkspaceOutlineSnapshot {
    pub documents: Vec<WorkspaceOutlineDocument>,
}

pub(super) fn snapshot(
    tabs: &BTreeMap<TabId, TabEntry>,
    tab_order: &[TabId],
) -> Result<WorkspaceOutlineSnapshot, UiError> {
    let mut documents = Vec::new();
    for tab_id in tab_order.iter().copied().filter(|id| tabs.contains_key(id)) {
        let Some(tab) = tabs.get(&tab_id) else {
            continue;
        };
        let Some(view) = tab.active_view() else {
            continue;
        };
        let value: Value = serde_json::from_str(&view.document_symbols_json()?).map_err(|err| {
            UiError::Processor(format!(
                "failed to decode tab {} document symbols: {err}",
                tab_id.get()
            ))
        })?;
        let symbols = value
            .get("symbols")
            .and_then(Value::as_array)
            .cloned()
            .unwrap_or_default();
        documents.push(WorkspaceOutlineDocument {
            tab_id: tab_id.get(),
            view_index: tab.active_view,
            document_uri: tab.document_uri.clone(),
            title: tab.title.clone(),
            symbol_count: symbols.iter().map(symbol_tree_count).sum(),
            symbols,
        });
    }
    Ok(WorkspaceOutlineSnapshot { documents })
}

pub(super) fn snapshot_json(
    tabs: &BTreeMap<TabId, TabEntry>,
    tab_order: &[TabId],
) -> Result<String, UiError> {
    serde_json::to_string(&snapshot(tabs, tab_order)?)
        .map_err(|err| UiError::Processor(format!("failed to encode workspace outline: {err}")))
}

fn symbol_tree_count(symbol: &Value) -> usize {
    1 + symbol
        .get("children")
        .and_then(Value::as_array)
        .map(|children| children.iter().map(symbol_tree_count).sum())
        .unwrap_or(0)
}
