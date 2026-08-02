use super::{TabEntry, TabId};
use crate::{EditorUi, UiError};
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
    pub applied_resource_operation_count: usize,
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
    Ok(result_from_plan("preview", plan, Vec::new(), 0, 0))
}

pub(super) fn apply(
    tabs: &mut BTreeMap<TabId, TabEntry>,
    tab_order: &mut Vec<TabId>,
    active_tab: &mut Option<TabId>,
    preview_tab: &mut Option<TabId>,
    workspace_edit_json: &str,
) -> Result<WorkspaceEditTransactionResult, UiError> {
    let value = workspace_edit_value(workspace_edit_json)?;
    let text_edits_by_uri = workspace_edit_text_edits(&value);
    let mut plan = transaction_plan(tabs, tab_order, &value);
    let mut applied_uris = BTreeSet::<String>::new();
    let mut applied_edit_count = 0usize;
    let mut applied_resource_operation_count = 0usize;

    for operation in plan.resource_operations.clone() {
        if !operation.supported {
            continue;
        }

        match apply_resource_operation(tabs, tab_order, active_tab, preview_tab, &operation.op)? {
            ResourceOperationApplyOutcome::Applied => {
                applied_resource_operation_count =
                    applied_resource_operation_count.saturating_add(1);
                for uri in operation.op.affected_uris() {
                    plan.skipped_uris.remove(uri.as_str());
                    applied_uris.insert(uri);
                }
            }
            ResourceOperationApplyOutcome::Noop => {
                for uri in operation.op.affected_uris() {
                    plan.skipped_uris.remove(uri.as_str());
                }
            }
            ResourceOperationApplyOutcome::Skipped => {
                for uri in operation.op.affected_uris() {
                    plan.skipped_uris.insert(uri);
                }
            }
        }
    }

    for doc in &mut plan.documents {
        let open_tab_id = tab_id_for_uri(tabs, tab_order, doc.uri.as_str());
        doc.is_open = open_tab_id.is_some();
        doc.tab_id = open_tab_id.map(TabId::get);

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
            applied_uris.insert(doc.uri.clone());
            applied_edit_count = applied_edit_count.saturating_add(edits.len());
            plan.skipped_uris.remove(doc.uri.as_str());
        } else {
            plan.skipped_uris.insert(doc.uri.clone());
        }
    }

    for doc in &mut plan.documents {
        let open_tab_id = tab_id_for_uri(tabs, tab_order, doc.uri.as_str());
        doc.is_open = open_tab_id.is_some();
        doc.tab_id = open_tab_id.map(TabId::get);
    }

    Ok(result_from_plan(
        "apply",
        plan,
        applied_uris.into_iter().collect(),
        applied_edit_count,
        applied_resource_operation_count,
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
    resource_operations: Vec<PlannedResourceOperation>,
    documents: Vec<WorkspaceEditTransactionDocument>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct PlannedResourceOperation {
    op: ResourceOperation,
    supported: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum ResourceOperation {
    Create {
        uri: String,
        overwrite: bool,
        ignore_if_exists: bool,
    },
    Rename {
        old_uri: String,
        new_uri: String,
        overwrite: bool,
        ignore_if_exists: bool,
    },
    Delete {
        uri: String,
        recursive: bool,
        ignore_if_not_exists: bool,
    },
}

impl ResourceOperation {
    fn affected_uris(&self) -> Vec<String> {
        match self {
            Self::Create { uri, .. } | Self::Delete { uri, .. } => vec![uri.clone()],
            Self::Rename {
                old_uri, new_uri, ..
            } => {
                if old_uri == new_uri {
                    vec![old_uri.clone()]
                } else {
                    vec![old_uri.clone(), new_uri.clone()]
                }
            }
        }
    }
}

enum ResourceOperationApplyOutcome {
    Applied,
    Noop,
    Skipped,
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
    let mut open_tabs_by_uri = open_tabs_by_uri(tabs, tab_order);
    let mut unsupported_operation_uris = BTreeSet::<String>::new();
    let mut skipped_uris = BTreeSet::<String>::new();
    let resource_operations = resource_operations(workspace_edit)
        .into_iter()
        .map(|op| {
            let supported = resource_operation_supported(tabs, &open_tabs_by_uri, &op);
            if supported {
                simulate_resource_operation(&mut open_tabs_by_uri, &op);
            } else {
                for uri in op.affected_uris() {
                    unsupported_operation_uris.insert(uri.clone());
                    skipped_uris.insert(uri);
                }
            }
            PlannedResourceOperation { op, supported }
        })
        .collect::<Vec<_>>();

    let mut documents = edit_summary
        .documents
        .into_iter()
        .map(|doc| {
            let open_tab_id = open_tabs_by_uri.get(doc.uri.as_str()).copied();
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
        if !documents.iter().any(|doc| doc.uri == *uri) {
            documents.push(WorkspaceEditTransactionDocument {
                uri: uri.clone(),
                edit_count: 0,
                has_overlapping_edits: false,
                is_open: open_tabs_by_uri.contains_key(uri),
                tab_id: open_tabs_by_uri.get(uri).copied().map(TabId::get),
            });
        }
    }
    for operation in &resource_operations {
        if !operation.supported {
            continue;
        }
        for uri in operation.op.affected_uris() {
            if !documents.iter().any(|doc| doc.uri == uri) {
                documents.push(WorkspaceEditTransactionDocument {
                    edit_count: 0,
                    has_overlapping_edits: false,
                    is_open: open_tabs_by_uri.contains_key(uri.as_str()),
                    tab_id: open_tabs_by_uri.get(uri.as_str()).copied().map(TabId::get),
                    uri,
                });
            }
        }
    }
    documents.sort_by(|a, b| a.uri.cmp(&b.uri));

    WorkspaceEditTransactionPlan {
        skipped_uris,
        unsupported_operation_uris: unsupported_operation_uris.into_iter().collect(),
        resource_operations,
        documents,
    }
}

fn result_from_plan(
    mode: &str,
    plan: WorkspaceEditTransactionPlan,
    applied_uris: Vec<String>,
    applied_edit_count: usize,
    applied_resource_operation_count: usize,
) -> WorkspaceEditTransactionResult {
    WorkspaceEditTransactionResult {
        mode: mode.to_string(),
        applied: applied_edit_count > 0 || applied_resource_operation_count > 0,
        applied_uri: applied_uris.first().cloned(),
        applied_uris,
        applied_edit_count,
        applied_resource_operation_count,
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

fn open_tabs_by_uri(
    tabs: &BTreeMap<TabId, TabEntry>,
    tab_order: &[TabId],
) -> BTreeMap<String, TabId> {
    let mut out = BTreeMap::new();
    for tab_id in tab_order.iter().copied() {
        let Some(uri) = tabs
            .get(&tab_id)
            .and_then(|tab| tab.document_uri.as_deref())
        else {
            continue;
        };
        out.entry(uri.to_string()).or_insert(tab_id);
    }
    out
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

fn resource_operations(workspace_edit: &Value) -> Vec<ResourceOperation> {
    let mut out = Vec::new();
    let Some(document_changes) = workspace_edit
        .get("documentChanges")
        .and_then(Value::as_array)
    else {
        return out;
    };

    for change in document_changes {
        if change.get("textDocument").is_some() && change.get("edits").is_some() {
            continue;
        }

        let kind = change.get("kind").and_then(Value::as_str);
        let options = change.get("options");
        match kind {
            Some("create") => {
                if let Some(uri) = change.get("uri").and_then(Value::as_str) {
                    out.push(ResourceOperation::Create {
                        uri: uri.to_string(),
                        overwrite: option_bool(options, "overwrite"),
                        ignore_if_exists: option_bool(options, "ignoreIfExists"),
                    });
                }
            }
            Some("rename") => {
                if let (Some(old_uri), Some(new_uri)) = (
                    change.get("oldUri").and_then(Value::as_str),
                    change.get("newUri").and_then(Value::as_str),
                ) {
                    out.push(ResourceOperation::Rename {
                        old_uri: old_uri.to_string(),
                        new_uri: new_uri.to_string(),
                        overwrite: option_bool(options, "overwrite"),
                        ignore_if_exists: option_bool(options, "ignoreIfExists"),
                    });
                }
            }
            Some("delete") => {
                if let Some(uri) = change.get("uri").and_then(Value::as_str) {
                    out.push(ResourceOperation::Delete {
                        uri: uri.to_string(),
                        recursive: option_bool(options, "recursive"),
                        ignore_if_not_exists: option_bool(options, "ignoreIfNotExists"),
                    });
                }
            }
            _ => {}
        }
    }

    out
}

fn option_bool(options: Option<&Value>, key: &str) -> bool {
    options
        .and_then(|options| options.get(key))
        .and_then(Value::as_bool)
        .unwrap_or(false)
}

fn resource_operation_supported(
    tabs: &BTreeMap<TabId, TabEntry>,
    open_tabs_by_uri: &BTreeMap<String, TabId>,
    operation: &ResourceOperation,
) -> bool {
    match operation {
        ResourceOperation::Create {
            uri,
            overwrite,
            ignore_if_exists,
        } => {
            let Some(tab_id) = open_tabs_by_uri.get(uri.as_str()).copied() else {
                return false;
            };
            *ignore_if_exists || (*overwrite && !tab_is_modified(tabs, tab_id))
        }
        ResourceOperation::Rename {
            old_uri,
            new_uri,
            overwrite: _,
            ignore_if_exists,
        } => {
            let Some(old_tab_id) = open_tabs_by_uri.get(old_uri.as_str()).copied() else {
                return false;
            };
            if old_uri == new_uri {
                return true;
            }
            let target_tab_id = open_tabs_by_uri.get(new_uri.as_str()).copied();
            target_tab_id.is_none() || target_tab_id == Some(old_tab_id) || *ignore_if_exists
        }
        ResourceOperation::Delete { uri, .. } => {
            let Some(tab_id) = open_tabs_by_uri.get(uri.as_str()).copied() else {
                return false;
            };
            !tab_is_modified(tabs, tab_id)
        }
    }
}

fn tab_is_modified(tabs: &BTreeMap<TabId, TabEntry>, tab_id: TabId) -> bool {
    tabs.get(&tab_id)
        .and_then(TabEntry::active_view)
        .is_some_and(EditorUi::is_modified)
}

fn simulate_resource_operation(
    open_tabs_by_uri: &mut BTreeMap<String, TabId>,
    operation: &ResourceOperation,
) {
    match operation {
        ResourceOperation::Create { .. } => {}
        ResourceOperation::Rename {
            old_uri, new_uri, ..
        } => {
            if old_uri == new_uri {
                return;
            }
            if let Some(tab_id) = open_tabs_by_uri.remove(old_uri.as_str()) {
                open_tabs_by_uri.insert(new_uri.clone(), tab_id);
            }
        }
        ResourceOperation::Delete { uri, .. } => {
            open_tabs_by_uri.remove(uri.as_str());
        }
    }
}

fn apply_resource_operation(
    tabs: &mut BTreeMap<TabId, TabEntry>,
    tab_order: &mut Vec<TabId>,
    active_tab: &mut Option<TabId>,
    preview_tab: &mut Option<TabId>,
    operation: &ResourceOperation,
) -> Result<ResourceOperationApplyOutcome, UiError> {
    match operation {
        ResourceOperation::Create {
            uri,
            overwrite,
            ignore_if_exists,
        } => {
            let Some(tab_id) = tab_id_for_uri(tabs, tab_order, uri.as_str()) else {
                return Ok(ResourceOperationApplyOutcome::Skipped);
            };
            if *ignore_if_exists {
                return Ok(ResourceOperationApplyOutcome::Noop);
            }
            if !*overwrite || tab_is_modified(tabs, tab_id) {
                return Ok(ResourceOperationApplyOutcome::Skipped);
            }
            replace_open_tab_text(tabs, tab_id, "", true)?;
            Ok(ResourceOperationApplyOutcome::Applied)
        }
        ResourceOperation::Rename {
            old_uri,
            new_uri,
            ignore_if_exists,
            ..
        } => {
            let Some(tab_id) = tab_id_for_uri(tabs, tab_order, old_uri.as_str()) else {
                return Ok(ResourceOperationApplyOutcome::Skipped);
            };
            if old_uri == new_uri {
                return Ok(ResourceOperationApplyOutcome::Noop);
            }
            if tab_id_for_uri(tabs, tab_order, new_uri.as_str()).is_some() {
                return if *ignore_if_exists {
                    Ok(ResourceOperationApplyOutcome::Noop)
                } else {
                    Ok(ResourceOperationApplyOutcome::Skipped)
                };
            }
            let tab = tabs
                .get_mut(&tab_id)
                .ok_or_else(|| UiError::Processor(format!("unknown tab id {}", tab_id.get())))?;
            tab.document_uri = Some(new_uri.clone());
            Ok(ResourceOperationApplyOutcome::Applied)
        }
        ResourceOperation::Delete {
            uri,
            ignore_if_not_exists,
            recursive: _,
        } => {
            let Some(tab_id) = tab_id_for_uri(tabs, tab_order, uri.as_str()) else {
                return if *ignore_if_not_exists {
                    Ok(ResourceOperationApplyOutcome::Noop)
                } else {
                    Ok(ResourceOperationApplyOutcome::Skipped)
                };
            };
            if tab_is_modified(tabs, tab_id) {
                return Ok(ResourceOperationApplyOutcome::Skipped);
            }
            close_tab(tabs, tab_order, active_tab, preview_tab, tab_id);
            Ok(ResourceOperationApplyOutcome::Applied)
        }
    }
}

fn replace_open_tab_text(
    tabs: &mut BTreeMap<TabId, TabEntry>,
    tab_id: TabId,
    text: &str,
    mark_saved: bool,
) -> Result<(), UiError> {
    let tab = tabs
        .get_mut(&tab_id)
        .ok_or_else(|| UiError::Processor(format!("unknown tab id {}", tab_id.get())))?;
    let view = tab
        .active_view_mut()
        .ok_or_else(|| UiError::Processor("tab has no views".to_string()))?;
    let length = view.text().chars().count();
    let text_json = serde_json::to_string(text)
        .map_err(|err| UiError::Processor(format!("failed to encode replacement text: {err}")))?;
    let command_json = format!(
        r#"{{"kind":"edit","op":"replace","start":0,"length":{},"text":{}}}"#,
        length, text_json
    );
    view.execute_command_json(command_json.as_str())?;
    if mark_saved {
        view.mark_saved();
    }
    Ok(())
}

fn close_tab(
    tabs: &mut BTreeMap<TabId, TabEntry>,
    tab_order: &mut Vec<TabId>,
    active_tab: &mut Option<TabId>,
    preview_tab: &mut Option<TabId>,
    tab_id: TabId,
) -> bool {
    let closed_pos = tab_order.iter().position(|id| *id == tab_id);
    let existed = tabs.remove(&tab_id).is_some();

    if existed {
        tab_order.retain(|id| *id != tab_id);
    }

    if existed && *active_tab == Some(tab_id) {
        *active_tab = closed_pos
            .and_then(|idx| tab_order.get(idx).copied())
            .or_else(|| {
                closed_pos
                    .and_then(|idx| idx.checked_sub(1))
                    .and_then(|idx| tab_order.get(idx).copied())
            })
            .or_else(|| tab_order.first().copied());
    }

    if existed && *preview_tab == Some(tab_id) {
        *preview_tab = None;
    }

    existed
}
