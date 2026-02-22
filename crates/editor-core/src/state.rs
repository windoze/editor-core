//! Editor State Interface
//!
//! Provides a complete state query interface for the editor, used for frontend rendering and state synchronization.
//!
//! # Overview
//!
//! The state interface layer exposes the editor's internal state to the frontend in a structured, immutable manner.
//! It supports:
//!
//! - **State Queries**: Retrieve document, cursor, viewport, and other state information
//! - **Version Tracking**: Track state changes through version numbers
//! - **Change Notifications**: Subscribe to state change events
//! - **Viewport Management**: Obtain rendering data for visible regions
//!
//! # Example
//!
//! ```rust
//! use editor_core::{EditorStateManager, StateChangeType};
//!
//! let mut manager = EditorStateManager::new("Hello, World!", 80);
//!
//! // Query document state
//! let doc_state = manager.get_document_state();
//! println!("Line count: {}", doc_state.line_count);
//!
//! // Subscribe to state changes
//! manager.subscribe(|change| {
//!     println!("State changed: {:?}", change.change_type);
//! });
//!
//! // Modify document and mark changes
//! manager.editor_mut().piece_table.insert(0, "New: ");
//! manager.mark_modified(StateChangeType::DocumentModified);
//! ```

use crate::delta::TextDelta;
use crate::intervals::{FoldRegion, Interval, StyleId, StyleLayerId};
use crate::processing::{DocumentProcessor, ProcessingEdit};
use crate::snapshot::HeadlessGrid;
use crate::{
    Command, CommandError, CommandExecutor, CommandResult, CursorCommand, Decoration,
    DecorationLayerId, Diagnostic, EditCommand, EditorCore, LineEnding, Position, Selection,
    SelectionDirection, StyleCommand, ViewCommand,
};
use std::collections::HashSet;
use std::ops::Range;
use std::sync::Arc;

/// Document state
#[derive(Debug, Clone)]
pub struct DocumentState {
    /// Total documentLine count
    pub line_count: usize,
    /// Total document character count
    pub char_count: usize,
    /// Total document byte count
    pub byte_count: usize,
    /// Whether document has been modified
    pub is_modified: bool,
    /// Document version number (incremented after each modification)
    pub version: u64,
}

/// Cursor state
#[derive(Debug, Clone)]
pub struct CursorState {
    /// Primary cursor position (logical coordinates)
    pub position: Position,
    /// Primary cursor position (char offsets)
    pub offset: usize,
    /// Multi-cursor list (active positions of secondary carets, excluding primary)
    pub multi_cursors: Vec<Position>,
    /// Primary selection range (only primary; returns None for empty selection)
    pub selection: Option<Selection>,
    /// All selection set (including primary; each Selection may be empty)
    pub selections: Vec<Selection>,
    /// Index of primary in `selections`
    pub primary_selection_index: usize,
}

/// Viewport state
#[derive(Debug, Clone)]
pub struct ViewportState {
    /// Viewport width (in character cells)
    pub width: usize,
    /// Viewport height (line count, determined by the frontend)
    pub height: Option<usize>,
    /// Current scroll position (visual line number)
    pub scroll_top: usize,
    /// Visible visual line range
    pub visible_lines: Range<usize>,
}

/// Undo/redo stack state
#[derive(Debug, Clone)]
pub struct UndoRedoState {
    /// Can undo
    pub can_undo: bool,
    /// Can redo
    pub can_redo: bool,
    /// Undo stack depth
    pub undo_depth: usize,
    /// Redo stack depth
    pub redo_depth: usize,
    /// Current change group ID
    pub current_change_group: Option<usize>,
}

/// Folding state
#[derive(Debug, Clone)]
pub struct FoldingState {
    /// All folding regions
    pub regions: Vec<FoldRegion>,
    /// Count of collapsed lines
    pub collapsed_line_count: usize,
    /// Count of visible logical lines
    pub visible_logical_lines: usize,
    /// Total visual line count (considering folding)
    pub total_visual_lines: usize,
}

/// Diagnostics state
#[derive(Debug, Clone)]
pub struct DiagnosticsState {
    /// Total number of diagnostics.
    pub diagnostics_count: usize,
}

/// Decorations state
#[derive(Debug, Clone)]
pub struct DecorationsState {
    /// Total number of decoration layers.
    pub layer_count: usize,
    /// Total number of decorations (across all layers).
    pub decoration_count: usize,
}

/// Style state
#[derive(Debug, Clone)]
pub struct StyleState {
    /// Total number of style intervals
    pub style_count: usize,
}

/// State change type
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum StateChangeType {
    /// Document content modified
    DocumentModified,
    /// Cursor moved
    CursorMoved,
    /// Selection changed
    SelectionChanged,
    /// Viewport changed
    ViewportChanged,
    /// Folding state changed
    FoldingChanged,
    /// Style changed
    StyleChanged,
    /// Decorations changed
    DecorationsChanged,
    /// Diagnostics changed
    DiagnosticsChanged,
}

/// State change record
#[derive(Debug, Clone)]
pub struct StateChange {
    /// Change type
    pub change_type: StateChangeType,
    /// Old version number
    pub old_version: u64,
    /// New version number
    pub new_version: u64,
    /// Affected region (character offset range)
    pub affected_region: Option<Range<usize>>,
    /// Structured text delta for document changes (if available).
    pub text_delta: Option<Arc<TextDelta>>,
}

impl StateChange {
    /// Create a new state change record without an affected region.
    pub fn new(change_type: StateChangeType, old_version: u64, new_version: u64) -> Self {
        Self {
            change_type,
            old_version,
            new_version,
            affected_region: None,
            text_delta: None,
        }
    }

    /// Attach the affected character range to this change record.
    pub fn with_region(mut self, region: Range<usize>) -> Self {
        self.affected_region = Some(region);
        self
    }

    /// Attach a structured text delta to this change record.
    pub fn with_text_delta(mut self, delta: Arc<TextDelta>) -> Self {
        self.text_delta = Some(delta);
        self
    }
}

/// Complete editor state snapshot
#[derive(Debug, Clone)]
pub struct EditorState {
    /// Document state
    pub document: DocumentState,
    /// Cursor state
    pub cursor: CursorState,
    /// Viewport state
    pub viewport: ViewportState,
    /// Undo/redo state
    pub undo_redo: UndoRedoState,
    /// Folding state
    pub folding: FoldingState,
    /// Diagnostics state
    pub diagnostics: DiagnosticsState,
    /// Decorations state
    pub decorations: DecorationsState,
    /// Style state
    pub style: StyleState,
}

/// State change callback function type
pub type StateChangeCallback = Box<dyn FnMut(&StateChange) + Send>;

/// Editor state manager
///
/// `EditorStateManager` wraps the command executor ([`CommandExecutor`]) and its internal [`EditorCore`]
/// and provides the following features:
///
/// - **State Queries**: Retrieve various state snapshots (document, cursor, viewport, etc.)
/// - **Version Tracking**: Automatically increment version number after each modification, supporting incremental updates
/// - **Change Notifications**: Notify subscribers of state changes via callback mechanism
/// - **Viewport Management**: Manage scroll position and visible regions
/// - **Modification Tracking**: Track whether the document has been modified (for save prompts)
///
/// # Architecture Notes
///
/// The state manager adopts a "unidirectional data flow" pattern:
///
/// 1. Frontend executes commands via [`execute()`](EditorStateManager::execute) (recommended)
/// 2. Or directly modifies internal state via [`editor_mut()`](EditorStateManager::editor_mut) (advanced usage)
/// 3. If using `editor_mut()`, call [`mark_modified()`](EditorStateManager::mark_modified) after modification
///    to mark the change type
/// 3. Manager increments version number and triggers all subscribed callbacks
/// 4. Frontend retrieves the latest state via various `get_*_state()` methods
///
/// # Example
///
/// ```rust
/// use editor_core::{Command, EditCommand, EditorStateManager};
///
/// let mut manager = EditorStateManager::new("Initial text", 80);
///
/// // Subscribe to state changes
/// manager.subscribe(|change| {
///     println!("Version {} -> {}: {:?}",
///         change.old_version, change.new_version, change.change_type);
/// });
///
/// // Modify document (automatically maintains consistency + automatically triggers state notifications)
/// manager.execute(Command::Edit(EditCommand::Insert {
///     offset: 0,
///     text: "New: ".to_string(),
/// })).unwrap();
///
/// // Query state
/// let doc_state = manager.get_document_state();
/// assert!(doc_state.is_modified);
/// assert_eq!(doc_state.version, 1);
/// ```
pub struct EditorStateManager {
    /// Command executor (wraps EditorCore and maintains consistency)
    executor: CommandExecutor,
    /// State version number
    state_version: u64,
    /// Whether document has been modified
    is_modified: bool,
    /// State change callback list
    callbacks: Vec<StateChangeCallback>,
    /// Current scroll position
    scroll_top: usize,
    /// Viewport height (optional)
    viewport_height: Option<usize>,
    /// Structured text delta produced by the last document edit.
    last_text_delta: Option<Arc<TextDelta>>,
}

impl EditorStateManager {
    /// Create a new state manager
    pub fn new(text: &str, viewport_width: usize) -> Self {
        Self {
            executor: CommandExecutor::new(text, viewport_width),
            state_version: 0,
            is_modified: false,
            callbacks: Vec::new(),
            scroll_top: 0,
            viewport_height: None,
            last_text_delta: None,
        }
    }

    /// Create an empty state manager
    pub fn empty(viewport_width: usize) -> Self {
        Self::new("", viewport_width)
    }

    /// Get a reference to the Editor Core
    pub fn editor(&self) -> &EditorCore {
        self.executor.editor()
    }

    /// Get a mutable reference to the Editor Core
    pub fn editor_mut(&mut self) -> &mut EditorCore {
        self.executor.editor_mut()
    }

    /// Get the preferred line ending for saving this document.
    pub fn line_ending(&self) -> LineEnding {
        self.executor.line_ending()
    }

    /// Override the preferred line ending for saving this document.
    pub fn set_line_ending(&mut self, line_ending: LineEnding) {
        self.executor.set_line_ending(line_ending);
    }

    /// Get the current document text converted to the preferred line ending for saving.
    pub fn get_text_for_saving(&self) -> String {
        let text = self.editor().get_text();
        self.line_ending().apply_to_text(&text)
    }

    /// Execute a command and automatically trigger state change notifications.
    ///
    /// - This method calls the underlying [`CommandExecutor`] to ensure consistency of components
    ///   such as `piece_table` / `line_index` / `layout_engine`.
    /// - For commands that cause state changes, [`mark_modified`](Self::mark_modified) is automatically called.
    /// - For pure query commands (such as `GetViewport`), the version number is not incremented.
    pub fn execute(&mut self, command: Command) -> Result<CommandResult, CommandError> {
        let change_type = Self::change_type_for_command(&command);
        let is_delete_like = matches!(
            &command,
            Command::Edit(EditCommand::Backspace | EditCommand::DeleteForward)
        );

        // Detect changes for potential no-ops: when command execution succeeds but state doesn't change, version should not increment.
        let cursor_before = self.executor.editor().cursor_position();
        let selection_before = self.executor.editor().selection().cloned();
        let secondary_before = self.executor.editor().secondary_selections().to_vec();
        let viewport_width_before = self.executor.editor().viewport_width;
        let char_count_before = self.executor.editor().char_count();

        let result = self.executor.execute(command)?;
        let char_count_after = self.executor.editor().char_count();
        let delta_present = self.executor.last_text_delta().is_some();

        if let Some(change_type) = change_type {
            let changed = match change_type {
                StateChangeType::CursorMoved => {
                    self.executor.editor().cursor_position() != cursor_before
                        || self.executor.editor().secondary_selections()
                            != secondary_before.as_slice()
                }
                StateChangeType::SelectionChanged => {
                    self.executor.editor().cursor_position() != cursor_before
                        || self.executor.editor().selection().cloned() != selection_before
                        || self.executor.editor().secondary_selections()
                            != secondary_before.as_slice()
                }
                StateChangeType::ViewportChanged => {
                    self.executor.editor().viewport_width != viewport_width_before
                }
                StateChangeType::DocumentModified => {
                    // EditCommand::Backspace / DeleteForward can be valid no-ops at boundaries.
                    // Detect via char count change (they only delete text).
                    if is_delete_like {
                        char_count_after != char_count_before
                    } else {
                        delta_present
                    }
                }
                // Style/folding/diagnostics commands are currently treated as "success means change".
                StateChangeType::FoldingChanged
                | StateChangeType::StyleChanged
                | StateChangeType::DecorationsChanged
                | StateChangeType::DiagnosticsChanged => true,
            };

            if changed {
                if matches!(change_type, StateChangeType::DocumentModified) {
                    let is_modified = !self.executor.is_clean();
                    let delta = self.executor.take_last_text_delta().map(Arc::new);
                    self.last_text_delta = delta.clone();
                    self.mark_modified_internal(change_type, Some(is_modified), delta);
                } else {
                    self.mark_modified_internal(change_type, None, None);
                }
            }
        }

        Ok(result)
    }

    fn change_type_for_command(command: &Command) -> Option<StateChangeType> {
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
                | CursorCommand::MoveWordRight,
            ) => Some(StateChangeType::CursorMoved),
            Command::Cursor(
                CursorCommand::SetSelection { .. }
                | CursorCommand::ExtendSelection { .. }
                | CursorCommand::ClearSelection
                | CursorCommand::SetSelections { .. }
                | CursorCommand::ClearSecondarySelections
                | CursorCommand::SetRectSelection { .. }
                | CursorCommand::SelectLine
                | CursorCommand::SelectWord
                | CursorCommand::ExpandSelection
                | CursorCommand::AddCursorAbove
                | CursorCommand::AddCursorBelow
                | CursorCommand::AddNextOccurrence { .. }
                | CursorCommand::AddAllOccurrences { .. }
                | CursorCommand::FindNext { .. }
                | CursorCommand::FindPrev { .. },
            ) => Some(StateChangeType::SelectionChanged),
            Command::View(
                ViewCommand::SetViewportWidth { .. }
                | ViewCommand::SetWrapMode { .. }
                | ViewCommand::SetWrapIndent { .. }
                | ViewCommand::SetTabWidth { .. },
            ) => Some(StateChangeType::ViewportChanged),
            Command::View(
                ViewCommand::SetTabKeyBehavior { .. }
                | ViewCommand::ScrollTo { .. }
                | ViewCommand::GetViewport { .. },
            ) => None,
            Command::Style(StyleCommand::AddStyle { .. } | StyleCommand::RemoveStyle { .. }) => {
                Some(StateChangeType::StyleChanged)
            }
            Command::Style(
                StyleCommand::Fold { .. } | StyleCommand::Unfold { .. } | StyleCommand::UnfoldAll,
            ) => Some(StateChangeType::FoldingChanged),
        }
    }

    /// Get current version number
    pub fn version(&self) -> u64 {
        self.state_version
    }

    /// Set viewport height
    pub fn set_viewport_height(&mut self, height: usize) {
        self.viewport_height = Some(height);
    }

    /// Set scroll position
    pub fn set_scroll_top(&mut self, scroll_top: usize) {
        let old_scroll = self.scroll_top;
        self.scroll_top = scroll_top;

        if old_scroll != scroll_top {
            self.notify_change(StateChangeType::ViewportChanged);
        }
    }

    /// Get complete editor state snapshot
    pub fn get_full_state(&self) -> EditorState {
        EditorState {
            document: self.get_document_state(),
            cursor: self.get_cursor_state(),
            viewport: self.get_viewport_state(),
            undo_redo: self.get_undo_redo_state(),
            folding: self.get_folding_state(),
            diagnostics: self.get_diagnostics_state(),
            decorations: self.get_decorations_state(),
            style: self.get_style_state(),
        }
    }

    /// Get document state
    pub fn get_document_state(&self) -> DocumentState {
        let editor = self.executor.editor();
        DocumentState {
            line_count: editor.line_count(),
            char_count: editor.char_count(),
            byte_count: editor.get_text().len(),
            is_modified: self.is_modified,
            version: self.state_version,
        }
    }

    /// Get cursor state
    pub fn get_cursor_state(&self) -> CursorState {
        let editor = self.executor.editor();
        let mut selections: Vec<Selection> =
            Vec::with_capacity(1 + editor.secondary_selections().len());

        let primary = editor.selection().cloned().unwrap_or(Selection {
            start: editor.cursor_position(),
            end: editor.cursor_position(),
            direction: SelectionDirection::Forward,
        });
        selections.push(primary);
        selections.extend(editor.secondary_selections().iter().cloned());

        let (selections, primary_selection_index) =
            crate::selection_set::normalize_selections(selections, 0);
        let primary = selections
            .get(primary_selection_index)
            .cloned()
            .unwrap_or(Selection {
                start: editor.cursor_position(),
                end: editor.cursor_position(),
                direction: SelectionDirection::Forward,
            });

        let position = primary.end;
        let offset = editor
            .line_index
            .position_to_char_offset(position.line, position.column);

        let selection = if primary.start == primary.end {
            None
        } else {
            Some(primary)
        };

        let multi_cursors: Vec<Position> = selections
            .iter()
            .enumerate()
            .filter_map(|(idx, sel)| {
                if idx == primary_selection_index {
                    None
                } else {
                    Some(sel.end)
                }
            })
            .collect();

        CursorState {
            position,
            offset,
            multi_cursors,
            selection,
            selections,
            primary_selection_index,
        }
    }

    /// Get viewport state
    pub fn get_viewport_state(&self) -> ViewportState {
        let editor = self.executor.editor();
        let total_visual_lines = editor.visual_line_count();
        let visible_end = if let Some(height) = self.viewport_height {
            self.scroll_top + height
        } else {
            total_visual_lines
        };

        ViewportState {
            width: editor.viewport_width,
            height: self.viewport_height,
            scroll_top: self.scroll_top,
            visible_lines: self.scroll_top..visible_end.min(total_visual_lines),
        }
    }

    /// Get undo/redo state
    pub fn get_undo_redo_state(&self) -> UndoRedoState {
        UndoRedoState {
            can_undo: self.executor.can_undo(),
            can_redo: self.executor.can_redo(),
            undo_depth: self.executor.undo_depth(),
            redo_depth: self.executor.redo_depth(),
            current_change_group: self.executor.current_change_group(),
        }
    }

    /// Get folding state
    pub fn get_folding_state(&self) -> FoldingState {
        let editor = self.executor.editor();
        let regions = editor.folding_manager.regions().to_vec();
        let collapsed_line_count: usize = regions
            .iter()
            .filter(|r| r.is_collapsed)
            .map(|r| r.end_line - r.start_line)
            .sum();

        let visible_logical_lines = editor.line_count() - collapsed_line_count;

        FoldingState {
            regions,
            collapsed_line_count,
            visible_logical_lines,
            total_visual_lines: editor.visual_line_count(),
        }
    }

    /// Get style state
    pub fn get_style_state(&self) -> StyleState {
        let editor = self.executor.editor();
        let layered_count: usize = editor.style_layers.values().map(|t| t.len()).sum();
        StyleState {
            style_count: editor.interval_tree.len() + layered_count,
        }
    }

    /// Get diagnostics state.
    pub fn get_diagnostics_state(&self) -> DiagnosticsState {
        let editor = self.executor.editor();
        DiagnosticsState {
            diagnostics_count: editor.diagnostics.len(),
        }
    }

    /// Get decorations state.
    pub fn get_decorations_state(&self) -> DecorationsState {
        let editor = self.executor.editor();
        let decoration_count: usize = editor.decorations.values().map(|d| d.len()).sum();
        DecorationsState {
            layer_count: editor.decorations.len(),
            decoration_count,
        }
    }

    /// Get all styles within the specified range
    pub fn get_styles_in_range(&self, start: usize, end: usize) -> Vec<(usize, usize, StyleId)> {
        let editor = self.executor.editor();
        let mut result: Vec<(usize, usize, StyleId)> = editor
            .interval_tree
            .query_range(start, end)
            .iter()
            .map(|interval| (interval.start, interval.end, interval.style_id))
            .collect();

        for tree in editor.style_layers.values() {
            result.extend(
                tree.query_range(start, end)
                    .iter()
                    .map(|interval| (interval.start, interval.end, interval.style_id)),
            );
        }

        result.sort_unstable_by_key(|(s, e, id)| (*s, *e, *id));
        result
    }

    /// Get all styles at the specified position
    pub fn get_styles_at(&self, offset: usize) -> Vec<StyleId> {
        let editor = self.executor.editor();
        let mut styles: Vec<StyleId> = editor
            .interval_tree
            .query_point(offset)
            .iter()
            .map(|interval| interval.style_id)
            .collect();

        for tree in editor.style_layers.values() {
            styles.extend(
                tree.query_point(offset)
                    .iter()
                    .map(|interval| interval.style_id),
            );
        }

        styles.sort_unstable();
        styles.dedup();
        styles
    }

    /// Replace all intervals in the specified style layer.
    ///
    /// Suitable for scenarios such as LSP semantic highlighting and simple syntax highlighting that require "full layer refresh".
    /// This method only triggers `StyleChanged` once, avoiding version number explosion due to individual insertions.
    pub fn replace_style_layer(&mut self, layer: StyleLayerId, intervals: Vec<Interval>) {
        let editor = self.executor.editor_mut();

        if intervals.is_empty() {
            editor.style_layers.remove(&layer);
            self.mark_modified(StateChangeType::StyleChanged);
            return;
        }

        let tree = editor.style_layers.entry(layer).or_default();
        tree.clear();

        for interval in intervals {
            if interval.start < interval.end {
                tree.insert(interval);
            }
        }

        self.mark_modified(StateChangeType::StyleChanged);
    }

    /// Clear the specified style layer.
    pub fn clear_style_layer(&mut self, layer: StyleLayerId) {
        let editor = self.executor.editor_mut();
        editor.style_layers.remove(&layer);
        self.mark_modified(StateChangeType::StyleChanged);
    }

    /// Replace diagnostics wholesale.
    pub fn replace_diagnostics(&mut self, diagnostics: Vec<Diagnostic>) {
        let editor = self.executor.editor_mut();
        editor.diagnostics = diagnostics;
        self.mark_modified(StateChangeType::DiagnosticsChanged);
    }

    /// Clear all diagnostics.
    pub fn clear_diagnostics(&mut self) {
        let editor = self.executor.editor_mut();
        editor.diagnostics.clear();
        self.mark_modified(StateChangeType::DiagnosticsChanged);
    }

    /// Replace a decoration layer wholesale.
    pub fn replace_decorations(
        &mut self,
        layer: DecorationLayerId,
        mut decorations: Vec<Decoration>,
    ) {
        decorations.sort_unstable_by_key(|d| (d.range.start, d.range.end));
        let editor = self.executor.editor_mut();
        editor.decorations.insert(layer, decorations);
        self.mark_modified(StateChangeType::DecorationsChanged);
    }

    /// Clear a decoration layer.
    pub fn clear_decorations(&mut self, layer: DecorationLayerId) {
        let editor = self.executor.editor_mut();
        editor.decorations.remove(&layer);
        self.mark_modified(StateChangeType::DecorationsChanged);
    }

    /// Replace folding regions wholesale.
    ///
    /// If `preserve_collapsed` is true, any region that matches an existing collapsed region
    /// (`start_line`, `end_line`) will remain collapsed after replacement.
    pub fn replace_folding_regions(
        &mut self,
        mut regions: Vec<FoldRegion>,
        preserve_collapsed: bool,
    ) {
        if preserve_collapsed {
            let collapsed: HashSet<(usize, usize)> = self
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

        self.editor_mut()
            .folding_manager
            .replace_derived_regions(regions);
        self.mark_modified(StateChangeType::FoldingChanged);
    }

    /// Clear all *derived* folding regions (leaves user folds intact).
    pub fn clear_folding_regions(&mut self) {
        self.editor_mut().folding_manager.clear_derived_regions();
        self.mark_modified(StateChangeType::FoldingChanged);
    }

    /// Apply derived-state edits produced by a document processor (highlighting, folding, etc.).
    pub fn apply_processing_edits<I>(&mut self, edits: I)
    where
        I: IntoIterator<Item = ProcessingEdit>,
    {
        for edit in edits {
            match edit {
                ProcessingEdit::ReplaceStyleLayer { layer, intervals } => {
                    self.replace_style_layer(layer, intervals);
                }
                ProcessingEdit::ClearStyleLayer { layer } => {
                    self.clear_style_layer(layer);
                }
                ProcessingEdit::ReplaceFoldingRegions {
                    regions,
                    preserve_collapsed,
                } => {
                    self.replace_folding_regions(regions, preserve_collapsed);
                }
                ProcessingEdit::ClearFoldingRegions => {
                    self.clear_folding_regions();
                }
                ProcessingEdit::ReplaceDiagnostics { diagnostics } => {
                    self.replace_diagnostics(diagnostics);
                }
                ProcessingEdit::ClearDiagnostics => {
                    self.clear_diagnostics();
                }
                ProcessingEdit::ReplaceDecorations { layer, decorations } => {
                    self.replace_decorations(layer, decorations);
                }
                ProcessingEdit::ClearDecorations { layer } => {
                    self.clear_decorations(layer);
                }
            }
        }
    }

    /// Run a [`DocumentProcessor`] against the current document and apply its edits.
    pub fn apply_processor<P>(&mut self, processor: &mut P) -> Result<(), P::Error>
    where
        P: DocumentProcessor,
    {
        let edits = processor.process(self)?;
        self.apply_processing_edits(edits);
        Ok(())
    }

    /// Get viewport content
    pub fn get_viewport_content(&self, start_row: usize, count: usize) -> HeadlessGrid {
        let editor = self.executor.editor();
        let text = editor.get_text();
        let generator = crate::SnapshotGenerator::from_text_with_layout_options(
            &text,
            editor.viewport_width,
            editor.layout_engine.tab_width(),
            editor.layout_engine.wrap_mode(),
            editor.layout_engine.wrap_indent(),
        );
        generator.get_headless_grid(start_row, count)
    }

    /// Get styled viewport content (by visual line).
    ///
    /// - Supports soft wrapping (based on `LayoutEngine`)
    /// - `Cell.styles` will contain the merged result of `interval_tree` and all `style_layers`
    pub fn get_viewport_content_styled(
        &self,
        start_visual_row: usize,
        count: usize,
    ) -> HeadlessGrid {
        self.executor
            .editor()
            .get_headless_grid_styled(start_visual_row, count)
    }

    /// Subscribe to state change notifications
    pub fn subscribe<F>(&mut self, callback: F)
    where
        F: FnMut(&StateChange) + Send + 'static,
    {
        self.callbacks.push(Box::new(callback));
    }

    /// Check if state has changed since a version
    pub fn has_changed_since(&self, version: u64) -> bool {
        self.state_version > version
    }

    /// Mark document as modified and increment version number
    pub fn mark_modified(&mut self, change_type: StateChangeType) {
        self.mark_modified_internal(change_type, None, None);
    }

    fn mark_modified_internal(
        &mut self,
        change_type: StateChangeType,
        is_modified_override: Option<bool>,
        delta: Option<Arc<TextDelta>>,
    ) {
        let old_version = self.state_version;
        self.state_version += 1;

        // Only mark as modified for document content changes
        if matches!(change_type, StateChangeType::DocumentModified) {
            self.is_modified = is_modified_override.unwrap_or(true);
        }

        let mut change = StateChange::new(change_type, old_version, self.state_version);
        if let Some(delta) = delta {
            change = change.with_text_delta(delta);
        }
        self.notify_callbacks(&change);
    }

    /// Mark document as unmodified (e.g., after saving)
    pub fn mark_saved(&mut self) {
        self.executor.mark_clean();
        self.is_modified = false;
    }

    /// Notify state change (without modifying version number)
    fn notify_change(&mut self, change_type: StateChangeType) {
        let change = StateChange::new(change_type, self.state_version, self.state_version);
        self.notify_callbacks(&change);
    }

    /// Get the structured text delta produced by the last document edit, if any.
    pub fn last_text_delta(&self) -> Option<&TextDelta> {
        self.last_text_delta.as_deref()
    }

    /// Take the structured text delta produced by the last document edit, if any.
    pub fn take_last_text_delta(&mut self) -> Option<Arc<TextDelta>> {
        self.last_text_delta.take()
    }

    /// Notify all callbacks
    fn notify_callbacks(&mut self, change: &StateChange) {
        for callback in &mut self.callbacks {
            callback(change);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_document_state() {
        let manager = EditorStateManager::new("Hello World\nLine 2", 80);
        let doc_state = manager.get_document_state();

        assert_eq!(doc_state.line_count, 2);
        assert_eq!(doc_state.char_count, 18); // Including newline
        assert!(!doc_state.is_modified);
        assert_eq!(doc_state.version, 0);
    }

    #[test]
    fn test_cursor_state() {
        let manager = EditorStateManager::new("Hello World", 80);
        let cursor_state = manager.get_cursor_state();

        assert_eq!(cursor_state.position, Position::new(0, 0));
        assert_eq!(cursor_state.offset, 0);
        assert!(cursor_state.selection.is_none());
    }

    #[test]
    fn test_viewport_state() {
        let mut manager = EditorStateManager::new("Line 1\nLine 2\nLine 3", 80);
        manager.set_viewport_height(10);
        manager.set_scroll_top(1);

        let viewport_state = manager.get_viewport_state();

        assert_eq!(viewport_state.width, 80);
        assert_eq!(viewport_state.height, Some(10));
        assert_eq!(viewport_state.scroll_top, 1);
        assert_eq!(viewport_state.visible_lines, 1..3);
    }

    #[test]
    fn test_folding_state() {
        let manager = EditorStateManager::new("Line 1\nLine 2\nLine 3", 80);
        let folding_state = manager.get_folding_state();

        assert_eq!(folding_state.regions.len(), 0);
        assert_eq!(folding_state.collapsed_line_count, 0);
        assert_eq!(folding_state.visible_logical_lines, 3);
    }

    #[test]
    fn test_style_state() {
        let manager = EditorStateManager::new("Hello World", 80);
        let style_state = manager.get_style_state();

        assert_eq!(style_state.style_count, 0);
    }

    #[test]
    fn test_full_state() {
        let manager = EditorStateManager::new("Test", 80);
        let full_state = manager.get_full_state();

        assert_eq!(full_state.document.line_count, 1);
        assert_eq!(full_state.cursor.position, Position::new(0, 0));
        assert_eq!(full_state.viewport.width, 80);
    }

    #[test]
    fn test_version_tracking() {
        let mut manager = EditorStateManager::new("Test", 80);

        assert_eq!(manager.version(), 0);
        assert!(!manager.has_changed_since(0));

        manager.mark_modified(StateChangeType::DocumentModified);

        assert_eq!(manager.version(), 1);
        assert!(manager.has_changed_since(0));
        assert!(!manager.has_changed_since(1));
    }

    #[test]
    fn test_modification_tracking() {
        let mut manager = EditorStateManager::new("Test", 80);

        assert!(!manager.get_document_state().is_modified);

        manager.mark_modified(StateChangeType::DocumentModified);
        assert!(manager.get_document_state().is_modified);

        manager.mark_saved();
        assert!(!manager.get_document_state().is_modified);
    }

    #[test]
    fn test_undo_redo_state_and_dirty_tracking() {
        let mut manager = EditorStateManager::empty(80);

        let state = manager.get_undo_redo_state();
        assert!(!state.can_undo);
        assert!(!state.can_redo);

        manager
            .execute(Command::Edit(EditCommand::InsertText {
                text: "abc".to_string(),
            }))
            .unwrap();

        assert!(manager.get_document_state().is_modified);
        let state = manager.get_undo_redo_state();
        assert!(state.can_undo);
        assert!(!state.can_redo);
        assert_eq!(state.undo_depth, 1);

        manager.execute(Command::Edit(EditCommand::Undo)).unwrap();
        assert!(!manager.get_document_state().is_modified);
        let state = manager.get_undo_redo_state();
        assert!(!state.can_undo);
        assert!(state.can_redo);

        manager.execute(Command::Edit(EditCommand::Redo)).unwrap();
        assert!(manager.get_document_state().is_modified);
        let state = manager.get_undo_redo_state();
        assert!(state.can_undo);
        assert!(!state.can_redo);
    }

    #[test]
    fn test_insert_tab_undo_restores_clean_state() {
        let mut manager = EditorStateManager::empty(80);
        assert!(!manager.get_document_state().is_modified);

        manager
            .execute(Command::Edit(EditCommand::InsertTab))
            .unwrap();
        assert!(manager.get_document_state().is_modified);

        manager.execute(Command::Edit(EditCommand::Undo)).unwrap();
        assert!(!manager.get_document_state().is_modified);
    }

    #[test]
    fn test_insert_tab_spaces_undo_restores_clean_state() {
        let mut manager = EditorStateManager::empty(80);
        manager
            .execute(Command::View(ViewCommand::SetTabKeyBehavior {
                behavior: crate::TabKeyBehavior::Spaces,
            }))
            .unwrap();

        manager
            .execute(Command::Edit(EditCommand::InsertTab))
            .unwrap();
        assert!(manager.get_document_state().is_modified);

        manager.execute(Command::Edit(EditCommand::Undo)).unwrap();
        assert!(!manager.get_document_state().is_modified);
    }

    #[test]
    fn test_state_change_callback() {
        use std::sync::{Arc, Mutex};

        let mut manager = EditorStateManager::new("Test", 80);

        let callback_called = Arc::new(Mutex::new(false));
        let callback_called_clone = callback_called.clone();

        manager.subscribe(move |_change| {
            *callback_called_clone.lock().unwrap() = true;
        });

        manager.mark_modified(StateChangeType::CursorMoved);

        // Verify callback was called
        assert!(*callback_called.lock().unwrap());
    }

    #[test]
    fn test_execute_cursor_noop_does_not_bump_version() {
        let mut manager = EditorStateManager::new("A", 80);
        assert_eq!(manager.version(), 0);

        // Continue moving left at the beginning of file (unchanged after clamp), version should not change.
        manager
            .execute(Command::Cursor(CursorCommand::MoveBy {
                delta_line: 0,
                delta_column: -1,
            }))
            .unwrap();
        assert_eq!(manager.editor().cursor_position(), Position::new(0, 0));
        assert_eq!(manager.version(), 0);

        // Move to end of line (changed), version increments.
        manager
            .execute(Command::Cursor(CursorCommand::MoveTo {
                line: 0,
                column: usize::MAX,
            }))
            .unwrap();
        assert_eq!(manager.editor().cursor_position(), Position::new(0, 1));
        assert_eq!(manager.version(), 1);

        // Continue moving right at end of line (unchanged after clamp), version should not change.
        let version_before = manager.version();
        manager
            .execute(Command::Cursor(CursorCommand::MoveBy {
                delta_line: 0,
                delta_column: 1,
            }))
            .unwrap();
        assert_eq!(manager.editor().cursor_position(), Position::new(0, 1));
        assert_eq!(manager.version(), version_before);
    }

    #[test]
    fn test_viewport_height() {
        let mut manager = EditorStateManager::new("Test", 80);

        assert_eq!(manager.get_viewport_state().height, None);

        manager.set_viewport_height(20);
        assert_eq!(manager.get_viewport_state().height, Some(20));
    }

    #[test]
    fn test_scroll_position() {
        let mut manager = EditorStateManager::new("Line 1\nLine 2\nLine 3\nLine 4", 80);
        manager.set_viewport_height(2);

        assert_eq!(manager.get_viewport_state().scroll_top, 0);
        assert_eq!(manager.get_viewport_state().visible_lines, 0..2);

        manager.set_scroll_top(2);
        assert_eq!(manager.get_viewport_state().scroll_top, 2);
        assert_eq!(manager.get_viewport_state().visible_lines, 2..4);
    }

    #[test]
    fn test_get_styles() {
        let mut manager = EditorStateManager::new("Hello World", 80);

        // Add style via editor
        manager
            .editor_mut()
            .interval_tree
            .insert(crate::intervals::Interval::new(0, 5, 1));

        let styles = manager.get_styles_in_range(0, 10);
        assert_eq!(styles.len(), 1);
        assert_eq!(styles[0], (0, 5, 1));

        let styles_at = manager.get_styles_at(3);
        assert_eq!(styles_at.len(), 1);
        assert_eq!(styles_at[0], 1);
    }

    #[test]
    fn test_replace_style_layer_affects_queries() {
        let mut manager = EditorStateManager::new("Hello", 80);

        manager.replace_style_layer(
            StyleLayerId::SEMANTIC_TOKENS,
            vec![Interval::new(0, 1, 100)],
        );

        assert_eq!(manager.get_styles_at(0), vec![100]);

        // Base layer + layered styles are merged.
        manager
            .editor_mut()
            .interval_tree
            .insert(Interval::new(0, 5, 1));

        assert_eq!(manager.get_styles_at(0), vec![1, 100]);
    }

    #[test]
    fn test_viewport_content_styled_wraps_and_includes_styles() {
        let mut manager = EditorStateManager::new("abcdef", 3);

        // Highlight "bcd" across a wrap boundary: "abc" | "def"
        manager.replace_style_layer(StyleLayerId::SIMPLE_SYNTAX, vec![Interval::new(1, 4, 7)]);

        let grid = manager.get_viewport_content_styled(0, 10);
        assert_eq!(grid.actual_line_count(), 2);

        let line0 = &grid.lines[0];
        assert_eq!(line0.logical_line_index, 0);
        assert!(!line0.is_wrapped_part);
        assert_eq!(line0.cells.len(), 3);
        assert_eq!(line0.cells[0].ch, 'a');
        assert_eq!(line0.cells[1].ch, 'b');
        assert_eq!(line0.cells[2].ch, 'c');
        assert_eq!(line0.cells[0].styles, Vec::<StyleId>::new());
        assert_eq!(line0.cells[1].styles, vec![7]);
        assert_eq!(line0.cells[2].styles, vec![7]);

        let line1 = &grid.lines[1];
        assert_eq!(line1.logical_line_index, 0);
        assert!(line1.is_wrapped_part);
        assert_eq!(line1.cells.len(), 3);
        assert_eq!(line1.cells[0].ch, 'd');
        assert_eq!(line1.cells[0].styles, vec![7]);
        assert_eq!(line1.cells[1].ch, 'e');
        assert_eq!(line1.cells[1].styles, Vec::<StyleId>::new());
    }
}
