//! Workspace and multi-buffer / multi-view model.
//!
//! `editor-core` is intentionally UI-agnostic, but a full-featured editor typically needs a
//! kernel-level model for:
//!
//! - managing multiple open buffers (text + undo + derived metadata)
//! - managing multiple views into the same buffer (split panes)
//!
//! This module provides a small [`Workspace`] that owns:
//! - `BufferId` + `CommandExecutor` (buffer text + undo + derived state)
//! - `ViewId` + per-view state (selections/cursors, wrap config, scroll)
//!
//! The workspace executes commands **against a specific view**. Text edits are applied to the
//! underlying buffer, and any resulting [`crate::TextDelta`] is broadcast to all views of the
//! same buffer.

use crate::commands::{
    Command, CommandExecutor, CommandResult, CursorCommand, EditCommand, TextEditSpec,
};
use crate::delta::TextDelta;
use crate::processing::ProcessingEdit;
use crate::search::{SearchError, SearchMatch, SearchOptions, find_all};
use crate::selection_set::selection_direction;
use crate::{LineIndex, Position, Selection, TabKeyBehavior, ViewCommand};
use crate::{StateChange, StateChangeCallback, StateChangeType, WrapIndent, WrapMode};
use std::collections::{BTreeMap, HashMap, HashSet};
use std::ops::Range;
use std::sync::Arc;

/// Opaque identifier for an open buffer in a [`Workspace`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct BufferId(u64);

impl BufferId {
    /// Get the underlying numeric id.
    pub fn get(self) -> u64 {
        self.0
    }
}

/// Opaque identifier for a view into a buffer in a [`Workspace`].
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub struct ViewId(u64);

impl ViewId {
    /// Get the underlying numeric id.
    pub fn get(self) -> u64 {
        self.0
    }
}

/// Metadata attached to a workspace buffer.
#[derive(Debug, Clone)]
pub struct BufferMetadata {
    /// Optional buffer URI/path (host-provided).
    pub uri: Option<String>,
}

/// Result of opening a buffer (a buffer always starts with a default view).
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct OpenBufferResult {
    /// The created buffer id.
    pub buffer_id: BufferId,
    /// The initial view id into that buffer.
    pub view_id: ViewId,
}

#[derive(Debug, Clone, PartialEq, Eq)]
struct ViewCore {
    cursor_position: Position,
    selection: Option<Selection>,
    secondary_selections: Vec<Selection>,
    viewport_width: usize,
    wrap_mode: WrapMode,
    wrap_indent: WrapIndent,
    tab_width: usize,
    tab_key_behavior: TabKeyBehavior,
    preferred_x_cells: Option<usize>,
}

impl ViewCore {
    fn from_executor(executor: &CommandExecutor) -> Self {
        let editor = executor.editor();
        Self {
            cursor_position: editor.cursor_position,
            selection: editor.selection.clone(),
            secondary_selections: editor.secondary_selections.clone(),
            viewport_width: editor.viewport_width,
            wrap_mode: editor.layout_engine.wrap_mode(),
            wrap_indent: editor.layout_engine.wrap_indent(),
            tab_width: editor.layout_engine.tab_width(),
            tab_key_behavior: executor.tab_key_behavior(),
            preferred_x_cells: executor.preferred_x_cells(),
        }
    }

    fn apply_to_executor(&self, executor: &mut CommandExecutor) {
        let mut invalidate_visual_rows = false;
        let editor = executor.editor_mut();
        editor.cursor_position = self.cursor_position;
        editor.selection = self.selection.clone();
        editor.secondary_selections = self.secondary_selections.clone();

        if editor.viewport_width != self.viewport_width {
            editor.viewport_width = self.viewport_width;
            invalidate_visual_rows = true;
        }

        let before_wrap_mode = editor.layout_engine.wrap_mode();
        let before_wrap_indent = editor.layout_engine.wrap_indent();
        let before_tab_width = editor.layout_engine.tab_width();
        let before_viewport_width = editor.layout_engine.viewport_width();
        editor.layout_engine.set_viewport_width(self.viewport_width);
        editor.layout_engine.set_wrap_mode(self.wrap_mode);
        editor.layout_engine.set_wrap_indent(self.wrap_indent);
        editor.layout_engine.set_tab_width(self.tab_width);
        if before_wrap_mode != self.wrap_mode
            || before_wrap_indent != self.wrap_indent
            || before_tab_width != self.tab_width
            || before_viewport_width != self.viewport_width
        {
            invalidate_visual_rows = true;
        }

        if invalidate_visual_rows {
            editor.invalidate_visual_row_index_cache();
        }

        executor.set_tab_key_behavior(self.tab_key_behavior);
        executor.set_preferred_x_cells(self.preferred_x_cells);
    }
}

struct BufferEntry {
    meta: BufferMetadata,
    executor: CommandExecutor,
    version: u64,
    last_text_delta: Option<Arc<TextDelta>>,
}

struct ViewEntry {
    buffer: BufferId,
    core: ViewCore,
    version: u64,
    callbacks: Vec<StateChangeCallback>,
    scroll_top: usize,
    scroll_sub_row_offset: u16,
    overscan_rows: usize,
    viewport_height: Option<usize>,
    last_text_delta: Option<Arc<TextDelta>>,
}

/// Workspace-level errors.
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum WorkspaceError {
    /// A buffer with this uri already exists.
    UriAlreadyOpen(String),
    /// A buffer id was not found.
    BufferNotFound(BufferId),
    /// A view id was not found.
    ViewNotFound(ViewId),
    /// Executing a command failed.
    CommandFailed {
        /// Target view id.
        view: ViewId,
        /// Error message.
        message: String,
    },
    /// Applying edits to a buffer failed.
    ApplyEditsFailed {
        /// Target buffer id.
        buffer: BufferId,
        /// Error message.
        message: String,
    },
}

/// Search matches for a single open buffer in a [`Workspace`].
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceSearchResult {
    /// Buffer id.
    pub id: BufferId,
    /// Optional URI/path metadata.
    pub uri: Option<String>,
    /// All matches in this buffer (character offsets, half-open).
    pub matches: Vec<SearchMatch>,
}

/// Smooth-scrolling state for a view.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct ViewSmoothScrollState {
    /// Top visual row anchor.
    pub top_visual_row: usize,
    /// Sub-row offset within `top_visual_row` (0..=65535, normalized).
    pub sub_row_offset: u16,
    /// Overscan rows for prefetching.
    pub overscan_rows: usize,
}

/// Viewport state for a workspace view, including visual totals and smooth-scrolling metadata.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct WorkspaceViewportState {
    /// Viewport width (in cells).
    pub width: usize,
    /// Viewport height (line count, host-provided).
    pub height: Option<usize>,
    /// Current top visual row.
    pub scroll_top: usize,
    /// Visible visual range.
    pub visible_lines: Range<usize>,
    /// Total visual line count under current view config (wrap + folding aware).
    pub total_visual_lines: usize,
    /// Smooth-scroll metadata.
    pub smooth_scroll: ViewSmoothScrollState,
    /// Recommended prefetch range using overscan rows.
    pub prefetch_lines: Range<usize>,
}

fn apply_char_offset_delta(mut offset: usize, delta: &TextDelta) -> usize {
    for edit in &delta.edits {
        let start = edit.start;
        let end = edit.end();
        let deleted_len = edit.deleted_len();
        let inserted_len = edit.inserted_len();

        if offset < start {
            continue;
        }

        if offset < end {
            // If the caret was inside the replaced range, anchor it at the end of the inserted text.
            offset = start.saturating_add(inserted_len);
            continue;
        }

        // After the replaced range: shift by the net length delta.
        if inserted_len >= deleted_len {
            offset = offset.saturating_add(inserted_len - deleted_len);
        } else {
            offset = offset.saturating_sub(deleted_len - inserted_len);
        }
    }

    offset
}

fn apply_position_delta(
    old_index: &LineIndex,
    new_index: &LineIndex,
    pos: Position,
    delta: &TextDelta,
) -> Position {
    let before = old_index.position_to_char_offset(pos.line, pos.column);
    let after = apply_char_offset_delta(before, delta);
    let (line, column) = new_index.char_offset_to_position(after);
    Position::new(line, column)
}

fn apply_selection_delta(
    old_index: &LineIndex,
    new_index: &LineIndex,
    selection: &Selection,
    delta: &TextDelta,
) -> Selection {
    let start = apply_position_delta(old_index, new_index, selection.start, delta);
    let end = apply_position_delta(old_index, new_index, selection.end, delta);
    Selection {
        start,
        end,
        direction: selection_direction(start, end),
    }
}

/// A collection of open buffers and their views.
#[derive(Default)]
pub struct Workspace {
    next_buffer_id: u64,
    buffers: BTreeMap<BufferId, BufferEntry>,
    uri_to_buffer: HashMap<String, BufferId>,

    next_view_id: u64,
    views: BTreeMap<ViewId, ViewEntry>,
    active_view: Option<ViewId>,
}

impl std::fmt::Debug for Workspace {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Workspace")
            .field("buffer_count", &self.buffers.len())
            .field("view_count", &self.views.len())
            .field("uri_count", &self.uri_to_buffer.len())
            .field("active_view", &self.active_view)
            .finish()
    }
}

impl Workspace {
    /// Create an empty workspace.
    pub fn new() -> Self {
        Self::default()
    }

    /// Returns the number of open buffers.
    pub fn len(&self) -> usize {
        self.buffers.len()
    }

    /// Returns `true` if there are no open buffers.
    pub fn is_empty(&self) -> bool {
        self.buffers.is_empty()
    }

    /// Returns the number of open views.
    pub fn view_count(&self) -> usize {
        self.views.len()
    }

    /// Return the active view id (if any).
    pub fn active_view_id(&self) -> Option<ViewId> {
        self.active_view
    }

    /// Return the active buffer id (if any).
    pub fn active_buffer_id(&self) -> Option<BufferId> {
        let view_id = self.active_view?;
        self.views.get(&view_id).map(|v| v.buffer)
    }

    /// Set the active view.
    pub fn set_active_view(&mut self, id: ViewId) -> Result<(), WorkspaceError> {
        if !self.views.contains_key(&id) {
            return Err(WorkspaceError::ViewNotFound(id));
        }
        self.active_view = Some(id);
        Ok(())
    }

    /// Open a new buffer in the workspace, creating an initial view.
    ///
    /// - `uri` is optional and host-provided (e.g. `file:///...`).
    /// - `text` is the initial contents.
    /// - `viewport_width` is the initial view's wrap width.
    pub fn open_buffer(
        &mut self,
        uri: Option<String>,
        text: &str,
        viewport_width: usize,
    ) -> Result<OpenBufferResult, WorkspaceError> {
        if let Some(uri) = uri.as_ref()
            && self.uri_to_buffer.contains_key(uri)
        {
            return Err(WorkspaceError::UriAlreadyOpen(uri.clone()));
        }

        let buffer_id = BufferId(self.next_buffer_id);
        self.next_buffer_id = self.next_buffer_id.saturating_add(1);

        let executor = CommandExecutor::new(text, viewport_width);
        let meta = BufferMetadata { uri: uri.clone() };
        self.buffers.insert(
            buffer_id,
            BufferEntry {
                meta,
                executor,
                version: 0,
                last_text_delta: None,
            },
        );

        if let Some(uri) = uri {
            self.uri_to_buffer.insert(uri, buffer_id);
        }

        let view_id = self.create_view(buffer_id, viewport_width)?;

        if self.active_view.is_none() {
            self.active_view = Some(view_id);
        }

        Ok(OpenBufferResult { buffer_id, view_id })
    }

    /// Close a buffer (and all its views).
    pub fn close_buffer(&mut self, id: BufferId) -> Result<(), WorkspaceError> {
        let Some(entry) = self.buffers.remove(&id) else {
            return Err(WorkspaceError::BufferNotFound(id));
        };

        if let Some(uri) = entry.meta.uri.as_ref() {
            self.uri_to_buffer.remove(uri);
        }

        let views_to_remove: Vec<ViewId> = self
            .views
            .iter()
            .filter_map(|(vid, v)| if v.buffer == id { Some(*vid) } else { None })
            .collect();
        for view_id in views_to_remove {
            self.views.remove(&view_id);
        }

        if self
            .active_view
            .is_some_and(|active| !self.views.contains_key(&active))
        {
            self.active_view = self.views.keys().next().copied();
        }

        Ok(())
    }

    /// Close a view. If it was the last view of its buffer, the buffer is also closed.
    pub fn close_view(&mut self, id: ViewId) -> Result<(), WorkspaceError> {
        let Some(view) = self.views.remove(&id) else {
            return Err(WorkspaceError::ViewNotFound(id));
        };

        if self.active_view == Some(id) {
            self.active_view = self.views.keys().next().copied();
        }

        let still_has_views = self.views.values().any(|v| v.buffer == view.buffer);
        if !still_has_views {
            self.close_buffer(view.buffer)?;
        }

        Ok(())
    }

    /// Create a new view into an existing buffer.
    pub fn create_view(
        &mut self,
        buffer: BufferId,
        viewport_width: usize,
    ) -> Result<ViewId, WorkspaceError> {
        let Some(buffer_entry) = self.buffers.get_mut(&buffer) else {
            return Err(WorkspaceError::BufferNotFound(buffer));
        };

        // Create a view state by starting from the executor defaults, but overriding width and
        // clearing selection/cursors.
        let mut core = ViewCore::from_executor(&buffer_entry.executor);
        core.cursor_position = Position::new(0, 0);
        core.selection = None;
        core.secondary_selections.clear();
        core.viewport_width = viewport_width.max(1);
        core.preferred_x_cells = None;

        let view_id = ViewId(self.next_view_id);
        self.next_view_id = self.next_view_id.saturating_add(1);

        self.views.insert(
            view_id,
            ViewEntry {
                buffer,
                core,
                version: 0,
                callbacks: Vec::new(),
                scroll_top: 0,
                scroll_sub_row_offset: 0,
                overscan_rows: 0,
                viewport_height: None,
                last_text_delta: None,
            },
        );

        Ok(view_id)
    }

    /// Look up a buffer by uri.
    pub fn buffer_id_for_uri(&self, uri: &str) -> Option<BufferId> {
        self.uri_to_buffer.get(uri).copied()
    }

    /// Get a buffer's metadata.
    pub fn buffer_metadata(&self, id: BufferId) -> Option<&BufferMetadata> {
        self.buffers.get(&id).map(|e| &e.meta)
    }

    /// Get the buffer id that a view is pointing at.
    pub fn buffer_id_for_view(&self, id: ViewId) -> Result<BufferId, WorkspaceError> {
        self.views
            .get(&id)
            .map(|v| v.buffer)
            .ok_or(WorkspaceError::ViewNotFound(id))
    }

    /// Get the primary cursor position for a view.
    pub fn cursor_position_for_view(&self, id: ViewId) -> Result<Position, WorkspaceError> {
        self.views
            .get(&id)
            .map(|v| v.core.cursor_position)
            .ok_or(WorkspaceError::ViewNotFound(id))
    }

    /// Get the primary selection for a view (None means "empty selection / caret only").
    pub fn selection_for_view(&self, id: ViewId) -> Result<Option<Selection>, WorkspaceError> {
        self.views
            .get(&id)
            .map(|v| v.core.selection.clone())
            .ok_or(WorkspaceError::ViewNotFound(id))
    }

    /// Get the scroll position (top visual row) for a view.
    pub fn scroll_top_for_view(&self, id: ViewId) -> Result<usize, WorkspaceError> {
        self.views
            .get(&id)
            .map(|v| v.scroll_top)
            .ok_or(WorkspaceError::ViewNotFound(id))
    }

    /// Get the sub-row smooth-scroll offset for a view.
    pub fn scroll_sub_row_offset_for_view(&self, id: ViewId) -> Result<u16, WorkspaceError> {
        self.views
            .get(&id)
            .map(|v| v.scroll_sub_row_offset)
            .ok_or(WorkspaceError::ViewNotFound(id))
    }

    /// Get overscan rows for a view.
    pub fn overscan_rows_for_view(&self, id: ViewId) -> Result<usize, WorkspaceError> {
        self.views
            .get(&id)
            .map(|v| v.overscan_rows)
            .ok_or(WorkspaceError::ViewNotFound(id))
    }

    /// Get smooth-scroll state for a view.
    pub fn smooth_scroll_state_for_view(
        &self,
        id: ViewId,
    ) -> Result<ViewSmoothScrollState, WorkspaceError> {
        let Some(view) = self.views.get(&id) else {
            return Err(WorkspaceError::ViewNotFound(id));
        };
        Ok(ViewSmoothScrollState {
            top_visual_row: view.scroll_top,
            sub_row_offset: view.scroll_sub_row_offset,
            overscan_rows: view.overscan_rows,
        })
    }

    /// Update a buffer's uri/path.
    pub fn set_buffer_uri(
        &mut self,
        id: BufferId,
        uri: Option<String>,
    ) -> Result<(), WorkspaceError> {
        let Some(entry) = self.buffers.get_mut(&id) else {
            return Err(WorkspaceError::BufferNotFound(id));
        };

        if let Some(next) = uri.as_ref()
            && self.uri_to_buffer.contains_key(next)
            && entry.meta.uri.as_deref() != Some(next.as_str())
        {
            return Err(WorkspaceError::UriAlreadyOpen(next.clone()));
        }

        if let Some(prev) = entry.meta.uri.take() {
            self.uri_to_buffer.remove(&prev);
        }

        if let Some(next) = uri.clone() {
            self.uri_to_buffer.insert(next, id);
        }

        entry.meta.uri = uri;
        Ok(())
    }

    /// Get a view's current version (increments on view-local changes and buffer changes).
    pub fn view_version(&self, id: ViewId) -> Option<u64> {
        self.views.get(&id).map(|v| v.version)
    }

    /// Get the last broadcast text delta for this view (if any).
    pub fn last_text_delta_for_view(&self, id: ViewId) -> Option<&Arc<TextDelta>> {
        self.views.get(&id)?.last_text_delta.as_ref()
    }

    /// Take the last broadcast text delta for this view (if any).
    pub fn take_last_text_delta_for_view(&mut self, id: ViewId) -> Option<Arc<TextDelta>> {
        self.views.get_mut(&id)?.last_text_delta.take()
    }

    /// Take the last text delta for a buffer (if any).
    ///
    /// This is useful for incremental consumers (e.g. LSP sync) that want to observe each buffer
    /// edit exactly once, regardless of how many views exist for that buffer.
    pub fn take_last_text_delta_for_buffer(
        &mut self,
        id: BufferId,
    ) -> Result<Option<Arc<TextDelta>>, WorkspaceError> {
        let Some(buffer) = self.buffers.get_mut(&id) else {
            return Err(WorkspaceError::BufferNotFound(id));
        };
        Ok(buffer.last_text_delta.take())
    }

    /// Subscribe to changes for a view.
    pub fn subscribe_view<F>(&mut self, id: ViewId, callback: F) -> Result<(), WorkspaceError>
    where
        F: FnMut(&StateChange) + Send + 'static,
    {
        let Some(view) = self.views.get_mut(&id) else {
            return Err(WorkspaceError::ViewNotFound(id));
        };

        view.callbacks.push(Box::new(callback));
        Ok(())
    }

    fn notify_view(
        view: &mut ViewEntry,
        change_type: StateChangeType,
        delta: Option<Arc<TextDelta>>,
    ) {
        let old_version = view.version;
        view.version = view.version.saturating_add(1);

        let mut change = StateChange::new(change_type, old_version, view.version);
        if let Some(delta) = delta {
            change = change.with_text_delta(delta);
        }

        for cb in &mut view.callbacks {
            cb(&change);
        }
    }

    fn command_change_type(command: &Command) -> Option<StateChangeType> {
        match command {
            Command::Edit(EditCommand::InsertText { text }) if text.is_empty() => None,
            Command::Edit(EditCommand::Delete { length: 0, .. }) => None,
            Command::Edit(EditCommand::Replace {
                length: 0, text, ..
            }) if text.is_empty() => None,
            Command::Edit(EditCommand::EndUndoGroup) => None,
            Command::Edit(_) => Some(StateChangeType::DocumentModified),
            Command::Cursor(
                CursorCommand::MoveTo { .. }
                | CursorCommand::MoveBy { .. }
                | CursorCommand::MoveVisualBy { .. }
                | CursorCommand::MoveToVisual { .. }
                | CursorCommand::MoveToLineStart
                | CursorCommand::MoveToLineEnd
                | CursorCommand::MoveToVisualLineStart
                | CursorCommand::MoveToVisualLineEnd
                | CursorCommand::MoveGraphemeLeft
                | CursorCommand::MoveGraphemeRight
                | CursorCommand::MoveWordLeft
                | CursorCommand::MoveWordRight
                | CursorCommand::FindNext { .. }
                | CursorCommand::FindPrev { .. },
            ) => Some(StateChangeType::CursorMoved),
            Command::Cursor(_) => Some(StateChangeType::SelectionChanged),
            Command::View(ViewCommand::ScrollTo { .. } | ViewCommand::GetViewport { .. }) => None,
            Command::View(_) => Some(StateChangeType::ViewportChanged),
            Command::Style(
                crate::StyleCommand::AddStyle { .. } | crate::StyleCommand::RemoveStyle { .. },
            ) => Some(StateChangeType::StyleChanged),
            Command::Style(
                crate::StyleCommand::Fold { .. }
                | crate::StyleCommand::Unfold { .. }
                | crate::StyleCommand::UnfoldAll,
            ) => Some(StateChangeType::FoldingChanged),
        }
    }

    /// Execute a command against a specific view.
    ///
    /// - Cursor/selection state is view-local.
    /// - Text edits and derived-state edits are applied to the underlying buffer.
    /// - Any text delta is broadcast to all views of that buffer.
    pub fn execute(
        &mut self,
        view_id: ViewId,
        command: Command,
    ) -> Result<CommandResult, WorkspaceError> {
        let Some(buffer_id) = self.views.get(&view_id).map(|v| v.buffer) else {
            return Err(WorkspaceError::ViewNotFound(view_id));
        };

        let change_type = Self::command_change_type(&command);
        if change_type.is_none() {
            // Still run command because it may validate (e.g. ScrollTo), but treat as no version bump.
        }

        // Borrow maps separately so we can mutably access a view and its buffer.
        let views = &mut self.views;
        let buffers = &mut self.buffers;

        let Some(view) = views.get_mut(&view_id) else {
            return Err(WorkspaceError::ViewNotFound(view_id));
        };
        let Some(buffer) = buffers.get_mut(&buffer_id) else {
            return Err(WorkspaceError::BufferNotFound(buffer_id));
        };

        let before_view_core = view.core.clone();
        let before_line_index = buffer.executor.editor().line_index.clone();
        let before_char_count = buffer.executor.editor().char_count();

        // Load view-local state into the executor, execute, then snapshot it back.
        view.core.apply_to_executor(&mut buffer.executor);

        let result = buffer.executor.execute(command.clone()).map_err(|err| {
            WorkspaceError::CommandFailed {
                view: view_id,
                message: err.to_string(),
            }
        })?;

        view.core = ViewCore::from_executor(&buffer.executor);

        let delta = buffer.executor.take_last_text_delta().map(Arc::new);
        let after_char_count = buffer.executor.editor().char_count();

        // Detect no-ops: successful execution but no meaningful state change.
        let view_changed = view.core != before_view_core;
        let buffer_text_changed = delta.is_some()
            // `Backspace`/`DeleteForward` can succeed as boundary no-ops; detect via char count.
            || after_char_count != before_char_count;

        let buffer_derived_changed = matches!(command, Command::Style(_));

        if !(view_changed || buffer_text_changed || buffer_derived_changed) {
            return Ok(result);
        }

        let change_type = if buffer_text_changed {
            StateChangeType::DocumentModified
        } else {
            change_type.unwrap_or(StateChangeType::ViewportChanged)
        };

        if buffer_text_changed || buffer_derived_changed {
            // Broadcast to all views of this buffer.
            let delta_arc = delta.clone();
            if let Some(delta_arc) = delta_arc {
                buffer.last_text_delta = Some(delta_arc.clone());
                for other in views.values_mut() {
                    if other.buffer != buffer_id {
                        continue;
                    }
                    other.last_text_delta = Some(delta_arc.clone());
                }
            } else {
                buffer.last_text_delta = None;
            }

            // Shift other views' cursor/selections through the delta (if any).
            if let Some(ref delta_arc) = delta {
                let new_index = &buffer.executor.editor().line_index;
                for (other_id, other) in views.iter_mut() {
                    if other.buffer != buffer_id || *other_id == view_id {
                        continue;
                    }

                    other.core.cursor_position = apply_position_delta(
                        &before_line_index,
                        new_index,
                        other.core.cursor_position,
                        delta_arc,
                    );

                    if let Some(ref sel) = other.core.selection {
                        other.core.selection = Some(apply_selection_delta(
                            &before_line_index,
                            new_index,
                            sel,
                            delta_arc,
                        ));
                    }

                    for sel in &mut other.core.secondary_selections {
                        *sel = apply_selection_delta(&before_line_index, new_index, sel, delta_arc);
                    }
                }
            }

            for other in views.values_mut() {
                if other.buffer != buffer_id {
                    continue;
                }
                Self::notify_view(other, change_type, delta.clone());
            }

            buffer.version = buffer.version.saturating_add(1);
        } else {
            Self::notify_view(view, change_type, None);
        }

        Ok(result)
    }

    /// Set the viewport height for a view (used for `ViewportState` calculations).
    pub fn set_viewport_height(
        &mut self,
        view_id: ViewId,
        height: usize,
    ) -> Result<(), WorkspaceError> {
        let Some(view) = self.views.get_mut(&view_id) else {
            return Err(WorkspaceError::ViewNotFound(view_id));
        };
        view.viewport_height = Some(height);
        Ok(())
    }

    /// Set the scroll position (top visual row) for a view.
    pub fn set_scroll_top(
        &mut self,
        view_id: ViewId,
        scroll_top: usize,
    ) -> Result<(), WorkspaceError> {
        let Some(view) = self.views.get_mut(&view_id) else {
            return Err(WorkspaceError::ViewNotFound(view_id));
        };
        view.scroll_top = scroll_top;
        Ok(())
    }

    /// Set sub-row smooth-scroll offset for a view.
    pub fn set_scroll_sub_row_offset(
        &mut self,
        view_id: ViewId,
        sub_row_offset: u16,
    ) -> Result<(), WorkspaceError> {
        let Some(view) = self.views.get_mut(&view_id) else {
            return Err(WorkspaceError::ViewNotFound(view_id));
        };
        view.scroll_sub_row_offset = sub_row_offset;
        Ok(())
    }

    /// Set overscan rows for a view.
    pub fn set_overscan_rows(
        &mut self,
        view_id: ViewId,
        overscan_rows: usize,
    ) -> Result<(), WorkspaceError> {
        let Some(view) = self.views.get_mut(&view_id) else {
            return Err(WorkspaceError::ViewNotFound(view_id));
        };
        view.overscan_rows = overscan_rows;
        Ok(())
    }

    /// Set smooth-scroll state for a view.
    pub fn set_smooth_scroll_state(
        &mut self,
        view_id: ViewId,
        state: ViewSmoothScrollState,
    ) -> Result<(), WorkspaceError> {
        let Some(view) = self.views.get_mut(&view_id) else {
            return Err(WorkspaceError::ViewNotFound(view_id));
        };
        view.scroll_top = state.top_visual_row;
        view.scroll_sub_row_offset = state.sub_row_offset;
        view.overscan_rows = state.overscan_rows;
        Ok(())
    }

    /// Get viewport state for a view, including total visual lines and overscan prefetch range.
    pub fn viewport_state_for_view(
        &mut self,
        view_id: ViewId,
    ) -> Result<WorkspaceViewportState, WorkspaceError> {
        let Some((
            buffer_id,
            view_core,
            scroll_top,
            viewport_height,
            sub_row_offset,
            overscan_rows,
        )) = self.views.get(&view_id).map(|v| {
            (
                v.buffer,
                v.core.clone(),
                v.scroll_top,
                v.viewport_height,
                v.scroll_sub_row_offset,
                v.overscan_rows,
            )
        })
        else {
            return Err(WorkspaceError::ViewNotFound(view_id));
        };

        let Some(buffer) = self.buffers.get_mut(&buffer_id) else {
            return Err(WorkspaceError::BufferNotFound(buffer_id));
        };
        view_core.apply_to_executor(&mut buffer.executor);
        let editor = buffer.executor.editor();

        let total_visual_lines = editor.visual_line_count();
        let visible_end = if let Some(height) = viewport_height {
            scroll_top.saturating_add(height).min(total_visual_lines)
        } else {
            total_visual_lines
        };
        let visible_lines = scroll_top.min(total_visual_lines)..visible_end;
        let prefetch_start = visible_lines.start.saturating_sub(overscan_rows);
        let prefetch_end = visible_lines
            .end
            .saturating_add(overscan_rows)
            .min(total_visual_lines);

        Ok(WorkspaceViewportState {
            width: editor.viewport_width,
            height: viewport_height,
            scroll_top,
            visible_lines,
            total_visual_lines,
            smooth_scroll: ViewSmoothScrollState {
                top_visual_row: scroll_top,
                sub_row_offset,
                overscan_rows,
            },
            prefetch_lines: prefetch_start..prefetch_end,
        })
    }

    /// Get total visual lines for a view (wrap + folding aware).
    pub fn total_visual_lines_for_view(
        &mut self,
        view_id: ViewId,
    ) -> Result<usize, WorkspaceError> {
        Ok(self.viewport_state_for_view(view_id)?.total_visual_lines)
    }

    /// Map global visual row to `(logical_line, visual_in_logical)` for a view.
    pub fn visual_to_logical_for_view(
        &mut self,
        view_id: ViewId,
        visual_row: usize,
    ) -> Result<(usize, usize), WorkspaceError> {
        let Some((buffer_id, view_core)) =
            self.views.get(&view_id).map(|v| (v.buffer, v.core.clone()))
        else {
            return Err(WorkspaceError::ViewNotFound(view_id));
        };
        let Some(buffer) = self.buffers.get_mut(&buffer_id) else {
            return Err(WorkspaceError::BufferNotFound(buffer_id));
        };
        view_core.apply_to_executor(&mut buffer.executor);
        Ok(buffer.executor.editor().visual_to_logical_line(visual_row))
    }

    /// Map logical position to global visual `(row, x_cells)` for a view.
    pub fn logical_to_visual_for_view(
        &mut self,
        view_id: ViewId,
        line: usize,
        column: usize,
    ) -> Result<Option<(usize, usize)>, WorkspaceError> {
        let Some((buffer_id, view_core)) =
            self.views.get(&view_id).map(|v| (v.buffer, v.core.clone()))
        else {
            return Err(WorkspaceError::ViewNotFound(view_id));
        };
        let Some(buffer) = self.buffers.get_mut(&buffer_id) else {
            return Err(WorkspaceError::BufferNotFound(buffer_id));
        };
        view_core.apply_to_executor(&mut buffer.executor);
        Ok(buffer
            .executor
            .editor()
            .logical_position_to_visual(line, column))
    }

    /// Map visual `(row, x_cells)` back to logical position for a view.
    pub fn visual_position_to_logical_for_view(
        &mut self,
        view_id: ViewId,
        visual_row: usize,
        x_cells: usize,
    ) -> Result<Option<Position>, WorkspaceError> {
        let Some((buffer_id, view_core)) =
            self.views.get(&view_id).map(|v| (v.buffer, v.core.clone()))
        else {
            return Err(WorkspaceError::ViewNotFound(view_id));
        };
        let Some(buffer) = self.buffers.get_mut(&buffer_id) else {
            return Err(WorkspaceError::BufferNotFound(buffer_id));
        };
        view_core.apply_to_executor(&mut buffer.executor);
        Ok(buffer
            .executor
            .editor()
            .visual_position_to_logical(visual_row, x_cells))
    }

    /// Get the full document text for a buffer.
    pub fn buffer_text(&self, buffer_id: BufferId) -> Result<String, WorkspaceError> {
        let Some(buffer) = self.buffers.get(&buffer_id) else {
            return Err(WorkspaceError::BufferNotFound(buffer_id));
        };
        Ok(buffer.executor.editor().get_text())
    }

    /// Get styled viewport content for a view (by visual line).
    pub fn get_viewport_content_styled(
        &mut self,
        view_id: ViewId,
        start_visual_row: usize,
        count: usize,
    ) -> Result<crate::HeadlessGrid, WorkspaceError> {
        let Some(buffer_id) = self.views.get(&view_id).map(|v| v.buffer) else {
            return Err(WorkspaceError::ViewNotFound(view_id));
        };

        let view_core = self
            .views
            .get(&view_id)
            .map(|v| v.core.clone())
            .ok_or(WorkspaceError::ViewNotFound(view_id))?;

        let Some(buffer) = self.buffers.get_mut(&buffer_id) else {
            return Err(WorkspaceError::BufferNotFound(buffer_id));
        };

        view_core.apply_to_executor(&mut buffer.executor);
        Ok(buffer
            .executor
            .editor()
            .get_headless_grid_styled(start_visual_row, count))
    }

    /// Get lightweight minimap content for a view (by visual line).
    pub fn get_minimap_content(
        &mut self,
        view_id: ViewId,
        start_visual_row: usize,
        count: usize,
    ) -> Result<crate::MinimapGrid, WorkspaceError> {
        let Some(buffer_id) = self.views.get(&view_id).map(|v| v.buffer) else {
            return Err(WorkspaceError::ViewNotFound(view_id));
        };

        let view_core = self
            .views
            .get(&view_id)
            .map(|v| v.core.clone())
            .ok_or(WorkspaceError::ViewNotFound(view_id))?;

        let Some(buffer) = self.buffers.get_mut(&buffer_id) else {
            return Err(WorkspaceError::BufferNotFound(buffer_id));
        };

        view_core.apply_to_executor(&mut buffer.executor);
        Ok(buffer
            .executor
            .editor()
            .get_minimap_grid(start_visual_row, count))
    }

    /// Get a decoration-aware composed viewport snapshot for a view (by composed visual line).
    ///
    /// This snapshot can include virtual text (inlay hints, code lens) injected from the buffer's
    /// decoration layers. See [`crate::EditorCore::get_headless_grid_composed`] for details.
    pub fn get_viewport_content_composed(
        &mut self,
        view_id: ViewId,
        start_visual_row: usize,
        count: usize,
    ) -> Result<crate::ComposedGrid, WorkspaceError> {
        let Some(buffer_id) = self.views.get(&view_id).map(|v| v.buffer) else {
            return Err(WorkspaceError::ViewNotFound(view_id));
        };

        let view_core = self
            .views
            .get(&view_id)
            .map(|v| v.core.clone())
            .ok_or(WorkspaceError::ViewNotFound(view_id))?;

        let Some(buffer) = self.buffers.get_mut(&buffer_id) else {
            return Err(WorkspaceError::BufferNotFound(buffer_id));
        };

        view_core.apply_to_executor(&mut buffer.executor);
        Ok(buffer
            .executor
            .editor()
            .get_headless_grid_composed(start_visual_row, count))
    }

    /// Apply derived-state edits to a buffer and broadcast them to all views of that buffer.
    pub fn apply_processing_edits<I>(
        &mut self,
        buffer_id: BufferId,
        edits: I,
    ) -> Result<(), WorkspaceError>
    where
        I: IntoIterator<Item = ProcessingEdit>,
    {
        let Some(buffer) = self.buffers.get_mut(&buffer_id) else {
            return Err(WorkspaceError::BufferNotFound(buffer_id));
        };

        let mut style_changed = false;
        let mut folding_changed = false;
        let mut diagnostics_changed = false;
        let mut decorations_changed = false;
        let mut symbols_changed = false;

        for edit in edits {
            match edit {
                ProcessingEdit::ReplaceStyleLayer { layer, intervals } => {
                    let editor = buffer.executor.editor_mut();
                    if intervals.is_empty() {
                        editor.style_layers.remove(&layer);
                    } else {
                        let tree = editor.style_layers.entry(layer).or_default();
                        tree.clear();
                        for interval in intervals {
                            if interval.start < interval.end {
                                tree.insert(interval);
                            }
                        }
                    }
                    style_changed = true;
                }
                ProcessingEdit::ClearStyleLayer { layer } => {
                    buffer.executor.editor_mut().style_layers.remove(&layer);
                    style_changed = true;
                }
                ProcessingEdit::ReplaceFoldingRegions {
                    mut regions,
                    preserve_collapsed,
                } => {
                    if preserve_collapsed {
                        let collapsed: HashSet<(usize, usize)> = buffer
                            .executor
                            .editor()
                            .folding_manager
                            .derived_regions()
                            .iter()
                            .filter(|r| r.is_collapsed)
                            .map(|r| (r.start_line, r.end_line))
                            .collect();

                        for region in &mut regions {
                            if collapsed.contains(&(region.start_line, region.end_line)) {
                                region.is_collapsed = true;
                            }
                        }
                    }

                    buffer
                        .executor
                        .editor_mut()
                        .folding_manager
                        .replace_derived_regions(regions);
                    buffer
                        .executor
                        .editor_mut()
                        .invalidate_visual_row_index_cache();
                    folding_changed = true;
                }
                ProcessingEdit::ClearFoldingRegions => {
                    buffer
                        .executor
                        .editor_mut()
                        .folding_manager
                        .clear_derived_regions();
                    buffer
                        .executor
                        .editor_mut()
                        .invalidate_visual_row_index_cache();
                    folding_changed = true;
                }
                ProcessingEdit::ReplaceDiagnostics { diagnostics } => {
                    buffer.executor.editor_mut().diagnostics = diagnostics;
                    diagnostics_changed = true;
                }
                ProcessingEdit::ClearDiagnostics => {
                    buffer.executor.editor_mut().diagnostics.clear();
                    diagnostics_changed = true;
                }
                ProcessingEdit::ReplaceDecorations {
                    layer,
                    mut decorations,
                } => {
                    decorations.sort_unstable_by_key(|d| (d.range.start, d.range.end));
                    buffer
                        .executor
                        .editor_mut()
                        .decorations
                        .insert(layer, decorations);
                    decorations_changed = true;
                }
                ProcessingEdit::ClearDecorations { layer } => {
                    buffer.executor.editor_mut().decorations.remove(&layer);
                    decorations_changed = true;
                }
                ProcessingEdit::ReplaceDocumentSymbols { symbols } => {
                    buffer.executor.editor_mut().document_symbols = symbols;
                    symbols_changed = true;
                }
                ProcessingEdit::ClearDocumentSymbols => {
                    buffer.executor.editor_mut().document_symbols =
                        crate::DocumentOutline::default();
                    symbols_changed = true;
                }
            }
        }

        let change_type = if folding_changed {
            Some(StateChangeType::FoldingChanged)
        } else if style_changed {
            Some(StateChangeType::StyleChanged)
        } else if decorations_changed {
            Some(StateChangeType::DecorationsChanged)
        } else if diagnostics_changed {
            Some(StateChangeType::DiagnosticsChanged)
        } else if symbols_changed {
            Some(StateChangeType::SymbolsChanged)
        } else {
            None
        };

        if let Some(change_type) = change_type {
            for view in self.views.values_mut() {
                if view.buffer == buffer_id {
                    Self::notify_view(view, change_type, None);
                }
            }
            buffer.version = buffer.version.saturating_add(1);
        }

        Ok(())
    }

    /// Search across all open buffers in the workspace.
    ///
    /// - This is purely in-memory (no file I/O).
    /// - Match ranges are returned as **character offsets** (half-open).
    pub fn search_all_open_buffers(
        &self,
        query: &str,
        options: SearchOptions,
    ) -> Result<Vec<WorkspaceSearchResult>, SearchError> {
        let mut out: Vec<WorkspaceSearchResult> = Vec::new();

        for (id, entry) in &self.buffers {
            let text = entry.executor.editor().get_text();
            let matches = find_all(&text, query, options)?;
            if matches.is_empty() {
                continue;
            }

            out.push(WorkspaceSearchResult {
                id: *id,
                uri: entry.meta.uri.clone(),
                matches,
            });
        }

        Ok(out)
    }

    /// Apply a set of text edits to multiple open buffers.
    ///
    /// - This is purely in-memory (no file I/O).
    /// - Edits are applied as a single undoable step **per buffer**.
    /// - Buffers are applied in deterministic `BufferId` order.
    pub fn apply_text_edits<I>(
        &mut self,
        edits: I,
    ) -> Result<Vec<(BufferId, usize)>, WorkspaceError>
    where
        I: IntoIterator<Item = (BufferId, Vec<TextEditSpec>)>,
    {
        let mut by_id: BTreeMap<BufferId, Vec<TextEditSpec>> = BTreeMap::new();
        for (id, mut buffer_edits) in edits {
            by_id.entry(id).or_default().append(&mut buffer_edits);
        }

        let mut applied: Vec<(BufferId, usize)> = Vec::new();
        for (buffer_id, buffer_edits) in by_id {
            let edit_count = buffer_edits.len();
            if edit_count == 0 {
                continue;
            }

            let Some(buffer) = self.buffers.get_mut(&buffer_id) else {
                return Err(WorkspaceError::BufferNotFound(buffer_id));
            };

            let before_line_index = buffer.executor.editor().line_index.clone();
            let before_char_count = buffer.executor.editor().char_count();

            // Apply without relying on any specific view selection: load a neutral view state.
            let neutral = ViewCore {
                cursor_position: Position::new(0, 0),
                selection: None,
                secondary_selections: Vec::new(),
                viewport_width: buffer.executor.editor().viewport_width.max(1),
                wrap_mode: buffer.executor.editor().layout_engine.wrap_mode(),
                wrap_indent: buffer.executor.editor().layout_engine.wrap_indent(),
                tab_width: buffer.executor.editor().layout_engine.tab_width(),
                tab_key_behavior: buffer.executor.tab_key_behavior(),
                preferred_x_cells: None,
            };
            neutral.apply_to_executor(&mut buffer.executor);

            buffer
                .executor
                .execute(Command::Edit(EditCommand::ApplyTextEdits {
                    edits: buffer_edits,
                }))
                .map_err(|err| WorkspaceError::ApplyEditsFailed {
                    buffer: buffer_id,
                    message: err.to_string(),
                })?;

            let delta = buffer.executor.take_last_text_delta().map(Arc::new);
            let after_char_count = buffer.executor.editor().char_count();
            let changed = delta.is_some() || after_char_count != before_char_count;

            if changed {
                if let Some(ref delta_arc) = delta {
                    buffer.last_text_delta = Some(delta_arc.clone());
                    let new_index = &buffer.executor.editor().line_index;
                    for view in self.views.values_mut() {
                        if view.buffer != buffer_id {
                            continue;
                        }

                        view.last_text_delta = Some(delta_arc.clone());

                        view.core.cursor_position = apply_position_delta(
                            &before_line_index,
                            new_index,
                            view.core.cursor_position,
                            delta_arc,
                        );
                        if let Some(ref sel) = view.core.selection {
                            view.core.selection = Some(apply_selection_delta(
                                &before_line_index,
                                new_index,
                                sel,
                                delta_arc,
                            ));
                        }
                        for sel in &mut view.core.secondary_selections {
                            *sel = apply_selection_delta(
                                &before_line_index,
                                new_index,
                                sel,
                                delta_arc,
                            );
                        }

                        Self::notify_view(
                            view,
                            StateChangeType::DocumentModified,
                            Some(delta_arc.clone()),
                        );
                    }
                } else {
                    buffer.last_text_delta = None;
                    for view in self.views.values_mut() {
                        if view.buffer == buffer_id {
                            Self::notify_view(view, StateChangeType::DocumentModified, None);
                        }
                    }
                }

                buffer.version = buffer.version.saturating_add(1);
            }

            applied.push((buffer_id, edit_count));
        }

        Ok(applied)
    }
}
