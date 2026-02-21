//! Command Interface Layer
//!
//! Provides a unified command interface for convenient frontend integration.
//!
//! # Overview
//!
//! The Command Interface Layer is the primary entry point for Editor Core, wrapping all underlying components in a unified command pattern.
//! It supports the following types of operations:
//!
//! - **Text Editing**: Insert, delete, and replace text
//! - **Cursor Operations**: Move cursor and set selection range
//! - **View Management**: Set viewport, scroll, and get visible content
//! - **Style Control**: Add/remove styles and code folding
//!
//! # Example
//!
//! ```rust
//! use editor_core::{CommandExecutor, Command, EditCommand};
//!
//! let mut executor = CommandExecutor::empty(80);
//!
//! // Insert text
//! executor.execute(Command::Edit(EditCommand::Insert {
//!     offset: 0,
//!     text: "Hello, World!".to_string(),
//! })).unwrap();
//!
//! // Batch execute commands
//! let commands = vec![
//!     Command::Edit(EditCommand::Insert { offset: 0, text: "Line 1\n".to_string() }),
//!     Command::Edit(EditCommand::Insert { offset: 7, text: "Line 2\n".to_string() }),
//! ];
//! executor.execute_batch(commands).unwrap();
//! ```

use crate::delta::{TextDelta, TextDeltaEdit};
use crate::intervals::{FoldRegion, StyleId, StyleLayerId};
use crate::layout::{cell_width_at, char_width, visual_x_for_column};
use crate::search::{CharIndex, SearchMatch, SearchOptions, find_all, find_next, find_prev};
use crate::snapshot::{Cell, HeadlessGrid, HeadlessLine};
use crate::{
    FOLD_PLACEHOLDER_STYLE_ID, FoldingManager, IntervalTree, LayoutEngine, LineIndex, PieceTable,
    SnapshotGenerator,
};
use regex::RegexBuilder;
use std::cmp::Ordering;
use std::collections::BTreeMap;

/// Position coordinates (line and column numbers)
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Position {
    /// Zero-based logical line index.
    pub line: usize,
    /// Zero-based column in characters within the logical line.
    pub column: usize,
}

impl Position {
    /// Create a new logical position.
    pub fn new(line: usize, column: usize) -> Self {
        Self { line, column }
    }
}

impl Ord for Position {
    fn cmp(&self, other: &Self) -> Ordering {
        self.line
            .cmp(&other.line)
            .then_with(|| self.column.cmp(&other.column))
    }
}

impl PartialOrd for Position {
    fn partial_cmp(&self, other: &Self) -> Option<Ordering> {
        Some(self.cmp(other))
    }
}

/// Selection range
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Selection {
    /// Selection start position
    pub start: Position,
    /// Selection end position
    pub end: Position,
    /// Selection direction
    pub direction: SelectionDirection,
}

/// Selection direction
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SelectionDirection {
    /// Forward selection (from start to end)
    Forward,
    /// Backward selection (from end to start)
    Backward,
}

/// Controls how a Tab key press is handled by the editor when using [`EditCommand::InsertTab`].
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum TabKeyBehavior {
    /// Insert a literal tab character (`'\t'`).
    Tab,
    /// Insert spaces up to the next tab stop (based on the current `tab_width` setting).
    Spaces,
}

/// Text editing commands
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum EditCommand {
    /// Insert text at the specified position
    Insert {
        /// Character offset to insert at.
        offset: usize,
        /// Text to insert.
        text: String,
    },
    /// Delete text in specified range
    Delete {
        /// Character offset of the deletion start.
        start: usize,
        /// Length of the deletion in characters.
        length: usize,
    },
    /// Replace text in specified range
    Replace {
        /// Character offset of the replacement start.
        start: usize,
        /// Length of the replaced range in characters.
        length: usize,
        /// Replacement text.
        text: String,
    },
    /// VSCode-like typing/paste: apply to all carets/selections (primary + secondary)
    InsertText {
        /// Text to insert/replace at each selection/caret.
        text: String,
    },
    /// Insert a tab at each caret (or replace each selection), using the current tab settings.
    ///
    /// - If `TabKeyBehavior::Tab`, inserts `'\t'`.
    /// - If `TabKeyBehavior::Spaces`, inserts spaces up to the next tab stop.
    InsertTab,
    /// Backspace-like deletion: delete selection(s) if any, otherwise delete 1 char before each caret.
    Backspace,
    /// Delete key-like deletion: delete selection(s) if any, otherwise delete 1 char after each caret.
    DeleteForward,
    /// Undo last edit operation (supports grouping)
    Undo,
    /// Redo last undone operation (supports grouping)
    Redo,
    /// Explicitly end the current undo group (for idle or external boundaries)
    EndUndoGroup,
    /// Replace the current occurrence of `query` (based on selection/caret) with `replacement`.
    ///
    /// - Honors `options` (case sensitivity / whole-word / regex).
    /// - Treated as a single undoable edit.
    ReplaceCurrent {
        /// Search query.
        query: String,
        /// Replacement text.
        replacement: String,
        /// Search options (case sensitivity, whole-word, regex).
        options: SearchOptions,
    },
    /// Replace all occurrences of `query` with `replacement`.
    ///
    /// - Honors `options` (case sensitivity / whole-word / regex).
    /// - Treated as a single undoable edit.
    ReplaceAll {
        /// Search query.
        query: String,
        /// Replacement text.
        replacement: String,
        /// Search options (case sensitivity, whole-word, regex).
        options: SearchOptions,
    },
}

/// Cursor & selection commands
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CursorCommand {
    /// Move cursor to the specified position
    MoveTo {
        /// Target logical line index.
        line: usize,
        /// Target column in characters (will be clamped to line length).
        column: usize,
    },
    /// Move cursor relatively
    MoveBy {
        /// Delta in logical lines.
        delta_line: isize,
        /// Delta in columns (characters).
        delta_column: isize,
    },
    /// Set selection range
    SetSelection {
        /// Selection start position.
        start: Position,
        /// Selection end position.
        end: Position,
    },
    /// Extend selection range
    ExtendSelection {
        /// New active end position.
        to: Position,
    },
    /// Clear selection
    ClearSelection,
    /// Set multiple selections/multi-cursor (including primary)
    SetSelections {
        /// All selections (including primary).
        selections: Vec<Selection>,
        /// Index of the primary selection in `selections`.
        primary_index: usize,
    },
    /// Clear secondary selections/cursors, keeping only primary
    ClearSecondarySelections,
    /// Set rectangular selection (box/column selection), which expands into one Selection per line
    SetRectSelection {
        /// Anchor position (fixed corner).
        anchor: Position,
        /// Active position (moving corner).
        active: Position,
    },
    /// Find the next occurrence of `query` and select it (primary selection only).
    FindNext {
        /// Search query.
        query: String,
        /// Search options (case sensitivity, whole-word, regex).
        options: SearchOptions,
    },
    /// Find the previous occurrence of `query` and select it (primary selection only).
    FindPrev {
        /// Search query.
        query: String,
        /// Search options (case sensitivity, whole-word, regex).
        options: SearchOptions,
    },
}

/// View commands
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum ViewCommand {
    /// Set viewport width
    SetViewportWidth {
        /// Width in character cells.
        width: usize,
    },
    /// Set tab width (in character cells) used for measuring `'\t'` and tab stops.
    SetTabWidth {
        /// Tab width in character cells (must be greater than 0).
        width: usize,
    },
    /// Configure how [`EditCommand::InsertTab`] inserts text.
    SetTabKeyBehavior {
        /// Tab key behavior.
        behavior: TabKeyBehavior,
    },
    /// Scroll to specified line
    ScrollTo {
        /// Logical line index to scroll to.
        line: usize,
    },
    /// Get current viewport content
    GetViewport {
        /// Starting visual row.
        start_row: usize,
        /// Number of visual rows requested.
        count: usize,
    },
}

/// Style and folding commands
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum StyleCommand {
    /// Add style interval
    AddStyle {
        /// Interval start offset in characters.
        start: usize,
        /// Interval end offset in characters (exclusive).
        end: usize,
        /// Style identifier.
        style_id: StyleId,
    },
    /// Remove style interval
    RemoveStyle {
        /// Interval start offset in characters.
        start: usize,
        /// Interval end offset in characters (exclusive).
        end: usize,
        /// Style identifier.
        style_id: StyleId,
    },
    /// Fold code block
    Fold {
        /// Start logical line (inclusive).
        start_line: usize,
        /// End logical line (inclusive).
        end_line: usize,
    },
    /// Unfold code block
    Unfold {
        /// Start logical line (inclusive) of the fold region to unfold.
        start_line: usize,
    },
    /// Unfold all folds
    UnfoldAll,
}

/// Unified command enum
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum Command {
    /// Text editing commands
    Edit(EditCommand),
    /// Cursor command
    Cursor(CursorCommand),
    /// View commands
    View(ViewCommand),
    /// Style command
    Style(StyleCommand),
}

/// Command execution result
#[derive(Debug, Clone)]
pub enum CommandResult {
    /// Success, no return value
    Success,
    /// Success, returns text
    Text(String),
    /// Success, returns position
    Position(Position),
    /// Success, returns offset
    Offset(usize),
    /// Success, returns viewport content
    Viewport(HeadlessGrid),
    /// Find/search result: a match in char offsets (half-open).
    SearchMatch {
        /// Inclusive start character offset.
        start: usize,
        /// Exclusive end character offset.
        end: usize,
    },
    /// Find/search result: no match found.
    SearchNotFound,
    /// Replace result: how many occurrences were replaced.
    ReplaceResult {
        /// Number of occurrences replaced.
        replaced: usize,
    },
}

/// Command error type
#[derive(Debug, Clone, PartialEq, Eq)]
pub enum CommandError {
    /// Invalid offset
    InvalidOffset(usize),
    /// Invalid position
    InvalidPosition {
        /// Logical line index.
        line: usize,
        /// Column in characters.
        column: usize,
    },
    /// Invalid range
    InvalidRange {
        /// Inclusive start character offset.
        start: usize,
        /// Exclusive end character offset.
        end: usize,
    },
    /// Empty text
    EmptyText,
    /// Other error
    Other(String),
}

impl std::fmt::Display for CommandError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CommandError::InvalidOffset(offset) => {
                write!(f, "Invalid offset: {}", offset)
            }
            CommandError::InvalidPosition { line, column } => {
                write!(f, "Invalid position: line {}, column {}", line, column)
            }
            CommandError::InvalidRange { start, end } => {
                write!(f, "Invalid range: {}..{}", start, end)
            }
            CommandError::EmptyText => {
                write!(f, "Text cannot be empty")
            }
            CommandError::Other(msg) => {
                write!(f, "{}", msg)
            }
        }
    }
}

impl std::error::Error for CommandError {}

#[derive(Debug, Clone)]
struct SelectionSetSnapshot {
    selections: Vec<Selection>,
    primary_index: usize,
}

#[derive(Debug, Clone)]
struct TextEdit {
    start_before: usize,
    start_after: usize,
    deleted_text: String,
    inserted_text: String,
}

impl TextEdit {
    fn deleted_len(&self) -> usize {
        self.deleted_text.chars().count()
    }

    fn inserted_len(&self) -> usize {
        self.inserted_text.chars().count()
    }
}

#[derive(Debug, Clone)]
struct UndoStep {
    group_id: usize,
    edits: Vec<TextEdit>,
    before_selection: SelectionSetSnapshot,
    after_selection: SelectionSetSnapshot,
}

#[derive(Debug)]
struct UndoRedoManager {
    undo_stack: Vec<UndoStep>,
    redo_stack: Vec<UndoStep>,
    max_undo: usize,
    /// Clean point tracking. Uses `undo_stack.len()` as the saved position in the linear history.
    /// When `redo_stack` is non-empty, `clean_index` may be greater than `undo_stack.len()`.
    clean_index: Option<usize>,
    next_group_id: usize,
    open_group_id: Option<usize>,
}

impl UndoRedoManager {
    fn new(max_undo: usize) -> Self {
        Self {
            undo_stack: Vec::new(),
            redo_stack: Vec::new(),
            max_undo,
            clean_index: Some(0),
            next_group_id: 0,
            open_group_id: None,
        }
    }

    fn can_undo(&self) -> bool {
        !self.undo_stack.is_empty()
    }

    fn can_redo(&self) -> bool {
        !self.redo_stack.is_empty()
    }

    fn undo_depth(&self) -> usize {
        self.undo_stack.len()
    }

    fn redo_depth(&self) -> usize {
        self.redo_stack.len()
    }

    fn current_group_id(&self) -> Option<usize> {
        self.open_group_id
    }

    fn is_clean(&self) -> bool {
        self.clean_index == Some(self.undo_stack.len())
    }

    fn mark_clean(&mut self) {
        self.clean_index = Some(self.undo_stack.len());
        self.end_group();
    }

    fn end_group(&mut self) {
        self.open_group_id = None;
    }

    fn clear_redo_and_adjust_clean(&mut self) {
        if self.redo_stack.is_empty() {
            return;
        }

        // If clean point is in redo area, it becomes unreachable after clearing redo.
        if let Some(clean_index) = self.clean_index
            && clean_index > self.undo_stack.len()
        {
            self.clean_index = None;
        }

        self.redo_stack.clear();
    }

    fn push_step(&mut self, mut step: UndoStep, coalescible_insert: bool) -> usize {
        self.clear_redo_and_adjust_clean();

        if self.undo_stack.len() >= self.max_undo {
            self.undo_stack.remove(0);
            if let Some(clean_index) = self.clean_index {
                if clean_index == 0 {
                    self.clean_index = None;
                } else {
                    self.clean_index = Some(clean_index - 1);
                }
            }
        }

        let reuse_open_group = coalescible_insert
            && self.open_group_id.is_some()
            && self.clean_index != Some(self.undo_stack.len());

        if reuse_open_group {
            step.group_id = self.open_group_id.expect("checked");
        } else {
            step.group_id = self.next_group_id;
            self.next_group_id = self.next_group_id.wrapping_add(1);
        }

        if coalescible_insert {
            self.open_group_id = Some(step.group_id);
        } else {
            self.open_group_id = None;
        }

        let group_id = step.group_id;
        self.undo_stack.push(step);
        group_id
    }

    fn pop_undo_group(&mut self) -> Option<Vec<UndoStep>> {
        let last_group_id = self.undo_stack.last().map(|s| s.group_id)?;
        let mut steps: Vec<UndoStep> = Vec::new();

        while let Some(step) = self.undo_stack.last() {
            if step.group_id != last_group_id {
                break;
            }
            steps.push(self.undo_stack.pop().expect("checked"));
        }

        Some(steps)
    }

    fn pop_redo_group(&mut self) -> Option<Vec<UndoStep>> {
        let last_group_id = self.redo_stack.last().map(|s| s.group_id)?;
        let mut steps: Vec<UndoStep> = Vec::new();

        while let Some(step) = self.redo_stack.last() {
            if step.group_id != last_group_id {
                break;
            }
            steps.push(self.redo_stack.pop().expect("checked"));
        }

        Some(steps)
    }
}

/// Editor Core state
///
/// `EditorCore` aggregates all underlying editor components, including:
///
/// - **PieceTable**: Efficient text storage and modification
/// - **LineIndex**: Rope-based line index, supporting fast line access
/// - **LayoutEngine**: Soft wrapping and text layout calculation
/// - **IntervalTree**: Style interval management
/// - **FoldingManager**: Code folding management
/// - **Cursor & Selection**: Cursor and selection state
///
/// # Example
///
/// ```rust
/// use editor_core::EditorCore;
///
/// let mut core = EditorCore::new("Hello\nWorld", 80);
/// assert_eq!(core.line_count(), 2);
/// assert_eq!(core.get_text(), "Hello\nWorld");
/// ```
pub struct EditorCore {
    /// Piece Table storage layer
    pub piece_table: PieceTable,
    /// Line index
    pub line_index: LineIndex,
    /// Layout engine
    pub layout_engine: LayoutEngine,
    /// Interval tree (style management)
    pub interval_tree: IntervalTree,
    /// Layered styles (for semantic highlighting/simple syntax highlighting, etc.)
    pub style_layers: BTreeMap<StyleLayerId, IntervalTree>,
    /// Folding manager
    pub folding_manager: FoldingManager,
    /// Current cursor position
    pub cursor_position: Position,
    /// Current selection range
    pub selection: Option<Selection>,
    /// Secondary selections/cursors (multi-cursor). Each Selection can be empty (start==end), representing a caret.
    pub secondary_selections: Vec<Selection>,
    /// Viewport width
    pub viewport_width: usize,
}

impl EditorCore {
    /// Create a new Editor Core
    pub fn new(text: &str, viewport_width: usize) -> Self {
        let piece_table = PieceTable::new(text);
        let line_index = LineIndex::from_text(text);
        let mut layout_engine = LayoutEngine::new(viewport_width);

        // Initialize layout engine to be consistent with initial text (including trailing empty line).
        let lines = crate::text::split_lines_preserve_trailing(text);
        let line_refs: Vec<&str> = lines.iter().map(|s| s.as_str()).collect();
        layout_engine.from_lines(&line_refs);

        Self {
            piece_table,
            line_index,
            layout_engine,
            interval_tree: IntervalTree::new(),
            style_layers: BTreeMap::new(),
            folding_manager: FoldingManager::new(),
            cursor_position: Position::new(0, 0),
            selection: None,
            secondary_selections: Vec::new(),
            viewport_width,
        }
    }

    /// Create an empty Editor Core
    pub fn empty(viewport_width: usize) -> Self {
        Self::new("", viewport_width)
    }

    /// Get text content
    pub fn get_text(&self) -> String {
        self.piece_table.get_text()
    }

    /// Get total line count
    pub fn line_count(&self) -> usize {
        self.line_index.line_count()
    }

    /// Get total character count
    pub fn char_count(&self) -> usize {
        self.piece_table.char_count()
    }

    /// Get cursor position
    pub fn cursor_position(&self) -> Position {
        self.cursor_position
    }

    /// Get selection range
    pub fn selection(&self) -> Option<&Selection> {
        self.selection.as_ref()
    }

    /// Get secondary selections/cursors (multi-cursor)
    pub fn secondary_selections(&self) -> &[Selection] {
        &self.secondary_selections
    }

    /// Get styled headless grid snapshot (by visual line).
    ///
    /// - Supportsoft wrapping (based `layout_engine`)
    /// - `Cell.styles` will `interval_tree` + `style_layers` merged from
    /// - Supportcode folding (based `folding_manager`)
    ///
    /// Note: This API is not responsible for mapping `StyleId` to specific colors.
    pub fn get_headless_grid_styled(&self, start_visual_row: usize, count: usize) -> HeadlessGrid {
        let mut grid = HeadlessGrid::new(start_visual_row, count);
        if count == 0 {
            return grid;
        }

        let tab_width = self.layout_engine.tab_width();

        let total_visual = self.visual_line_count();
        if start_visual_row >= total_visual {
            return grid;
        }

        let end_visual = start_visual_row.saturating_add(count).min(total_visual);

        let mut current_visual = 0usize;
        let logical_line_count = self.layout_engine.logical_line_count();
        let regions = self.folding_manager.regions();

        'outer: for logical_line in 0..logical_line_count {
            if Self::is_logical_line_hidden(regions, logical_line) {
                continue;
            }

            let Some(layout) = self.layout_engine.get_line_layout(logical_line) else {
                continue;
            };

            let line_text = self
                .line_index
                .get_line_text(logical_line)
                .unwrap_or_default();
            let line_char_len = line_text.chars().count();
            let line_start_offset = self.line_index.position_to_char_offset(logical_line, 0);

            for visual_in_line in 0..layout.visual_line_count {
                if current_visual >= end_visual {
                    break 'outer;
                }

                if current_visual >= start_visual_row {
                    let segment_start_col = if visual_in_line == 0 {
                        0
                    } else {
                        layout
                            .wrap_points
                            .get(visual_in_line - 1)
                            .map(|wp| wp.char_index)
                            .unwrap_or(0)
                            .min(line_char_len)
                    };

                    let segment_end_col = if visual_in_line < layout.wrap_points.len() {
                        layout.wrap_points[visual_in_line]
                            .char_index
                            .min(line_char_len)
                    } else {
                        line_char_len
                    };

                    let mut headless_line = HeadlessLine::new(logical_line, visual_in_line > 0);
                    let mut x_in_line =
                        visual_x_for_column(&line_text, segment_start_col, tab_width);

                    for (col, ch) in line_text
                        .chars()
                        .enumerate()
                        .skip(segment_start_col)
                        .take(segment_end_col.saturating_sub(segment_start_col))
                    {
                        let offset = line_start_offset + col;
                        let styles = self.styles_at_offset(offset);
                        let w = cell_width_at(ch, x_in_line, tab_width);
                        x_in_line = x_in_line.saturating_add(w);
                        headless_line.add_cell(Cell::with_styles(ch, w, styles));
                    }

                    // For collapsed folding start line, append placeholder to the last segment.
                    if visual_in_line + 1 == layout.visual_line_count
                        && let Some(region) =
                            Self::collapsed_region_starting_at(regions, logical_line)
                        && !region.placeholder.is_empty()
                    {
                        if !headless_line.cells.is_empty() {
                            x_in_line = x_in_line.saturating_add(char_width(' '));
                            headless_line.add_cell(Cell::with_styles(
                                ' ',
                                char_width(' '),
                                vec![FOLD_PLACEHOLDER_STYLE_ID],
                            ));
                        }
                        for ch in region.placeholder.chars() {
                            let w = cell_width_at(ch, x_in_line, tab_width);
                            x_in_line = x_in_line.saturating_add(w);
                            headless_line.add_cell(Cell::with_styles(
                                ch,
                                w,
                                vec![FOLD_PLACEHOLDER_STYLE_ID],
                            ));
                        }
                    }

                    grid.add_line(headless_line);
                }

                current_visual = current_visual.saturating_add(1);
            }
        }

        grid
    }

    /// Get total visual line count (considering soft wrapping + folding).
    pub fn visual_line_count(&self) -> usize {
        let regions = self.folding_manager.regions();
        let mut total = 0usize;

        for logical_line in 0..self.layout_engine.logical_line_count() {
            if Self::is_logical_line_hidden(regions, logical_line) {
                continue;
            }

            total = total.saturating_add(
                self.layout_engine
                    .get_line_layout(logical_line)
                    .map(|l| l.visual_line_count)
                    .unwrap_or(1),
            );
        }

        total
    }

    /// Map visual line number back to (logical_line, visual_in_logical), considering folding.
    pub fn visual_to_logical_line(&self, visual_line: usize) -> (usize, usize) {
        let regions = self.folding_manager.regions();
        let mut cumulative_visual = 0usize;
        let mut last_visible = (0usize, 0usize);

        for logical_line in 0..self.layout_engine.logical_line_count() {
            if Self::is_logical_line_hidden(regions, logical_line) {
                continue;
            }

            let visual_count = self
                .layout_engine
                .get_line_layout(logical_line)
                .map(|l| l.visual_line_count)
                .unwrap_or(1);

            if cumulative_visual + visual_count > visual_line {
                return (logical_line, visual_line - cumulative_visual);
            }

            cumulative_visual = cumulative_visual.saturating_add(visual_count);
            last_visible = (logical_line, visual_count.saturating_sub(1));
        }

        last_visible
    }

    /// Convert logical coordinates (line, column) to visual coordinates (visual line number, in-line x cell offset), considering folding.
    pub fn logical_position_to_visual(
        &self,
        logical_line: usize,
        column: usize,
    ) -> Option<(usize, usize)> {
        let regions = self.folding_manager.regions();
        let logical_line = Self::closest_visible_line(regions, logical_line)?;
        let visual_start = self.visual_start_for_logical_line(logical_line)?;

        let tab_width = self.layout_engine.tab_width();

        let layout = self.layout_engine.get_line_layout(logical_line)?;
        let line_text = self
            .line_index
            .get_line_text(logical_line)
            .unwrap_or_default();

        let line_char_len = line_text.chars().count();
        let column = column.min(line_char_len);

        let mut wrapped_offset = 0usize;
        let mut segment_start_col = 0usize;
        for wrap_point in &layout.wrap_points {
            if column >= wrap_point.char_index {
                wrapped_offset = wrapped_offset.saturating_add(1);
                segment_start_col = wrap_point.char_index;
            } else {
                break;
            }
        }

        let seg_start_x_in_line = visual_x_for_column(&line_text, segment_start_col, tab_width);
        let mut x_in_line = seg_start_x_in_line;
        let mut x_in_segment = 0usize;
        for ch in line_text
            .chars()
            .skip(segment_start_col)
            .take(column.saturating_sub(segment_start_col))
        {
            let w = cell_width_at(ch, x_in_line, tab_width);
            x_in_line = x_in_line.saturating_add(w);
            x_in_segment = x_in_segment.saturating_add(w);
        }

        Some((visual_start.saturating_add(wrapped_offset), x_in_segment))
    }

    /// Convert logical coordinates (line, column) to visual coordinates (visual line number, in-line x cell offset), considering folding.
    ///
    /// Difference from [`logical_position_to_visual`](Self::logical_position_to_visual) is that it allows `column`
    /// to exceed the line end: the exceeding part is treated as `' '` (width=1) virtual spaces, suitable for rectangular selection / column editing.
    pub fn logical_position_to_visual_allow_virtual(
        &self,
        logical_line: usize,
        column: usize,
    ) -> Option<(usize, usize)> {
        let regions = self.folding_manager.regions();
        let logical_line = Self::closest_visible_line(regions, logical_line)?;
        let visual_start = self.visual_start_for_logical_line(logical_line)?;

        let tab_width = self.layout_engine.tab_width();

        let layout = self.layout_engine.get_line_layout(logical_line)?;
        let line_text = self
            .line_index
            .get_line_text(logical_line)
            .unwrap_or_default();

        let line_char_len = line_text.chars().count();
        let clamped_column = column.min(line_char_len);

        let mut wrapped_offset = 0usize;
        let mut segment_start_col = 0usize;
        for wrap_point in &layout.wrap_points {
            if clamped_column >= wrap_point.char_index {
                wrapped_offset = wrapped_offset.saturating_add(1);
                segment_start_col = wrap_point.char_index;
            } else {
                break;
            }
        }

        let seg_start_x_in_line = visual_x_for_column(&line_text, segment_start_col, tab_width);
        let mut x_in_line = seg_start_x_in_line;
        let mut x_in_segment = 0usize;
        for ch in line_text
            .chars()
            .skip(segment_start_col)
            .take(clamped_column.saturating_sub(segment_start_col))
        {
            let w = cell_width_at(ch, x_in_line, tab_width);
            x_in_line = x_in_line.saturating_add(w);
            x_in_segment = x_in_segment.saturating_add(w);
        }

        let x_in_segment = x_in_segment + column.saturating_sub(line_char_len);

        Some((visual_start.saturating_add(wrapped_offset), x_in_segment))
    }

    fn visual_start_for_logical_line(&self, logical_line: usize) -> Option<usize> {
        if logical_line >= self.layout_engine.logical_line_count() {
            return None;
        }

        let regions = self.folding_manager.regions();
        if Self::is_logical_line_hidden(regions, logical_line) {
            return None;
        }

        let mut start = 0usize;
        for line in 0..logical_line {
            if Self::is_logical_line_hidden(regions, line) {
                continue;
            }
            start = start.saturating_add(
                self.layout_engine
                    .get_line_layout(line)
                    .map(|l| l.visual_line_count)
                    .unwrap_or(1),
            );
        }
        Some(start)
    }

    fn is_logical_line_hidden(regions: &[FoldRegion], logical_line: usize) -> bool {
        regions.iter().any(|region| {
            region.is_collapsed
                && logical_line > region.start_line
                && logical_line <= region.end_line
        })
    }

    fn collapsed_region_starting_at(
        regions: &[FoldRegion],
        start_line: usize,
    ) -> Option<&FoldRegion> {
        regions
            .iter()
            .filter(|region| {
                region.is_collapsed
                    && region.start_line == start_line
                    && region.end_line > start_line
            })
            .min_by_key(|region| region.end_line)
    }

    fn closest_visible_line(regions: &[FoldRegion], logical_line: usize) -> Option<usize> {
        let mut line = logical_line;
        if regions.is_empty() {
            return Some(line);
        }

        while Self::is_logical_line_hidden(regions, line) {
            let Some(start) = regions
                .iter()
                .filter(|region| {
                    region.is_collapsed && line > region.start_line && line <= region.end_line
                })
                .map(|region| region.start_line)
                .max()
            else {
                break;
            };
            line = start;
        }

        if Self::is_logical_line_hidden(regions, line) {
            None
        } else {
            Some(line)
        }
    }

    fn styles_at_offset(&self, offset: usize) -> Vec<StyleId> {
        let mut styles: Vec<StyleId> = self
            .interval_tree
            .query_point(offset)
            .iter()
            .map(|interval| interval.style_id)
            .collect();

        for tree in self.style_layers.values() {
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
}

/// Command executor
///
/// `CommandExecutor` is the main interface for the editor, responsible for:
///
/// - Execute various editor commands
/// - Maintain command history
/// - Handle errors and exceptions
/// - Ensure editor state consistency
///
/// # Command Types
///
/// - [`EditCommand`] - Text insertion, deletion, replacement
/// - [`CursorCommand`] - Cursor movement, selection operations
/// - [`ViewCommand`] - Viewport management and scroll control
/// - [`StyleCommand`] - Style and folding management
///
/// # Example
///
/// ```rust
/// use editor_core::{CommandExecutor, Command, EditCommand, CursorCommand, Position};
///
/// let mut executor = CommandExecutor::empty(80);
///
/// // Insert text
/// executor.execute(Command::Edit(EditCommand::Insert {
///     offset: 0,
///     text: "fn main() {}".to_string(),
/// })).unwrap();
///
/// // Move cursor
/// executor.execute(Command::Cursor(CursorCommand::MoveTo {
///     line: 0,
///     column: 3,
/// })).unwrap();
///
/// assert_eq!(executor.editor().cursor_position(), Position::new(0, 3));
/// ```
pub struct CommandExecutor {
    /// Editor Core
    editor: EditorCore,
    /// Command history
    command_history: Vec<Command>,
    /// Undo/redo manager (only records CommandExecutor edit commands executed via)
    undo_redo: UndoRedoManager,
    /// Controls how [`EditCommand::InsertTab`] behaves.
    tab_key_behavior: TabKeyBehavior,
    /// Structured delta for the last executed text modification (cleared on each `execute()` call).
    last_text_delta: Option<TextDelta>,
}

impl CommandExecutor {
    /// Create a new command executor
    pub fn new(text: &str, viewport_width: usize) -> Self {
        Self {
            editor: EditorCore::new(text, viewport_width),
            command_history: Vec::new(),
            undo_redo: UndoRedoManager::new(1000),
            tab_key_behavior: TabKeyBehavior::Tab,
            last_text_delta: None,
        }
    }

    /// Create an empty command executor
    pub fn empty(viewport_width: usize) -> Self {
        Self::new("", viewport_width)
    }

    /// Execute command
    pub fn execute(&mut self, command: Command) -> Result<CommandResult, CommandError> {
        self.last_text_delta = None;

        // Save command to history
        self.command_history.push(command.clone());

        // Undo grouping: any non-edit command ends the current coalescing group.
        if !matches!(command, Command::Edit(_)) {
            self.undo_redo.end_group();
        }

        // Execute command
        match command {
            Command::Edit(edit_cmd) => self.execute_edit(edit_cmd),
            Command::Cursor(cursor_cmd) => self.execute_cursor(cursor_cmd),
            Command::View(view_cmd) => self.execute_view(view_cmd),
            Command::Style(style_cmd) => self.execute_style(style_cmd),
        }
    }

    /// Get the structured text delta produced by the last successful `execute()` call, if any.
    pub fn last_text_delta(&self) -> Option<&TextDelta> {
        self.last_text_delta.as_ref()
    }

    /// Take the structured text delta produced by the last successful `execute()` call, if any.
    pub fn take_last_text_delta(&mut self) -> Option<TextDelta> {
        self.last_text_delta.take()
    }

    /// Batch execute commands (transactional)
    pub fn execute_batch(
        &mut self,
        commands: Vec<Command>,
    ) -> Result<Vec<CommandResult>, CommandError> {
        let mut results = Vec::new();

        for command in commands {
            let result = self.execute(command)?;
            results.push(result);
        }

        Ok(results)
    }

    /// Get command history
    pub fn get_command_history(&self) -> &[Command] {
        &self.command_history
    }

    /// Can undo
    pub fn can_undo(&self) -> bool {
        self.undo_redo.can_undo()
    }

    /// Can redo
    pub fn can_redo(&self) -> bool {
        self.undo_redo.can_redo()
    }

    /// Undo stack depth (counted by undo steps; grouped undo may pop multiple steps at once)
    pub fn undo_depth(&self) -> usize {
        self.undo_redo.undo_depth()
    }

    /// Redo stack depth (counted by undo steps)
    pub fn redo_depth(&self) -> usize {
        self.undo_redo.redo_depth()
    }

    /// Currently open undo group ID (for insert coalescing only)
    pub fn current_change_group(&self) -> Option<usize> {
        self.undo_redo.current_group_id()
    }

    /// Whether current state is at clean point (for dirty tracking)
    pub fn is_clean(&self) -> bool {
        self.undo_redo.is_clean()
    }

    /// Mark current state as clean point (call after saving file)
    pub fn mark_clean(&mut self) {
        self.undo_redo.mark_clean();
    }

    /// Get a reference to the Editor Core
    pub fn editor(&self) -> &EditorCore {
        &self.editor
    }

    /// Get a mutable reference to the Editor Core
    pub fn editor_mut(&mut self) -> &mut EditorCore {
        &mut self.editor
    }

    /// Get current tab key behavior used by [`EditCommand::InsertTab`].
    pub fn tab_key_behavior(&self) -> TabKeyBehavior {
        self.tab_key_behavior
    }

    /// Set tab key behavior used by [`EditCommand::InsertTab`].
    pub fn set_tab_key_behavior(&mut self, behavior: TabKeyBehavior) {
        self.tab_key_behavior = behavior;
    }

    // Private method: execute edit command
    fn execute_edit(&mut self, command: EditCommand) -> Result<CommandResult, CommandError> {
        match command {
            EditCommand::Undo => self.execute_undo_command(),
            EditCommand::Redo => self.execute_redo_command(),
            EditCommand::EndUndoGroup => {
                self.undo_redo.end_group();
                Ok(CommandResult::Success)
            }
            EditCommand::ReplaceCurrent {
                query,
                replacement,
                options,
            } => self.execute_replace_current_command(query, replacement, options),
            EditCommand::ReplaceAll {
                query,
                replacement,
                options,
            } => self.execute_replace_all_command(query, replacement, options),
            EditCommand::Backspace => self.execute_backspace_command(),
            EditCommand::DeleteForward => self.execute_delete_forward_command(),
            EditCommand::InsertText { text } => self.execute_insert_text_command(text),
            EditCommand::InsertTab => self.execute_insert_tab_command(),
            EditCommand::Insert { offset, text } => self.execute_insert_command(offset, text),
            EditCommand::Delete { start, length } => self.execute_delete_command(start, length),
            EditCommand::Replace {
                start,
                length,
                text,
            } => self.execute_replace_command(start, length, text),
        }
    }

    fn execute_undo_command(&mut self) -> Result<CommandResult, CommandError> {
        self.undo_redo.end_group();
        if !self.undo_redo.can_undo() {
            return Err(CommandError::Other("Nothing to undo".to_string()));
        }

        let before_char_count = self.editor.piece_table.char_count();
        let steps = self
            .undo_redo
            .pop_undo_group()
            .ok_or_else(|| CommandError::Other("Nothing to undo".to_string()))?;

        let undo_group_id = steps.first().map(|s| s.group_id);
        let mut delta_edits: Vec<TextDeltaEdit> = Vec::new();

        for step in &steps {
            let mut step_edits: Vec<TextDeltaEdit> = step
                .edits
                .iter()
                .map(|edit| TextDeltaEdit {
                    start: edit.start_after,
                    deleted_text: edit.inserted_text.clone(),
                    inserted_text: edit.deleted_text.clone(),
                })
                .collect();
            step_edits.sort_by_key(|e| std::cmp::Reverse(e.start));
            delta_edits.extend(step_edits);

            self.apply_undo_edits(&step.edits)?;
            self.restore_selection_set(step.before_selection.clone());
        }

        // Move steps to redo stack in the same pop order (newest->oldest) so redo pops oldest first.
        for step in steps {
            self.undo_redo.redo_stack.push(step);
        }

        self.last_text_delta = Some(TextDelta {
            before_char_count,
            after_char_count: self.editor.piece_table.char_count(),
            edits: delta_edits,
            undo_group_id: undo_group_id,
        });

        Ok(CommandResult::Success)
    }

    fn execute_redo_command(&mut self) -> Result<CommandResult, CommandError> {
        self.undo_redo.end_group();
        if !self.undo_redo.can_redo() {
            return Err(CommandError::Other("Nothing to redo".to_string()));
        }

        let before_char_count = self.editor.piece_table.char_count();
        let steps = self
            .undo_redo
            .pop_redo_group()
            .ok_or_else(|| CommandError::Other("Nothing to redo".to_string()))?;

        let undo_group_id = steps.first().map(|s| s.group_id);
        let mut delta_edits: Vec<TextDeltaEdit> = Vec::new();

        for step in &steps {
            let mut step_edits: Vec<TextDeltaEdit> = step
                .edits
                .iter()
                .map(|edit| TextDeltaEdit {
                    start: edit.start_before,
                    deleted_text: edit.deleted_text.clone(),
                    inserted_text: edit.inserted_text.clone(),
                })
                .collect();
            step_edits.sort_by_key(|e| std::cmp::Reverse(e.start));
            delta_edits.extend(step_edits);

            self.apply_redo_edits(&step.edits)?;
            self.restore_selection_set(step.after_selection.clone());
        }

        // Reapplied steps return to undo stack in the same order (oldest->newest).
        for step in steps {
            self.undo_redo.undo_stack.push(step);
        }

        self.last_text_delta = Some(TextDelta {
            before_char_count,
            after_char_count: self.editor.piece_table.char_count(),
            edits: delta_edits,
            undo_group_id: undo_group_id,
        });

        Ok(CommandResult::Success)
    }

    fn execute_insert_text_command(&mut self, text: String) -> Result<CommandResult, CommandError> {
        if text.is_empty() {
            return Ok(CommandResult::Success);
        }

        let before_char_count = self.editor.piece_table.char_count();
        let before_selection = self.snapshot_selection_set();

        // Build canonical selection set (primary + secondary), VSCode-like: edits are applied
        // "simultaneously" by computing ranges in the original document and mutating in
        // descending offset order.
        let mut selections: Vec<Selection> =
            Vec::with_capacity(1 + self.editor.secondary_selections.len());
        let primary_selection = self.editor.selection.clone().unwrap_or(Selection {
            start: self.editor.cursor_position,
            end: self.editor.cursor_position,
            direction: SelectionDirection::Forward,
        });
        selections.push(primary_selection);
        selections.extend(self.editor.secondary_selections.iter().cloned());

        let (selections, primary_index) = crate::selection_set::normalize_selections(selections, 0);

        let text_char_len = text.chars().count();

        struct Op {
            selection_index: usize,
            start_offset: usize,
            start_after: usize,
            delete_len: usize,
            deleted_text: String,
            insert_text: String,
            insert_char_len: usize,
        }

        let mut ops: Vec<Op> = Vec::with_capacity(selections.len());

        for (selection_index, selection) in selections.iter().enumerate() {
            let (range_start_pos, range_end_pos) = if selection.start <= selection.end {
                (selection.start, selection.end)
            } else {
                (selection.end, selection.start)
            };

            let (start_offset, start_pad) =
                self.position_to_char_offset_and_virtual_pad(range_start_pos);
            let end_offset = self.position_to_char_offset_clamped(range_end_pos);

            let delete_len = end_offset.saturating_sub(start_offset);
            let insert_char_len = start_pad + text_char_len;

            let deleted_text = if delete_len == 0 {
                String::new()
            } else {
                self.editor.piece_table.get_range(start_offset, delete_len)
            };

            let mut insert_text = String::with_capacity(text.len() + start_pad);
            for _ in 0..start_pad {
                insert_text.push(' ');
            }
            insert_text.push_str(&text);

            ops.push(Op {
                selection_index,
                start_offset,
                start_after: start_offset,
                delete_len,
                deleted_text,
                insert_text,
                insert_char_len,
            });
        }

        // Compute final caret offsets in the post-edit document (ascending order with delta),
        // while also recording each operation's start offset in the post-edit document.
        let mut asc_indices: Vec<usize> = (0..ops.len()).collect();
        asc_indices.sort_by_key(|&idx| ops[idx].start_offset);

        let mut caret_offsets: Vec<usize> = vec![0; ops.len()];
        let mut delta: i64 = 0;
        for &idx in &asc_indices {
            let op = &mut ops[idx];
            let effective_start = (op.start_offset as i64 + delta) as usize;
            op.start_after = effective_start;
            caret_offsets[op.selection_index] = effective_start + op.insert_char_len;
            delta += op.insert_char_len as i64 - op.delete_len as i64;
        }

        // Apply edits safely (descending offsets).
        let mut desc_indices = asc_indices;
        desc_indices.sort_by_key(|&idx| std::cmp::Reverse(ops[idx].start_offset));

        for &idx in &desc_indices {
            let op = &ops[idx];

            if op.delete_len > 0 {
                self.editor
                    .piece_table
                    .delete(op.start_offset, op.delete_len);
                self.editor
                    .interval_tree
                    .update_for_deletion(op.start_offset, op.start_offset + op.delete_len);
                for layer_tree in self.editor.style_layers.values_mut() {
                    layer_tree
                        .update_for_deletion(op.start_offset, op.start_offset + op.delete_len);
                }
            }

            if !op.insert_text.is_empty() {
                self.editor
                    .piece_table
                    .insert(op.start_offset, &op.insert_text);
                self.editor
                    .interval_tree
                    .update_for_insertion(op.start_offset, op.insert_char_len);
                for layer_tree in self.editor.style_layers.values_mut() {
                    layer_tree.update_for_insertion(op.start_offset, op.insert_char_len);
                }
            }
        }

        // Rebuild derived structures once.
        let updated_text = self.editor.piece_table.get_text();
        self.editor.line_index = LineIndex::from_text(&updated_text);
        self.rebuild_layout_engine_from_text(&updated_text);

        // Update selection state: collapse to carets after typing.
        let mut new_carets: Vec<Selection> = Vec::with_capacity(caret_offsets.len());
        for offset in &caret_offsets {
            let (line, column) = self.editor.line_index.char_offset_to_position(*offset);
            let pos = Position::new(line, column);
            new_carets.push(Selection {
                start: pos,
                end: pos,
                direction: SelectionDirection::Forward,
            });
        }

        let (new_carets, new_primary_index) =
            crate::selection_set::normalize_selections(new_carets, primary_index);
        let primary = new_carets
            .get(new_primary_index)
            .cloned()
            .ok_or_else(|| CommandError::Other("Invalid primary caret".to_string()))?;

        self.editor.cursor_position = primary.end;
        self.editor.selection = None;
        self.editor.secondary_selections = new_carets
            .into_iter()
            .enumerate()
            .filter_map(|(idx, sel)| {
                if idx == new_primary_index {
                    None
                } else {
                    Some(sel)
                }
            })
            .collect();

        let after_selection = self.snapshot_selection_set();

        let edits: Vec<TextEdit> = ops
            .into_iter()
            .map(|op| TextEdit {
                start_before: op.start_offset,
                start_after: op.start_after,
                deleted_text: op.deleted_text,
                inserted_text: op.insert_text,
            })
            .collect();

        let is_pure_insert = edits.iter().all(|e| e.deleted_text.is_empty());
        let coalescible_insert = is_pure_insert && !text.contains('\n');

        let mut delta_edits: Vec<TextDeltaEdit> = edits
            .iter()
            .map(|e| TextDeltaEdit {
                start: e.start_before,
                deleted_text: e.deleted_text.clone(),
                inserted_text: e.inserted_text.clone(),
            })
            .collect();
        delta_edits.sort_by_key(|e| std::cmp::Reverse(e.start));

        let step = UndoStep {
            group_id: 0,
            edits,
            before_selection,
            after_selection,
        };
        let group_id = self.undo_redo.push_step(step, coalescible_insert);

        self.last_text_delta = Some(TextDelta {
            before_char_count,
            after_char_count: self.editor.piece_table.char_count(),
            edits: delta_edits,
            undo_group_id: Some(group_id),
        });

        Ok(CommandResult::Success)
    }

    fn execute_insert_tab_command(&mut self) -> Result<CommandResult, CommandError> {
        let before_char_count = self.editor.piece_table.char_count();
        let before_selection = self.snapshot_selection_set();

        let mut selections: Vec<Selection> =
            Vec::with_capacity(1 + self.editor.secondary_selections.len());
        let primary_selection = self.editor.selection.clone().unwrap_or(Selection {
            start: self.editor.cursor_position,
            end: self.editor.cursor_position,
            direction: SelectionDirection::Forward,
        });
        selections.push(primary_selection);
        selections.extend(self.editor.secondary_selections.iter().cloned());

        let (selections, primary_index) = crate::selection_set::normalize_selections(selections, 0);

        let tab_width = self.editor.layout_engine.tab_width();

        struct Op {
            selection_index: usize,
            start_offset: usize,
            start_after: usize,
            delete_len: usize,
            deleted_text: String,
            insert_text: String,
            insert_char_len: usize,
        }

        let mut ops: Vec<Op> = Vec::with_capacity(selections.len());

        for (selection_index, selection) in selections.iter().enumerate() {
            let (range_start_pos, range_end_pos) = if selection.start <= selection.end {
                (selection.start, selection.end)
            } else {
                (selection.end, selection.start)
            };

            let (start_offset, start_pad) =
                self.position_to_char_offset_and_virtual_pad(range_start_pos);
            let end_offset = self.position_to_char_offset_clamped(range_end_pos);

            let delete_len = end_offset.saturating_sub(start_offset);

            let deleted_text = if delete_len == 0 {
                String::new()
            } else {
                self.editor.piece_table.get_range(start_offset, delete_len)
            };

            // Compute cell X within the logical line at the insertion position (including virtual pad).
            let line_text = self
                .editor
                .line_index
                .get_line_text(range_start_pos.line)
                .unwrap_or_default();
            let line_char_len = line_text.chars().count();
            let clamped_col = range_start_pos.column.min(line_char_len);
            let x_in_line =
                visual_x_for_column(&line_text, clamped_col, tab_width).saturating_add(start_pad);

            let mut insert_text = String::new();
            for _ in 0..start_pad {
                insert_text.push(' ');
            }

            match self.tab_key_behavior {
                TabKeyBehavior::Tab => {
                    insert_text.push('\t');
                    ops.push(Op {
                        selection_index,
                        start_offset,
                        start_after: start_offset,
                        delete_len,
                        deleted_text,
                        insert_text,
                        insert_char_len: start_pad + 1,
                    });
                }
                TabKeyBehavior::Spaces => {
                    let tab_width = tab_width.max(1);
                    let rem = x_in_line % tab_width;
                    let spaces = tab_width - rem;
                    for _ in 0..spaces {
                        insert_text.push(' ');
                    }

                    ops.push(Op {
                        selection_index,
                        start_offset,
                        start_after: start_offset,
                        delete_len,
                        deleted_text,
                        insert_text,
                        insert_char_len: start_pad + spaces,
                    });
                }
            }
        }

        // Compute final caret offsets in the post-edit document (ascending order with delta),
        // while also recording each operation's start offset in the post-edit document.
        let mut asc_indices: Vec<usize> = (0..ops.len()).collect();
        asc_indices.sort_by_key(|&idx| ops[idx].start_offset);

        let mut caret_offsets: Vec<usize> = vec![0; ops.len()];
        let mut delta: i64 = 0;
        for &idx in &asc_indices {
            let op = &mut ops[idx];
            let effective_start = (op.start_offset as i64 + delta) as usize;
            op.start_after = effective_start;
            caret_offsets[op.selection_index] = effective_start + op.insert_char_len;
            delta += op.insert_char_len as i64 - op.delete_len as i64;
        }

        // Apply edits safely (descending offsets).
        let mut desc_indices = asc_indices;
        desc_indices.sort_by_key(|&idx| std::cmp::Reverse(ops[idx].start_offset));

        for &idx in &desc_indices {
            let op = &ops[idx];

            if op.delete_len > 0 {
                self.editor
                    .piece_table
                    .delete(op.start_offset, op.delete_len);
                self.editor
                    .interval_tree
                    .update_for_deletion(op.start_offset, op.start_offset + op.delete_len);
                for layer_tree in self.editor.style_layers.values_mut() {
                    layer_tree
                        .update_for_deletion(op.start_offset, op.start_offset + op.delete_len);
                }
            }

            if !op.insert_text.is_empty() {
                self.editor
                    .piece_table
                    .insert(op.start_offset, &op.insert_text);
                self.editor
                    .interval_tree
                    .update_for_insertion(op.start_offset, op.insert_char_len);
                for layer_tree in self.editor.style_layers.values_mut() {
                    layer_tree.update_for_insertion(op.start_offset, op.insert_char_len);
                }
            }
        }

        // Rebuild derived structures once.
        let updated_text = self.editor.piece_table.get_text();
        self.editor.line_index = LineIndex::from_text(&updated_text);
        self.rebuild_layout_engine_from_text(&updated_text);

        // Update selection state: collapse to carets after insertion.
        let mut new_carets: Vec<Selection> = Vec::with_capacity(caret_offsets.len());
        for offset in &caret_offsets {
            let (line, column) = self.editor.line_index.char_offset_to_position(*offset);
            let pos = Position::new(line, column);
            new_carets.push(Selection {
                start: pos,
                end: pos,
                direction: SelectionDirection::Forward,
            });
        }

        let (new_carets, new_primary_index) =
            crate::selection_set::normalize_selections(new_carets, primary_index);
        let primary = new_carets
            .get(new_primary_index)
            .cloned()
            .ok_or_else(|| CommandError::Other("Invalid primary caret".to_string()))?;

        self.editor.cursor_position = primary.end;
        self.editor.selection = None;
        self.editor.secondary_selections = new_carets
            .into_iter()
            .enumerate()
            .filter_map(|(idx, sel)| {
                if idx == new_primary_index {
                    None
                } else {
                    Some(sel)
                }
            })
            .collect();

        let after_selection = self.snapshot_selection_set();

        let edits: Vec<TextEdit> = ops
            .into_iter()
            .map(|op| TextEdit {
                start_before: op.start_offset,
                start_after: op.start_after,
                deleted_text: op.deleted_text,
                inserted_text: op.insert_text,
            })
            .collect();

        let is_pure_insert = edits.iter().all(|e| e.deleted_text.is_empty());
        let coalescible_insert = is_pure_insert;

        let mut delta_edits: Vec<TextDeltaEdit> = edits
            .iter()
            .map(|e| TextDeltaEdit {
                start: e.start_before,
                deleted_text: e.deleted_text.clone(),
                inserted_text: e.inserted_text.clone(),
            })
            .collect();
        delta_edits.sort_by_key(|e| std::cmp::Reverse(e.start));

        let step = UndoStep {
            group_id: 0,
            edits,
            before_selection,
            after_selection,
        };
        let group_id = self.undo_redo.push_step(step, coalescible_insert);

        self.last_text_delta = Some(TextDelta {
            before_char_count,
            after_char_count: self.editor.piece_table.char_count(),
            edits: delta_edits,
            undo_group_id: Some(group_id),
        });

        Ok(CommandResult::Success)
    }

    fn execute_insert_command(
        &mut self,
        offset: usize,
        text: String,
    ) -> Result<CommandResult, CommandError> {
        if text.is_empty() {
            return Err(CommandError::EmptyText);
        }

        let max_offset = self.editor.piece_table.char_count();
        if offset > max_offset {
            return Err(CommandError::InvalidOffset(offset));
        }

        let before_char_count = self.editor.piece_table.char_count();
        let before_selection = self.snapshot_selection_set();

        let affected_line = self.editor.line_index.char_offset_to_position(offset).0;
        let inserts_newline = text.contains('\n');

        // Execute insertion
        self.editor.piece_table.insert(offset, &text);

        // Update line index
        let updated_text = self.editor.piece_table.get_text();
        self.editor.line_index = LineIndex::from_text(&updated_text);

        // Update layout engine (soft wrappingneeds to stay consistent with text)
        if inserts_newline {
            self.rebuild_layout_engine_from_text(&updated_text);
        } else {
            let line_text = self
                .editor
                .line_index
                .get_line_text(affected_line)
                .unwrap_or_default();
            self.editor
                .layout_engine
                .update_line(affected_line, &line_text);
        }

        let inserted_len = text.chars().count();

        // Update interval tree offsets
        self.editor
            .interval_tree
            .update_for_insertion(offset, inserted_len);
        for layer_tree in self.editor.style_layers.values_mut() {
            layer_tree.update_for_insertion(offset, inserted_len);
        }

        // Ensure cursor/selection still within valid range
        self.normalize_cursor_and_selection();

        let after_selection = self.snapshot_selection_set();

        let step = UndoStep {
            group_id: 0,
            edits: vec![TextEdit {
                start_before: offset,
                start_after: offset,
                deleted_text: String::new(),
                inserted_text: text.clone(),
            }],
            before_selection,
            after_selection,
        };

        let coalescible_insert = !text.contains('\n');
        let group_id = self.undo_redo.push_step(step, coalescible_insert);

        self.last_text_delta = Some(TextDelta {
            before_char_count,
            after_char_count: self.editor.piece_table.char_count(),
            edits: vec![TextDeltaEdit {
                start: offset,
                deleted_text: String::new(),
                inserted_text: text,
            }],
            undo_group_id: Some(group_id),
        });

        Ok(CommandResult::Success)
    }

    fn execute_delete_command(
        &mut self,
        start: usize,
        length: usize,
    ) -> Result<CommandResult, CommandError> {
        if length == 0 {
            return Ok(CommandResult::Success);
        }

        let before_char_count = self.editor.piece_table.char_count();
        let max_offset = self.editor.piece_table.char_count();
        if start > max_offset {
            return Err(CommandError::InvalidOffset(start));
        }
        if start + length > max_offset {
            return Err(CommandError::InvalidRange {
                start,
                end: start + length,
            });
        }

        let before_selection = self.snapshot_selection_set();

        let deleted_text = self.editor.piece_table.get_range(start, length);
        let delta_deleted_text = deleted_text.clone();
        let deletes_newline = deleted_text.contains('\n');
        let affected_line = self.editor.line_index.char_offset_to_position(start).0;

        // Execute deletion
        self.editor.piece_table.delete(start, length);

        // Update line index
        let updated_text = self.editor.piece_table.get_text();
        self.editor.line_index = LineIndex::from_text(&updated_text);

        // Update layout engine (soft wrappingneeds to stay consistent with text)
        if deletes_newline {
            self.rebuild_layout_engine_from_text(&updated_text);
        } else {
            let line_text = self
                .editor
                .line_index
                .get_line_text(affected_line)
                .unwrap_or_default();
            self.editor
                .layout_engine
                .update_line(affected_line, &line_text);
        }

        // Update interval tree offsets
        self.editor
            .interval_tree
            .update_for_deletion(start, start + length);
        for layer_tree in self.editor.style_layers.values_mut() {
            layer_tree.update_for_deletion(start, start + length);
        }

        // Ensure cursor/selection still within valid range
        self.normalize_cursor_and_selection();

        let after_selection = self.snapshot_selection_set();

        let step = UndoStep {
            group_id: 0,
            edits: vec![TextEdit {
                start_before: start,
                start_after: start,
                deleted_text,
                inserted_text: String::new(),
            }],
            before_selection,
            after_selection,
        };
        let group_id = self.undo_redo.push_step(step, false);

        self.last_text_delta = Some(TextDelta {
            before_char_count,
            after_char_count: self.editor.piece_table.char_count(),
            edits: vec![TextDeltaEdit {
                start,
                deleted_text: delta_deleted_text,
                inserted_text: String::new(),
            }],
            undo_group_id: Some(group_id),
        });

        Ok(CommandResult::Success)
    }

    fn execute_replace_command(
        &mut self,
        start: usize,
        length: usize,
        text: String,
    ) -> Result<CommandResult, CommandError> {
        let before_char_count = self.editor.piece_table.char_count();
        let max_offset = self.editor.piece_table.char_count();
        if start > max_offset {
            return Err(CommandError::InvalidOffset(start));
        }
        if start + length > max_offset {
            return Err(CommandError::InvalidRange {
                start,
                end: start + length,
            });
        }

        if length == 0 && text.is_empty() {
            return Ok(CommandResult::Success);
        }

        let before_selection = self.snapshot_selection_set();

        let deleted_text = if length == 0 {
            String::new()
        } else {
            self.editor.piece_table.get_range(start, length)
        };
        let delta_deleted_text = deleted_text.clone();
        let delta_inserted_text = text.clone();

        let affected_line = self.editor.line_index.char_offset_to_position(start).0;
        let replace_affects_layout = deleted_text.contains('\n') || text.contains('\n');

        // Apply as a single operation (delete then insert at the same offset).
        if length > 0 {
            self.editor.piece_table.delete(start, length);
            self.editor
                .interval_tree
                .update_for_deletion(start, start + length);
            for layer_tree in self.editor.style_layers.values_mut() {
                layer_tree.update_for_deletion(start, start + length);
            }
        }

        let inserted_len = text.chars().count();
        if inserted_len > 0 {
            self.editor.piece_table.insert(start, &text);
            self.editor
                .interval_tree
                .update_for_insertion(start, inserted_len);
            for layer_tree in self.editor.style_layers.values_mut() {
                layer_tree.update_for_insertion(start, inserted_len);
            }
        }

        // Rebuild derived structures.
        let updated_text = self.editor.piece_table.get_text();
        self.editor.line_index = LineIndex::from_text(&updated_text);

        if replace_affects_layout {
            self.rebuild_layout_engine_from_text(&updated_text);
        } else {
            let line_text = self
                .editor
                .line_index
                .get_line_text(affected_line)
                .unwrap_or_default();
            self.editor
                .layout_engine
                .update_line(affected_line, &line_text);
        }

        // Ensure cursor/selection still valid.
        self.normalize_cursor_and_selection();

        let after_selection = self.snapshot_selection_set();

        let step = UndoStep {
            group_id: 0,
            edits: vec![TextEdit {
                start_before: start,
                start_after: start,
                deleted_text,
                inserted_text: text,
            }],
            before_selection,
            after_selection,
        };
        let group_id = self.undo_redo.push_step(step, false);

        self.last_text_delta = Some(TextDelta {
            before_char_count,
            after_char_count: self.editor.piece_table.char_count(),
            edits: vec![TextDeltaEdit {
                start,
                deleted_text: delta_deleted_text,
                inserted_text: delta_inserted_text,
            }],
            undo_group_id: Some(group_id),
        });

        Ok(CommandResult::Success)
    }

    fn cursor_char_offset(&self) -> usize {
        self.position_to_char_offset_clamped(self.editor.cursor_position)
    }

    fn primary_selection_char_range(&self) -> Option<SearchMatch> {
        let selection = self.editor.selection.as_ref()?;
        let (min_pos, max_pos) = crate::selection_set::selection_min_max(selection);
        let start = self.position_to_char_offset_clamped(min_pos);
        let end = self.position_to_char_offset_clamped(max_pos);
        if start == end {
            None
        } else {
            Some(SearchMatch { start, end })
        }
    }

    fn set_primary_selection_by_char_range(&mut self, range: SearchMatch) {
        let (start_line, start_col) = self.editor.line_index.char_offset_to_position(range.start);
        let (end_line, end_col) = self.editor.line_index.char_offset_to_position(range.end);

        self.editor.cursor_position = Position::new(end_line, end_col);
        self.editor.secondary_selections.clear();

        if range.start == range.end {
            self.editor.selection = None;
        } else {
            self.editor.selection = Some(Selection {
                start: Position::new(start_line, start_col),
                end: Position::new(end_line, end_col),
                direction: SelectionDirection::Forward,
            });
        }
    }

    fn execute_find_command(
        &mut self,
        query: String,
        options: SearchOptions,
        forward: bool,
    ) -> Result<CommandResult, CommandError> {
        if query.is_empty() {
            return Ok(CommandResult::SearchNotFound);
        }

        let text = self.editor.piece_table.get_text();
        let from = if let Some(selection) = self.primary_selection_char_range() {
            if forward {
                selection.end
            } else {
                selection.start
            }
        } else {
            self.cursor_char_offset()
        };

        let found = if forward {
            find_next(&text, &query, options, from)
        } else {
            find_prev(&text, &query, options, from)
        }
        .map_err(|err| CommandError::Other(err.to_string()))?;

        let Some(m) = found else {
            return Ok(CommandResult::SearchNotFound);
        };

        self.set_primary_selection_by_char_range(m);

        Ok(CommandResult::SearchMatch {
            start: m.start,
            end: m.end,
        })
    }

    fn compile_user_regex(
        query: &str,
        options: SearchOptions,
    ) -> Result<regex::Regex, CommandError> {
        RegexBuilder::new(query)
            .case_insensitive(!options.case_sensitive)
            .multi_line(true)
            .build()
            .map_err(|err| CommandError::Other(format!("Invalid regex: {}", err)))
    }

    fn regex_expand_replacement(
        re: &regex::Regex,
        text: &str,
        index: &CharIndex,
        range: SearchMatch,
        replacement: &str,
    ) -> Result<String, CommandError> {
        let start_byte = index.char_to_byte(range.start);
        let end_byte = index.char_to_byte(range.end);

        let caps = re
            .captures_at(text, start_byte)
            .ok_or_else(|| CommandError::Other("Regex match not found".to_string()))?;
        let whole = caps
            .get(0)
            .ok_or_else(|| CommandError::Other("Regex match missing capture 0".to_string()))?;
        if whole.start() != start_byte || whole.end() != end_byte {
            return Err(CommandError::Other(
                "Regex match did not align with the selected range".to_string(),
            ));
        }

        let mut expanded = String::new();
        caps.expand(replacement, &mut expanded);
        Ok(expanded)
    }

    fn execute_replace_current_command(
        &mut self,
        query: String,
        replacement: String,
        options: SearchOptions,
    ) -> Result<CommandResult, CommandError> {
        if query.is_empty() {
            return Err(CommandError::Other("Search query is empty".to_string()));
        }

        let text = self.editor.piece_table.get_text();
        let selection_range = self.primary_selection_char_range();

        let mut target = None::<SearchMatch>;
        if let Some(range) = selection_range {
            let is_match = crate::search::is_match_exact(&text, &query, options, range)
                .map_err(|err| CommandError::Other(err.to_string()))?;
            if is_match {
                target = Some(range);
            }
        }

        if target.is_none() {
            let from = self.cursor_char_offset();
            target = find_next(&text, &query, options, from)
                .map_err(|err| CommandError::Other(err.to_string()))?;
        }

        let Some(target) = target else {
            return Err(CommandError::Other("No match found".to_string()));
        };

        let index = CharIndex::new(&text);
        let inserted_text = if options.regex {
            let re = Self::compile_user_regex(&query, options)?;
            Self::regex_expand_replacement(&re, &text, &index, target, &replacement)?
        } else {
            replacement
        };

        let deleted_text = self
            .editor
            .piece_table
            .get_range(target.start, target.len());
        let before_char_count = self.editor.piece_table.char_count();
        let delta_deleted_text = deleted_text.clone();

        let before_selection = self.snapshot_selection_set();
        self.apply_text_ops(vec![(target.start, target.len(), inserted_text.as_str())])?;

        let inserted_len = inserted_text.chars().count();
        let new_range = SearchMatch {
            start: target.start,
            end: target.start + inserted_len,
        };
        self.set_primary_selection_by_char_range(new_range);
        let after_selection = self.snapshot_selection_set();

        let step = UndoStep {
            group_id: 0,
            edits: vec![TextEdit {
                start_before: target.start,
                start_after: target.start,
                deleted_text,
                inserted_text: inserted_text.clone(),
            }],
            before_selection,
            after_selection,
        };
        let group_id = self.undo_redo.push_step(step, false);

        self.last_text_delta = Some(TextDelta {
            before_char_count,
            after_char_count: self.editor.piece_table.char_count(),
            edits: vec![TextDeltaEdit {
                start: target.start,
                deleted_text: delta_deleted_text,
                inserted_text,
            }],
            undo_group_id: Some(group_id),
        });

        Ok(CommandResult::ReplaceResult { replaced: 1 })
    }

    fn execute_replace_all_command(
        &mut self,
        query: String,
        replacement: String,
        options: SearchOptions,
    ) -> Result<CommandResult, CommandError> {
        if query.is_empty() {
            return Err(CommandError::Other("Search query is empty".to_string()));
        }

        let text = self.editor.piece_table.get_text();
        let matches =
            find_all(&text, &query, options).map_err(|err| CommandError::Other(err.to_string()))?;
        if matches.is_empty() {
            return Err(CommandError::Other("No match found".to_string()));
        }
        let match_count = matches.len();

        let index = CharIndex::new(&text);

        struct Op {
            start_before: usize,
            start_after: usize,
            delete_len: usize,
            deleted_text: String,
            inserted_text: String,
            inserted_len: usize,
        }

        let mut ops: Vec<Op> = Vec::with_capacity(match_count);
        if options.regex {
            let re = Self::compile_user_regex(&query, options)?;
            for m in matches {
                let deleted_text = {
                    let start_byte = index.char_to_byte(m.start);
                    let end_byte = index.char_to_byte(m.end);
                    text.get(start_byte..end_byte)
                        .unwrap_or_default()
                        .to_string()
                };
                let inserted_text =
                    Self::regex_expand_replacement(&re, &text, &index, m, &replacement)?;
                let inserted_len = inserted_text.chars().count();
                ops.push(Op {
                    start_before: m.start,
                    start_after: m.start,
                    delete_len: m.len(),
                    deleted_text,
                    inserted_text,
                    inserted_len,
                });
            }
        } else {
            let inserted_len = replacement.chars().count();
            for m in matches {
                let deleted_text = {
                    let start_byte = index.char_to_byte(m.start);
                    let end_byte = index.char_to_byte(m.end);
                    text.get(start_byte..end_byte)
                        .unwrap_or_default()
                        .to_string()
                };
                ops.push(Op {
                    start_before: m.start,
                    start_after: m.start,
                    delete_len: m.len(),
                    deleted_text,
                    inserted_text: replacement.clone(),
                    inserted_len,
                });
            }
        }

        ops.sort_by_key(|op| op.start_before);

        let mut delta: i64 = 0;
        for op in &mut ops {
            let effective_start = op.start_before as i64 + delta;
            if effective_start < 0 {
                return Err(CommandError::Other(
                    "ReplaceAll produced an invalid intermediate offset".to_string(),
                ));
            }
            op.start_after = effective_start as usize;
            delta += op.inserted_len as i64 - op.delete_len as i64;
        }

        let before_char_count = self.editor.piece_table.char_count();
        let before_selection = self.snapshot_selection_set();
        let apply_ops: Vec<(usize, usize, &str)> = ops
            .iter()
            .map(|op| (op.start_before, op.delete_len, op.inserted_text.as_str()))
            .collect();
        self.apply_text_ops(apply_ops)?;

        if let Some(first) = ops.first() {
            let caret_end = first.start_after + first.inserted_len;
            let select_end = if first.inserted_len == 0 {
                first.start_after
            } else {
                caret_end
            };
            self.set_primary_selection_by_char_range(SearchMatch {
                start: first.start_after,
                end: select_end,
            });
        } else {
            self.editor.selection = None;
            self.editor.secondary_selections.clear();
        }

        let after_selection = self.snapshot_selection_set();

        let edits: Vec<TextEdit> = ops
            .into_iter()
            .map(|op| TextEdit {
                start_before: op.start_before,
                start_after: op.start_after,
                deleted_text: op.deleted_text,
                inserted_text: op.inserted_text,
            })
            .collect();

        let mut delta_edits: Vec<TextDeltaEdit> = edits
            .iter()
            .map(|e| TextDeltaEdit {
                start: e.start_before,
                deleted_text: e.deleted_text.clone(),
                inserted_text: e.inserted_text.clone(),
            })
            .collect();
        delta_edits.sort_by_key(|e| std::cmp::Reverse(e.start));

        let step = UndoStep {
            group_id: 0,
            edits,
            before_selection,
            after_selection,
        };
        let group_id = self.undo_redo.push_step(step, false);

        self.last_text_delta = Some(TextDelta {
            before_char_count,
            after_char_count: self.editor.piece_table.char_count(),
            edits: delta_edits,
            undo_group_id: Some(group_id),
        });

        Ok(CommandResult::ReplaceResult {
            replaced: match_count,
        })
    }

    fn execute_backspace_command(&mut self) -> Result<CommandResult, CommandError> {
        self.execute_delete_like_command(false)
    }

    fn execute_delete_forward_command(&mut self) -> Result<CommandResult, CommandError> {
        self.execute_delete_like_command(true)
    }

    fn execute_delete_like_command(
        &mut self,
        forward: bool,
    ) -> Result<CommandResult, CommandError> {
        // Any delete-like action should end an open insert coalescing group, even if it turns out
        // to be a no-op (e.g. backspace at the beginning of the document).
        self.undo_redo.end_group();

        let before_selection = self.snapshot_selection_set();
        let selections = before_selection.selections.clone();
        let primary_index = before_selection.primary_index;

        let doc_char_count = self.editor.piece_table.char_count();

        #[derive(Debug)]
        struct Op {
            selection_index: usize,
            start_offset: usize,
            delete_len: usize,
            deleted_text: String,
            start_after: usize,
        }

        let mut ops: Vec<Op> = Vec::with_capacity(selections.len());

        for (selection_index, selection) in selections.iter().enumerate() {
            let (range_start_pos, range_end_pos) = if selection.start <= selection.end {
                (selection.start, selection.end)
            } else {
                (selection.end, selection.start)
            };

            let (start_offset, end_offset) = if range_start_pos != range_end_pos {
                let start_offset = self.position_to_char_offset_clamped(range_start_pos);
                let end_offset = self.position_to_char_offset_clamped(range_end_pos);
                if start_offset <= end_offset {
                    (start_offset, end_offset)
                } else {
                    (end_offset, start_offset)
                }
            } else {
                let caret_offset = self.position_to_char_offset_clamped(selection.end);
                if forward {
                    if caret_offset >= doc_char_count {
                        (caret_offset, caret_offset)
                    } else {
                        (caret_offset, (caret_offset + 1).min(doc_char_count))
                    }
                } else if caret_offset == 0 {
                    (0, 0)
                } else {
                    (caret_offset - 1, caret_offset)
                }
            };

            let delete_len = end_offset.saturating_sub(start_offset);
            let deleted_text = if delete_len == 0 {
                String::new()
            } else {
                self.editor.piece_table.get_range(start_offset, delete_len)
            };

            ops.push(Op {
                selection_index,
                start_offset,
                delete_len,
                deleted_text,
                start_after: start_offset,
            });
        }

        if !ops.iter().any(|op| op.delete_len > 0) {
            return Ok(CommandResult::Success);
        }

        let before_char_count = self.editor.piece_table.char_count();

        // Compute caret offsets in the post-delete document (ascending order with delta).
        let mut asc_indices: Vec<usize> = (0..ops.len()).collect();
        asc_indices.sort_by_key(|&idx| ops[idx].start_offset);

        let mut caret_offsets: Vec<usize> = vec![0; ops.len()];
        let mut delta: i64 = 0;
        for &idx in &asc_indices {
            let op = &mut ops[idx];
            let effective_start = (op.start_offset as i64 + delta) as usize;
            op.start_after = effective_start;
            caret_offsets[op.selection_index] = effective_start;
            delta -= op.delete_len as i64;
        }

        // Apply deletes descending to keep offsets valid.
        let mut desc_indices = asc_indices;
        desc_indices.sort_by_key(|&idx| std::cmp::Reverse(ops[idx].start_offset));

        for &idx in &desc_indices {
            let op = &ops[idx];
            if op.delete_len == 0 {
                continue;
            }

            self.editor
                .piece_table
                .delete(op.start_offset, op.delete_len);
            self.editor
                .interval_tree
                .update_for_deletion(op.start_offset, op.start_offset + op.delete_len);
            for layer_tree in self.editor.style_layers.values_mut() {
                layer_tree.update_for_deletion(op.start_offset, op.start_offset + op.delete_len);
            }
        }

        // Rebuild derived structures once.
        let updated_text = self.editor.piece_table.get_text();
        self.editor.line_index = LineIndex::from_text(&updated_text);
        self.rebuild_layout_engine_from_text(&updated_text);

        // Collapse selection state to carets at the start of deleted ranges.
        let mut new_carets: Vec<Selection> = Vec::with_capacity(caret_offsets.len());
        for offset in &caret_offsets {
            let (line, column) = self.editor.line_index.char_offset_to_position(*offset);
            let pos = Position::new(line, column);
            new_carets.push(Selection {
                start: pos,
                end: pos,
                direction: SelectionDirection::Forward,
            });
        }

        let (new_carets, new_primary_index) =
            crate::selection_set::normalize_selections(new_carets, primary_index);
        let primary = new_carets
            .get(new_primary_index)
            .cloned()
            .ok_or_else(|| CommandError::Other("Invalid primary caret".to_string()))?;

        self.editor.cursor_position = primary.end;
        self.editor.selection = None;
        self.editor.secondary_selections = new_carets
            .into_iter()
            .enumerate()
            .filter_map(|(idx, sel)| {
                if idx == new_primary_index {
                    None
                } else {
                    Some(sel)
                }
            })
            .collect();

        let after_selection = self.snapshot_selection_set();

        let edits: Vec<TextEdit> = ops
            .into_iter()
            .map(|op| TextEdit {
                start_before: op.start_offset,
                start_after: op.start_after,
                deleted_text: op.deleted_text,
                inserted_text: String::new(),
            })
            .collect();

        let mut delta_edits: Vec<TextDeltaEdit> = edits
            .iter()
            .map(|e| TextDeltaEdit {
                start: e.start_before,
                deleted_text: e.deleted_text.clone(),
                inserted_text: String::new(),
            })
            .collect();
        delta_edits.sort_by_key(|e| std::cmp::Reverse(e.start));

        let step = UndoStep {
            group_id: 0,
            edits,
            before_selection,
            after_selection,
        };
        let group_id = self.undo_redo.push_step(step, false);

        self.last_text_delta = Some(TextDelta {
            before_char_count,
            after_char_count: self.editor.piece_table.char_count(),
            edits: delta_edits,
            undo_group_id: Some(group_id),
        });

        Ok(CommandResult::Success)
    }

    fn snapshot_selection_set(&self) -> SelectionSetSnapshot {
        let mut selections: Vec<Selection> =
            Vec::with_capacity(1 + self.editor.secondary_selections.len());

        let primary = self.editor.selection.clone().unwrap_or(Selection {
            start: self.editor.cursor_position,
            end: self.editor.cursor_position,
            direction: SelectionDirection::Forward,
        });
        selections.push(primary);
        selections.extend(self.editor.secondary_selections.iter().cloned());

        let (selections, primary_index) = crate::selection_set::normalize_selections(selections, 0);
        SelectionSetSnapshot {
            selections,
            primary_index,
        }
    }

    fn restore_selection_set(&mut self, snapshot: SelectionSetSnapshot) {
        if snapshot.selections.is_empty() {
            self.editor.cursor_position = Position::new(0, 0);
            self.editor.selection = None;
            self.editor.secondary_selections.clear();
            return;
        }

        let primary = snapshot
            .selections
            .get(snapshot.primary_index)
            .cloned()
            .unwrap_or_else(|| snapshot.selections[0].clone());

        self.editor.cursor_position = primary.end;
        self.editor.selection = if primary.start == primary.end {
            None
        } else {
            Some(primary.clone())
        };

        self.editor.secondary_selections = snapshot
            .selections
            .into_iter()
            .enumerate()
            .filter_map(|(idx, sel)| {
                if idx == snapshot.primary_index {
                    None
                } else {
                    Some(sel)
                }
            })
            .collect();

        self.normalize_cursor_and_selection();
    }

    fn apply_undo_edits(&mut self, edits: &[TextEdit]) -> Result<(), CommandError> {
        // Apply inverse: delete inserted text, then reinsert deleted text.
        let mut ops: Vec<(usize, usize, &str)> = Vec::with_capacity(edits.len());
        for edit in edits {
            let start = edit.start_after;
            let delete_len = edit.inserted_len();
            let insert_text = edit.deleted_text.as_str();
            ops.push((start, delete_len, insert_text));
        }
        self.apply_text_ops(ops)
    }

    fn apply_redo_edits(&mut self, edits: &[TextEdit]) -> Result<(), CommandError> {
        let mut ops: Vec<(usize, usize, &str)> = Vec::with_capacity(edits.len());
        for edit in edits {
            let start = edit.start_before;
            let delete_len = edit.deleted_len();
            let insert_text = edit.inserted_text.as_str();
            ops.push((start, delete_len, insert_text));
        }
        self.apply_text_ops(ops)
    }

    fn apply_text_ops(&mut self, mut ops: Vec<(usize, usize, &str)>) -> Result<(), CommandError> {
        // Sort descending by start offset to make offsets stable while mutating.
        ops.sort_by_key(|(start, _, _)| std::cmp::Reverse(*start));

        for (start, delete_len, insert_text) in ops {
            let max_offset = self.editor.piece_table.char_count();
            if start > max_offset {
                return Err(CommandError::InvalidOffset(start));
            }
            if start + delete_len > max_offset {
                return Err(CommandError::InvalidRange {
                    start,
                    end: start + delete_len,
                });
            }

            if delete_len > 0 {
                self.editor.piece_table.delete(start, delete_len);
                self.editor
                    .interval_tree
                    .update_for_deletion(start, start + delete_len);
                for layer_tree in self.editor.style_layers.values_mut() {
                    layer_tree.update_for_deletion(start, start + delete_len);
                }
            }

            let insert_len = insert_text.chars().count();
            if insert_len > 0 {
                self.editor.piece_table.insert(start, insert_text);
                self.editor
                    .interval_tree
                    .update_for_insertion(start, insert_len);
                for layer_tree in self.editor.style_layers.values_mut() {
                    layer_tree.update_for_insertion(start, insert_len);
                }
            }
        }

        // Rebuild derived structures.
        let updated_text = self.editor.piece_table.get_text();
        self.editor.line_index = LineIndex::from_text(&updated_text);
        self.rebuild_layout_engine_from_text(&updated_text);
        self.normalize_cursor_and_selection();

        Ok(())
    }

    // Private method: execute cursor command
    fn execute_cursor(&mut self, command: CursorCommand) -> Result<CommandResult, CommandError> {
        match command {
            CursorCommand::MoveTo { line, column } => {
                if line >= self.editor.line_index.line_count() {
                    return Err(CommandError::InvalidPosition { line, column });
                }

                let clamped_column = self.clamp_column_for_line(line, column);
                self.editor.cursor_position = Position::new(line, clamped_column);
                // VSCode-like: moving the primary caret to an absolute position collapses multi-cursor.
                self.editor.secondary_selections.clear();
                Ok(CommandResult::Success)
            }
            CursorCommand::MoveBy {
                delta_line,
                delta_column,
            } => {
                let new_line = if delta_line >= 0 {
                    self.editor.cursor_position.line + delta_line as usize
                } else {
                    self.editor
                        .cursor_position
                        .line
                        .saturating_sub((-delta_line) as usize)
                };

                let new_column = if delta_column >= 0 {
                    self.editor.cursor_position.column + delta_column as usize
                } else {
                    self.editor
                        .cursor_position
                        .column
                        .saturating_sub((-delta_column) as usize)
                };

                if new_line >= self.editor.line_index.line_count() {
                    return Err(CommandError::InvalidPosition {
                        line: new_line,
                        column: new_column,
                    });
                }

                let clamped_column = self.clamp_column_for_line(new_line, new_column);
                self.editor.cursor_position = Position::new(new_line, clamped_column);
                Ok(CommandResult::Success)
            }
            CursorCommand::SetSelection { start, end } => {
                if start.line >= self.editor.line_index.line_count()
                    || end.line >= self.editor.line_index.line_count()
                {
                    return Err(CommandError::InvalidPosition {
                        line: start.line.max(end.line),
                        column: start.column.max(end.column),
                    });
                }

                let start = Position::new(
                    start.line,
                    self.clamp_column_for_line(start.line, start.column),
                );
                let end = Position::new(end.line, self.clamp_column_for_line(end.line, end.column));

                let direction = if start.line < end.line
                    || (start.line == end.line && start.column <= end.column)
                {
                    SelectionDirection::Forward
                } else {
                    SelectionDirection::Backward
                };

                self.editor.selection = Some(Selection {
                    start,
                    end,
                    direction,
                });
                Ok(CommandResult::Success)
            }
            CursorCommand::ExtendSelection { to } => {
                if to.line >= self.editor.line_index.line_count() {
                    return Err(CommandError::InvalidPosition {
                        line: to.line,
                        column: to.column,
                    });
                }

                let to = Position::new(to.line, self.clamp_column_for_line(to.line, to.column));

                if let Some(ref mut selection) = self.editor.selection {
                    selection.end = to;
                    selection.direction = if selection.start.line < to.line
                        || (selection.start.line == to.line && selection.start.column <= to.column)
                    {
                        SelectionDirection::Forward
                    } else {
                        SelectionDirection::Backward
                    };
                } else {
                    // If no selection, create selection from current cursor
                    self.editor.selection = Some(Selection {
                        start: self.editor.cursor_position,
                        end: to,
                        direction: if self.editor.cursor_position.line < to.line
                            || (self.editor.cursor_position.line == to.line
                                && self.editor.cursor_position.column <= to.column)
                        {
                            SelectionDirection::Forward
                        } else {
                            SelectionDirection::Backward
                        },
                    });
                }
                Ok(CommandResult::Success)
            }
            CursorCommand::ClearSelection => {
                self.editor.selection = None;
                Ok(CommandResult::Success)
            }
            CursorCommand::SetSelections {
                selections,
                primary_index,
            } => {
                let line_count = self.editor.line_index.line_count();
                if selections.is_empty() {
                    return Err(CommandError::Other(
                        "SetSelections requires a non-empty selection list".to_string(),
                    ));
                }
                if primary_index >= selections.len() {
                    return Err(CommandError::Other(format!(
                        "Invalid primary_index {} for {} selections",
                        primary_index,
                        selections.len()
                    )));
                }

                for sel in &selections {
                    if sel.start.line >= line_count || sel.end.line >= line_count {
                        return Err(CommandError::InvalidPosition {
                            line: sel.start.line.max(sel.end.line),
                            column: sel.start.column.max(sel.end.column),
                        });
                    }
                }

                let (selections, primary_index) =
                    crate::selection_set::normalize_selections(selections, primary_index);

                let primary = selections
                    .get(primary_index)
                    .cloned()
                    .ok_or_else(|| CommandError::Other("Invalid primary selection".to_string()))?;

                self.editor.cursor_position = primary.end;
                self.editor.selection = if primary.start == primary.end {
                    None
                } else {
                    Some(primary.clone())
                };

                self.editor.secondary_selections = selections
                    .into_iter()
                    .enumerate()
                    .filter_map(|(idx, sel)| {
                        if idx == primary_index {
                            None
                        } else {
                            Some(sel)
                        }
                    })
                    .collect();

                Ok(CommandResult::Success)
            }
            CursorCommand::ClearSecondarySelections => {
                self.editor.secondary_selections.clear();
                Ok(CommandResult::Success)
            }
            CursorCommand::SetRectSelection { anchor, active } => {
                let line_count = self.editor.line_index.line_count();
                if anchor.line >= line_count || active.line >= line_count {
                    return Err(CommandError::InvalidPosition {
                        line: anchor.line.max(active.line),
                        column: anchor.column.max(active.column),
                    });
                }

                let (selections, primary_index) =
                    crate::selection_set::rect_selections(anchor, active);

                // Delegate to SetSelections so normalization rules are shared.
                self.execute_cursor(CursorCommand::SetSelections {
                    selections,
                    primary_index,
                })?;
                Ok(CommandResult::Success)
            }
            CursorCommand::FindNext { query, options } => {
                self.execute_find_command(query, options, true)
            }
            CursorCommand::FindPrev { query, options } => {
                self.execute_find_command(query, options, false)
            }
        }
    }

    // Private method: execute view command
    fn execute_view(&mut self, command: ViewCommand) -> Result<CommandResult, CommandError> {
        match command {
            ViewCommand::SetViewportWidth { width } => {
                if width == 0 {
                    return Err(CommandError::Other(
                        "Viewport width must be greater than 0".to_string(),
                    ));
                }

                self.editor.viewport_width = width;
                self.editor.layout_engine.set_viewport_width(width);
                Ok(CommandResult::Success)
            }
            ViewCommand::SetTabWidth { width } => {
                if width == 0 {
                    return Err(CommandError::Other(
                        "Tab width must be greater than 0".to_string(),
                    ));
                }

                self.editor.layout_engine.set_tab_width(width);
                Ok(CommandResult::Success)
            }
            ViewCommand::SetTabKeyBehavior { behavior } => {
                self.tab_key_behavior = behavior;
                Ok(CommandResult::Success)
            }
            ViewCommand::ScrollTo { line } => {
                if line >= self.editor.line_index.line_count() {
                    return Err(CommandError::InvalidPosition { line, column: 0 });
                }

                // Scroll operation only validates line number validity
                // Actual scrolling handled by frontend
                Ok(CommandResult::Success)
            }
            ViewCommand::GetViewport { start_row, count } => {
                let text = self.editor.piece_table.get_text();
                let generator = SnapshotGenerator::from_text_with_tab_width(
                    &text,
                    self.editor.viewport_width,
                    self.editor.layout_engine.tab_width(),
                );
                let grid = generator.get_headless_grid(start_row, count);
                Ok(CommandResult::Viewport(grid))
            }
        }
    }

    // Private method: execute style command
    fn execute_style(&mut self, command: StyleCommand) -> Result<CommandResult, CommandError> {
        match command {
            StyleCommand::AddStyle {
                start,
                end,
                style_id,
            } => {
                if start >= end {
                    return Err(CommandError::InvalidRange { start, end });
                }

                let interval = crate::intervals::Interval::new(start, end, style_id);
                self.editor.interval_tree.insert(interval);
                Ok(CommandResult::Success)
            }
            StyleCommand::RemoveStyle {
                start,
                end,
                style_id,
            } => {
                self.editor.interval_tree.remove(start, end, style_id);
                Ok(CommandResult::Success)
            }
            StyleCommand::Fold {
                start_line,
                end_line,
            } => {
                if start_line >= end_line {
                    return Err(CommandError::InvalidRange {
                        start: start_line,
                        end: end_line,
                    });
                }

                let mut region = crate::intervals::FoldRegion::new(start_line, end_line);
                region.collapse();
                self.editor.folding_manager.add_region(region);
                Ok(CommandResult::Success)
            }
            StyleCommand::Unfold { start_line } => {
                self.editor.folding_manager.expand_line(start_line);
                Ok(CommandResult::Success)
            }
            StyleCommand::UnfoldAll => {
                self.editor.folding_manager.expand_all();
                Ok(CommandResult::Success)
            }
        }
    }

    fn rebuild_layout_engine_from_text(&mut self, text: &str) {
        let lines = crate::text::split_lines_preserve_trailing(text);
        let line_refs: Vec<&str> = lines.iter().map(|s| s.as_str()).collect();
        self.editor.layout_engine.from_lines(&line_refs);
    }

    fn position_to_char_offset_clamped(&self, pos: Position) -> usize {
        let line_count = self.editor.line_index.line_count();
        if line_count == 0 {
            return 0;
        }

        let line = pos.line.min(line_count.saturating_sub(1));
        let line_text = self
            .editor
            .line_index
            .get_line_text(line)
            .unwrap_or_default();
        let line_char_len = line_text.chars().count();
        let column = pos.column.min(line_char_len);
        self.editor.line_index.position_to_char_offset(line, column)
    }

    fn position_to_char_offset_and_virtual_pad(&self, pos: Position) -> (usize, usize) {
        let line_count = self.editor.line_index.line_count();
        if line_count == 0 {
            return (0, 0);
        }

        let line = pos.line.min(line_count.saturating_sub(1));
        let line_text = self
            .editor
            .line_index
            .get_line_text(line)
            .unwrap_or_default();
        let line_char_len = line_text.chars().count();
        let clamped_col = pos.column.min(line_char_len);
        let offset = self
            .editor
            .line_index
            .position_to_char_offset(line, clamped_col);
        let pad = pos.column.saturating_sub(clamped_col);
        (offset, pad)
    }

    fn normalize_cursor_and_selection(&mut self) {
        let line_index = &self.editor.line_index;
        let line_count = line_index.line_count();
        if line_count == 0 {
            self.editor.cursor_position = Position::new(0, 0);
            self.editor.selection = None;
            self.editor.secondary_selections.clear();
            return;
        }

        self.editor.cursor_position =
            Self::clamp_position_lenient_with_index(line_index, self.editor.cursor_position);

        if let Some(ref mut selection) = self.editor.selection {
            selection.start = Self::clamp_position_lenient_with_index(line_index, selection.start);
            selection.end = Self::clamp_position_lenient_with_index(line_index, selection.end);
            selection.direction = if selection.start.line < selection.end.line
                || (selection.start.line == selection.end.line
                    && selection.start.column <= selection.end.column)
            {
                SelectionDirection::Forward
            } else {
                SelectionDirection::Backward
            };
        }

        for selection in &mut self.editor.secondary_selections {
            selection.start = Self::clamp_position_lenient_with_index(line_index, selection.start);
            selection.end = Self::clamp_position_lenient_with_index(line_index, selection.end);
            selection.direction = if selection.start.line < selection.end.line
                || (selection.start.line == selection.end.line
                    && selection.start.column <= selection.end.column)
            {
                SelectionDirection::Forward
            } else {
                SelectionDirection::Backward
            };
        }
    }

    fn clamp_column_for_line(&self, line: usize, column: usize) -> usize {
        Self::clamp_column_for_line_with_index(&self.editor.line_index, line, column)
    }

    fn clamp_position_lenient_with_index(line_index: &LineIndex, pos: Position) -> Position {
        let line_count = line_index.line_count();
        if line_count == 0 {
            return Position::new(0, 0);
        }

        let clamped_line = pos.line.min(line_count.saturating_sub(1));
        // Note: do NOT clamp column here. Virtual columns (box selection) are allowed.
        Position::new(clamped_line, pos.column)
    }

    fn clamp_column_for_line_with_index(
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> usize {
        let line_start = line_index.position_to_char_offset(line, 0);
        let line_end = line_index.position_to_char_offset(line, usize::MAX);
        let line_len = line_end.saturating_sub(line_start);
        column.min(line_len)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_edit_insert() {
        let mut executor = CommandExecutor::new("Hello", 80);

        let result = executor.execute(Command::Edit(EditCommand::Insert {
            offset: 5,
            text: " World".to_string(),
        }));

        assert!(result.is_ok());
        assert_eq!(executor.editor().get_text(), "Hello World");
    }

    #[test]
    fn test_edit_delete() {
        let mut executor = CommandExecutor::new("Hello World", 80);

        let result = executor.execute(Command::Edit(EditCommand::Delete {
            start: 5,
            length: 6,
        }));

        assert!(result.is_ok());
        assert_eq!(executor.editor().get_text(), "Hello");
    }

    #[test]
    fn test_edit_replace() {
        let mut executor = CommandExecutor::new("Hello World", 80);

        let result = executor.execute(Command::Edit(EditCommand::Replace {
            start: 6,
            length: 5,
            text: "Rust".to_string(),
        }));

        assert!(result.is_ok());
        assert_eq!(executor.editor().get_text(), "Hello Rust");
    }

    #[test]
    fn test_cursor_move_to() {
        let mut executor = CommandExecutor::new("Line 1\nLine 2\nLine 3", 80);

        let result = executor.execute(Command::Cursor(CursorCommand::MoveTo {
            line: 1,
            column: 3,
        }));

        assert!(result.is_ok());
        assert_eq!(executor.editor().cursor_position(), Position::new(1, 3));
    }

    #[test]
    fn test_cursor_selection() {
        let mut executor = CommandExecutor::new("Hello World", 80);

        let result = executor.execute(Command::Cursor(CursorCommand::SetSelection {
            start: Position::new(0, 0),
            end: Position::new(0, 5),
        }));

        assert!(result.is_ok());
        assert!(executor.editor().selection().is_some());
    }

    #[test]
    fn test_view_set_width() {
        let mut executor = CommandExecutor::new("Test", 80);

        let result = executor.execute(Command::View(ViewCommand::SetViewportWidth { width: 40 }));

        assert!(result.is_ok());
        assert_eq!(executor.editor().viewport_width, 40);
    }

    #[test]
    fn test_style_add_remove() {
        let mut executor = CommandExecutor::new("Hello World", 80);

        // Add style
        let result = executor.execute(Command::Style(StyleCommand::AddStyle {
            start: 0,
            end: 5,
            style_id: 1,
        }));
        assert!(result.is_ok());

        // Remove style
        let result = executor.execute(Command::Style(StyleCommand::RemoveStyle {
            start: 0,
            end: 5,
            style_id: 1,
        }));
        assert!(result.is_ok());
    }

    #[test]
    fn test_batch_execution() {
        let mut executor = CommandExecutor::new("", 80);

        let commands = vec![
            Command::Edit(EditCommand::Insert {
                offset: 0,
                text: "Hello".to_string(),
            }),
            Command::Edit(EditCommand::Insert {
                offset: 5,
                text: " World".to_string(),
            }),
        ];

        let results = executor.execute_batch(commands);
        assert!(results.is_ok());
        assert_eq!(executor.editor().get_text(), "Hello World");
    }

    #[test]
    fn test_error_invalid_offset() {
        let mut executor = CommandExecutor::new("Hello", 80);

        let result = executor.execute(Command::Edit(EditCommand::Insert {
            offset: 100,
            text: "X".to_string(),
        }));

        assert!(result.is_err());
        assert!(matches!(
            result.unwrap_err(),
            CommandError::InvalidOffset(_)
        ));
    }
}
