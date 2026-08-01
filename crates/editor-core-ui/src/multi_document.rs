use crate::{EditorUi, UiError};
use editor_core::{SearchMatch, SearchOptions};
use std::collections::BTreeMap;

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
    active_tab: Option<TabId>,
    preview_tab: Option<TabId>,
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
        self.tabs.keys().cloned().collect()
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
                views: vec![ui],
                active_view: 0,
                is_preview,
            },
        );

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
        let existed = self.tabs.remove(&tab_id).is_some();

        if existed && self.active_tab == Some(tab_id) {
            self.active_tab = self.tabs.keys().next().cloned();
        }

        if existed && self.preview_tab == Some(tab_id) {
            self.preview_tab = None;
        }

        existed
    }

    /// Close all tabs.
    pub fn close_all_tabs(&mut self) {
        self.tabs.clear();
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
        for (tab_id, tab) in &self.tabs {
            let Some(view) = tab.active_view() else {
                continue;
            };
            let matches = editor_core::search::find_all(view.text().as_str(), query, options)?;
            if matches.is_empty() {
                continue;
            }
            out.push(TabSearchResult {
                tab_id: *tab_id,
                matches,
            });
        }
        Ok(out)
    }
}
