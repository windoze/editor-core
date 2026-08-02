use crate::{EditorUi, UiError};
use editor_core::{SearchMatch, SearchOptions};
use std::collections::BTreeMap;

mod lsp_request_events;
mod lsp_result_events;
mod state_events;
mod workspace_diagnostics;
mod workspace_edit;
mod workspace_outline;

pub use lsp_request_events::{MultiDocumentLspRequestEvent, MultiDocumentLspRequestEventsSnapshot};
pub use lsp_result_events::{MultiDocumentLspResultEvent, MultiDocumentLspResultEventsSnapshot};
pub use state_events::{MultiDocumentStateEvent, MultiDocumentStateEventsSnapshot};
pub use workspace_diagnostics::{
    WorkspaceDiagnostic, WorkspaceDiagnosticDocumentReport, WorkspaceDiagnosticMarker,
    WorkspaceDiagnosticMarkersSnapshot, WorkspaceDiagnosticTarget, WorkspaceDiagnosticsEvent,
    WorkspaceDiagnosticsEventsSnapshot, WorkspaceDiagnosticsSnapshot, WorkspaceDiagnosticsStore,
};
pub use workspace_edit::{
    WorkspaceEditTransactionDocument, WorkspaceEditTransactionEvent,
    WorkspaceEditTransactionEventsSnapshot, WorkspaceEditTransactionResult,
};
pub use workspace_outline::{WorkspaceOutlineDocument, WorkspaceOutlineSnapshot};

/// Opaque id for an open tab/document managed by [`MultiDocumentEditorUi`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct TabId(u64);

impl TabId {
    /// Construct a tab id from its stable numeric representation.
    pub fn from_raw(raw: u64) -> Self {
        Self(raw)
    }

    /// Return the underlying numeric id.
    pub fn get(self) -> u64 {
        self.0
    }
}

/// Search results for a single tab.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TabSearchResult {
    /// Tab id.
    pub tab_id: TabId,
    /// Match ranges (character offsets, half-open).
    pub matches: Vec<SearchMatch>,
}

struct TabEntry {
    title: Option<String>,
    document_uri: Option<String>,
    views: Vec<EditorUi>,
    active_view: usize,
    is_preview: bool,
}

impl TabEntry {
    fn active_view(&self) -> Option<&EditorUi> {
        self.views.get(self.active_view)
    }

    fn active_view_mut(&mut self) -> Option<&mut EditorUi> {
        self.views.get_mut(self.active_view)
    }
}

/// A small multi-document orchestrator on top of [`EditorUi`].
///
/// Notes:
/// - Each tab owns its own `EditorUi` document (text/undo/derived state).
/// - Within a tab, split panes are supported via `EditorUi::clone_view(...)`.
#[derive(Default)]
pub struct MultiDocumentEditorUi {
    next_tab_id: u64,
    tabs: BTreeMap<TabId, TabEntry>,
    tab_order: Vec<TabId>,
    active_tab: Option<TabId>,
    preview_tab: Option<TabId>,
    workspace_diagnostics: WorkspaceDiagnosticsStore,
    lsp_result_events: lsp_result_events::MultiDocumentLspResultEventStore,
    lsp_request_events: lsp_request_events::MultiDocumentLspRequestEventStore,
    state_events: state_events::MultiDocumentStateEventStore,
    workspace_edit_transactions: workspace_edit::WorkspaceEditTransactionEventStore,
}

impl MultiDocumentEditorUi {
    /// Create an empty multi-document UI orchestrator.
    pub fn new() -> Self {
        Self::default()
    }

    /// Return the active tab id (if any).
    pub fn active_tab_id(&self) -> Option<TabId> {
        self.active_tab
    }

    /// Return all currently open tab ids in deterministic order.
    pub fn tab_ids(&self) -> Vec<TabId> {
        self.tab_order
            .iter()
            .copied()
            .filter(|id| self.tabs.contains_key(id))
            .collect()
    }

    /// Open a new tab with initial text and an initial wrap width.
    ///
    /// Returns the created tab id.
    pub fn open_tab(&mut self, text: &str, viewport_width_cells: usize) -> TabId {
        self.open_tab_impl(text, viewport_width_cells, false)
    }

    /// Open a preview tab (transient) with initial text.
    ///
    /// Notes:
    /// - If a preview tab already exists and is still unmodified, it is **reused** (replaced).
    /// - If the current preview tab is modified, it is treated as pinned and a new preview is opened.
    pub fn open_preview_tab(&mut self, text: &str, viewport_width_cells: usize) -> TabId {
        if let Some(prev) = self.preview_tab
            && let Some(tab) = self.tabs.get(&prev)
            && tab.is_preview
            && tab.active_view().is_some_and(|v| !v.is_modified())
        {
            // Replace the preview tab in-place (keep `TabId` stable for UI layers).
            let ui = EditorUi::new(text, viewport_width_cells.max(1));
            if let Some(entry) = self.tabs.get_mut(&prev) {
                entry.views = vec![ui];
                entry.active_view = 0;
                entry.title = None;
                entry.document_uri = None;
                entry.is_preview = true;
            }
            return prev;
        }

        let tab_id = self.open_tab_impl(text, viewport_width_cells, true);
        self.preview_tab = Some(tab_id);
        tab_id
    }

    fn open_tab_impl(
        &mut self,
        text: &str,
        viewport_width_cells: usize,
        is_preview: bool,
    ) -> TabId {
        let tab_id = TabId(self.next_tab_id);
        self.next_tab_id = self.next_tab_id.saturating_add(1);

        let ui = EditorUi::new(text, viewport_width_cells.max(1));

        self.tabs.insert(
            tab_id,
            TabEntry {
                title: None,
                document_uri: None,
                views: vec![ui],
                active_view: 0,
                is_preview,
            },
        );
        self.tab_order.push(tab_id);

        if self.active_tab.is_none() {
            self.active_tab = Some(tab_id);
        }

        tab_id
    }

    /// Return whether a tab is currently a preview tab.
    pub fn is_preview_tab(&self, tab_id: TabId) -> Option<bool> {
        self.tabs.get(&tab_id).map(|t| t.is_preview)
    }

    /// Pin a preview tab, converting it into a normal tab.
    pub fn pin_tab(&mut self, tab_id: TabId) -> Result<(), UiError> {
        let tab = self
            .tabs
            .get_mut(&tab_id)
            .ok_or_else(|| UiError::Processor(format!("unknown tab id {}", tab_id.get())))?;
        tab.is_preview = false;
        if self.preview_tab == Some(tab_id) {
            self.preview_tab = None;
        }
        Ok(())
    }

    /// Close a tab.
    ///
    /// Returns `true` if the tab existed.
    pub fn close_tab(&mut self, tab_id: TabId) -> bool {
        let closed_pos = self.tab_order.iter().position(|id| *id == tab_id);
        let existed = self.tabs.remove(&tab_id).is_some();

        if existed {
            self.tab_order.retain(|id| *id != tab_id);
        }

        if existed && self.active_tab == Some(tab_id) {
            self.active_tab = closed_pos
                .and_then(|idx| self.tab_order.get(idx).copied())
                .or_else(|| {
                    closed_pos
                        .and_then(|idx| idx.checked_sub(1))
                        .and_then(|idx| self.tab_order.get(idx).copied())
                })
                .or_else(|| self.tab_order.first().copied());
        }

        if existed && self.preview_tab == Some(tab_id) {
            self.preview_tab = None;
        }

        existed
    }

    /// Close all tabs.
    pub fn close_all_tabs(&mut self) {
        self.tabs.clear();
        self.tab_order.clear();
        self.active_tab = None;
        self.preview_tab = None;
    }

    /// Close all tabs except `tab_id`.
    ///
    /// Returns the number of tabs closed.
    pub fn close_other_tabs(&mut self, tab_id: TabId) -> Result<usize, UiError> {
        if !self.tabs.contains_key(&tab_id) {
            return Err(UiError::Processor(format!(
                "unknown tab id {}",
                tab_id.get()
            )));
        }

        let ids: Vec<TabId> = self.tab_ids();
        let mut closed = 0usize;
        for id in ids {
            if id == tab_id {
                continue;
            }
            if self.close_tab(id) {
                closed = closed.saturating_add(1);
            }
        }

        self.active_tab = Some(tab_id);
        Ok(closed)
    }

    /// Close tabs to the right of `tab_id`, based on current tab order.
    ///
    /// Returns the number of tabs closed.
    pub fn close_tabs_to_right(&mut self, tab_id: TabId) -> Result<usize, UiError> {
        let ids = self.tab_ids();
        let Some(pos) = ids.iter().position(|id| *id == tab_id) else {
            return Err(UiError::Processor(format!(
                "unknown tab id {}",
                tab_id.get()
            )));
        };

        let mut closed = 0usize;
        for id in ids.into_iter().skip(pos.saturating_add(1)) {
            if self.close_tab(id) {
                closed = closed.saturating_add(1);
            }
        }
        Ok(closed)
    }

    /// Move a tab by index in the current tab order.
    ///
    /// Returns `true` if the tab existed and its index changed.
    pub fn move_tab_index(&mut self, from_index: usize, to_index: usize) -> Result<bool, UiError> {
        if from_index >= self.tab_order.len()
            || to_index >= self.tab_order.len()
            || from_index == to_index
        {
            return Ok(false);
        }

        let tab_id = self.tab_order.remove(from_index);
        if !self.tabs.contains_key(&tab_id) {
            return Err(UiError::Processor(format!(
                "tab order referenced unknown tab id {}",
                tab_id.get()
            )));
        }
        self.tab_order.insert(to_index, tab_id);
        Ok(true)
    }

    /// Set the active tab.
    pub fn set_active_tab(&mut self, tab_id: TabId) -> Result<(), UiError> {
        if !self.tabs.contains_key(&tab_id) {
            return Err(UiError::Processor(format!(
                "unknown tab id {}",
                tab_id.get()
            )));
        }
        self.active_tab = Some(tab_id);
        Ok(())
    }

    /// Get the active tab title (if any).
    pub fn active_tab_title(&self) -> Option<&str> {
        let id = self.active_tab?;
        self.tabs.get(&id)?.title.as_deref()
    }

    /// Get a tab title by id (if the tab exists and has a title).
    pub fn tab_title(&self, tab_id: TabId) -> Option<&str> {
        self.tabs.get(&tab_id)?.title.as_deref()
    }

    /// Set a tab title.
    pub fn set_tab_title(&mut self, tab_id: TabId, title: Option<String>) -> Result<(), UiError> {
        let tab = self
            .tabs
            .get_mut(&tab_id)
            .ok_or_else(|| UiError::Processor(format!("unknown tab id {}", tab_id.get())))?;
        tab.title = title;
        Ok(())
    }

    /// Get the document URI associated with a tab, if one is known.
    pub fn tab_document_uri(&self, tab_id: TabId) -> Option<&str> {
        self.tabs.get(&tab_id)?.document_uri.as_deref()
    }

    /// Set or clear the document URI associated with a tab.
    pub fn set_tab_document_uri(
        &mut self,
        tab_id: TabId,
        document_uri: Option<String>,
    ) -> Result<(), UiError> {
        let tab = self
            .tabs
            .get_mut(&tab_id)
            .ok_or_else(|| UiError::Processor(format!("unknown tab id {}", tab_id.get())))?;
        tab.document_uri = document_uri;
        Ok(())
    }

    /// Borrow the active tab's active view (read-only).
    pub fn active_editor(&self) -> Option<&EditorUi> {
        let id = self.active_tab?;
        self.tabs.get(&id)?.active_view()
    }

    /// Borrow the active tab's active view (mutable).
    pub fn active_editor_mut(&mut self) -> Option<&mut EditorUi> {
        let id = self.active_tab?;
        self.tabs.get_mut(&id)?.active_view_mut()
    }

    /// Borrow a specific tab's active view (read-only).
    pub fn editor_for_tab(&self, tab_id: TabId) -> Option<&EditorUi> {
        self.tabs.get(&tab_id)?.active_view()
    }

    /// Borrow a specific tab's active view (mutable).
    pub fn editor_for_tab_mut(&mut self, tab_id: TabId) -> Option<&mut EditorUi> {
        self.tabs.get_mut(&tab_id)?.active_view_mut()
    }

    fn tab_entry(&self, tab_id: TabId) -> Result<&TabEntry, UiError> {
        self.tabs
            .get(&tab_id)
            .ok_or_else(|| UiError::Processor(format!("unknown tab id {}", tab_id.get())))
    }

    fn tab_entry_mut(&mut self, tab_id: TabId) -> Result<&mut TabEntry, UiError> {
        self.tabs
            .get_mut(&tab_id)
            .ok_or_else(|| UiError::Processor(format!("unknown tab id {}", tab_id.get())))
    }

    /// Return the active view text for a tab.
    pub fn tab_text(&self, tab_id: TabId) -> Result<String, UiError> {
        let tab = self.tab_entry(tab_id)?;
        Ok(tab
            .active_view()
            .ok_or_else(|| UiError::Processor("tab has no views".to_string()))?
            .text())
    }

    /// Return whether the active view for a tab is modified.
    pub fn is_tab_modified(&self, tab_id: TabId) -> Result<bool, UiError> {
        let tab = self.tab_entry(tab_id)?;
        Ok(tab
            .active_view()
            .ok_or_else(|| UiError::Processor("tab has no views".to_string()))?
            .is_modified())
    }

    /// Replace a tab's full text in the active view.
    ///
    /// This is intended for native UI mirrors that currently own text input but still need the
    /// core multi-document model to stay searchable and dirty-aware during migration.
    pub fn replace_tab_text(
        &mut self,
        tab_id: TabId,
        text: &str,
        mark_saved: bool,
    ) -> Result<(), UiError> {
        let tab = self.tab_entry_mut(tab_id)?;
        let view = tab
            .active_view_mut()
            .ok_or_else(|| UiError::Processor("tab has no views".to_string()))?;
        let length = view.text().chars().count();
        let text_json = serde_json::to_string(text).map_err(|err| {
            UiError::Processor(format!("failed to encode replacement text: {err}"))
        })?;
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

    /// Mark a tab's active view as saved.
    pub fn mark_tab_saved(&mut self, tab_id: TabId) -> Result<(), UiError> {
        let tab = self.tab_entry_mut(tab_id)?;
        tab.active_view_mut()
            .ok_or_else(|| UiError::Processor("tab has no views".to_string()))?
            .mark_saved();
        Ok(())
    }

    /// Create a split pane within a tab by cloning the active view.
    ///
    /// Returns the new view index within the tab.
    pub fn split_tab(
        &mut self,
        tab_id: TabId,
        viewport_width_cells: usize,
    ) -> Result<usize, UiError> {
        let tab = self
            .tabs
            .get_mut(&tab_id)
            .ok_or_else(|| UiError::Processor(format!("unknown tab id {}", tab_id.get())))?;

        let new_view = tab
            .active_view()
            .ok_or_else(|| UiError::Processor("tab has no views".to_string()))?
            .clone_view(viewport_width_cells.max(1))?;

        tab.views.push(new_view);
        let idx = tab.views.len().saturating_sub(1);
        tab.active_view = idx;
        Ok(idx)
    }

    /// Set the active view index for a tab.
    pub fn set_active_view_index(
        &mut self,
        tab_id: TabId,
        view_index: usize,
    ) -> Result<(), UiError> {
        let tab = self
            .tabs
            .get_mut(&tab_id)
            .ok_or_else(|| UiError::Processor(format!("unknown tab id {}", tab_id.get())))?;
        if view_index >= tab.views.len() {
            return Err(UiError::Processor(format!(
                "invalid view index {} (tab has {})",
                view_index,
                tab.views.len()
            )));
        }
        tab.active_view = view_index;
        Ok(())
    }

    /// Close a view within a tab.
    ///
    /// Returns `true` if the view existed and was closed. The last remaining view is kept.
    pub fn close_view_index(&mut self, tab_id: TabId, view_index: usize) -> Result<bool, UiError> {
        let tab = self
            .tabs
            .get_mut(&tab_id)
            .ok_or_else(|| UiError::Processor(format!("unknown tab id {}", tab_id.get())))?;
        if view_index >= tab.views.len() {
            return Ok(false);
        }
        if tab.views.len() <= 1 {
            return Ok(false);
        }
        tab.views.remove(view_index);
        if tab.active_view >= tab.views.len() {
            tab.active_view = tab.views.len().saturating_sub(1);
        } else if tab.active_view > view_index {
            tab.active_view = tab.active_view.saturating_sub(1);
        }
        Ok(true)
    }

    /// Move a view within a tab.
    ///
    /// Returns `true` if the view existed and its index changed.
    pub fn move_view_index(
        &mut self,
        tab_id: TabId,
        from_index: usize,
        to_index: usize,
    ) -> Result<bool, UiError> {
        let tab = self
            .tabs
            .get_mut(&tab_id)
            .ok_or_else(|| UiError::Processor(format!("unknown tab id {}", tab_id.get())))?;
        if from_index >= tab.views.len() || to_index >= tab.views.len() || from_index == to_index {
            return Ok(false);
        }

        let view = tab.views.remove(from_index);
        tab.views.insert(to_index, view);

        if tab.active_view == from_index {
            tab.active_view = to_index;
        } else if from_index < tab.active_view && tab.active_view <= to_index {
            tab.active_view = tab.active_view.saturating_sub(1);
        } else if to_index <= tab.active_view && tab.active_view < from_index {
            tab.active_view = tab.active_view.saturating_add(1);
        }

        Ok(true)
    }

    /// Return the number of views in a tab.
    pub fn view_count(&self, tab_id: TabId) -> Option<usize> {
        self.tabs.get(&tab_id).map(|t| t.views.len())
    }

    /// Return the active view index in a tab.
    pub fn active_view_index(&self, tab_id: TabId) -> Option<usize> {
        self.tabs.get(&tab_id).map(|t| t.active_view)
    }

    /// Search across all open tabs.
    ///
    /// This is an in-memory helper intended for command palette / panel UIs.
    pub fn search_all_tabs(
        &self,
        query: &str,
        options: SearchOptions,
    ) -> Result<Vec<TabSearchResult>, editor_core::SearchError> {
        let mut out = Vec::new();
        for tab_id in self.tab_ids() {
            let Some(tab) = self.tabs.get(&tab_id) else {
                continue;
            };
            let Some(view) = tab.active_view() else {
                continue;
            };
            let matches = editor_core::search::find_all(view.text().as_str(), query, options)?;
            if matches.is_empty() {
                continue;
            }
            out.push(TabSearchResult { tab_id, matches });
        }
        Ok(out)
    }

    /// Return the current workspace outline aggregated from each tab's active view.
    pub fn workspace_outline_snapshot(&self) -> Result<WorkspaceOutlineSnapshot, UiError> {
        workspace_outline::snapshot(&self.tabs, &self.tab_order)
    }

    /// Return the current workspace outline as JSON.
    pub fn workspace_outline_snapshot_json(&self) -> Result<String, UiError> {
        workspace_outline::snapshot_json(&self.tabs, &self.tab_order)
    }

    /// Apply an LSP `textDocument/documentSymbol` result JSON payload to a tab's document.
    pub fn apply_tab_document_symbols_json(
        &mut self,
        tab_id: TabId,
        json: &str,
    ) -> Result<(), UiError> {
        let tab = self
            .tabs
            .get_mut(&tab_id)
            .ok_or_else(|| UiError::Processor(format!("unknown tab id {}", tab_id.get())))?;
        let view = tab.active_view_mut().ok_or_else(|| {
            UiError::Processor(format!("tab {} has no active view", tab_id.get()))
        })?;
        view.lsp_apply_document_symbols_json(json)
    }

    /// Preview applying an LSP `WorkspaceEdit` across open tabs owned by this model.
    pub fn preview_workspace_edit_transaction(
        &self,
        workspace_edit_json: &str,
    ) -> Result<WorkspaceEditTransactionResult, UiError> {
        workspace_edit::preview(&self.tabs, &self.tab_order, workspace_edit_json)
    }

    /// Preview applying an LSP `WorkspaceEdit` across open tabs as JSON.
    pub fn preview_workspace_edit_transaction_json(
        &self,
        workspace_edit_json: &str,
    ) -> Result<String, UiError> {
        workspace_edit::preview_json(&self.tabs, &self.tab_order, workspace_edit_json)
    }

    /// Apply an LSP `WorkspaceEdit` to matching open tabs owned by this model.
    pub fn apply_workspace_edit_transaction(
        &mut self,
        workspace_edit_json: &str,
    ) -> Result<WorkspaceEditTransactionResult, UiError> {
        let result = workspace_edit::apply(&mut self.tabs, &self.tab_order, workspace_edit_json)?;
        self.workspace_edit_transactions
            .record("apply", result.clone());
        Ok(result)
    }

    /// Apply an LSP `WorkspaceEdit` to matching open tabs owned by this model as JSON.
    pub fn apply_workspace_edit_transaction_json(
        &mut self,
        workspace_edit_json: &str,
    ) -> Result<String, UiError> {
        let result = self.apply_workspace_edit_transaction(workspace_edit_json)?;
        serde_json::to_string(&result).map_err(|err| {
            UiError::Processor(format!(
                "failed to encode workspace edit transaction: {err}"
            ))
        })
    }

    /// Return latest WorkspaceEdit transaction event sequence.
    pub fn workspace_edit_transaction_events_latest_sequence(&self) -> u64 {
        self.workspace_edit_transactions.latest_sequence()
    }

    /// Return WorkspaceEdit transaction events newer than `after_sequence`.
    pub fn workspace_edit_transaction_events_after(
        &self,
        after_sequence: u64,
    ) -> WorkspaceEditTransactionEventsSnapshot {
        self.workspace_edit_transactions
            .events_after(after_sequence)
    }

    /// Return WorkspaceEdit transaction events newer than `after_sequence` as JSON.
    pub fn workspace_edit_transaction_events_json(
        &self,
        after_sequence: u64,
    ) -> Result<String, UiError> {
        self.workspace_edit_transactions
            .events_after_json(after_sequence)
    }

    /// Clear the project/workspace diagnostic state owned by this multi-document UI model.
    pub fn clear_workspace_diagnostics(&mut self) {
        self.workspace_diagnostics.clear();
    }

    /// Merge an LSP `workspace/diagnostic` result JSON payload into the project diagnostics.
    pub fn apply_workspace_diagnostics_json(
        &mut self,
        json: &str,
    ) -> Result<WorkspaceDiagnosticsSnapshot, UiError> {
        self.workspace_diagnostics.apply_lsp_result_json(json)
    }

    /// Return the current workspace diagnostics snapshot.
    pub fn workspace_diagnostics_snapshot(&self) -> WorkspaceDiagnosticsSnapshot {
        self.workspace_diagnostics.snapshot()
    }

    /// Return the current workspace diagnostics snapshot as JSON.
    pub fn workspace_diagnostics_snapshot_json(&self) -> Result<String, UiError> {
        self.workspace_diagnostics.snapshot_json()
    }

    /// Return project-level diagnostic marker projections.
    pub fn workspace_diagnostic_markers_snapshot(&self) -> WorkspaceDiagnosticMarkersSnapshot {
        self.workspace_diagnostics.marker_snapshot()
    }

    /// Return project-level diagnostic marker projections as JSON.
    pub fn workspace_diagnostic_markers_json(&self) -> Result<String, UiError> {
        self.workspace_diagnostics.marker_snapshot_json()
    }

    /// Return previous-result ids for the next LSP `workspace/diagnostic` request.
    pub fn workspace_diagnostics_previous_result_ids_json(&self) -> Result<String, UiError> {
        self.workspace_diagnostics.previous_result_ids_json()
    }

    /// Return latest workspace diagnostics event sequence.
    pub fn workspace_diagnostics_latest_event_sequence(&self) -> u64 {
        self.workspace_diagnostics.latest_event_sequence()
    }

    /// Return workspace diagnostics events newer than `after_sequence`.
    pub fn workspace_diagnostics_events_after(
        &self,
        after_sequence: u64,
    ) -> WorkspaceDiagnosticsEventsSnapshot {
        self.workspace_diagnostics.events_after(after_sequence)
    }

    /// Return workspace diagnostics events newer than `after_sequence` as JSON.
    pub fn workspace_diagnostics_events_json(
        &self,
        after_sequence: u64,
    ) -> Result<String, UiError> {
        self.workspace_diagnostics.events_after_json(after_sequence)
    }

    /// Refresh and return latest aggregated LSP result event sequence across tabs/views.
    pub fn lsp_result_events_latest_sequence(&mut self) -> u64 {
        self.lsp_result_events
            .refresh_from_tabs(&self.tabs, &self.tab_order);
        self.lsp_result_events.latest_sequence()
    }

    /// Refresh and return aggregated LSP result events newer than `after_sequence`.
    pub fn lsp_result_events_after(
        &mut self,
        after_sequence: u64,
    ) -> MultiDocumentLspResultEventsSnapshot {
        self.lsp_result_events
            .refresh_from_tabs(&self.tabs, &self.tab_order);
        self.lsp_result_events.events_after(after_sequence)
    }

    /// Refresh and return aggregated LSP result events newer than `after_sequence` as JSON.
    pub fn lsp_result_events_json(&mut self, after_sequence: u64) -> Result<String, UiError> {
        self.lsp_result_events
            .refresh_from_tabs(&self.tabs, &self.tab_order);
        self.lsp_result_events
            .events_after_json(after_sequence)
            .map_err(|err| UiError::Processor(err.to_string()))
    }

    /// Refresh and return latest aggregated LSP request event sequence across tabs/views.
    pub fn lsp_request_events_latest_sequence(&mut self) -> u64 {
        self.lsp_request_events
            .refresh_from_tabs(&self.tabs, &self.tab_order);
        self.lsp_request_events.latest_sequence()
    }

    /// Refresh and return aggregated LSP request events newer than `after_sequence`.
    pub fn lsp_request_events_after(
        &mut self,
        after_sequence: u64,
    ) -> MultiDocumentLspRequestEventsSnapshot {
        self.lsp_request_events
            .refresh_from_tabs(&self.tabs, &self.tab_order);
        self.lsp_request_events.events_after(after_sequence)
    }

    /// Refresh and return aggregated LSP request events newer than `after_sequence` as JSON.
    pub fn lsp_request_events_json(&mut self, after_sequence: u64) -> Result<String, UiError> {
        self.lsp_request_events
            .refresh_from_tabs(&self.tabs, &self.tab_order);
        self.lsp_request_events
            .events_after_json(after_sequence)
            .map_err(|err| UiError::Processor(err.to_string()))
    }

    /// Refresh and return latest aggregated state event sequence across tabs/views.
    pub fn state_events_latest_sequence(&mut self) -> u64 {
        self.state_events
            .refresh_from_tabs(&self.tabs, &self.tab_order);
        self.state_events.latest_sequence()
    }

    /// Refresh and return aggregated state events newer than `after_sequence`.
    pub fn state_events_after(&mut self, after_sequence: u64) -> MultiDocumentStateEventsSnapshot {
        self.state_events
            .refresh_from_tabs(&self.tabs, &self.tab_order);
        self.state_events.events_after(after_sequence)
    }

    /// Refresh and return aggregated state events newer than `after_sequence` as JSON.
    pub fn state_events_json(&mut self, after_sequence: u64) -> Result<String, UiError> {
        self.state_events
            .refresh_from_tabs(&self.tabs, &self.tab_order);
        self.state_events
            .events_after_json(after_sequence)
            .map_err(|err| UiError::Processor(err.to_string()))
    }
}
