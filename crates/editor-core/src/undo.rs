//! Undo/redo history model and tree management.

use super::{CommandError, Selection, SelectionSetSnapshot};
#[cfg(feature = "serde")]
use serde::{Deserialize, Serialize};
use std::time::{Duration, Instant};

const DEFAULT_UNDO_COALESCING_TIMEOUT: Duration = Duration::from_secs(1);

#[derive(Debug, Clone)]
pub(super) struct TextEdit {
    pub(super) start_before: usize,
    pub(super) start_after: usize,
    pub(super) deleted_text: String,
    pub(super) inserted_text: String,
}

impl TextEdit {
    pub(super) fn deleted_len(&self) -> usize {
        self.deleted_text.chars().count()
    }

    pub(super) fn inserted_len(&self) -> usize {
        self.inserted_text.chars().count()
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum UndoEditKind {
    Insert,
    Explicit,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct CoalescingEdit {
    start_before: usize,
    start_after: usize,
    deleted_len: usize,
    inserted_len: usize,
}

#[derive(Debug, Clone)]
struct UndoCoalescingState {
    group_id: usize,
    last_at: Instant,
    edit_kind: UndoEditKind,
    after_selection: SelectionSetSnapshot,
    edits: Vec<CoalescingEdit>,
}

impl UndoCoalescingState {
    fn from_step(
        group_id: usize,
        edit_kind: UndoEditKind,
        step: &UndoStep,
        last_at: Instant,
    ) -> Option<Self> {
        Some(Self {
            group_id,
            last_at,
            edit_kind,
            after_selection: step.after_selection.clone(),
            edits: coalescing_edits_for_kind(edit_kind, step)?,
        })
    }

    fn extend_with(
        &self,
        edit_kind: UndoEditKind,
        step: &UndoStep,
        now: Instant,
        timeout: Duration,
    ) -> Option<Vec<CoalescingEdit>> {
        if self.edit_kind != edit_kind {
            return None;
        }
        if edit_kind == UndoEditKind::Insert
            && now.saturating_duration_since(self.last_at) >= timeout
        {
            return None;
        }
        if self.after_selection != step.before_selection {
            return None;
        }

        let next_edits = coalescing_edits_for_kind(edit_kind, step)?;
        if self.edits.len() != next_edits.len() {
            return None;
        }

        for (previous, next) in self.edits.iter().zip(&next_edits) {
            match edit_kind {
                UndoEditKind::Insert => {
                    let previous_end = previous.start_after.saturating_add(previous.inserted_len);
                    if previous_end != next.start_before {
                        return None;
                    }
                }
                UndoEditKind::Explicit => {
                    if previous.start_after != next.start_before
                        || previous.inserted_len != next.deleted_len
                    {
                        return None;
                    }
                }
            }
        }

        Some(next_edits)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum UndoCoalescingMode {
    None,
    Insert,
    Explicit,
}

fn coalescing_edits_for_kind(
    edit_kind: UndoEditKind,
    step: &UndoStep,
) -> Option<Vec<CoalescingEdit>> {
    if step.edits.is_empty() {
        return None;
    }

    let mut edits = Vec::with_capacity(step.edits.len());
    for edit in &step.edits {
        let deleted_len = edit.deleted_len();
        let inserted_len = edit.inserted_len();
        match edit_kind {
            UndoEditKind::Insert => {
                if deleted_len != 0 || inserted_len == 0 || edit.inserted_text.contains('\n') {
                    return None;
                }
            }
            UndoEditKind::Explicit => {
                if deleted_len == 0 && inserted_len == 0 {
                    return None;
                }
            }
        }

        edits.push(CoalescingEdit {
            start_before: edit.start_before,
            start_after: edit.start_after,
            deleted_len,
            inserted_len,
        });
    }

    edits.sort_by_key(|edit| (edit.start_before, edit.start_after));
    Some(edits)
}

#[derive(Debug, Clone)]
pub(super) struct UndoStep {
    pub(super) group_id: usize,
    pub(super) edits: Vec<TextEdit>,
    pub(super) before_selection: SelectionSetSnapshot,
    pub(super) after_selection: SelectionSetSnapshot,
}

#[derive(Debug)]
pub(super) struct UndoRedoManager {
    /// All nodes in the undo tree (stable indices).
    ///
    /// - Node `0` is the root ("base" state) and has no step.
    /// - Other nodes contain one [`UndoStep`] representing an edit from `parent → node`.
    nodes: Vec<UndoNode>,
    /// Current node id in the undo tree.
    current: UndoNodeId,
    /// Count of nodes that currently hold a step (excludes root and pruned tombstones).
    step_count: usize,
    max_undo: usize,
    /// Clean point tracking (node id in the undo tree).
    clean_node: Option<UndoNodeId>,
    next_group_id: usize,
    open_group: Option<UndoCoalescingState>,
    coalescing_timeout: Duration,
}

type UndoNodeId = usize;

#[derive(Debug)]
struct UndoNode {
    parent: Option<UndoNodeId>,
    children: Vec<UndoNodeId>,
    /// The selected child branch to use for `Redo` when multiple exist.
    preferred_child: Option<UndoNodeId>,
    /// The step that produced this node (none for root and pruned tombstones).
    step: Option<UndoStep>,
}

impl UndoRedoManager {
    pub(super) fn new(max_undo: usize) -> Self {
        let max_undo = max_undo.max(1);
        Self {
            nodes: vec![UndoNode {
                parent: None,
                children: Vec::new(),
                preferred_child: None,
                step: None,
            }],
            current: 0,
            step_count: 0,
            max_undo,
            clean_node: Some(0),
            next_group_id: 0,
            open_group: None,
            coalescing_timeout: DEFAULT_UNDO_COALESCING_TIMEOUT,
        }
    }

    pub(super) fn can_undo(&self) -> bool {
        self.current != 0
    }

    pub(super) fn can_redo(&self) -> bool {
        !self.nodes[self.current].children.is_empty()
    }

    pub(super) fn undo_depth(&self) -> usize {
        let mut depth = 0usize;
        let mut node = self.current;
        while node != 0 {
            depth = depth.saturating_add(1);
            node = self.nodes[node].parent.unwrap_or(0);
        }
        depth
    }

    pub(super) fn redo_depth(&self) -> usize {
        let mut depth = 0usize;
        let mut node = self.current;
        while let Some(child) = self.selected_child(node) {
            depth = depth.saturating_add(1);
            node = child;
        }
        depth
    }

    pub(super) fn current_group_id(&self) -> Option<usize> {
        self.open_group.as_ref().map(|group| group.group_id)
    }

    pub(super) fn coalescing_timeout(&self) -> Duration {
        self.coalescing_timeout
    }

    pub(super) fn set_coalescing_timeout(&mut self, timeout: Duration) {
        self.coalescing_timeout = timeout;
    }

    pub(super) fn is_clean(&self) -> bool {
        self.clean_node == Some(self.current)
    }

    pub(super) fn mark_clean(&mut self) {
        self.clean_node = Some(self.current);
        self.end_group();
    }

    pub(super) fn end_group(&mut self) {
        self.open_group = None;
    }

    pub(super) fn push_step(&mut self, step: UndoStep, coalescible_insert: bool) -> usize {
        let mode = if coalescible_insert {
            UndoCoalescingMode::Insert
        } else {
            UndoCoalescingMode::None
        };
        self.push_step_with_mode(step, mode)
    }

    pub(super) fn push_explicit_coalescing_step(&mut self, step: UndoStep) -> usize {
        self.push_step_with_mode(step, UndoCoalescingMode::Explicit)
    }

    fn push_step_with_mode(&mut self, mut step: UndoStep, mode: UndoCoalescingMode) -> usize {
        let now = Instant::now();
        let edit_kind = match mode {
            UndoCoalescingMode::None => None,
            UndoCoalescingMode::Insert => Some(UndoEditKind::Insert),
            UndoCoalescingMode::Explicit => Some(UndoEditKind::Explicit),
        };
        let next_edits = edit_kind.and_then(|kind| coalescing_edits_for_kind(kind, &step));
        let reuse_open_group = next_edits.is_some()
            && self.clean_node != Some(self.current)
            && edit_kind.is_some_and(|kind| {
                self.open_group
                    .as_ref()
                    .and_then(|group| group.extend_with(kind, &step, now, self.coalescing_timeout))
                    .is_some()
            });

        if reuse_open_group {
            if let Some(group) = &self.open_group {
                step.group_id = group.group_id;
            }
        } else {
            step.group_id = self.next_group_id;
            self.next_group_id = self.next_group_id.wrapping_add(1);
        }

        if let Some(kind) = edit_kind.filter(|_| next_edits.is_some()) {
            self.open_group = UndoCoalescingState::from_step(step.group_id, kind, &step, now);
        } else {
            self.open_group = None;
        }

        let group_id = step.group_id;
        let parent = self.current;
        let new_id = self.nodes.len();
        self.nodes.push(UndoNode {
            parent: Some(parent),
            children: Vec::new(),
            preferred_child: None,
            step: Some(step),
        });

        self.nodes[parent].children.push(new_id);
        self.nodes[parent].preferred_child = Some(new_id);
        self.current = new_id;
        self.step_count = self.step_count.saturating_add(1);

        self.prune_if_needed();
        group_id
    }

    pub(super) fn pop_undo_group(&mut self) -> Option<Vec<UndoStep>> {
        let mut node = self.current;
        let group_id = self.nodes[node].step.as_ref().map(|s| s.group_id)?;

        let mut steps: Vec<UndoStep> = Vec::new();
        while node != 0 {
            let current_step_group = self.nodes[node].step.as_ref().map(|s| s.group_id);
            if current_step_group != Some(group_id) {
                break;
            }

            let step = self.nodes[node].step.as_ref()?.clone();
            steps.push(step);

            let parent = self.nodes[node].parent.unwrap_or(0);
            // Remember which branch we came from so redo follows it.
            if parent != 0 || node != 0 {
                self.nodes[parent].preferred_child = Some(node);
            }

            node = parent;
        }

        if steps.is_empty() {
            return None;
        }

        self.current = node;
        Some(steps)
    }

    pub(super) fn pop_redo_group(&mut self) -> Option<Vec<UndoStep>> {
        let first = self.selected_child(self.current)?;
        let group_id = self.nodes[first].step.as_ref().map(|s| s.group_id)?;

        let mut node = self.current;
        let mut steps: Vec<UndoStep> = Vec::new();
        while let Some(child) = self.selected_child(node) {
            let child_group = self.nodes[child].step.as_ref().map(|s| s.group_id);
            if child_group != Some(group_id) {
                break;
            }

            // Ensure this branch remains the selected redo path.
            self.nodes[node].preferred_child = Some(child);

            steps.push(self.nodes[child].step.as_ref()?.clone());
            node = child;
        }

        if steps.is_empty() {
            return None;
        }

        self.current = node;
        Some(steps)
    }

    pub(super) fn redo_branch_count(&self) -> usize {
        self.nodes[self.current].children.len()
    }

    pub(super) fn selected_redo_branch_index(&self) -> Option<usize> {
        let node = &self.nodes[self.current];
        let selected = self.selected_child(self.current)?;
        node.children.iter().position(|c| *c == selected)
    }

    pub(super) fn select_redo_branch(&mut self, index: usize) -> Result<(), CommandError> {
        let children = self.nodes[self.current].children.clone();
        if index >= children.len() {
            return Err(CommandError::Other(format!(
                "Invalid redo branch index {} (count={})",
                index,
                children.len()
            )));
        }
        self.nodes[self.current].preferred_child = Some(children[index]);
        Ok(())
    }

    pub(super) fn selected_child(&self, node: UndoNodeId) -> Option<UndoNodeId> {
        let n = &self.nodes[node];
        if n.children.is_empty() {
            return None;
        }
        if let Some(pref) = n.preferred_child
            && n.children.contains(&pref)
        {
            return Some(pref);
        }
        n.children.last().copied()
    }

    pub(super) fn prune_if_needed(&mut self) {
        while self.step_count > self.max_undo {
            if let Some(leaf) = self.find_prunable_leaf() {
                self.remove_leaf_node(leaf);
                continue;
            }

            if self.prune_root_child() {
                continue;
            }

            // No safe pruning candidate found; give up.
            break;
        }
    }

    pub(super) fn find_prunable_leaf(&self) -> Option<UndoNodeId> {
        (1..self.nodes.len())
            .filter(|id| *id != self.current)
            .filter(|id| self.nodes[*id].step.is_some())
            .filter(|id| self.nodes[*id].children.is_empty())
            .min()
    }

    pub(super) fn remove_leaf_node(&mut self, id: UndoNodeId) {
        let parent = self.nodes[id].parent.unwrap_or(0);
        self.nodes[parent].children.retain(|c| *c != id);
        if self.nodes[parent].preferred_child == Some(id) {
            self.nodes[parent].preferred_child = self.nodes[parent].children.last().copied();
        }

        if self.clean_node == Some(id) {
            self.clean_node = None;
        }

        self.nodes[id].parent = None;
        self.nodes[id].children.clear();
        self.nodes[id].preferred_child = None;
        self.nodes[id].step = None;

        self.step_count = self.step_count.saturating_sub(1);
    }

    pub(super) fn prune_root_child(&mut self) -> bool {
        let children = self.nodes[0].children.clone();
        if children.len() != 1 {
            return false;
        }
        let doomed = children[0];
        if doomed == self.current {
            return false;
        }
        if self.nodes[doomed].step.is_none() {
            return false;
        }

        // Re-parent all of `doomed`'s children directly under root (root now represents the state
        // *after* `doomed`).
        let adopted = std::mem::take(&mut self.nodes[doomed].children);
        for child in &adopted {
            self.nodes[*child].parent = Some(0);
        }

        self.nodes[0].children = adopted;
        self.nodes[0].preferred_child = self.nodes[0].children.last().copied();

        if self.clean_node == Some(doomed) {
            self.clean_node = Some(0);
        }

        self.nodes[doomed].parent = None;
        self.nodes[doomed].children.clear();
        self.nodes[doomed].preferred_child = None;
        self.nodes[doomed].step = None;

        self.step_count = self.step_count.saturating_sub(1);
        true
    }
}

/// A persistable snapshot of the undo/redo history for a single document.
///
/// This is intended for "hot exit" workflows: persist the editor text plus this snapshot, then
/// restore both on startup so undo/redo keeps working across restarts.
///
/// Notes:
/// - This snapshot does **not** include the current document text; callers are responsible for
///   persisting/restoring the text separately.
/// - Restoring a snapshot into a different document text will produce undefined undo behavior.
#[derive(Debug, Clone, PartialEq, Eq)]
#[cfg_attr(feature = "serde", derive(Serialize, Deserialize))]
pub struct UndoHistorySnapshot {
    /// Snapshot format version for forward compatibility.
    pub format_version: u32,
    /// Undo steps (oldest → newest).
    pub undo_stack: Vec<UndoHistoryStep>,
    /// Redo steps (oldest → newest).
    pub redo_stack: Vec<UndoHistoryStep>,
    /// Configured maximum undo history depth.
    pub max_undo: usize,
    /// Clean point tracking in the linearized history (index into `undo_stack + redo_stack`).
    pub clean_index: Option<usize>,
    /// The next group id to allocate.
    pub next_group_id: usize,
    /// Currently open coalescing group id, if any.
    pub open_group_id: Option<usize>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
#[cfg_attr(feature = "serde", derive(Serialize, Deserialize))]
/// A single undo/redo step in a persisted history snapshot.
pub struct UndoHistoryStep {
    /// Undo group id. Grouped undo pops all adjacent steps with the same id.
    pub group_id: usize,
    /// Text edits captured by this step.
    pub edits: Vec<UndoHistoryTextEdit>,
    /// Selection set snapshot before applying this step.
    pub before_selection: UndoHistorySelectionSet,
    /// Selection set snapshot after applying this step.
    pub after_selection: UndoHistorySelectionSet,
}

#[derive(Debug, Clone, PartialEq, Eq)]
#[cfg_attr(feature = "serde", derive(Serialize, Deserialize))]
/// A single persisted text edit in an undo/redo step.
pub struct UndoHistoryTextEdit {
    /// Start offset in the document *before* applying the edit.
    pub start_before: usize,
    /// Start offset in the document *after* applying the edit.
    pub start_after: usize,
    /// Deleted text (from the pre-edit document).
    pub deleted_text: String,
    /// Inserted text (from the post-edit document).
    pub inserted_text: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
#[cfg_attr(feature = "serde", derive(Serialize, Deserialize))]
/// Persisted selection set state captured alongside undo/redo steps.
pub struct UndoHistorySelectionSet {
    /// All selections (primary + secondary); may include empty selections (carets).
    pub selections: Vec<Selection>,
    /// Index of the primary selection in `selections`.
    pub primary_index: usize,
}

/// Errors produced when restoring undo history snapshots.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum UndoHistoryRestoreError {
    /// The snapshot uses a newer/unknown format version.
    UnsupportedFormatVersion(u32),
    /// The snapshot contains an invalid clean point index.
    InvalidCleanIndex {
        /// The invalid clean index value found in the snapshot.
        clean_index: usize,
        /// The maximum valid clean index (`undo_stack.len() + redo_stack.len()`).
        max_index: usize,
    },
}

impl std::fmt::Display for UndoHistoryRestoreError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            Self::UnsupportedFormatVersion(v) => {
                write!(f, "Unsupported undo history snapshot format_version={}", v)
            }
            Self::InvalidCleanIndex {
                clean_index,
                max_index,
            } => write!(
                f,
                "Invalid undo history snapshot clean_index={} (max={})",
                clean_index, max_index
            ),
        }
    }
}

impl std::error::Error for UndoHistoryRestoreError {}

const UNDO_HISTORY_SNAPSHOT_FORMAT_VERSION: u32 = 1;

impl UndoRedoManager {
    pub(super) fn snapshot(&self) -> UndoHistorySnapshot {
        let undo_nodes = self.undo_path_nodes_oldest_first();
        let redo_nodes_nearest_first = self.redo_path_nodes_nearest_first();

        let clean_index = self.clean_node.and_then(|clean| {
            if clean == 0 {
                return Some(0);
            }
            if let Some(pos) = undo_nodes.iter().position(|id| *id == clean) {
                return Some(pos + 1);
            }
            if let Some(pos) = redo_nodes_nearest_first.iter().position(|id| *id == clean) {
                return Some(undo_nodes.len() + pos + 1);
            }
            None
        });

        UndoHistorySnapshot {
            format_version: UNDO_HISTORY_SNAPSHOT_FORMAT_VERSION,
            undo_stack: self
                .undo_path_steps_oldest_first()
                .iter()
                .map(|step| UndoHistoryStep {
                    group_id: step.group_id,
                    edits: step
                        .edits
                        .iter()
                        .map(|edit| UndoHistoryTextEdit {
                            start_before: edit.start_before,
                            start_after: edit.start_after,
                            deleted_text: edit.deleted_text.clone(),
                            inserted_text: edit.inserted_text.clone(),
                        })
                        .collect(),
                    before_selection: UndoHistorySelectionSet {
                        selections: step.before_selection.selections.clone(),
                        primary_index: step.before_selection.primary_index,
                    },
                    after_selection: UndoHistorySelectionSet {
                        selections: step.after_selection.selections.clone(),
                        primary_index: step.after_selection.primary_index,
                    },
                })
                .collect(),
            redo_stack: self
                .redo_path_steps_newest_first()
                .iter()
                .map(|step| UndoHistoryStep {
                    group_id: step.group_id,
                    edits: step
                        .edits
                        .iter()
                        .map(|edit| UndoHistoryTextEdit {
                            start_before: edit.start_before,
                            start_after: edit.start_after,
                            deleted_text: edit.deleted_text.clone(),
                            inserted_text: edit.inserted_text.clone(),
                        })
                        .collect(),
                    before_selection: UndoHistorySelectionSet {
                        selections: step.before_selection.selections.clone(),
                        primary_index: step.before_selection.primary_index,
                    },
                    after_selection: UndoHistorySelectionSet {
                        selections: step.after_selection.selections.clone(),
                        primary_index: step.after_selection.primary_index,
                    },
                })
                .collect(),
            max_undo: self.max_undo,
            clean_index,
            next_group_id: self.next_group_id,
            open_group_id: self.current_group_id(),
        }
    }

    pub(super) fn restore_from_snapshot(
        &mut self,
        snapshot: UndoHistorySnapshot,
    ) -> Result<(), UndoHistoryRestoreError> {
        if snapshot.format_version != UNDO_HISTORY_SNAPSHOT_FORMAT_VERSION {
            return Err(UndoHistoryRestoreError::UnsupportedFormatVersion(
                snapshot.format_version,
            ));
        }

        let undo_steps = snapshot
            .undo_stack
            .into_iter()
            .map(|step| UndoStep {
                group_id: step.group_id,
                edits: step
                    .edits
                    .into_iter()
                    .map(|edit| TextEdit {
                        start_before: edit.start_before,
                        start_after: edit.start_after,
                        deleted_text: edit.deleted_text,
                        inserted_text: edit.inserted_text,
                    })
                    .collect(),
                before_selection: SelectionSetSnapshot {
                    selections: step.before_selection.selections,
                    primary_index: step.before_selection.primary_index,
                },
                after_selection: SelectionSetSnapshot {
                    selections: step.after_selection.selections,
                    primary_index: step.after_selection.primary_index,
                },
            })
            .collect::<Vec<_>>();

        let redo_steps = snapshot
            .redo_stack
            .into_iter()
            .map(|step| UndoStep {
                group_id: step.group_id,
                edits: step
                    .edits
                    .into_iter()
                    .map(|edit| TextEdit {
                        start_before: edit.start_before,
                        start_after: edit.start_after,
                        deleted_text: edit.deleted_text,
                        inserted_text: edit.inserted_text,
                    })
                    .collect(),
                before_selection: SelectionSetSnapshot {
                    selections: step.before_selection.selections,
                    primary_index: step.before_selection.primary_index,
                },
                after_selection: SelectionSetSnapshot {
                    selections: step.after_selection.selections,
                    primary_index: step.after_selection.primary_index,
                },
            })
            .collect::<Vec<_>>();

        let total_steps = undo_steps.len() + redo_steps.len();
        let max_undo = snapshot.max_undo.max(total_steps).max(1);
        if let Some(clean_index) = snapshot.clean_index
            && clean_index > total_steps
        {
            return Err(UndoHistoryRestoreError::InvalidCleanIndex {
                clean_index,
                max_index: total_steps,
            });
        }

        // Rebuild as a linear chain (snapshots do not persist alternative branches).
        self.nodes = vec![UndoNode {
            parent: None,
            children: Vec::new(),
            preferred_child: None,
            step: None,
        }];
        self.current = 0;
        self.step_count = 0;

        let mut node = 0usize;
        let mut undo_node_ids: Vec<UndoNodeId> = Vec::new();
        for step in undo_steps {
            let new_id = self.nodes.len();
            self.nodes.push(UndoNode {
                parent: Some(node),
                children: Vec::new(),
                preferred_child: None,
                step: Some(step),
            });
            self.nodes[node].children.push(new_id);
            self.nodes[node].preferred_child = Some(new_id);
            node = new_id;
            undo_node_ids.push(new_id);
            self.step_count = self.step_count.saturating_add(1);
        }

        let current_node = node;

        // `redo_steps` in the v1 snapshot format is stored in "stack order" (newest → oldest).
        // We recreate the redo path in redo order (oldest → newest) as a simple child chain.
        let mut redo_node_ids_nearest_first: Vec<UndoNodeId> = Vec::new();
        let mut redo_parent = current_node;
        for step in redo_steps.into_iter().rev() {
            let new_id = self.nodes.len();
            self.nodes.push(UndoNode {
                parent: Some(redo_parent),
                children: Vec::new(),
                preferred_child: None,
                step: Some(step),
            });
            self.nodes[redo_parent].children.push(new_id);
            self.nodes[redo_parent].preferred_child = Some(new_id);
            redo_parent = new_id;
            redo_node_ids_nearest_first.push(new_id);
            self.step_count = self.step_count.saturating_add(1);
        }

        self.current = current_node;
        self.max_undo = max_undo;
        self.next_group_id = snapshot.next_group_id;
        self.open_group = snapshot.open_group_id.and_then(|group_id| {
            let step = self.nodes.get(self.current)?.step.as_ref()?;
            if step.group_id != group_id {
                return None;
            }
            let kind = if coalescing_edits_for_kind(UndoEditKind::Insert, step).is_some() {
                UndoEditKind::Insert
            } else {
                UndoEditKind::Explicit
            };
            UndoCoalescingState::from_step(group_id, kind, step, Instant::now())
        });

        self.clean_node = snapshot.clean_index.and_then(|idx| {
            if idx == 0 {
                return Some(0);
            }
            let undo_len = undo_node_ids.len();
            if idx <= undo_len {
                return undo_node_ids.get(idx - 1).copied();
            }
            let redo_pos = idx.saturating_sub(undo_len + 1);
            redo_node_ids_nearest_first.get(redo_pos).copied()
        });

        Ok(())
    }

    pub(super) fn undo_path_nodes_oldest_first(&self) -> Vec<UndoNodeId> {
        let mut nodes: Vec<UndoNodeId> = Vec::new();
        let mut node = self.current;
        while node != 0 {
            nodes.push(node);
            node = self.nodes[node].parent.unwrap_or(0);
        }
        nodes.reverse();
        nodes
    }

    pub(super) fn redo_path_nodes_nearest_first(&self) -> Vec<UndoNodeId> {
        let mut out: Vec<UndoNodeId> = Vec::new();
        let mut node = self.current;
        while let Some(child) = self.selected_child(node) {
            out.push(child);
            node = child;
        }
        out
    }

    pub(super) fn undo_path_steps_oldest_first(&self) -> Vec<UndoStep> {
        self.undo_path_nodes_oldest_first()
            .into_iter()
            .filter_map(|id| self.nodes[id].step.as_ref().cloned())
            .collect()
    }

    /// Redo path steps in the legacy "redo stack order" (newest → oldest), matching the v1
    /// `UndoHistorySnapshot` semantics.
    pub(super) fn redo_path_steps_newest_first(&self) -> Vec<UndoStep> {
        let mut steps: Vec<UndoStep> = self
            .redo_path_nodes_nearest_first()
            .into_iter()
            .filter_map(|id| self.nodes[id].step.as_ref().cloned())
            .collect();
        steps.reverse();
        steps
    }
}
