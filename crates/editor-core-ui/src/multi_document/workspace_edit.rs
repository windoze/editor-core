use super::{TabEntry, TabId};
use crate::{EditorUi, UiError};
use editor_core::LineIndex;
use editor_core_lsp::{
    LspTextEdit, char_offsets_for_lsp_range, file_uri_to_path, summarize_workspace_edit,
    text_edits_from_value, workspace_edit_expected_versions,
};
use serde::Serialize;
use serde_json::Value;
use std::collections::{BTreeMap, BTreeSet, VecDeque};
use std::fs;
use std::path::{Component, Path, PathBuf};

const MAX_WORKSPACE_EDIT_TRANSACTION_EVENTS: usize = 256;

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct WorkspaceEditTransactionDocument {
    pub uri: String,
    pub edit_count: usize,
    pub has_overlapping_edits: bool,
    pub expected_version: Option<i32>,
    pub actual_version: Option<u64>,
    pub version_mismatch: bool,
    pub is_open: bool,
    pub is_dirty: bool,
    pub tab_id: Option<u64>,
}

#[derive(Debug, Clone, PartialEq, Eq, PartialOrd, Ord, Serialize)]
pub struct WorkspaceEditTransactionSkippedDetail {
    pub uri: String,
    pub reason: String,
    pub operation: Option<String>,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct WorkspaceEditTransactionConflict {
    pub uri: String,
    pub kind: String,
    pub reason: String,
    pub operation: Option<String>,
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct WorkspaceEditTransactionResourceOperation {
    pub kind: String,
    pub uri: Option<String>,
    pub old_uri: Option<String>,
    pub new_uri: Option<String>,
    pub affected_uris: Vec<String>,
    pub supported: bool,
    pub applied: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct WorkspaceEditTransactionResult {
    pub mode: String,
    pub apply_mode: String,
    pub applied: bool,
    pub applied_uri: Option<String>,
    pub applied_uris: Vec<String>,
    pub applied_edit_count: usize,
    pub applied_resource_operation_count: usize,
    pub resource_operations: Vec<WorkspaceEditTransactionResourceOperation>,
    pub dirty_document_uris: Vec<String>,
    pub conflicts: Vec<WorkspaceEditTransactionConflict>,
    pub skipped_uris: Vec<String>,
    pub skipped_details: Vec<WorkspaceEditTransactionSkippedDetail>,
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

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct WorkspaceEditTransactionUndoResult {
    pub undone: bool,
    pub restored_uris: Vec<String>,
    pub restored_open_tab_count: usize,
    pub restored_filesystem_entry_count: usize,
    pub message: String,
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

pub(super) struct WorkspaceEditTransactionApplyResult {
    pub result: WorkspaceEditTransactionResult,
    pub undo_record: Option<WorkspaceEditTransactionUndoRecord>,
}

pub(super) struct WorkspaceEditTransactionUndoRecord {
    open_tab_rollback: OpenTabRollback,
    filesystem_rollback: FilesystemRollback,
    restored_uris: Vec<String>,
    restored_open_tab_count: usize,
    restored_filesystem_entry_count: usize,
}

impl WorkspaceEditTransactionUndoRecord {
    fn new(
        open_tab_rollback: OpenTabRollback,
        filesystem_rollback: FilesystemRollback,
        restored_uris: Vec<String>,
    ) -> Self {
        let restored_open_tab_count = open_tab_rollback.affected_tab_count();
        let restored_filesystem_entry_count = filesystem_rollback.entry_count();
        Self {
            open_tab_rollback,
            filesystem_rollback,
            restored_uris,
            restored_open_tab_count,
            restored_filesystem_entry_count,
        }
    }

    pub(super) fn discard(mut self) -> Result<(), UiError> {
        self.filesystem_rollback.cleanup_backups()
    }

    pub(super) fn undo(
        &mut self,
        tabs: &mut BTreeMap<TabId, TabEntry>,
        tab_order: &mut Vec<TabId>,
        active_tab: &mut Option<TabId>,
        preview_tab: &mut Option<TabId>,
    ) -> Result<WorkspaceEditTransactionUndoResult, UiError> {
        let filesystem_result = self.filesystem_rollback.rollback();
        let open_tab_result = if self.open_tab_rollback.has_entries() {
            self.open_tab_rollback
                .rollback(tabs, tab_order, active_tab, preview_tab)
        } else {
            Ok(())
        };

        match (filesystem_result, open_tab_result) {
            (Ok(()), Ok(())) => Ok(WorkspaceEditTransactionUndoResult {
                undone: true,
                restored_uris: self.restored_uris.clone(),
                restored_open_tab_count: self.restored_open_tab_count,
                restored_filesystem_entry_count: self.restored_filesystem_entry_count,
                message: "workspace edit transaction was undone".to_string(),
            }),
            (Err(filesystem_err), Ok(())) => Err(UiError::Processor(format!(
                "failed to undo WorkspaceEdit filesystem changes: {filesystem_err}; open tab state was restored"
            ))),
            (Ok(()), Err(open_tab_err)) => Err(UiError::Processor(format!(
                "WorkspaceEdit filesystem changes were undone; failed to restore open tab state: {open_tab_err}"
            ))),
            (Err(filesystem_err), Err(open_tab_err)) => Err(UiError::Processor(format!(
                "failed to undo WorkspaceEdit filesystem changes: {filesystem_err}; failed to restore open tab state: {open_tab_err}"
            ))),
        }
    }
}

impl Drop for WorkspaceEditTransactionUndoRecord {
    fn drop(&mut self) {
        let _ = self.filesystem_rollback.cleanup_backups();
    }
}

pub(super) fn undo_unavailable_result() -> WorkspaceEditTransactionUndoResult {
    WorkspaceEditTransactionUndoResult {
        undone: false,
        restored_uris: Vec::new(),
        restored_open_tab_count: 0,
        restored_filesystem_entry_count: 0,
        message: "no WorkspaceEdit transaction undo record is available".to_string(),
    }
}

pub(super) fn preview(
    tabs: &BTreeMap<TabId, TabEntry>,
    tab_order: &[TabId],
    workspace_roots: &[String],
    workspace_edit_json: &str,
) -> Result<WorkspaceEditTransactionResult, UiError> {
    let input = workspace_edit_input(workspace_edit_json)?;
    let plan = transaction_plan(tabs, tab_order, workspace_roots, &input.workspace_edit);
    Ok(result_from_plan(
        "preview",
        input.apply_mode,
        plan,
        Vec::new(),
        0,
        0,
    ))
}

pub(super) fn apply(
    tabs: &mut BTreeMap<TabId, TabEntry>,
    tab_order: &mut Vec<TabId>,
    active_tab: &mut Option<TabId>,
    preview_tab: &mut Option<TabId>,
    workspace_roots: &[String],
    workspace_edit_json: &str,
) -> Result<WorkspaceEditTransactionApplyResult, UiError> {
    let input = workspace_edit_input(workspace_edit_json)?;
    let steps = workspace_edit_steps(&input.workspace_edit);
    let mut plan = transaction_plan(tabs, tab_order, workspace_roots, &input.workspace_edit);
    if input.apply_mode == WorkspaceEditApplyMode::Atomic
        && (!plan.skipped_uris.is_empty() || !plan.unsupported_operation_uris.is_empty())
    {
        return Ok(WorkspaceEditTransactionApplyResult {
            result: result_from_plan("apply", input.apply_mode, plan, Vec::new(), 0, 0),
            undo_record: None,
        });
    }
    let mut applied_uris = BTreeSet::<String>::new();
    let mut applied_edit_count = 0usize;
    let mut applied_resource_operation_count = 0usize;
    let unopened_file_text_edit_uris = plan.unopened_file_text_edit_uris.clone();
    let mut planned_resource_operations = VecDeque::from(plan.resource_operations.clone());
    let mut resource_operation_index = 0usize;
    let mut runtime_blocked_text_edit_uris = BTreeSet::<String>::new();
    let mut runtime_removed_text_edit_uris = BTreeSet::<String>::new();
    let mut filesystem_rollback = FilesystemRollback::default();
    let mut open_tab_rollback = OpenTabRollback::default();

    for step in steps {
        match step {
            WorkspaceEditStep::Resource(operation) => {
                let plan_index = resource_operation_index;
                resource_operation_index = resource_operation_index.saturating_add(1);
                let planned_operation = planned_resource_operations.pop_front();
                if !planned_operation
                    .as_ref()
                    .is_some_and(|planned| planned.op == operation && planned.supported)
                {
                    for uri in operation.affected_uris() {
                        runtime_blocked_text_edit_uris.insert(uri);
                    }
                    continue;
                }

                let resource_outcome = match apply_resource_operation(
                    tabs,
                    tab_order,
                    active_tab,
                    preview_tab,
                    workspace_roots,
                    &mut filesystem_rollback,
                    &mut open_tab_rollback,
                    &operation,
                ) {
                    Ok(outcome) => outcome,
                    Err(err) => {
                        let rollback_result = filesystem_rollback.rollback();
                        let had_open_tab_rollback = open_tab_rollback.has_entries();
                        let open_tab_rollback_result = if had_open_tab_rollback {
                            open_tab_rollback.rollback(tabs, tab_order, active_tab, preview_tab)
                        } else {
                            Ok(())
                        };
                        return Err(resource_operation_error_with_rollbacks(
                            err,
                            rollback_result,
                            open_tab_rollback_result,
                            had_open_tab_rollback,
                        ));
                    }
                };

                match resource_outcome {
                    ResourceOperationApplyOutcome::Applied => {
                        if let Some(planned_operation) =
                            plan.resource_operations.get_mut(plan_index)
                        {
                            planned_operation.applied = true;
                        }
                        applied_resource_operation_count =
                            applied_resource_operation_count.saturating_add(1);
                        for uri in operation.affected_uris() {
                            applied_uris.insert(uri);
                        }
                        for uri in operation.removed_uris() {
                            runtime_removed_text_edit_uris.insert(uri);
                        }
                        for uri in operation.produced_uris() {
                            runtime_blocked_text_edit_uris.remove(uri.as_str());
                            runtime_removed_text_edit_uris.remove(uri.as_str());
                        }
                    }
                    ResourceOperationApplyOutcome::Noop => {
                        for uri in operation.produced_uris() {
                            runtime_blocked_text_edit_uris.remove(uri.as_str());
                            runtime_removed_text_edit_uris.remove(uri.as_str());
                        }
                    }
                    ResourceOperationApplyOutcome::Skipped => {
                        let open_tabs_by_uri = open_tabs_by_uri(tabs, tab_order);
                        let details = resource_operation_skip_details(
                            tabs,
                            &open_tabs_by_uri,
                            workspace_roots,
                            &operation,
                        );
                        if details.is_empty() {
                            for uri in operation.affected_uris() {
                                mark_skipped(
                                    &mut plan.skipped_uris,
                                    &mut plan.skipped_details,
                                    skipped_detail(
                                        uri,
                                        "resource_operation_apply_skipped",
                                        Some(operation.kind()),
                                        "resource operation was skipped during apply",
                                    ),
                                );
                            }
                        } else {
                            for detail in details {
                                mark_skipped(
                                    &mut plan.skipped_uris,
                                    &mut plan.skipped_details,
                                    detail,
                                );
                            }
                        }
                        if input.apply_mode == WorkspaceEditApplyMode::Atomic {
                            return atomic_apply_runtime_failure_result(
                                tabs,
                                tab_order,
                                active_tab,
                                preview_tab,
                                &mut filesystem_rollback,
                                &mut open_tab_rollback,
                                input.apply_mode,
                                plan,
                            );
                        }
                        for uri in operation.affected_uris() {
                            runtime_blocked_text_edit_uris.insert(uri);
                        }
                    }
                }
            }
            WorkspaceEditStep::TextEdits { uri, edits } => {
                if edits.is_empty() {
                    continue;
                }
                if runtime_removed_text_edit_uris.contains(uri.as_str()) {
                    mark_skipped(
                        &mut plan.skipped_uris,
                        &mut plan.skipped_details,
                        skipped_detail(
                            uri,
                            "resource_operation_dependency_removed",
                            Some("text_edit"),
                            "text edits for this URI are blocked because a preceding resource operation removes the target",
                        ),
                    );
                    if input.apply_mode == WorkspaceEditApplyMode::Atomic {
                        return atomic_apply_runtime_failure_result(
                            tabs,
                            tab_order,
                            active_tab,
                            preview_tab,
                            &mut filesystem_rollback,
                            &mut open_tab_rollback,
                            input.apply_mode,
                            plan,
                        );
                    }
                    continue;
                }
                if runtime_blocked_text_edit_uris.contains(uri.as_str()) {
                    mark_skipped(
                        &mut plan.skipped_uris,
                        &mut plan.skipped_details,
                        skipped_detail(
                            uri,
                            "resource_operation_dependency_skipped",
                            Some("text_edit"),
                            "text edits for this URI are blocked because a preceding resource operation did not apply",
                        ),
                    );
                    if input.apply_mode == WorkspaceEditApplyMode::Atomic {
                        return atomic_apply_runtime_failure_result(
                            tabs,
                            tab_order,
                            active_tab,
                            preview_tab,
                            &mut filesystem_rollback,
                            &mut open_tab_rollback,
                            input.apply_mode,
                            plan,
                        );
                    }
                    continue;
                }
                if text_edit_has_preflight_block(&plan, uri.as_str()) {
                    continue;
                }
                let Some(document) = plan.documents.iter().find(|doc| doc.uri == uri) else {
                    continue;
                };
                if document.edit_count == 0
                    || document.has_overlapping_edits
                    || document.version_mismatch
                {
                    continue;
                }

                if let Some(tab_id) = tab_id_for_uri(tabs, tab_order, uri.as_str()) {
                    match apply_open_tab_text_edits(
                        tabs,
                        tab_order,
                        *active_tab,
                        *preview_tab,
                        &mut open_tab_rollback,
                        tab_id,
                        &edits,
                    ) {
                        Ok(true) => {
                            applied_uris.insert(uri.clone());
                            applied_edit_count = applied_edit_count.saturating_add(edits.len());
                            clear_text_edit_skipped_uri(&mut plan, uri.as_str());
                        }
                        Ok(false) => {}
                        Err(err) => {
                            mark_skipped(
                                &mut plan.skipped_uris,
                                &mut plan.skipped_details,
                                skipped_detail(
                                    uri,
                                    "text_edit_apply_failed",
                                    Some("text_edit"),
                                    format!("open tab text edit apply failed: {err}"),
                                ),
                            );
                            if input.apply_mode == WorkspaceEditApplyMode::Atomic {
                                return atomic_apply_runtime_failure_result(
                                    tabs,
                                    tab_order,
                                    active_tab,
                                    preview_tab,
                                    &mut filesystem_rollback,
                                    &mut open_tab_rollback,
                                    input.apply_mode,
                                    plan,
                                );
                            }
                        }
                    }
                    continue;
                }

                if !unopened_file_text_edit_uris.contains(uri.as_str()) {
                    continue;
                }
                match apply_unopened_file_text_edits(
                    workspace_roots,
                    &mut filesystem_rollback,
                    uri.as_str(),
                    &edits,
                ) {
                    Ok(()) => {
                        applied_uris.insert(uri.clone());
                        applied_edit_count = applied_edit_count.saturating_add(edits.len());
                        clear_text_edit_skipped_uri(&mut plan, uri.as_str());
                    }
                    Err(detail) => {
                        mark_skipped(&mut plan.skipped_uris, &mut plan.skipped_details, detail);
                        if input.apply_mode == WorkspaceEditApplyMode::Atomic {
                            return atomic_apply_runtime_failure_result(
                                tabs,
                                tab_order,
                                active_tab,
                                preview_tab,
                                &mut filesystem_rollback,
                                &mut open_tab_rollback,
                                input.apply_mode,
                                plan,
                            );
                        }
                    }
                }
            }
        }
    }

    for doc in &mut plan.documents {
        let open_tab_id = tab_id_for_uri(tabs, tab_order, doc.uri.as_str());
        doc.is_open = open_tab_id.is_some();
        doc.is_dirty = open_tab_id.is_some_and(|tab_id| tab_is_modified(tabs, tab_id));
        doc.tab_id = open_tab_id.map(TabId::get);
    }

    let result = result_from_plan(
        "apply",
        input.apply_mode,
        plan,
        applied_uris.into_iter().collect(),
        applied_edit_count,
        applied_resource_operation_count,
    );
    let undo_record = if result.applied
        && (open_tab_rollback.has_entries() || filesystem_rollback.has_entries())
    {
        Some(WorkspaceEditTransactionUndoRecord::new(
            open_tab_rollback,
            filesystem_rollback,
            result.applied_uris.clone(),
        ))
    } else {
        filesystem_rollback.commit()?;
        None
    };

    Ok(WorkspaceEditTransactionApplyResult {
        result,
        undo_record,
    })
}

pub(super) fn preview_json(
    tabs: &BTreeMap<TabId, TabEntry>,
    tab_order: &[TabId],
    workspace_roots: &[String],
    workspace_edit_json: &str,
) -> Result<String, UiError> {
    encode(preview(
        tabs,
        tab_order,
        workspace_roots,
        workspace_edit_json,
    )?)
}

struct WorkspaceEditTransactionPlan {
    skipped_uris: BTreeSet<String>,
    skipped_details: BTreeSet<WorkspaceEditTransactionSkippedDetail>,
    unsupported_operation_uris: Vec<String>,
    unopened_file_text_edit_uris: BTreeSet<String>,
    resource_operations: Vec<PlannedResourceOperation>,
    documents: Vec<WorkspaceEditTransactionDocument>,
}

struct WorkspaceEditTransactionInput {
    workspace_edit: Value,
    apply_mode: WorkspaceEditApplyMode,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum WorkspaceEditApplyMode {
    Partial,
    Atomic,
}

impl WorkspaceEditApplyMode {
    fn as_str(self) -> &'static str {
        match self {
            Self::Partial => "partial",
            Self::Atomic => "atomic",
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct PlannedResourceOperation {
    op: ResourceOperation,
    supported: bool,
    applied: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
enum WorkspaceEditStep {
    TextEdits {
        uri: String,
        edits: Vec<LspTextEdit>,
    },
    Resource(ResourceOperation),
}

#[derive(Default)]
struct PlannedResourceUriState {
    produced_uris: BTreeSet<String>,
    removed_uris: BTreeSet<String>,
}

impl PlannedResourceUriState {
    fn apply(&mut self, operation: &ResourceOperation) {
        match operation {
            ResourceOperation::Create { uri, .. } => {
                self.removed_uris.remove(uri);
                self.produced_uris.insert(uri.clone());
            }
            ResourceOperation::Rename {
                old_uri, new_uri, ..
            } => {
                if old_uri == new_uri {
                    return;
                }
                self.produced_uris.remove(old_uri);
                self.removed_uris.insert(old_uri.clone());
                self.removed_uris.remove(new_uri);
                self.produced_uris.insert(new_uri.clone());
            }
            ResourceOperation::Delete { uri, .. } => {
                self.produced_uris.remove(uri);
                self.removed_uris.insert(uri.clone());
            }
        }
    }

    fn path_exists(&self, uri: &str, path: &Path) -> bool {
        if self.removed_uris.contains(uri) {
            return false;
        }
        if self.produced_uris.contains(uri) {
            return true;
        }
        path.exists()
    }

    fn produced(&self, uri: &str) -> bool {
        self.produced_uris.contains(uri)
    }
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
    fn kind(&self) -> &'static str {
        match self {
            Self::Create { .. } => "create",
            Self::Rename { .. } => "rename",
            Self::Delete { .. } => "delete",
        }
    }

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

    fn produced_uris(&self) -> Vec<String> {
        match self {
            Self::Create { uri, .. } => vec![uri.clone()],
            Self::Rename {
                old_uri, new_uri, ..
            } if old_uri != new_uri => vec![new_uri.clone()],
            _ => Vec::new(),
        }
    }

    fn removed_uris(&self) -> Vec<String> {
        match self {
            Self::Delete { uri, .. } => vec![uri.clone()],
            Self::Rename {
                old_uri, new_uri, ..
            } if old_uri != new_uri => vec![old_uri.clone()],
            _ => Vec::new(),
        }
    }
}

enum ResourceOperationApplyOutcome {
    Applied,
    Noop,
    Skipped,
}

#[derive(Default)]
struct OpenTabRollback {
    initial_tab_order: Option<Vec<TabId>>,
    initial_active_tab: Option<TabId>,
    initial_preview_tab: Option<TabId>,
    text_snapshots: BTreeMap<TabId, OpenTabTextSnapshot>,
    uri_snapshots: BTreeMap<TabId, Option<String>>,
    closed_tabs: BTreeMap<TabId, TabEntry>,
}

struct OpenTabTextSnapshot {
    text: String,
    is_modified: bool,
}

impl OpenTabRollback {
    fn capture_scope(
        &mut self,
        tab_order: &[TabId],
        active_tab: Option<TabId>,
        preview_tab: Option<TabId>,
    ) {
        if self.initial_tab_order.is_some() {
            return;
        }
        self.initial_tab_order = Some(tab_order.to_vec());
        self.initial_active_tab = active_tab;
        self.initial_preview_tab = preview_tab;
    }

    fn has_entries(&self) -> bool {
        self.initial_tab_order.is_some()
            || !self.text_snapshots.is_empty()
            || !self.uri_snapshots.is_empty()
            || !self.closed_tabs.is_empty()
    }

    fn affected_tab_count(&self) -> usize {
        self.text_snapshots
            .keys()
            .chain(self.uri_snapshots.keys())
            .chain(self.closed_tabs.keys())
            .copied()
            .collect::<BTreeSet<_>>()
            .len()
    }

    fn backup_text(
        &mut self,
        tabs: &BTreeMap<TabId, TabEntry>,
        tab_order: &[TabId],
        active_tab: Option<TabId>,
        preview_tab: Option<TabId>,
        tab_id: TabId,
    ) -> Result<(), UiError> {
        self.capture_scope(tab_order, active_tab, preview_tab);
        if self.text_snapshots.contains_key(&tab_id) {
            return Ok(());
        }
        let tab = tabs
            .get(&tab_id)
            .ok_or_else(|| UiError::Processor(format!("unknown tab id {}", tab_id.get())))?;
        let view = tab.active_view().ok_or_else(|| {
            UiError::Processor(format!("tab {} has no active view", tab_id.get()))
        })?;
        self.text_snapshots.insert(
            tab_id,
            OpenTabTextSnapshot {
                text: view.text(),
                is_modified: view.is_modified(),
            },
        );
        Ok(())
    }

    fn backup_uri(
        &mut self,
        tabs: &BTreeMap<TabId, TabEntry>,
        tab_order: &[TabId],
        active_tab: Option<TabId>,
        preview_tab: Option<TabId>,
        tab_id: TabId,
    ) -> Result<(), UiError> {
        self.capture_scope(tab_order, active_tab, preview_tab);
        if self.uri_snapshots.contains_key(&tab_id) {
            return Ok(());
        }
        let tab = tabs
            .get(&tab_id)
            .ok_or_else(|| UiError::Processor(format!("unknown tab id {}", tab_id.get())))?;
        self.uri_snapshots.insert(tab_id, tab.document_uri.clone());
        Ok(())
    }

    fn capture_before_close(
        &mut self,
        tab_order: &[TabId],
        active_tab: Option<TabId>,
        preview_tab: Option<TabId>,
    ) {
        self.capture_scope(tab_order, active_tab, preview_tab);
    }

    fn record_closed_tab(&mut self, tab_id: TabId, tab: TabEntry) {
        self.closed_tabs.entry(tab_id).or_insert(tab);
    }

    fn rollback(
        &mut self,
        tabs: &mut BTreeMap<TabId, TabEntry>,
        tab_order: &mut Vec<TabId>,
        active_tab: &mut Option<TabId>,
        preview_tab: &mut Option<TabId>,
    ) -> Result<(), String> {
        let mut errors = Vec::new();

        for (tab_id, tab) in std::mem::take(&mut self.closed_tabs) {
            tabs.entry(tab_id).or_insert(tab);
        }

        for (tab_id, uri) in std::mem::take(&mut self.uri_snapshots) {
            match tabs.get_mut(&tab_id) {
                Some(tab) => tab.document_uri = uri,
                None => errors.push(format!(
                    "failed to restore WorkspaceEdit tab URI: unknown tab id {}",
                    tab_id.get()
                )),
            }
        }

        for (tab_id, snapshot) in std::mem::take(&mut self.text_snapshots) {
            if let Err(err) =
                replace_open_tab_text(tabs, tab_id, snapshot.text.as_str(), !snapshot.is_modified)
            {
                errors.push(format!(
                    "failed to restore WorkspaceEdit tab text for tab {}: {err}",
                    tab_id.get()
                ));
            }
        }

        if let Some(initial_order) = self.initial_tab_order.take() {
            if let Some(missing) = initial_order
                .iter()
                .find(|tab_id| !tabs.contains_key(tab_id))
            {
                errors.push(format!(
                    "failed to restore WorkspaceEdit tab order: missing tab id {}",
                    missing.get()
                ));
            } else {
                *tab_order = initial_order;
            }
            *active_tab = self
                .initial_active_tab
                .filter(|tab_id| tabs.contains_key(tab_id));
            *preview_tab = self
                .initial_preview_tab
                .filter(|tab_id| tabs.contains_key(tab_id));
        }

        if errors.is_empty() {
            Ok(())
        } else {
            Err(errors.join("; "))
        }
    }
}

#[derive(Default)]
struct FilesystemRollback {
    entries: Vec<FilesystemRollbackEntry>,
    backup_counter: u64,
}

enum FilesystemRollbackEntry {
    RemovePath { path: PathBuf },
    RemoveEmptyDir { path: PathBuf },
    MovePath { from: PathBuf, to: PathBuf },
    RestoreBackup { original: PathBuf, backup: PathBuf },
}

impl FilesystemRollback {
    fn has_entries(&self) -> bool {
        !self.entries.is_empty()
    }

    fn entry_count(&self) -> usize {
        self.entries.len()
    }

    fn record_created_path(&mut self, path: PathBuf) {
        self.entries
            .push(FilesystemRollbackEntry::RemovePath { path });
    }

    fn record_created_parent_dirs(&mut self, parent: &Path) {
        let mut missing_dirs = Vec::new();
        let mut current = Some(parent);
        while let Some(path) = current {
            if path.exists() {
                break;
            }
            missing_dirs.push(path.to_path_buf());
            current = path.parent();
        }

        for path in missing_dirs.into_iter().rev() {
            self.entries
                .push(FilesystemRollbackEntry::RemoveEmptyDir { path });
        }
    }

    fn record_move_for_rollback(&mut self, from: PathBuf, to: PathBuf) {
        self.entries
            .push(FilesystemRollbackEntry::MovePath { from, to });
    }

    fn backup_existing_path(&mut self, path: &Path) -> Result<bool, UiError> {
        if !path.exists() {
            return Ok(false);
        }

        let backup = self.next_backup_path(path)?;
        fs::rename(path, &backup).map_err(|err| {
            UiError::Processor(format!(
                "failed to create WorkspaceEdit rollback backup: {err}"
            ))
        })?;
        self.entries.push(FilesystemRollbackEntry::RestoreBackup {
            original: path.to_path_buf(),
            backup,
        });
        Ok(true)
    }

    fn rollback(&mut self) -> Result<(), String> {
        let mut errors = Vec::new();
        while let Some(entry) = self.entries.pop() {
            if let Err(err) = rollback_entry(entry) {
                errors.push(err);
            }
        }
        if errors.is_empty() {
            Ok(())
        } else {
            Err(errors.join("; "))
        }
    }

    fn rollback_latest(&mut self) -> Result<(), String> {
        if let Some(entry) = self.entries.pop() {
            rollback_entry(entry)
        } else {
            Ok(())
        }
    }

    fn cleanup_backups(&mut self) -> Result<(), UiError> {
        let mut errors = Vec::new();
        for entry in &self.entries {
            if let FilesystemRollbackEntry::RestoreBackup { backup, .. } = entry
                && let Err(err) = remove_path_if_exists(backup)
            {
                errors.push(format!(
                    "failed to remove WorkspaceEdit rollback backup: {err}"
                ));
            }
        }
        if errors.is_empty() {
            Ok(())
        } else {
            Err(UiError::Processor(errors.join("; ")))
        }
    }

    fn commit(mut self) -> Result<(), UiError> {
        self.cleanup_backups()
    }

    fn next_backup_path(&mut self, path: &Path) -> Result<PathBuf, UiError> {
        let parent = path.parent().ok_or_else(|| {
            UiError::Processor(
                "failed to create WorkspaceEdit rollback backup: target has no parent directory"
                    .to_string(),
            )
        })?;
        loop {
            self.backup_counter = self.backup_counter.saturating_add(1);
            let candidate = parent.join(format!(
                ".atto-workspace-edit-rollback-{}-{}",
                std::process::id(),
                self.backup_counter
            ));
            if !candidate.exists() {
                return Ok(candidate);
            }
        }
    }
}

fn rollback_entry(entry: FilesystemRollbackEntry) -> Result<(), String> {
    match entry {
        FilesystemRollbackEntry::RemovePath { path } => remove_path_if_exists(&path)
            .map_err(|err| format!("failed to remove rollback-created path {path:?}: {err}")),
        FilesystemRollbackEntry::RemoveEmptyDir { path } => remove_empty_dir_if_exists(&path)
            .map_err(|err| format!("failed to remove rollback-created directory {path:?}: {err}")),
        FilesystemRollbackEntry::MovePath { from, to } => {
            if !from.exists() {
                return Ok(());
            }
            if to.exists() {
                return Err(format!(
                    "failed to roll back WorkspaceEdit move from {from:?} to {to:?}: destination already exists"
                ));
            }
            fs::rename(&from, &to).map_err(|err| {
                format!("failed to roll back WorkspaceEdit move from {from:?} to {to:?}: {err}")
            })
        }
        FilesystemRollbackEntry::RestoreBackup { original, backup } => {
            if !backup.exists() {
                return Ok(());
            }
            remove_path_if_exists(&original).map_err(|err| {
                format!("failed to remove rollback replacement path {original:?}: {err}")
            })?;
            fs::rename(&backup, &original).map_err(|err| {
                format!(
                    "failed to restore WorkspaceEdit rollback backup {backup:?} to {original:?}: {err}"
                )
            })
        }
    }
}

fn remove_path_if_exists(path: &Path) -> std::io::Result<()> {
    let Ok(metadata) = fs::symlink_metadata(path) else {
        return Ok(());
    };
    if metadata.is_dir() {
        fs::remove_dir_all(path)
    } else {
        fs::remove_file(path)
    }
}

fn remove_empty_dir_if_exists(path: &Path) -> std::io::Result<()> {
    let Ok(metadata) = fs::symlink_metadata(path) else {
        return Ok(());
    };
    if !metadata.is_dir() {
        return Ok(());
    }
    let is_empty = fs::read_dir(path)?.next().is_none();
    if is_empty {
        fs::remove_dir(path)?;
    }
    Ok(())
}

fn resource_operation_error_with_rollbacks(
    err: UiError,
    filesystem_rollback_result: Result<(), String>,
    open_tab_rollback_result: Result<(), String>,
    had_open_tab_rollback: bool,
) -> UiError {
    if !had_open_tab_rollback {
        return match filesystem_rollback_result {
            Ok(()) => UiError::Processor(format!(
                "workspace edit resource operation failed; filesystem side effects were rolled back: {err}"
            )),
            Err(filesystem_rollback_err) => UiError::Processor(format!(
                "workspace edit resource operation failed: {err}; filesystem rollback also failed: {filesystem_rollback_err}"
            )),
        };
    }

    match (filesystem_rollback_result, open_tab_rollback_result) {
        (Ok(()), Ok(())) => UiError::Processor(format!(
            "workspace edit resource operation failed; filesystem side effects were rolled back; open tab state was rolled back: {err}"
        )),
        (Err(filesystem_rollback_err), Ok(())) => UiError::Processor(format!(
            "workspace edit resource operation failed: {err}; filesystem rollback also failed: {filesystem_rollback_err}; open tab state was rolled back"
        )),
        (Ok(()), Err(open_tab_rollback_err)) => UiError::Processor(format!(
            "workspace edit resource operation failed: {err}; filesystem side effects were rolled back; open tab rollback also failed: {open_tab_rollback_err}"
        )),
        (Err(filesystem_rollback_err), Err(open_tab_rollback_err)) => UiError::Processor(format!(
            "workspace edit resource operation failed: {err}; filesystem rollback also failed: {filesystem_rollback_err}; open tab rollback also failed: {open_tab_rollback_err}"
        )),
    }
}

fn atomic_apply_runtime_failure_result(
    tabs: &mut BTreeMap<TabId, TabEntry>,
    tab_order: &mut Vec<TabId>,
    active_tab: &mut Option<TabId>,
    preview_tab: &mut Option<TabId>,
    filesystem_rollback: &mut FilesystemRollback,
    open_tab_rollback: &mut OpenTabRollback,
    apply_mode: WorkspaceEditApplyMode,
    plan: WorkspaceEditTransactionPlan,
) -> Result<WorkspaceEditTransactionApplyResult, UiError> {
    let mut plan = plan;
    rollback_atomic_apply_side_effects(
        tabs,
        tab_order,
        active_tab,
        preview_tab,
        filesystem_rollback,
        open_tab_rollback,
    )?;
    clear_applied_resource_operations(&mut plan);
    Ok(WorkspaceEditTransactionApplyResult {
        result: result_from_plan("apply", apply_mode, plan, Vec::new(), 0, 0),
        undo_record: None,
    })
}

fn clear_applied_resource_operations(plan: &mut WorkspaceEditTransactionPlan) {
    for operation in &mut plan.resource_operations {
        operation.applied = false;
    }
}

fn rollback_atomic_apply_side_effects(
    tabs: &mut BTreeMap<TabId, TabEntry>,
    tab_order: &mut Vec<TabId>,
    active_tab: &mut Option<TabId>,
    preview_tab: &mut Option<TabId>,
    filesystem_rollback: &mut FilesystemRollback,
    open_tab_rollback: &mut OpenTabRollback,
) -> Result<(), UiError> {
    let filesystem_rollback_result = filesystem_rollback.rollback();
    let had_open_tab_rollback = open_tab_rollback.has_entries();
    let open_tab_rollback_result = if had_open_tab_rollback {
        open_tab_rollback.rollback(tabs, tab_order, active_tab, preview_tab)
    } else {
        Ok(())
    };

    if !had_open_tab_rollback {
        return filesystem_rollback_result.map_err(|err| {
            UiError::Processor(format!(
                "atomic workspace edit apply failed; filesystem rollback also failed: {err}"
            ))
        });
    }

    match (filesystem_rollback_result, open_tab_rollback_result) {
        (Ok(()), Ok(())) => Ok(()),
        (Err(filesystem_rollback_err), Ok(())) => Err(UiError::Processor(format!(
            "atomic workspace edit apply failed; filesystem rollback also failed: {filesystem_rollback_err}; open tab state was rolled back"
        ))),
        (Ok(()), Err(open_tab_rollback_err)) => Err(UiError::Processor(format!(
            "atomic workspace edit apply failed; filesystem side effects were rolled back; open tab rollback also failed: {open_tab_rollback_err}"
        ))),
        (Err(filesystem_rollback_err), Err(open_tab_rollback_err)) => {
            Err(UiError::Processor(format!(
                "atomic workspace edit apply failed; filesystem rollback also failed: {filesystem_rollback_err}; open tab rollback also failed: {open_tab_rollback_err}"
            )))
        }
    }
}

fn workspace_edit_value(workspace_edit_json: &str) -> Result<Value, UiError> {
    serde_json::from_str(workspace_edit_json)
        .map_err(|err| UiError::Processor(format!("failed to decode workspace edit: {err}")))
}

fn workspace_edit_input(
    workspace_edit_json: &str,
) -> Result<WorkspaceEditTransactionInput, UiError> {
    let value = workspace_edit_value(workspace_edit_json)?;
    let apply_mode = workspace_edit_apply_mode(&value)?;
    let workspace_edit = match value.get("workspaceEdit") {
        Some(workspace_edit) if workspace_edit.is_object() => workspace_edit.clone(),
        Some(_) => {
            return Err(UiError::Processor(
                "workspaceEdit transaction envelope field must be an object".to_string(),
            ));
        }
        None => value,
    };
    Ok(WorkspaceEditTransactionInput {
        workspace_edit,
        apply_mode,
    })
}

fn workspace_edit_apply_mode(value: &Value) -> Result<WorkspaceEditApplyMode, UiError> {
    let mode = value
        .get("applyMode")
        .or_else(|| value.get("apply_mode"))
        .and_then(Value::as_str)
        .unwrap_or("partial");
    match mode {
        "partial" => Ok(WorkspaceEditApplyMode::Partial),
        "atomic" => Ok(WorkspaceEditApplyMode::Atomic),
        other => Err(UiError::Processor(format!(
            "unsupported workspace edit applyMode: {other}"
        ))),
    }
}

fn transaction_plan(
    tabs: &BTreeMap<TabId, TabEntry>,
    tab_order: &[TabId],
    workspace_roots: &[String],
    workspace_edit: &Value,
) -> WorkspaceEditTransactionPlan {
    let edit_summary = summarize_workspace_edit(workspace_edit);
    let expected_versions = workspace_edit_expected_versions(workspace_edit);
    let mut open_tabs_by_uri = open_tabs_by_uri(tabs, tab_order);
    let initial_open_tabs_by_uri = open_tabs_by_uri.clone();
    let mut unsupported_operation_uris = BTreeSet::<String>::new();
    let mut unopened_file_text_edit_uris = BTreeSet::<String>::new();
    let mut skipped_uris = BTreeSet::<String>::new();
    let mut skipped_details = BTreeSet::<WorkspaceEditTransactionSkippedDetail>::new();
    let mut planned_resource_uri_state = PlannedResourceUriState::default();
    let mut planned_resource_operations = Vec::new();
    for op in resource_operations(workspace_edit) {
        let supported = resource_operation_supported(
            tabs,
            &open_tabs_by_uri,
            workspace_roots,
            &planned_resource_uri_state,
            &op,
        );
        if supported {
            simulate_resource_operation(&mut open_tabs_by_uri, &op);
            planned_resource_uri_state.apply(&op);
        } else {
            for uri in op.affected_uris() {
                unsupported_operation_uris.insert(uri.clone());
            }
            for detail in resource_operation_skip_details_with_state(
                tabs,
                &open_tabs_by_uri,
                workspace_roots,
                Some(&planned_resource_uri_state),
                &op,
            ) {
                mark_skipped(&mut skipped_uris, &mut skipped_details, detail);
            }
        }
        planned_resource_operations.push(PlannedResourceOperation {
            op,
            supported,
            applied: false,
        });
    }
    mark_ordered_text_edit_resource_dependencies(
        workspace_edit,
        &planned_resource_operations,
        &mut skipped_uris,
        &mut skipped_details,
    );
    let produced_resource_operation_uris = planned_resource_operations
        .iter()
        .filter(|operation| operation.supported)
        .flat_map(|operation| operation.op.produced_uris())
        .collect::<BTreeSet<_>>();
    let removed_resource_operation_uris = planned_resource_operations
        .iter()
        .filter(|operation| operation.supported)
        .flat_map(|operation| operation.op.removed_uris())
        .collect::<BTreeSet<_>>();

    let mut documents = edit_summary
        .documents
        .into_iter()
        .map(|doc| {
            let open_tab_id = open_tabs_by_uri
                .get(doc.uri.as_str())
                .or_else(|| initial_open_tabs_by_uri.get(doc.uri.as_str()))
                .copied();
            let expected_version = expected_versions.get(doc.uri.as_str()).copied();
            let actual_version =
                open_tab_id.and_then(|tab_id| tab_text_version(tabs, tab_id));
            let version_mismatch = expected_version
                .and_then(|expected| u64::try_from(expected).ok())
                .zip(actual_version)
                .is_some_and(|(expected, actual)| expected != actual);
            let has_ordered_resource_dependency =
                text_edit_has_ordered_resource_dependency(&skipped_details, doc.uri.as_str());
            if !has_ordered_resource_dependency && open_tab_id.is_none() {
                if workspace_roots.is_empty() {
                    mark_skipped(
                        &mut skipped_uris,
                        &mut skipped_details,
                        skipped_detail(
                            doc.uri.clone(),
                            "document_not_open",
                            Some("text_edit"),
                            "text edits for this URI are not supported because the document is not open in the core workspace",
                        ),
                    );
                } else if expected_version.is_some() {
                    mark_skipped(
                        &mut skipped_uris,
                        &mut skipped_details,
                        skipped_detail(
                            doc.uri.clone(),
                            "version_unavailable",
                            Some("text_edit"),
                            "versioned text edits for unopened files cannot be checked against a core document version",
                        ),
                    );
                } else if removed_resource_operation_uris.contains(&doc.uri)
                    && !produced_resource_operation_uris.contains(&doc.uri)
                {
                    mark_skipped(
                        &mut skipped_uris,
                        &mut skipped_details,
                        skipped_detail(
                            doc.uri.clone(),
                            "resource_operation_dependency_removed",
                            Some("text_edit"),
                            "text edits for this URI are blocked because a preceding resource operation removes the target",
                        ),
                    );
                } else if produced_resource_operation_uris.contains(&doc.uri) {
                    match workspace_file_path_for_pending_text_edit(
                        workspace_roots,
                        doc.uri.as_str(),
                    ) {
                        Ok(_) => {
                            unopened_file_text_edit_uris.insert(doc.uri.clone());
                        }
                        Err(detail) => {
                            mark_skipped(&mut skipped_uris, &mut skipped_details, detail);
                        }
                    }
                } else {
                    match workspace_file_path_for_text_edit(workspace_roots, doc.uri.as_str()) {
                        Ok(_) => {
                            unopened_file_text_edit_uris.insert(doc.uri.clone());
                        }
                        Err(detail) => {
                            mark_skipped(&mut skipped_uris, &mut skipped_details, detail);
                        }
                    }
                }
            }
            if let (Some(expected), Some(actual)) = (expected_version, actual_version)
                && version_mismatch
            {
                mark_skipped(
                    &mut skipped_uris,
                    &mut skipped_details,
                    skipped_detail(
                        doc.uri.clone(),
                        "version_mismatch",
                        Some("text_edit"),
                        format!(
                            "text edits for this URI expect version {expected}, but the open document is at version {actual}",
                        ),
                    ),
                );
            }
            if doc.has_overlapping_edits {
                mark_skipped(
                    &mut skipped_uris,
                    &mut skipped_details,
                    skipped_detail(
                        doc.uri.clone(),
                        "overlapping_text_edits",
                        Some("text_edit"),
                        "text edits for this URI overlap and cannot be applied safely",
                    ),
                );
            }
            WorkspaceEditTransactionDocument {
                uri: doc.uri,
                edit_count: doc.edit_count,
                has_overlapping_edits: doc.has_overlapping_edits,
                expected_version,
                actual_version,
                version_mismatch,
                is_open: open_tab_id.is_some(),
                is_dirty: open_tab_id.is_some_and(|tab_id| tab_is_modified(tabs, tab_id)),
                tab_id: open_tab_id.map(TabId::get),
            }
        })
        .collect::<Vec<_>>();

    for uri in &unsupported_operation_uris {
        if !documents.iter().any(|doc| doc.uri == *uri) {
            let tab_id = open_tabs_by_uri.get(uri).copied();
            documents.push(WorkspaceEditTransactionDocument {
                uri: uri.clone(),
                edit_count: 0,
                has_overlapping_edits: false,
                expected_version: None,
                actual_version: tab_id.and_then(|tab_id| tab_text_version(tabs, tab_id)),
                version_mismatch: false,
                is_open: tab_id.is_some(),
                is_dirty: tab_id.is_some_and(|tab_id| tab_is_modified(tabs, tab_id)),
                tab_id: tab_id.map(TabId::get),
            });
        }
    }
    for operation in &planned_resource_operations {
        if !operation.supported {
            continue;
        }
        for uri in operation.op.affected_uris() {
            if !documents.iter().any(|doc| doc.uri == uri) {
                let tab_id = open_tabs_by_uri.get(uri.as_str()).copied();
                documents.push(WorkspaceEditTransactionDocument {
                    edit_count: 0,
                    has_overlapping_edits: false,
                    expected_version: None,
                    actual_version: tab_id.and_then(|tab_id| tab_text_version(tabs, tab_id)),
                    version_mismatch: false,
                    is_open: tab_id.is_some(),
                    is_dirty: tab_id.is_some_and(|tab_id| tab_is_modified(tabs, tab_id)),
                    tab_id: tab_id.map(TabId::get),
                    uri,
                });
            }
        }
    }
    documents.sort_by(|a, b| a.uri.cmp(&b.uri));

    WorkspaceEditTransactionPlan {
        skipped_uris,
        skipped_details,
        unsupported_operation_uris: unsupported_operation_uris.into_iter().collect(),
        unopened_file_text_edit_uris,
        resource_operations: planned_resource_operations,
        documents,
    }
}

fn mark_ordered_text_edit_resource_dependencies(
    workspace_edit: &Value,
    planned_resource_operations: &[PlannedResourceOperation],
    skipped_uris: &mut BTreeSet<String>,
    skipped_details: &mut BTreeSet<WorkspaceEditTransactionSkippedDetail>,
) {
    let mut planned_operations = planned_resource_operations.iter();
    let mut removed_uris = BTreeSet::<String>::new();
    let mut blocked_uris = BTreeSet::<String>::new();

    for step in workspace_edit_steps(workspace_edit) {
        match step {
            WorkspaceEditStep::Resource(operation) => {
                let Some(planned_operation) = planned_operations.next() else {
                    continue;
                };
                if planned_operation.op != operation {
                    continue;
                }
                if !planned_operation.supported {
                    for uri in operation.affected_uris() {
                        blocked_uris.insert(uri);
                    }
                    continue;
                }
                for uri in operation.removed_uris() {
                    removed_uris.insert(uri);
                }
                for uri in operation.produced_uris() {
                    removed_uris.remove(uri.as_str());
                    blocked_uris.remove(uri.as_str());
                }
            }
            WorkspaceEditStep::TextEdits { uri, edits } => {
                if edits.is_empty() {
                    continue;
                }
                if removed_uris.contains(uri.as_str()) {
                    mark_skipped(
                        skipped_uris,
                        skipped_details,
                        skipped_detail(
                            uri,
                            "resource_operation_dependency_removed",
                            Some("text_edit"),
                            "text edits for this URI are blocked because a preceding resource operation removes the target",
                        ),
                    );
                } else if blocked_uris.contains(uri.as_str()) {
                    mark_skipped(
                        skipped_uris,
                        skipped_details,
                        skipped_detail(
                            uri,
                            "resource_operation_dependency_unsupported",
                            Some("text_edit"),
                            "text edits for this URI are blocked because a preceding resource operation is unsupported",
                        ),
                    );
                }
            }
        }
    }
}

fn text_edit_has_ordered_resource_dependency(
    skipped_details: &BTreeSet<WorkspaceEditTransactionSkippedDetail>,
    uri: &str,
) -> bool {
    skipped_details.iter().any(|detail| {
        detail.uri == uri
            && detail.operation.as_deref() == Some("text_edit")
            && matches!(
                detail.reason.as_str(),
                "resource_operation_dependency_removed"
                    | "resource_operation_dependency_unsupported"
            )
    })
}

fn result_from_plan(
    mode: &str,
    apply_mode: WorkspaceEditApplyMode,
    plan: WorkspaceEditTransactionPlan,
    applied_uris: Vec<String>,
    applied_edit_count: usize,
    applied_resource_operation_count: usize,
) -> WorkspaceEditTransactionResult {
    WorkspaceEditTransactionResult {
        mode: mode.to_string(),
        apply_mode: apply_mode.as_str().to_string(),
        applied: applied_edit_count > 0 || applied_resource_operation_count > 0,
        applied_uri: applied_uris.first().cloned(),
        applied_uris,
        applied_edit_count,
        applied_resource_operation_count,
        resource_operations: plan
            .resource_operations
            .iter()
            .map(workspace_edit_transaction_resource_operation)
            .collect(),
        dirty_document_uris: plan
            .documents
            .iter()
            .filter(|document| document.is_dirty)
            .map(|document| document.uri.clone())
            .collect(),
        conflicts: plan
            .skipped_details
            .iter()
            .map(workspace_edit_transaction_conflict)
            .collect(),
        skipped_uris: plan.skipped_uris.into_iter().collect(),
        skipped_details: plan.skipped_details.into_iter().collect(),
        unsupported_operation_uris: plan.unsupported_operation_uris,
        documents: plan.documents,
    }
}

fn workspace_edit_transaction_resource_operation(
    planned: &PlannedResourceOperation,
) -> WorkspaceEditTransactionResourceOperation {
    let (uri, old_uri, new_uri) = match &planned.op {
        ResourceOperation::Create { uri, .. } | ResourceOperation::Delete { uri, .. } => {
            (Some(uri.clone()), None, None)
        }
        ResourceOperation::Rename {
            old_uri, new_uri, ..
        } => (None, Some(old_uri.clone()), Some(new_uri.clone())),
    };
    WorkspaceEditTransactionResourceOperation {
        kind: planned.op.kind().to_string(),
        uri,
        old_uri,
        new_uri,
        affected_uris: planned.op.affected_uris(),
        supported: planned.supported,
        applied: planned.applied,
    }
}

fn workspace_edit_transaction_conflict(
    detail: &WorkspaceEditTransactionSkippedDetail,
) -> WorkspaceEditTransactionConflict {
    WorkspaceEditTransactionConflict {
        uri: detail.uri.clone(),
        kind: conflict_kind_for_skipped_reason(detail.reason.as_str()).to_string(),
        reason: detail.reason.clone(),
        operation: detail.operation.clone(),
        message: detail.message.clone(),
    }
}

fn conflict_kind_for_skipped_reason(reason: &str) -> &'static str {
    match reason {
        "resource_operation_dirty_target" => "dirty_document",
        "version_mismatch" | "version_unavailable" => "version",
        "overlapping_text_edits" => "overlap",
        "resource_operation_dependency_removed"
        | "resource_operation_dependency_skipped"
        | "resource_operation_dependency_unsupported" => "resource_dependency",
        "resource_operation_create_exists"
        | "resource_operation_target_exists"
        | "resource_operation_target_open"
        | "resource_operation_target_not_file"
        | "resource_operation_target_overwrite_not_supported" => "resource_target",
        "resource_operation_source_not_found"
        | "resource_operation_source_not_open"
        | "resource_operation_target_not_found"
        | "resource_operation_target_not_open"
        | "document_not_open"
        | "file_not_found" => "missing_resource",
        "document_outside_workspace"
        | "resource_operation_path_traversal"
        | "resource_operation_path_unavailable" => "workspace_boundary",
        "unsupported_uri" => "unsupported_uri",
        "resource_operation_delete_directory_requires_recursive" => "resource_options",
        "resource_operation_apply_skipped"
        | "text_edit_apply_failed"
        | "file_text_edit_apply_failed"
        | "file_text_edit_read_failed"
        | "file_text_edit_rollback_failed"
        | "file_text_edit_write_failed" => "apply_failure",
        _ => "other",
    }
}

fn skipped_detail(
    uri: impl Into<String>,
    reason: &str,
    operation: Option<&str>,
    message: impl Into<String>,
) -> WorkspaceEditTransactionSkippedDetail {
    WorkspaceEditTransactionSkippedDetail {
        uri: uri.into(),
        reason: reason.to_string(),
        operation: operation.map(str::to_string),
        message: message.into(),
    }
}

fn mark_skipped(
    skipped_uris: &mut BTreeSet<String>,
    skipped_details: &mut BTreeSet<WorkspaceEditTransactionSkippedDetail>,
    detail: WorkspaceEditTransactionSkippedDetail,
) {
    skipped_uris.insert(detail.uri.clone());
    skipped_details.insert(detail);
}

fn text_edit_has_preflight_block(plan: &WorkspaceEditTransactionPlan, uri: &str) -> bool {
    plan.skipped_details.iter().any(|detail| {
        detail.uri == uri
            && detail.operation.as_deref() == Some("text_edit")
            && detail.reason != "resource_operation_dependency_unsupported"
            && detail.reason != "resource_operation_dependency_removed"
            && detail.reason != "resource_operation_dependency_skipped"
    })
}

fn clear_text_edit_skipped_uri(plan: &mut WorkspaceEditTransactionPlan, uri: &str) {
    plan.skipped_details
        .retain(|detail| !(detail.uri == uri && detail.operation.as_deref() == Some("text_edit")));
    if !plan.skipped_details.iter().any(|detail| detail.uri == uri) {
        plan.skipped_uris.remove(uri);
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

fn tab_text_version(tabs: &BTreeMap<TabId, TabEntry>, tab_id: TabId) -> Option<u64> {
    tabs.get(&tab_id)
        .and_then(TabEntry::active_view)
        .map(EditorUi::text_version)
}

fn workspace_file_path_for_text_edit(
    workspace_roots: &[String],
    uri: &str,
) -> Result<PathBuf, WorkspaceEditTransactionSkippedDetail> {
    let path = file_uri_to_path(uri).ok_or_else(|| {
        skipped_detail(
            uri.to_string(),
            "unsupported_uri",
            Some("text_edit"),
            "unopened file text edits require a local file:// URI",
        )
    })?;

    let metadata = fs::metadata(&path).map_err(|err| {
        skipped_detail(
            uri.to_string(),
            "file_not_found",
            Some("text_edit"),
            format!("unopened file text edit target cannot be read: {err}"),
        )
    })?;
    if !metadata.is_file() {
        return Err(skipped_detail(
            uri.to_string(),
            "file_not_regular_file",
            Some("text_edit"),
            "unopened file text edit target is not a regular file",
        ));
    }

    let canonical_path = fs::canonicalize(&path).map_err(|err| {
        skipped_detail(
            uri.to_string(),
            "file_not_found",
            Some("text_edit"),
            format!("unopened file text edit target cannot be canonicalized: {err}"),
        )
    })?;
    let mut canonical_roots = Vec::<PathBuf>::new();
    for root in workspace_roots {
        let Some(root_path) = file_uri_to_path(root) else {
            continue;
        };
        let Ok(root_metadata) = fs::metadata(&root_path) else {
            continue;
        };
        if !root_metadata.is_dir() {
            continue;
        }
        if let Ok(canonical_root) = fs::canonicalize(root_path) {
            canonical_roots.push(canonical_root);
        }
    }

    if canonical_roots.is_empty() {
        return Err(skipped_detail(
            uri.to_string(),
            "workspace_roots_unavailable",
            Some("text_edit"),
            "no configured workspace root can be resolved to a local directory",
        ));
    }

    if canonical_roots
        .iter()
        .any(|root| canonical_path == *root || canonical_path.starts_with(root))
    {
        Ok(path)
    } else {
        Err(skipped_detail(
            uri.to_string(),
            "document_outside_workspace",
            Some("text_edit"),
            "unopened file text edit target is outside the configured workspace roots",
        ))
    }
}

fn workspace_file_path_for_pending_text_edit(
    workspace_roots: &[String],
    uri: &str,
) -> Result<PathBuf, WorkspaceEditTransactionSkippedDetail> {
    workspace_path_for_resource_operation(workspace_roots, uri, "text_edit")
}

fn workspace_path_for_resource_operation(
    workspace_roots: &[String],
    uri: &str,
    operation: &str,
) -> Result<PathBuf, WorkspaceEditTransactionSkippedDetail> {
    let path = file_uri_to_path(uri).ok_or_else(|| {
        skipped_detail(
            uri.to_string(),
            "unsupported_uri",
            Some(operation),
            "workspace resource operations require a local file:// URI",
        )
    })?;

    if path
        .components()
        .any(|component| matches!(component, Component::ParentDir))
    {
        return Err(skipped_detail(
            uri.to_string(),
            "resource_operation_path_traversal",
            Some(operation),
            "workspace resource operation paths may not contain parent-directory traversal",
        ));
    }

    let canonical_roots = canonical_workspace_roots(workspace_roots);
    if canonical_roots.is_empty() {
        return Err(skipped_detail(
            uri.to_string(),
            "workspace_roots_unavailable",
            Some(operation),
            "no configured workspace root can be resolved to a local directory",
        ));
    }

    let check_path = canonical_existing_path_or_ancestor(&path).map_err(|err| {
        skipped_detail(
            uri.to_string(),
            "resource_operation_path_unavailable",
            Some(operation),
            format!("workspace resource operation path cannot be resolved: {err}"),
        )
    })?;

    if canonical_roots
        .iter()
        .any(|root| check_path == *root || check_path.starts_with(root))
    {
        Ok(path)
    } else {
        Err(skipped_detail(
            uri.to_string(),
            "document_outside_workspace",
            Some(operation),
            "workspace resource operation target is outside the configured workspace roots",
        ))
    }
}

fn canonical_workspace_roots(workspace_roots: &[String]) -> Vec<PathBuf> {
    workspace_roots
        .iter()
        .filter_map(|root| file_uri_to_path(root))
        .filter_map(|root_path| {
            fs::metadata(&root_path)
                .ok()
                .map(|metadata| (root_path, metadata))
        })
        .filter(|(_, metadata)| metadata.is_dir())
        .filter_map(|(root_path, _)| fs::canonicalize(root_path).ok())
        .collect()
}

fn canonical_existing_path_or_ancestor(path: &Path) -> std::io::Result<PathBuf> {
    if path.exists() {
        return fs::canonicalize(path);
    }

    let mut current = path.parent();
    while let Some(candidate) = current {
        if candidate.exists() {
            return fs::canonicalize(candidate);
        }
        current = candidate.parent();
    }

    fs::canonicalize(path)
}

fn apply_open_tab_text_edits(
    tabs: &mut BTreeMap<TabId, TabEntry>,
    tab_order: &[TabId],
    active_tab: Option<TabId>,
    preview_tab: Option<TabId>,
    open_tab_rollback: &mut OpenTabRollback,
    tab_id: TabId,
    edits: &[LspTextEdit],
) -> Result<bool, UiError> {
    open_tab_rollback.backup_text(tabs, tab_order, active_tab, preview_tab, tab_id)?;
    let tab = tabs
        .get_mut(&tab_id)
        .ok_or_else(|| UiError::Processor(format!("unknown tab id {}", tab_id.get())))?;
    let view = tab
        .active_view_mut()
        .ok_or_else(|| UiError::Processor(format!("tab {} has no active view", tab_id.get())))?;
    let buffer_id = view.buffer_id;
    view.lsp_apply_lsp_text_edits(buffer_id, edits)
}

fn apply_unopened_file_text_edits(
    workspace_roots: &[String],
    filesystem_rollback: &mut FilesystemRollback,
    uri: &str,
    edits: &[LspTextEdit],
) -> Result<(), WorkspaceEditTransactionSkippedDetail> {
    let path = workspace_file_path_for_text_edit(workspace_roots, uri)?;
    let old_text = fs::read_to_string(&path).map_err(|err| {
        skipped_detail(
            uri.to_string(),
            "file_text_edit_read_failed",
            Some("text_edit"),
            format!("failed to read unopened file text edit target: {err}"),
        )
    })?;
    let new_text = apply_text_edits_to_text(old_text.as_str(), edits).map_err(|err| {
        skipped_detail(
            uri.to_string(),
            "file_text_edit_apply_failed",
            Some("text_edit"),
            err,
        )
    })?;
    filesystem_rollback
        .backup_existing_path(&path)
        .map_err(|err| {
            skipped_detail(
                uri.to_string(),
                "file_text_edit_rollback_failed",
                Some("text_edit"),
                format!("failed to prepare unopened file text edit rollback: {err}"),
            )
        })?;
    fs::write(&path, new_text).map_err(|err| {
        let rollback_result = filesystem_rollback.rollback_latest();
        let message = match rollback_result {
            Ok(()) => format!("failed to write unopened file text edit target: {err}"),
            Err(rollback_err) => format!(
                "failed to write unopened file text edit target: {err}; rollback also failed: {rollback_err}"
            ),
        };
        skipped_detail(
            uri.to_string(),
            "file_text_edit_write_failed",
            Some("text_edit"),
            message,
        )
    })
}

fn apply_text_edits_to_text(text: &str, edits: &[LspTextEdit]) -> Result<String, String> {
    let line_index = LineIndex::from_text(text);
    let mut resolved = edits
        .iter()
        .map(|edit| {
            let (start, end) = char_offsets_for_lsp_range(&line_index, &edit.range);
            let start_byte = line_index.char_offset_to_byte_offset(start);
            let end_byte = line_index.char_offset_to_byte_offset(end);
            (start, start_byte, end_byte, edit.new_text.as_str())
        })
        .collect::<Vec<_>>();

    resolved.sort_by_key(|(start, _, _, _)| std::cmp::Reverse(*start));

    let mut out = text.to_string();
    for (_, start_byte, end_byte, new_text) in resolved {
        let range = start_byte..end_byte;
        if !out.is_char_boundary(range.start) || !out.is_char_boundary(range.end) {
            return Err(format!(
                "text edit byte range {}..{} does not align to UTF-8 character boundaries",
                range.start, range.end
            ));
        }
        out.replace_range(range, new_text);
    }
    Ok(out)
}

fn workspace_edit_steps(workspace_edit: &Value) -> Vec<WorkspaceEditStep> {
    let mut out = Vec::new();

    if let Some(changes) = workspace_edit.get("changes").and_then(Value::as_object) {
        let mut entries = changes.iter().collect::<Vec<_>>();
        entries.sort_by(|(left, _), (right, _)| left.cmp(right));
        for (uri, edits) in entries {
            out.push(WorkspaceEditStep::TextEdits {
                uri: uri.to_string(),
                edits: text_edits_from_value(edits),
            });
        }
    }

    if let Some(document_changes) = workspace_edit
        .get("documentChanges")
        .and_then(Value::as_array)
    {
        for change in document_changes {
            if let Some(text_document) = change.get("textDocument")
                && let (Some(uri), Some(edits)) = (
                    text_document.get("uri").and_then(Value::as_str),
                    change.get("edits"),
                )
            {
                out.push(WorkspaceEditStep::TextEdits {
                    uri: uri.to_string(),
                    edits: text_edits_from_value(edits),
                });
                continue;
            }

            if let Some(operation) = resource_operation_from_change(change) {
                out.push(WorkspaceEditStep::Resource(operation));
            }
        }
    }

    out
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
        if let Some(operation) = resource_operation_from_change(change) {
            out.push(operation);
        }
    }

    out
}

fn resource_operation_from_change(change: &Value) -> Option<ResourceOperation> {
    if change.get("textDocument").is_some() && change.get("edits").is_some() {
        return None;
    }

    let kind = change.get("kind").and_then(Value::as_str);
    let options = change.get("options");
    match kind {
        Some("create") => {
            change
                .get("uri")
                .and_then(Value::as_str)
                .map(|uri| ResourceOperation::Create {
                    uri: uri.to_string(),
                    overwrite: option_bool(options, "overwrite"),
                    ignore_if_exists: option_bool(options, "ignoreIfExists"),
                })
        }
        Some("rename") => {
            let old_uri = change.get("oldUri").and_then(Value::as_str)?;
            let new_uri = change.get("newUri").and_then(Value::as_str)?;
            Some(ResourceOperation::Rename {
                old_uri: old_uri.to_string(),
                new_uri: new_uri.to_string(),
                overwrite: option_bool(options, "overwrite"),
                ignore_if_exists: option_bool(options, "ignoreIfExists"),
            })
        }
        Some("delete") => {
            change
                .get("uri")
                .and_then(Value::as_str)
                .map(|uri| ResourceOperation::Delete {
                    uri: uri.to_string(),
                    recursive: option_bool(options, "recursive"),
                    ignore_if_not_exists: option_bool(options, "ignoreIfNotExists"),
                })
        }
        _ => None,
    }
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
    workspace_roots: &[String],
    planned_resource_uri_state: &PlannedResourceUriState,
    operation: &ResourceOperation,
) -> bool {
    resource_operation_skip_details_with_state(
        tabs,
        open_tabs_by_uri,
        workspace_roots,
        Some(planned_resource_uri_state),
        operation,
    )
    .is_empty()
}

fn resource_operation_skip_details(
    tabs: &BTreeMap<TabId, TabEntry>,
    open_tabs_by_uri: &BTreeMap<String, TabId>,
    workspace_roots: &[String],
    operation: &ResourceOperation,
) -> Vec<WorkspaceEditTransactionSkippedDetail> {
    resource_operation_skip_details_with_state(
        tabs,
        open_tabs_by_uri,
        workspace_roots,
        None,
        operation,
    )
}

fn resource_operation_skip_details_with_state(
    tabs: &BTreeMap<TabId, TabEntry>,
    open_tabs_by_uri: &BTreeMap<String, TabId>,
    workspace_roots: &[String],
    planned_resource_uri_state: Option<&PlannedResourceUriState>,
    operation: &ResourceOperation,
) -> Vec<WorkspaceEditTransactionSkippedDetail> {
    match operation {
        ResourceOperation::Create {
            uri,
            overwrite,
            ignore_if_exists,
        } => {
            let Some(tab_id) = open_tabs_by_uri.get(uri.as_str()).copied() else {
                if workspace_roots.is_empty() {
                    return vec![skipped_detail(
                        uri.clone(),
                        "resource_operation_target_not_open",
                        Some(operation.kind()),
                        "create is currently supported only for already-open core tabs or local files under configured workspace roots",
                    )];
                }
                return resource_operation_file_skip_details_with_state(
                    workspace_roots,
                    planned_resource_uri_state,
                    operation,
                );
            };
            if *ignore_if_exists {
                return Vec::new();
            }
            if !*overwrite {
                return vec![skipped_detail(
                    uri.clone(),
                    "resource_operation_create_exists",
                    Some(operation.kind()),
                    "create targets an already-open tab without overwrite or ignoreIfExists",
                )];
            }
            if tab_is_modified(tabs, tab_id) {
                return vec![skipped_detail(
                    uri.clone(),
                    "resource_operation_dirty_target",
                    Some(operation.kind()),
                    "create overwrite targets a modified open tab",
                )];
            }
            Vec::new()
        }
        ResourceOperation::Rename {
            old_uri,
            new_uri,
            overwrite,
            ignore_if_exists,
        } => {
            let Some(old_tab_id) = open_tabs_by_uri.get(old_uri.as_str()).copied() else {
                if workspace_roots.is_empty() {
                    return operation
                        .affected_uris()
                        .into_iter()
                        .map(|uri| {
                            skipped_detail(
                                uri,
                                "resource_operation_source_not_open",
                                Some(operation.kind()),
                                "rename source is not open in the core workspace and no local workspace root is configured",
                            )
                        })
                        .collect();
                }
                if open_tabs_by_uri.contains_key(new_uri.as_str()) {
                    return operation
                        .affected_uris()
                        .into_iter()
                        .map(|uri| {
                            skipped_detail(
                                uri,
                                "resource_operation_target_open",
                                Some(operation.kind()),
                                "rename target is open in the core workspace while the source is an unopened file",
                            )
                        })
                        .collect();
                }
                return resource_operation_file_skip_details_with_state(
                    workspace_roots,
                    planned_resource_uri_state,
                    operation,
                );
            };
            if old_uri == new_uri {
                return Vec::new();
            }
            let target_tab_id = open_tabs_by_uri.get(new_uri.as_str()).copied();
            if target_tab_id == Some(old_tab_id) || *ignore_if_exists {
                return Vec::new();
            }
            if target_tab_id.is_some() {
                let reason = if *overwrite {
                    "resource_operation_target_overwrite_not_supported"
                } else {
                    "resource_operation_target_exists"
                };
                let message = if *overwrite {
                    "rename target is already open; replacing an existing open tab is not supported by this transaction path"
                } else {
                    "rename target is already open and ignoreIfExists is false"
                };
                return operation
                    .affected_uris()
                    .into_iter()
                    .map(|uri| skipped_detail(uri, reason, Some(operation.kind()), message))
                    .collect();
            }
            Vec::new()
        }
        ResourceOperation::Delete { uri, .. } => {
            let Some(tab_id) = open_tabs_by_uri.get(uri.as_str()).copied() else {
                if workspace_roots.is_empty() {
                    return vec![skipped_detail(
                        uri.clone(),
                        "resource_operation_target_not_open",
                        Some(operation.kind()),
                        "delete is currently supported only for already-open core tabs or local files under configured workspace roots",
                    )];
                }
                return resource_operation_file_skip_details_with_state(
                    workspace_roots,
                    planned_resource_uri_state,
                    operation,
                );
            };
            if tab_is_modified(tabs, tab_id) {
                return vec![skipped_detail(
                    uri.clone(),
                    "resource_operation_dirty_target",
                    Some(operation.kind()),
                    "delete targets a modified open tab",
                )];
            }
            Vec::new()
        }
    }
}

fn resource_operation_file_skip_details(
    workspace_roots: &[String],
    operation: &ResourceOperation,
) -> Vec<WorkspaceEditTransactionSkippedDetail> {
    resource_operation_file_skip_details_with_state(workspace_roots, None, operation)
}

fn resource_operation_file_skip_details_with_state(
    workspace_roots: &[String],
    planned_resource_uri_state: Option<&PlannedResourceUriState>,
    operation: &ResourceOperation,
) -> Vec<WorkspaceEditTransactionSkippedDetail> {
    match operation {
        ResourceOperation::Create {
            uri,
            overwrite,
            ignore_if_exists,
        } => {
            let path =
                match workspace_path_for_resource_operation(workspace_roots, uri, operation.kind())
                {
                    Ok(path) => path,
                    Err(detail) => return vec![detail],
                };
            let path_exists = planned_resource_uri_state
                .map(|state| state.path_exists(uri, &path))
                .unwrap_or_else(|| path.exists());
            if path_exists {
                if *ignore_if_exists {
                    return Vec::new();
                }
                if !*overwrite {
                    return vec![skipped_detail(
                        uri.clone(),
                        "resource_operation_create_exists",
                        Some(operation.kind()),
                        "create target already exists and overwrite/ignoreIfExists is false",
                    )];
                }
                if !planned_resource_uri_state.is_some_and(|state| state.produced(uri))
                    && !path.is_file()
                {
                    return vec![skipped_detail(
                        uri.clone(),
                        "resource_operation_target_not_file",
                        Some(operation.kind()),
                        "create overwrite target exists but is not a regular file",
                    )];
                }
            }
            Vec::new()
        }
        ResourceOperation::Rename {
            old_uri,
            new_uri,
            overwrite,
            ignore_if_exists,
        } => {
            if old_uri == new_uri {
                return Vec::new();
            }
            let old_path = match workspace_path_for_resource_operation(
                workspace_roots,
                old_uri,
                operation.kind(),
            ) {
                Ok(path) => path,
                Err(detail) => return vec![detail],
            };
            let old_path_exists = planned_resource_uri_state
                .map(|state| state.path_exists(old_uri, &old_path))
                .unwrap_or_else(|| old_path.exists());
            if !old_path_exists {
                return vec![skipped_detail(
                    old_uri.clone(),
                    "resource_operation_source_not_found",
                    Some(operation.kind()),
                    "rename source does not exist under the configured workspace roots",
                )];
            }
            let new_path = match workspace_path_for_resource_operation(
                workspace_roots,
                new_uri,
                operation.kind(),
            ) {
                Ok(path) => path,
                Err(detail) => return vec![detail],
            };
            let new_path_exists = planned_resource_uri_state
                .map(|state| state.path_exists(new_uri, &new_path))
                .unwrap_or_else(|| new_path.exists());
            if new_path_exists {
                if *ignore_if_exists {
                    return Vec::new();
                }
                if !*overwrite {
                    return operation
                        .affected_uris()
                        .into_iter()
                        .map(|uri| {
                            skipped_detail(
                                uri,
                                "resource_operation_target_exists",
                                Some(operation.kind()),
                                "rename target exists and overwrite/ignoreIfExists is false",
                            )
                        })
                        .collect();
                }
            }
            Vec::new()
        }
        ResourceOperation::Delete {
            uri,
            recursive,
            ignore_if_not_exists,
        } => {
            let path =
                match workspace_path_for_resource_operation(workspace_roots, uri, operation.kind())
                {
                    Ok(path) => path,
                    Err(detail) => return vec![detail],
                };
            let path_exists = planned_resource_uri_state
                .map(|state| state.path_exists(uri, &path))
                .unwrap_or_else(|| path.exists());
            if !path_exists {
                if *ignore_if_not_exists {
                    return Vec::new();
                }
                return vec![skipped_detail(
                    uri.clone(),
                    "resource_operation_target_not_found",
                    Some(operation.kind()),
                    "delete target does not exist under the configured workspace roots",
                )];
            }
            if !planned_resource_uri_state.is_some_and(|state| state.produced(uri))
                && path.is_dir()
                && !*recursive
            {
                return vec![skipped_detail(
                    uri.clone(),
                    "resource_operation_delete_directory_requires_recursive",
                    Some(operation.kind()),
                    "delete target is a directory but recursive is false",
                )];
            }
            Vec::new()
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
    workspace_roots: &[String],
    filesystem_rollback: &mut FilesystemRollback,
    open_tab_rollback: &mut OpenTabRollback,
    operation: &ResourceOperation,
) -> Result<ResourceOperationApplyOutcome, UiError> {
    match operation {
        ResourceOperation::Create {
            uri,
            overwrite,
            ignore_if_exists,
        } => {
            let Some(tab_id) = tab_id_for_uri(tabs, tab_order, uri.as_str()) else {
                return apply_unopened_resource_operation(
                    workspace_roots,
                    filesystem_rollback,
                    operation,
                );
            };
            if *ignore_if_exists {
                return Ok(ResourceOperationApplyOutcome::Noop);
            }
            if !*overwrite || tab_is_modified(tabs, tab_id) {
                return Ok(ResourceOperationApplyOutcome::Skipped);
            }
            match workspace_path_for_open_resource_operation(workspace_roots, uri, operation.kind())
            {
                OpenResourcePathResolution::Path(path) => {
                    match apply_create_filesystem_side_effect(
                        &path,
                        *overwrite,
                        *ignore_if_exists,
                        filesystem_rollback,
                    )? {
                        ResourceOperationApplyOutcome::Applied => {}
                        outcome => return Ok(outcome),
                    }
                }
                OpenResourcePathResolution::Skipped => {
                    return Ok(ResourceOperationApplyOutcome::Skipped);
                }
                OpenResourcePathResolution::NoSideEffect => {}
            }
            open_tab_rollback.backup_text(tabs, tab_order, *active_tab, *preview_tab, tab_id)?;
            replace_open_tab_text(tabs, tab_id, "", true)?;
            Ok(ResourceOperationApplyOutcome::Applied)
        }
        ResourceOperation::Rename {
            old_uri,
            new_uri,
            overwrite,
            ignore_if_exists,
        } => {
            let Some(tab_id) = tab_id_for_uri(tabs, tab_order, old_uri.as_str()) else {
                return apply_unopened_resource_operation(
                    workspace_roots,
                    filesystem_rollback,
                    operation,
                );
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
            match workspace_paths_for_open_resource_rename(
                workspace_roots,
                old_uri,
                new_uri,
                operation.kind(),
            ) {
                OpenResourceRenamePathResolution::Paths(old_path, new_path) => {
                    match apply_rename_filesystem_side_effect(
                        &old_path,
                        &new_path,
                        *overwrite,
                        *ignore_if_exists,
                        filesystem_rollback,
                    )? {
                        ResourceOperationApplyOutcome::Applied => {}
                        outcome => return Ok(outcome),
                    }
                }
                OpenResourceRenamePathResolution::Skipped => {
                    return Ok(ResourceOperationApplyOutcome::Skipped);
                }
                OpenResourceRenamePathResolution::NoSideEffect => {}
            }
            open_tab_rollback.backup_uri(tabs, tab_order, *active_tab, *preview_tab, tab_id)?;
            let tab = tabs
                .get_mut(&tab_id)
                .ok_or_else(|| UiError::Processor(format!("unknown tab id {}", tab_id.get())))?;
            tab.document_uri = Some(new_uri.clone());
            Ok(ResourceOperationApplyOutcome::Applied)
        }
        ResourceOperation::Delete {
            uri,
            ignore_if_not_exists,
            recursive,
        } => {
            let Some(tab_id) = tab_id_for_uri(tabs, tab_order, uri.as_str()) else {
                return apply_unopened_resource_operation(
                    workspace_roots,
                    filesystem_rollback,
                    operation,
                );
            };
            if tab_is_modified(tabs, tab_id) {
                return Ok(ResourceOperationApplyOutcome::Skipped);
            }
            match workspace_path_for_open_resource_operation(workspace_roots, uri, operation.kind())
            {
                OpenResourcePathResolution::Path(path) => {
                    match apply_delete_filesystem_side_effect(
                        &path,
                        *recursive,
                        *ignore_if_not_exists,
                        filesystem_rollback,
                    )? {
                        ResourceOperationApplyOutcome::Applied
                        | ResourceOperationApplyOutcome::Noop => {}
                        ResourceOperationApplyOutcome::Skipped => {
                            return Ok(ResourceOperationApplyOutcome::Skipped);
                        }
                    }
                }
                OpenResourcePathResolution::Skipped => {
                    return Ok(ResourceOperationApplyOutcome::Skipped);
                }
                OpenResourcePathResolution::NoSideEffect => {}
            }
            open_tab_rollback.capture_before_close(tab_order, *active_tab, *preview_tab);
            if let Some(tab) = close_tab(tabs, tab_order, active_tab, preview_tab, tab_id) {
                open_tab_rollback.record_closed_tab(tab_id, tab);
            }
            Ok(ResourceOperationApplyOutcome::Applied)
        }
    }
}

fn apply_unopened_resource_operation(
    workspace_roots: &[String],
    filesystem_rollback: &mut FilesystemRollback,
    operation: &ResourceOperation,
) -> Result<ResourceOperationApplyOutcome, UiError> {
    if !resource_operation_file_skip_details(workspace_roots, operation).is_empty() {
        return Ok(ResourceOperationApplyOutcome::Skipped);
    }

    match operation {
        ResourceOperation::Create {
            uri,
            overwrite,
            ignore_if_exists,
        } => {
            let path =
                workspace_path_for_resource_operation(workspace_roots, uri, operation.kind())
                    .map_err(|detail| UiError::Processor(detail.message))?;
            apply_create_filesystem_side_effect(
                &path,
                *overwrite,
                *ignore_if_exists,
                filesystem_rollback,
            )
        }
        ResourceOperation::Rename {
            old_uri,
            new_uri,
            overwrite,
            ignore_if_exists,
        } => {
            if old_uri == new_uri {
                return Ok(ResourceOperationApplyOutcome::Noop);
            }
            let old_path =
                workspace_path_for_resource_operation(workspace_roots, old_uri, operation.kind())
                    .map_err(|detail| UiError::Processor(detail.message))?;
            let new_path =
                workspace_path_for_resource_operation(workspace_roots, new_uri, operation.kind())
                    .map_err(|detail| UiError::Processor(detail.message))?;
            apply_rename_filesystem_side_effect(
                &old_path,
                &new_path,
                *overwrite,
                *ignore_if_exists,
                filesystem_rollback,
            )
        }
        ResourceOperation::Delete {
            uri,
            recursive,
            ignore_if_not_exists,
        } => {
            let path =
                workspace_path_for_resource_operation(workspace_roots, uri, operation.kind())
                    .map_err(|detail| UiError::Processor(detail.message))?;
            if !path.exists() {
                return if *ignore_if_not_exists {
                    Ok(ResourceOperationApplyOutcome::Noop)
                } else {
                    Ok(ResourceOperationApplyOutcome::Skipped)
                };
            }
            apply_delete_filesystem_side_effect(
                &path,
                *recursive,
                *ignore_if_not_exists,
                filesystem_rollback,
            )
        }
    }
}

enum OpenResourcePathResolution {
    NoSideEffect,
    Path(PathBuf),
    Skipped,
}

enum OpenResourceRenamePathResolution {
    NoSideEffect,
    Paths(PathBuf, PathBuf),
    Skipped,
}

fn workspace_path_for_open_resource_operation(
    workspace_roots: &[String],
    uri: &str,
    operation: &str,
) -> OpenResourcePathResolution {
    if workspace_roots.is_empty() || file_uri_to_path(uri).is_none() {
        return OpenResourcePathResolution::NoSideEffect;
    }
    match workspace_path_for_resource_operation(workspace_roots, uri, operation) {
        Ok(path) => OpenResourcePathResolution::Path(path),
        Err(_) => OpenResourcePathResolution::Skipped,
    }
}

fn workspace_paths_for_open_resource_rename(
    workspace_roots: &[String],
    old_uri: &str,
    new_uri: &str,
    operation: &str,
) -> OpenResourceRenamePathResolution {
    match (
        workspace_path_for_open_resource_operation(workspace_roots, old_uri, operation),
        workspace_path_for_open_resource_operation(workspace_roots, new_uri, operation),
    ) {
        (
            OpenResourcePathResolution::Path(old_path),
            OpenResourcePathResolution::Path(new_path),
        ) => OpenResourceRenamePathResolution::Paths(old_path, new_path),
        (OpenResourcePathResolution::NoSideEffect, OpenResourcePathResolution::NoSideEffect) => {
            OpenResourceRenamePathResolution::NoSideEffect
        }
        _ => OpenResourceRenamePathResolution::Skipped,
    }
}

fn apply_create_filesystem_side_effect(
    path: &Path,
    overwrite: bool,
    ignore_if_exists: bool,
    filesystem_rollback: &mut FilesystemRollback,
) -> Result<ResourceOperationApplyOutcome, UiError> {
    if path.exists() {
        if ignore_if_exists {
            return Ok(ResourceOperationApplyOutcome::Noop);
        }
        if !overwrite {
            return Ok(ResourceOperationApplyOutcome::Skipped);
        }
        filesystem_rollback.backup_existing_path(path)?;
    }
    if let Some(parent) = path.parent() {
        filesystem_rollback.record_created_parent_dirs(parent);
        fs::create_dir_all(parent).map_err(|err| {
            UiError::Processor(format!(
                "failed to create WorkspaceEdit target parent directory: {err}"
            ))
        })?;
    }
    filesystem_rollback.record_created_path(path.to_path_buf());
    fs::write(path, "")
        .map_err(|err| UiError::Processor(format!("failed to create WorkspaceEdit file: {err}")))?;
    Ok(ResourceOperationApplyOutcome::Applied)
}

fn apply_rename_filesystem_side_effect(
    old_path: &Path,
    new_path: &Path,
    overwrite: bool,
    ignore_if_exists: bool,
    filesystem_rollback: &mut FilesystemRollback,
) -> Result<ResourceOperationApplyOutcome, UiError> {
    if old_path == new_path {
        return Ok(ResourceOperationApplyOutcome::Noop);
    }
    if !old_path.exists() {
        return Ok(ResourceOperationApplyOutcome::Skipped);
    }
    if new_path.exists() {
        if ignore_if_exists {
            return Ok(ResourceOperationApplyOutcome::Noop);
        }
        if !overwrite {
            return Ok(ResourceOperationApplyOutcome::Skipped);
        }
        filesystem_rollback.backup_existing_path(new_path)?;
    }
    if let Some(parent) = new_path.parent() {
        filesystem_rollback.record_created_parent_dirs(parent);
        fs::create_dir_all(parent).map_err(|err| {
            UiError::Processor(format!(
                "failed to create WorkspaceEdit rename target parent directory: {err}"
            ))
        })?;
    }
    fs::rename(old_path, new_path)
        .map_err(|err| UiError::Processor(format!("failed to rename WorkspaceEdit file: {err}")))?;
    filesystem_rollback.record_move_for_rollback(new_path.to_path_buf(), old_path.to_path_buf());
    Ok(ResourceOperationApplyOutcome::Applied)
}

fn apply_delete_filesystem_side_effect(
    path: &Path,
    recursive: bool,
    ignore_if_not_exists: bool,
    filesystem_rollback: &mut FilesystemRollback,
) -> Result<ResourceOperationApplyOutcome, UiError> {
    if !path.exists() {
        return if ignore_if_not_exists {
            Ok(ResourceOperationApplyOutcome::Noop)
        } else {
            Ok(ResourceOperationApplyOutcome::Skipped)
        };
    }
    if path.is_dir() && !recursive {
        return Ok(ResourceOperationApplyOutcome::Skipped);
    }
    filesystem_rollback.backup_existing_path(path)?;
    Ok(ResourceOperationApplyOutcome::Applied)
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
) -> Option<TabEntry> {
    let closed_pos = tab_order.iter().position(|id| *id == tab_id);
    let closed = tabs.remove(&tab_id);
    let existed = closed.is_some();

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

    closed
}
