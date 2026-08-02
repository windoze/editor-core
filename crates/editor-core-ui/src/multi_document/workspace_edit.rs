use super::{TabEntry, TabId};
use crate::UiError;
use editor_core_lsp::{summarize_workspace_edit, workspace_edit_text_edits};
use serde::Serialize;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet, VecDeque};

const MAX_WORKSPACE_EDIT_TRANSACTION_EVENTS: usize = 256;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct WorkspaceEditTransactionDocument {
    pub uri: String,
    pub edit_count: usize,
    pub has_overlapping_edits: bool,
    pub is_open: bool,
    pub tab_id: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct WorkspaceEditTransactionResult {
    pub mode: String,
    pub applied: bool,
    pub applied_uri: Option<String>,
    pub applied_uris: Vec<String>,
    pub applied_edit_count: usize,
    pub skipped_uris: Vec<String>,
    pub unsupported_operation_uris: Vec<String>,
    pub documents: Vec<WorkspaceEditTransactionDocument>,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct WorkspaceEditTransactionEvent {
    pub sequence: u64,
    pub operation: String,
    pub result: WorkspaceEditTransactionResult,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct WorkspaceEditTransactionEventsSnapshot {
    pub latest_sequence: u64,
    pub events: Vec<WorkspaceEditTransactionEvent>,
}

#[derive(Default)]
pub(crate) struct WorkspaceEditTransactionEventStore {
    next_sequence: u64,
    events: VecDeque<WorkspaceEditTransactionEvent>,
}

impl WorkspaceEditTransactionEventStore {
    pub(crate) fn record(
        &mut self,
        operation: impl Into<String>,
        result: WorkspaceEditTransactionResult,
    ) {
        if self.next_sequence == 0 {
            self.next_sequence = 1;
        }
        let sequence = self.next_sequence;
        self.next_sequence = self.next_sequence.saturating_add(1);
        self.events.push_back(WorkspaceEditTransactionEvent {
            sequence,
            operation: operation.into(),
            result,
        });

        while self.events.len() > MAX_WORKSPACE_EDIT_TRANSACTION_EVENTS {
            self.events.pop_front();
        }
    }

    pub(crate) fn latest_sequence(&self) -> u64 {
        self.next_sequence.saturating_sub(1)
    }

    pub(crate) fn events_after(
        &self,
        after_sequence: u64,
    ) -> WorkspaceEditTransactionEventsSnapshot {
        WorkspaceEditTransactionEventsSnapshot {
            latest_sequence: self.latest_sequence(),
            events: self
                .events
                .iter()
                .filter(|event| event.sequence > after_sequence)
                .cloned()
                .collect(),
        }
    }

    pub(crate) fn events_after_json(&self, after_sequence: u64) -> Result<String, UiError> {
        serde_json::to_string(&self.events_after(after_sequence)).map_err(|err| {
            UiError::Processor(format!(
                "failed to encode workspace edit transaction events: {err}"
            ))
        })
    }
}

pub(super) fn preview(
    tabs: &BTreeMap<TabId, TabEntry>,
    tab_order: &[TabId],
    workspace_edit_json: &str,
) -> Result<WorkspaceEditTransactionResult, UiError> {
    let value = workspace_edit_value(workspace_edit_json)?;
    let plan = transaction_plan(tabs, tab_order, &value);
    Ok(result_from_plan("preview", plan, Vec::new(), 0))
}

pub(super) fn apply(
    tabs: &mut BTreeMap<TabId, TabEntry>,
    tab_order: &[TabId],
    workspace_edit_json: &str,
) -> Result<WorkspaceEditTransactionResult, UiError> {
    let value = workspace_edit_value(workspace_edit_json)?;
    let text_edits_by_uri = workspace_edit_text_edits(&value);
    let mut plan = transaction_plan(tabs, tab_order, &value);
    let mut applied_uris = Vec::<String>::new();
    let mut applied_edit_count = 0usize;

    for doc in &plan.documents {
        if doc.edit_count == 0 || doc.has_overlapping_edits || !doc.is_open {
            continue;
        }
        let Some(edits) = text_edits_by_uri.get(doc.uri.as_str()) else {
            continue;
        };
        let Some(tab_id) = doc.tab_id.map(TabId::from_raw) else {
            continue;
        };
        let tab = tabs
            .get_mut(&tab_id)
            .ok_or_else(|| UiError::Processor(format!("unknown tab id {}", tab_id.get())))?;
        let view = tab.active_view_mut().ok_or_else(|| {
            UiError::Processor(format!("tab {} has no active view", tab_id.get()))
        })?;
        let result_json =
            view.lsp_apply_workspace_edit_json(workspace_edit_json, Some(&doc.uri))?;
        let result: Value = serde_json::from_str(&result_json).map_err(|err| {
            UiError::Processor(format!(
                "failed to decode workspace edit apply result: {err}"
            ))
        })?;
        if result
            .get("applied")
            .and_then(Value::as_bool)
            .unwrap_or(false)
        {
            applied_uris.push(doc.uri.clone());
            applied_edit_count = applied_edit_count.saturating_add(edits.len());
            plan.skipped_uris.remove(doc.uri.as_str());
        } else {
            plan.skipped_uris.insert(doc.uri.clone());
        }
    }

    Ok(result_from_plan(
        "apply",
        plan,
        applied_uris,
        applied_edit_count,
    ))
}

pub(super) fn preview_json(
    tabs: &BTreeMap<TabId, TabEntry>,
    tab_order: &[TabId],
    workspace_edit_json: &str,
) -> Result<String, UiError> {
    encode(preview(tabs, tab_order, workspace_edit_json)?)
}

struct WorkspaceEditTransactionPlan {
    skipped_uris: BTreeSet<String>,
    unsupported_operation_uris: Vec<String>,
    documents: Vec<WorkspaceEditTransactionDocument>,
}

fn workspace_edit_value(workspace_edit_json: &str) -> Result<Value, UiError> {
    serde_json::from_str(workspace_edit_json)
        .map_err(|err| UiError::Processor(format!("failed to decode workspace edit: {err}")))
}

fn transaction_plan(
    tabs: &BTreeMap<TabId, TabEntry>,
    tab_order: &[TabId],
    workspace_edit: &Value,
) -> WorkspaceEditTransactionPlan {
    let edit_summary = summarize_workspace_edit(workspace_edit);
    let unsupported_operation_uris = resource_operation_uris(workspace_edit);
    let mut skipped_uris = BTreeSet::<String>::new();
    let mut documents = edit_summary
        .documents
        .into_iter()
        .map(|doc| {
            let open_tab_id = tab_id_for_uri(tabs, tab_order, doc.uri.as_str());
            if open_tab_id.is_none() || doc.has_overlapping_edits {
                skipped_uris.insert(doc.uri.clone());
            }
            WorkspaceEditTransactionDocument {
                uri: doc.uri,
                edit_count: doc.edit_count,
                has_overlapping_edits: doc.has_overlapping_edits,
                is_open: open_tab_id.is_some(),
                tab_id: open_tab_id.map(TabId::get),
            }
        })
        .collect::<Vec<_>>();

    for uri in &unsupported_operation_uris {
        skipped_uris.insert(uri.clone());
        if !documents.iter().any(|doc| doc.uri == *uri) {
            documents.push(WorkspaceEditTransactionDocument {
                uri: uri.clone(),
                edit_count: 0,
                has_overlapping_edits: false,
                is_open: tab_id_for_uri(tabs, tab_order, uri).is_some(),
                tab_id: tab_id_for_uri(tabs, tab_order, uri).map(TabId::get),
            });
        }
    }
    documents.sort_by(|a, b| a.uri.cmp(&b.uri));

    WorkspaceEditTransactionPlan {
        skipped_uris,
        unsupported_operation_uris,
        documents,
    }
}

fn result_from_plan(
    mode: &str,
    plan: WorkspaceEditTransactionPlan,
    applied_uris: Vec<String>,
    applied_edit_count: usize,
) -> WorkspaceEditTransactionResult {
    WorkspaceEditTransactionResult {
        mode: mode.to_string(),
        applied: !applied_uris.is_empty(),
        applied_uri: applied_uris.first().cloned(),
        applied_uris,
        applied_edit_count,
        skipped_uris: plan.skipped_uris.into_iter().collect(),
        unsupported_operation_uris: plan.unsupported_operation_uris,
        documents: plan.documents,
    }
}

fn encode(result: WorkspaceEditTransactionResult) -> Result<String, UiError> {
    serde_json::to_string(&result).map_err(|err| {
        UiError::Processor(format!(
            "failed to encode workspace edit transaction: {err}"
        ))
    })
}

fn tab_id_for_uri(
    tabs: &BTreeMap<TabId, TabEntry>,
    tab_order: &[TabId],
    uri: &str,
) -> Option<TabId> {
    tab_order.iter().copied().find(|tab_id| {
        tabs.get(tab_id)
            .and_then(|tab| tab.document_uri.as_deref())
            .is_some_and(|document_uri| document_uri == uri)
    })
}

fn resource_operation_uris(workspace_edit: &Value) -> Vec<String> {
    let mut uris = BTreeSet::<String>::new();
    let Some(document_changes) = workspace_edit
        .get("documentChanges")
        .and_then(Value::as_array)
    else {
        return Vec::new();
    };

    for change in document_changes {
        if change.get("textDocument").is_some() && change.get("edits").is_some() {
            continue;
        }
        if let Some(uri) = change.get("uri").and_then(Value::as_str) {
            uris.insert(uri.to_string());
        }
        if let Some(uri) = change.get("oldUri").and_then(Value::as_str) {
            uris.insert(uri.to_string());
        }
        if let Some(uri) = change.get("newUri").and_then(Value::as_str) {
            uris.insert(uri.to_string());
        }
    }

    uris.into_iter().collect()
}
