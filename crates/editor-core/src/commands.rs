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

use crate::decorations::{Decoration, DecorationLayerId, DecorationPlacement};
use crate::delta::{TextDelta, TextDeltaEdit};
use crate::diagnostics::Diagnostic;
use crate::intervals::{FoldRegion, StyleId, StyleLayerId};
use crate::layout::{
    WrapIndent, WrapMode, cell_width_at, char_width, visual_x_for_column,
    wrap_indent_cells_for_line_text,
};
use crate::line_ending::LineEnding;
use crate::search::{CharIndex, SearchMatch, SearchOptions, find_all, find_next, find_prev};
use crate::snapshot::{
    Cell, ComposedCell, ComposedCellSource, ComposedGrid, ComposedLine, ComposedLineKind,
    HeadlessGrid, HeadlessLine,
};
use crate::{
    FOLD_PLACEHOLDER_STYLE_ID, FoldingManager, IntervalTree, LayoutEngine, LineIndex, PieceTable,
    SnapshotGenerator,
};
use editor_core_lang::CommentConfig;
use regex::RegexBuilder;
use std::cmp::Ordering;
use std::collections::{BTreeMap, HashMap};
use unicode_segmentation::UnicodeSegmentation;

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

/// A simple document text edit (character offsets, half-open).
///
/// This is commonly used for applying a batch of "simultaneous" edits (e.g. rename, refactor, or
/// workspace-wide search/replace), where the edit list is expressed in **pre-edit** coordinates.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct TextEditSpec {
    /// Inclusive start character offset.
    pub start: usize,
    /// Exclusive end character offset.
    pub end: usize,
    /// Replacement text.
    pub text: String,
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
    /// Insert a newline at each caret (or replace each selection).
    ///
    /// If `auto_indent` is true, the inserted newline is followed by the leading whitespace
    /// prefix of the current logical line.
    InsertNewline {
        /// Whether to auto-indent the new line.
        auto_indent: bool,
    },
    /// Indent the selected lines (or the current line for an empty selection).
    Indent,
    /// Outdent the selected lines (or the current line for an empty selection).
    Outdent,
    /// Duplicate the selected line(s) (or the current line for an empty selection).
    ///
    /// This is a line-based operation and will act on all carets/selections (primary + secondary),
    /// including rectangular selections.
    DuplicateLines,
    /// Delete the selected line(s) (or the current line for an empty selection).
    ///
    /// This is a line-based operation and will act on all carets/selections (primary + secondary),
    /// including rectangular selections.
    DeleteLines,
    /// Move the selected line(s) up by one line.
    ///
    /// This is a line-based operation and will act on all carets/selections (primary + secondary),
    /// including rectangular selections.
    MoveLinesUp,
    /// Move the selected line(s) down by one line.
    ///
    /// This is a line-based operation and will act on all carets/selections (primary + secondary),
    /// including rectangular selections.
    MoveLinesDown,
    /// Join the current line with the next line (for each caret/selection).
    ///
    /// If multiple carets/selections exist, joins are applied from bottom to top to keep offsets stable.
    JoinLines,
    /// Split the current line at each caret (or replace each selection) by inserting a newline.
    ///
    /// This is a convenience alias for [`EditCommand::InsertNewline`] with `auto_indent: false`.
    SplitLine,
    /// Toggle comments for the selected line(s) or selection ranges, using a language-provided
    /// comment configuration.
    ToggleComment {
        /// Comment tokens/config for the current language (data-driven).
        config: CommentConfig,
    },
    /// Apply a batch of text edits as a single undoable step.
    ///
    /// - Edits are interpreted in **pre-edit** character offsets.
    /// - Edits must be non-overlapping; they are applied in descending offset order internally.
    ApplyTextEdits {
        /// The edit list (character offsets, half-open).
        edits: Vec<TextEditSpec>,
    },
    /// Smart backspace: if the caret is in leading whitespace, delete back to the previous tab stop.
    ///
    /// Otherwise, behaves like [`EditCommand::Backspace`].
    DeleteToPrevTabStop,
    /// Delete the previous Unicode grapheme cluster (UAX #29) for each caret/selection.
    DeleteGraphemeBack,
    /// Delete the next Unicode grapheme cluster (UAX #29) for each caret/selection.
    DeleteGraphemeForward,
    /// Delete back to the previous Unicode word boundary (UAX #29) for each caret/selection.
    DeleteWordBack,
    /// Delete forward to the next Unicode word boundary (UAX #29) for each caret/selection.
    DeleteWordForward,
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
    /// Move cursor by visual rows (soft wrap + folding aware).
    ///
    /// This uses a "preferred x" in **cells** (sticky column) similar to many editors:
    /// horizontal moves update preferred x, while vertical visual moves try to preserve it.
    MoveVisualBy {
        /// Delta in global visual rows (after wrapping/folding).
        delta_rows: isize,
    },
    /// Move cursor to a visual position (global visual row + x in cells).
    MoveToVisual {
        /// Target global visual row (after wrapping/folding).
        row: usize,
        /// Target x offset in cells within that visual row.
        x_cells: usize,
    },
    /// Move cursor to the start of the current logical line.
    MoveToLineStart,
    /// Move cursor to the end of the current logical line.
    MoveToLineEnd,
    /// Move cursor to the start of the current visual line segment (wrap-aware).
    MoveToVisualLineStart,
    /// Move cursor to the end of the current visual line segment (wrap-aware).
    MoveToVisualLineEnd,
    /// Move cursor left by one Unicode grapheme cluster (UAX #29).
    MoveGraphemeLeft,
    /// Move cursor right by one Unicode grapheme cluster (UAX #29).
    MoveGraphemeRight,
    /// Move cursor left to the previous Unicode word boundary (UAX #29).
    MoveWordLeft,
    /// Move cursor right to the next Unicode word boundary (UAX #29).
    MoveWordRight,
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
    /// Select the entire current line (or the set of lines covered by the selection), for all carets.
    SelectLine,
    /// Select the word under each caret (or keep existing selections if already non-empty).
    SelectWord,
    /// Expand selection in a basic, editor-friendly way.
    ///
    /// - If the selection is empty, expands to the word under the caret.
    /// - If the selection is non-empty, expands to full line(s).
    ExpandSelection,
    /// Add a new caret above each existing caret/selection (at the same column, clamped to line length).
    AddCursorAbove,
    /// Add a new caret below each existing caret/selection (at the same column, clamped to line length).
    AddCursorBelow,
    /// Multi-cursor match op: add the next occurrence of the current selection/word as a new selection.
    AddNextOccurrence {
        /// Search options (case sensitivity, whole-word, regex).
        options: SearchOptions,
    },
    /// Multi-cursor match op: select all occurrences of the current selection/word.
    AddAllOccurrences {
        /// Search options (case sensitivity, whole-word, regex).
        options: SearchOptions,
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
    /// Set soft wrap mode.
    SetWrapMode {
        /// Wrap mode.
        mode: WrapMode,
    },
    /// Set wrapped-line indentation policy.
    SetWrapIndent {
        /// Wrap indent policy.
        indent: WrapIndent,
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

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum TextBoundary {
    Grapheme,
    Word,
}

fn byte_offset_for_char_column(text: &str, column: usize) -> usize {
    if column == 0 {
        return 0;
    }

    text.char_indices()
        .nth(column)
        .map(|(byte, _)| byte)
        .unwrap_or_else(|| text.len())
}

fn char_column_for_byte_offset(text: &str, byte_offset: usize) -> usize {
    text.get(..byte_offset).unwrap_or(text).chars().count()
}

fn prev_boundary_column(text: &str, column: usize, boundary: TextBoundary) -> usize {
    let byte_pos = byte_offset_for_char_column(text, column);

    let mut prev = 0usize;
    match boundary {
        TextBoundary::Grapheme => {
            for (b, _) in text.grapheme_indices(true) {
                if b >= byte_pos {
                    break;
                }
                prev = b;
            }
        }
        TextBoundary::Word => {
            for (b, _) in text.split_word_bound_indices() {
                if b >= byte_pos {
                    break;
                }
                prev = b;
            }
        }
    }

    char_column_for_byte_offset(text, prev)
}

fn next_boundary_column(text: &str, column: usize, boundary: TextBoundary) -> usize {
    let byte_pos = byte_offset_for_char_column(text, column);

    let mut next = text.len();
    match boundary {
        TextBoundary::Grapheme => {
            for (b, _) in text.grapheme_indices(true) {
                if b > byte_pos {
                    next = b;
                    break;
                }
            }
        }
        TextBoundary::Word => {
            for (b, _) in text.split_word_bound_indices() {
                if b > byte_pos {
                    next = b;
                    break;
                }
            }
        }
    }

    char_column_for_byte_offset(text, next)
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
    /// Derived diagnostics for this document (character-offset ranges + metadata).
    pub diagnostics: Vec<Diagnostic>,
    /// Derived decorations for this document (virtual text, links, etc.).
    pub decorations: BTreeMap<DecorationLayerId, Vec<Decoration>>,
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
        let normalized = crate::text::normalize_crlf_to_lf(text);
        let text = normalized.as_ref();

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
            diagnostics: Vec::new(),
            decorations: BTreeMap::new(),
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

    /// Get the current diagnostics list.
    pub fn diagnostics(&self) -> &[Diagnostic] {
        &self.diagnostics
    }

    /// Get all decorations for a given layer.
    pub fn decorations_for_layer(&self, layer: DecorationLayerId) -> &[Decoration] {
        self.decorations
            .get(&layer)
            .map(Vec::as_slice)
            .unwrap_or(&[])
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
                    if visual_in_line > 0 {
                        let indent_cells = wrap_indent_cells_for_line_text(
                            &line_text,
                            self.layout_engine.wrap_indent(),
                            self.viewport_width,
                            tab_width,
                        );
                        for _ in 0..indent_cells {
                            headless_line.add_cell(Cell::new(' ', 1));
                        }
                    }
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

    /// Get a decoration-aware composed grid snapshot (by composed visual line).
    ///
    /// This is an **optional** snapshot path that injects:
    /// - inline virtual text (`DecorationPlacement::{Before,After}`), e.g. inlay hints
    /// - above-line virtual text (`DecorationPlacement::AboveLine`), e.g. code lens
    ///
    /// Notes:
    /// - Wrapping is still computed from the underlying document text only.
    /// - Virtual text can therefore extend past the viewport width; hosts may clip.
    /// - Each [`ComposedCell`] carries its origin (`Document` vs `Virtual`) so hosts can map
    ///   interactions back to document offsets without re-implementing layout.
    pub fn get_headless_grid_composed(
        &self,
        start_visual_row: usize,
        count: usize,
    ) -> ComposedGrid {
        let mut grid = ComposedGrid::new(start_visual_row, count);
        if count == 0 {
            return grid;
        }

        #[derive(Debug, Clone)]
        struct VirtualText {
            anchor: usize,
            text: String,
            styles: Vec<StyleId>,
        }

        // Collect virtual text decorations from all layers.
        let mut inline_before: HashMap<usize, Vec<VirtualText>> = HashMap::new();
        let mut inline_after: HashMap<usize, Vec<VirtualText>> = HashMap::new();
        let mut above_by_line: BTreeMap<usize, Vec<VirtualText>> = BTreeMap::new();

        for decorations in self.decorations.values() {
            for deco in decorations {
                let Some(text) = deco.text.as_ref() else {
                    continue;
                };
                if text.is_empty() {
                    continue;
                }

                let anchor = match deco.placement {
                    DecorationPlacement::After => deco.range.end,
                    DecorationPlacement::Before | DecorationPlacement::AboveLine => {
                        deco.range.start
                    }
                };
                let vt = VirtualText {
                    anchor,
                    text: text.clone(),
                    styles: deco.styles.clone(),
                };

                match deco.placement {
                    DecorationPlacement::Before => {
                        inline_before.entry(anchor).or_default().push(vt);
                    }
                    DecorationPlacement::After => {
                        inline_after.entry(anchor).or_default().push(vt);
                    }
                    DecorationPlacement::AboveLine => {
                        let line = self.line_index.char_offset_to_position(anchor).0;
                        above_by_line.entry(line).or_default().push(vt);
                    }
                }
            }
        }

        // Compute the total composed visual line count for bounds checking.
        let regions = self.folding_manager.regions();
        let mut total_composed = 0usize;
        for logical_line in 0..self.layout_engine.logical_line_count() {
            if Self::is_logical_line_hidden(regions, logical_line) {
                continue;
            }

            if let Some(above) = above_by_line.get(&logical_line) {
                total_composed = total_composed.saturating_add(above.len());
            }

            total_composed = total_composed.saturating_add(
                self.layout_engine
                    .get_line_layout(logical_line)
                    .map(|l| l.visual_line_count)
                    .unwrap_or(1),
            );
        }

        if start_visual_row >= total_composed {
            return grid;
        }

        let end_visual = start_visual_row.saturating_add(count).min(total_composed);
        let tab_width = self.layout_engine.tab_width();

        let mut current_visual = 0usize;

        for logical_line in 0..self.layout_engine.logical_line_count() {
            if Self::is_logical_line_hidden(regions, logical_line) {
                continue;
            }

            // Above-line virtual text (e.g. code lens).
            if let Some(above) = above_by_line.get(&logical_line) {
                for vt in above {
                    if current_visual >= end_visual {
                        return grid;
                    }

                    if current_visual >= start_visual_row {
                        let mut x_render = 0usize;
                        let mut cells: Vec<ComposedCell> = Vec::new();
                        for ch in vt.text.chars() {
                            let w = cell_width_at(ch, x_render, tab_width);
                            x_render = x_render.saturating_add(w);
                            cells.push(ComposedCell {
                                ch,
                                width: w,
                                styles: vt.styles.clone(),
                                source: ComposedCellSource::Virtual {
                                    anchor_offset: vt.anchor,
                                },
                            });
                        }

                        grid.lines.push(ComposedLine {
                            kind: ComposedLineKind::VirtualAboveLine { logical_line },
                            cells,
                        });
                    }

                    current_visual = current_visual.saturating_add(1);
                }
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
                    return grid;
                }

                if current_visual < start_visual_row {
                    current_visual = current_visual.saturating_add(1);
                    continue;
                }

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

                let segment_start_offset = line_start_offset + segment_start_col;

                let mut cells: Vec<ComposedCell> = Vec::new();

                let mut x_render = 0usize;
                if visual_in_line > 0 {
                    let indent_cells = wrap_indent_cells_for_line_text(
                        &line_text,
                        self.layout_engine.wrap_indent(),
                        self.viewport_width,
                        tab_width,
                    );
                    x_render = x_render.saturating_add(indent_cells);
                    for _ in 0..indent_cells {
                        cells.push(ComposedCell {
                            ch: ' ',
                            width: 1,
                            styles: Vec::new(),
                            source: ComposedCellSource::Virtual {
                                anchor_offset: segment_start_offset,
                            },
                        });
                    }
                }

                let mut x_in_line = visual_x_for_column(&line_text, segment_start_col, tab_width);

                let push_virtual = |anchor: usize,
                                    list: &[VirtualText],
                                    cells: &mut Vec<ComposedCell>,
                                    x_render: &mut usize| {
                    for vt in list {
                        for ch in vt.text.chars() {
                            let w = cell_width_at(ch, *x_render, tab_width);
                            *x_render = x_render.saturating_add(w);
                            cells.push(ComposedCell {
                                ch,
                                width: w,
                                styles: vt.styles.clone(),
                                source: ComposedCellSource::Virtual {
                                    anchor_offset: anchor,
                                },
                            });
                        }
                    }
                };

                for (col, ch) in line_text
                    .chars()
                    .enumerate()
                    .skip(segment_start_col)
                    .take(segment_end_col.saturating_sub(segment_start_col))
                {
                    let offset = line_start_offset + col;

                    if let Some(list) = inline_before.get(&offset) {
                        push_virtual(offset, list, &mut cells, &mut x_render);
                    }
                    if let Some(list) = inline_after.get(&offset) {
                        push_virtual(offset, list, &mut cells, &mut x_render);
                    }

                    let styles = self.styles_at_offset(offset);
                    let w = cell_width_at(ch, x_in_line, tab_width);
                    x_in_line = x_in_line.saturating_add(w);
                    x_render = x_render.saturating_add(w);
                    cells.push(ComposedCell {
                        ch,
                        width: w,
                        styles,
                        source: ComposedCellSource::Document { offset },
                    });
                }

                // End-of-line inline virtual text (only on the last visual segment).
                if visual_in_line + 1 == layout.visual_line_count {
                    let eol_offset = line_start_offset + line_char_len;
                    if let Some(list) = inline_before.get(&eol_offset) {
                        push_virtual(eol_offset, list, &mut cells, &mut x_render);
                    }
                    if let Some(list) = inline_after.get(&eol_offset) {
                        push_virtual(eol_offset, list, &mut cells, &mut x_render);
                    }

                    // For collapsed folding start line, append placeholder to the last segment.
                    if let Some(region) = Self::collapsed_region_starting_at(regions, logical_line)
                        && !region.placeholder.is_empty()
                    {
                        if !cells.is_empty() {
                            x_render = x_render.saturating_add(char_width(' '));
                            cells.push(ComposedCell {
                                ch: ' ',
                                width: char_width(' '),
                                styles: vec![FOLD_PLACEHOLDER_STYLE_ID],
                                source: ComposedCellSource::Virtual {
                                    anchor_offset: eol_offset,
                                },
                            });
                        }
                        for ch in region.placeholder.chars() {
                            let w = cell_width_at(ch, x_render, tab_width);
                            x_render = x_render.saturating_add(w);
                            cells.push(ComposedCell {
                                ch,
                                width: w,
                                styles: vec![FOLD_PLACEHOLDER_STYLE_ID],
                                source: ComposedCellSource::Virtual {
                                    anchor_offset: eol_offset,
                                },
                            });
                        }
                    }
                }

                grid.lines.push(ComposedLine {
                    kind: ComposedLineKind::Document {
                        logical_line,
                        visual_in_logical: visual_in_line,
                    },
                    cells,
                });

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

        let indent = if wrapped_offset == 0 {
            0
        } else {
            wrap_indent_cells_for_line_text(
                &line_text,
                self.layout_engine.wrap_indent(),
                self.viewport_width,
                tab_width,
            )
        };

        Some((
            visual_start.saturating_add(wrapped_offset),
            indent.saturating_add(x_in_segment),
        ))
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

        let indent = if wrapped_offset == 0 {
            0
        } else {
            wrap_indent_cells_for_line_text(
                &line_text,
                self.layout_engine.wrap_indent(),
                self.viewport_width,
                tab_width,
            )
        };

        Some((
            visual_start.saturating_add(wrapped_offset),
            indent.saturating_add(x_in_segment),
        ))
    }

    /// Convert visual coordinates (global visual row + x in cells) back to logical `(line, column)`.
    ///
    /// - `visual_row` is the global visual row (after soft wrapping and folding).
    /// - `x_in_cells` is the cell offset within that visual row (0-based).
    ///
    /// Returns `None` if layout information is unavailable.
    pub fn visual_position_to_logical(
        &self,
        visual_row: usize,
        x_in_cells: usize,
    ) -> Option<Position> {
        let total_visual = self.visual_line_count();
        if total_visual == 0 {
            return Some(Position::new(0, 0));
        }

        let clamped_row = visual_row.min(total_visual.saturating_sub(1));
        let (logical_line, visual_in_logical) = self.visual_to_logical_line(clamped_row);

        let layout = self.layout_engine.get_line_layout(logical_line)?;
        let line_text = self
            .line_index
            .get_line_text(logical_line)
            .unwrap_or_default();
        let line_char_len = line_text.chars().count();

        let segment_start_col = if visual_in_logical == 0 {
            0
        } else {
            layout
                .wrap_points
                .get(visual_in_logical - 1)
                .map(|wp| wp.char_index)
                .unwrap_or(0)
        };

        let segment_end_col = layout
            .wrap_points
            .get(visual_in_logical)
            .map(|wp| wp.char_index)
            .unwrap_or(line_char_len)
            .max(segment_start_col)
            .min(line_char_len);

        let tab_width = self.layout_engine.tab_width();
        let x_in_cells = if visual_in_logical == 0 {
            x_in_cells
        } else {
            let indent = wrap_indent_cells_for_line_text(
                &line_text,
                self.layout_engine.wrap_indent(),
                self.viewport_width,
                tab_width,
            );
            x_in_cells.saturating_sub(indent)
        };
        let seg_start_x_in_line = visual_x_for_column(&line_text, segment_start_col, tab_width);
        let mut x_in_line = seg_start_x_in_line;
        let mut x_in_segment = 0usize;
        let mut column = segment_start_col;

        for (char_idx, ch) in line_text.chars().enumerate().skip(segment_start_col) {
            if char_idx >= segment_end_col {
                break;
            }

            let w = cell_width_at(ch, x_in_line, tab_width);
            if x_in_segment.saturating_add(w) > x_in_cells {
                break;
            }

            x_in_line = x_in_line.saturating_add(w);
            x_in_segment = x_in_segment.saturating_add(w);
            column = column.saturating_add(1);
        }

        Some(Position::new(logical_line, column))
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
    /// Preferred line ending for saving (internal storage is always LF).
    line_ending: LineEnding,
    /// Sticky x position for visual-row cursor movement (in cells).
    preferred_x_cells: Option<usize>,
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
            line_ending: LineEnding::detect_in_text(text),
            preferred_x_cells: None,
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

    /// Get the sticky x position (in cells) used by visual-row cursor movement.
    pub fn preferred_x_cells(&self) -> Option<usize> {
        self.preferred_x_cells
    }

    /// Set the sticky x position (in cells) used by visual-row cursor movement.
    pub fn set_preferred_x_cells(&mut self, preferred_x_cells: Option<usize>) {
        self.preferred_x_cells = preferred_x_cells;
    }

    /// Get the preferred line ending for saving this document.
    pub fn line_ending(&self) -> LineEnding {
        self.line_ending
    }

    /// Override the preferred line ending for saving this document.
    pub fn set_line_ending(&mut self, line_ending: LineEnding) {
        self.line_ending = line_ending;
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
            EditCommand::DeleteToPrevTabStop => self.execute_delete_to_prev_tab_stop_command(),
            EditCommand::DeleteGraphemeBack => {
                self.execute_delete_by_boundary_command(false, TextBoundary::Grapheme)
            }
            EditCommand::DeleteGraphemeForward => {
                self.execute_delete_by_boundary_command(true, TextBoundary::Grapheme)
            }
            EditCommand::DeleteWordBack => {
                self.execute_delete_by_boundary_command(false, TextBoundary::Word)
            }
            EditCommand::DeleteWordForward => {
                self.execute_delete_by_boundary_command(true, TextBoundary::Word)
            }
            EditCommand::Backspace => self.execute_backspace_command(),
            EditCommand::DeleteForward => self.execute_delete_forward_command(),
            EditCommand::InsertText { text } => self.execute_insert_text_command(text),
            EditCommand::InsertTab => self.execute_insert_tab_command(),
            EditCommand::InsertNewline { auto_indent } => {
                self.execute_insert_newline_command(auto_indent)
            }
            EditCommand::Indent => self.execute_indent_command(false),
            EditCommand::Outdent => self.execute_indent_command(true),
            EditCommand::DuplicateLines => self.execute_duplicate_lines_command(),
            EditCommand::DeleteLines => self.execute_delete_lines_command(),
            EditCommand::MoveLinesUp => self.execute_move_lines_command(true),
            EditCommand::MoveLinesDown => self.execute_move_lines_command(false),
            EditCommand::JoinLines => self.execute_join_lines_command(),
            EditCommand::SplitLine => self.execute_insert_newline_command(false),
            EditCommand::ToggleComment { config } => self.execute_toggle_comment_command(config),
            EditCommand::ApplyTextEdits { edits } => self.execute_apply_text_edits_command(edits),
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
            undo_group_id,
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
            undo_group_id,
        });

        Ok(CommandResult::Success)
    }

    fn execute_insert_text_command(&mut self, text: String) -> Result<CommandResult, CommandError> {
        if text.is_empty() {
            return Ok(CommandResult::Success);
        }

        let text = crate::text::normalize_crlf_to_lf_string(text);
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

            let edit_line = self
                .editor
                .line_index
                .char_offset_to_position(op.start_offset)
                .0;
            let deleted_newlines = op
                .deleted_text
                .as_bytes()
                .iter()
                .filter(|b| **b == b'\n')
                .count();
            let inserted_newlines = op
                .insert_text
                .as_bytes()
                .iter()
                .filter(|b| **b == b'\n')
                .count();
            let line_delta = inserted_newlines as isize - deleted_newlines as isize;
            if line_delta != 0 {
                self.editor
                    .folding_manager
                    .apply_line_delta(edit_line, line_delta);
            }

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
        self.editor
            .folding_manager
            .clamp_to_line_count(self.editor.line_index.line_count());
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

            let edit_line = self
                .editor
                .line_index
                .char_offset_to_position(op.start_offset)
                .0;
            let deleted_newlines = op
                .deleted_text
                .as_bytes()
                .iter()
                .filter(|b| **b == b'\n')
                .count();
            let inserted_newlines = op
                .insert_text
                .as_bytes()
                .iter()
                .filter(|b| **b == b'\n')
                .count();
            let line_delta = inserted_newlines as isize - deleted_newlines as isize;
            if line_delta != 0 {
                self.editor
                    .folding_manager
                    .apply_line_delta(edit_line, line_delta);
            }

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
        self.editor
            .folding_manager
            .clamp_to_line_count(self.editor.line_index.line_count());
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

    fn leading_whitespace_prefix(line_text: &str) -> String {
        line_text
            .chars()
            .take_while(|ch| *ch == ' ' || *ch == '\t')
            .collect()
    }

    fn indent_unit(&self) -> String {
        match self.tab_key_behavior {
            TabKeyBehavior::Tab => "\t".to_string(),
            TabKeyBehavior::Spaces => " ".repeat(self.editor.layout_engine.tab_width().max(1)),
        }
    }

    fn execute_insert_newline_command(
        &mut self,
        auto_indent: bool,
    ) -> Result<CommandResult, CommandError> {
        // Newline insertion should not coalesce into a typing group.
        self.undo_redo.end_group();

        let before_char_count = self.editor.piece_table.char_count();
        let before_selection = self.snapshot_selection_set();

        // Canonical selection set (primary + secondary).
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
            let (range_start_pos, range_end_pos) =
                crate::selection_set::selection_min_max(selection);

            let start_offset = self.position_to_char_offset_clamped(range_start_pos);
            let end_offset = self.position_to_char_offset_clamped(range_end_pos);

            let delete_len = end_offset.saturating_sub(start_offset);
            let deleted_text = if delete_len == 0 {
                String::new()
            } else {
                self.editor.piece_table.get_range(start_offset, delete_len)
            };

            let indent = if auto_indent {
                let line_text = self
                    .editor
                    .line_index
                    .get_line_text(range_start_pos.line)
                    .unwrap_or_default();
                Self::leading_whitespace_prefix(&line_text)
            } else {
                String::new()
            };

            let insert_text = format!("\n{}", indent);
            let insert_char_len = insert_text.chars().count();

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

        Ok(CommandResult::Success)
    }

    fn execute_indent_command(&mut self, outdent: bool) -> Result<CommandResult, CommandError> {
        self.undo_redo.end_group();

        let before_char_count = self.editor.piece_table.char_count();
        let before_selection = self.snapshot_selection_set();
        let selections = before_selection.selections.clone();

        let mut lines: Vec<usize> = Vec::new();
        for sel in &selections {
            let (min_pos, max_pos) = crate::selection_set::selection_min_max(sel);
            for line in min_pos.line..=max_pos.line {
                lines.push(line);
            }
        }
        lines.sort_unstable();
        lines.dedup();

        if lines.is_empty() {
            return Ok(CommandResult::Success);
        }

        let tab_width = self.editor.layout_engine.tab_width().max(1);
        let indent_unit = self.indent_unit();
        let indent_chars = indent_unit.chars().count();

        #[derive(Debug)]
        struct Op {
            start_offset: usize,
            start_after: usize,
            delete_len: usize,
            deleted_text: String,
            insert_text: String,
            insert_len: usize,
        }

        let mut ops: Vec<Op> = Vec::new();
        let mut line_deltas: std::collections::HashMap<usize, isize> =
            std::collections::HashMap::new();

        for line in lines {
            if line >= self.editor.line_index.line_count() {
                continue;
            }

            let start_offset = self.editor.line_index.position_to_char_offset(line, 0);
            let line_text = self
                .editor
                .line_index
                .get_line_text(line)
                .unwrap_or_default();

            if outdent {
                let mut remove_len = 0usize;
                if let Some(first) = line_text.chars().next() {
                    if first == '\t' {
                        remove_len = 1;
                    } else if first == ' ' {
                        let leading_spaces = line_text.chars().take_while(|c| *c == ' ').count();
                        remove_len = leading_spaces.min(tab_width);
                    }
                }

                if remove_len == 0 {
                    continue;
                }

                let deleted_text = self.editor.piece_table.get_range(start_offset, remove_len);
                ops.push(Op {
                    start_offset,
                    start_after: start_offset,
                    delete_len: remove_len,
                    deleted_text,
                    insert_text: String::new(),
                    insert_len: 0,
                });
                line_deltas.insert(line, -(remove_len as isize));
            } else {
                if indent_chars == 0 {
                    continue;
                }

                ops.push(Op {
                    start_offset,
                    start_after: start_offset,
                    delete_len: 0,
                    deleted_text: String::new(),
                    insert_text: indent_unit.clone(),
                    insert_len: indent_chars,
                });
                line_deltas.insert(line, indent_chars as isize);
            }
        }

        if ops.is_empty() {
            return Ok(CommandResult::Success);
        }

        // Compute start_after using ascending order and delta accumulation.
        let mut asc_indices: Vec<usize> = (0..ops.len()).collect();
        asc_indices.sort_by_key(|&idx| ops[idx].start_offset);

        let mut delta: i64 = 0;
        for &idx in &asc_indices {
            let op = &mut ops[idx];
            let effective_start = (op.start_offset as i64 + delta) as usize;
            op.start_after = effective_start;
            delta += op.insert_len as i64 - op.delete_len as i64;
        }

        // Apply ops descending so offsets remain valid.
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

            if op.insert_len > 0 {
                self.editor
                    .piece_table
                    .insert(op.start_offset, &op.insert_text);
                self.editor
                    .interval_tree
                    .update_for_insertion(op.start_offset, op.insert_len);
                for layer_tree in self.editor.style_layers.values_mut() {
                    layer_tree.update_for_insertion(op.start_offset, op.insert_len);
                }
            }
        }

        // Rebuild derived structures.
        let updated_text = self.editor.piece_table.get_text();
        self.editor.line_index = LineIndex::from_text(&updated_text);
        self.rebuild_layout_engine_from_text(&updated_text);

        // Shift cursor/selections for touched lines.
        let line_index = &self.editor.line_index;
        let apply_delta = |pos: &mut Position, deltas: &std::collections::HashMap<usize, isize>| {
            let Some(delta) = deltas.get(&pos.line) else {
                return;
            };

            let new_col = if *delta >= 0 {
                pos.column.saturating_add(*delta as usize)
            } else {
                pos.column.saturating_sub((-*delta) as usize)
            };

            pos.column = Self::clamp_column_for_line_with_index(line_index, pos.line, new_col);
        };

        apply_delta(&mut self.editor.cursor_position, &line_deltas);
        if let Some(sel) = &mut self.editor.selection {
            apply_delta(&mut sel.start, &line_deltas);
            apply_delta(&mut sel.end, &line_deltas);
        }
        for sel in &mut self.editor.secondary_selections {
            apply_delta(&mut sel.start, &line_deltas);
            apply_delta(&mut sel.end, &line_deltas);
        }

        self.normalize_cursor_and_selection();
        self.preferred_x_cells = self
            .editor
            .logical_position_to_visual(
                self.editor.cursor_position.line,
                self.editor.cursor_position.column,
            )
            .map(|(_, x)| x);

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

        Ok(CommandResult::Success)
    }

    fn selection_char_range(&self, selection: &Selection) -> SearchMatch {
        let (min_pos, max_pos) = crate::selection_set::selection_min_max(selection);
        let start = self.position_to_char_offset_clamped(min_pos);
        let end = self.position_to_char_offset_clamped(max_pos);
        SearchMatch {
            start: start.min(end),
            end: start.max(end),
        }
    }

    fn selected_line_blocks(selections: &[Selection]) -> Vec<(usize, usize)> {
        let mut lines: Vec<usize> = Vec::new();
        for sel in selections {
            let (min_pos, max_pos) = crate::selection_set::selection_min_max(sel);
            for line in min_pos.line..=max_pos.line {
                lines.push(line);
            }
        }

        lines.sort_unstable();
        lines.dedup();

        let mut blocks: Vec<(usize, usize)> = Vec::new();
        for line in lines {
            if let Some((_, end)) = blocks.last_mut() {
                if *end + 1 == line {
                    *end = line;
                    continue;
                }
            }
            blocks.push((line, line));
        }
        blocks
    }

    fn slice_text_for_lines(&self, start_line: usize, end_line: usize) -> String {
        let line_count = self.editor.line_index.line_count();
        if line_count == 0 || start_line >= line_count || start_line > end_line {
            return String::new();
        }

        let mut out = String::new();
        for line in start_line..=end_line.min(line_count - 1) {
            let text = self
                .editor
                .line_index
                .get_line_text(line)
                .unwrap_or_default();
            out.push_str(&text);
            // In the stored document, every line except the last has a trailing '\n'.
            if line + 1 < line_count {
                out.push('\n');
            }
        }
        out
    }

    fn execute_duplicate_lines_command(&mut self) -> Result<CommandResult, CommandError> {
        self.undo_redo.end_group();

        let before_char_count = self.editor.piece_table.char_count();
        let before_selection = self.snapshot_selection_set();
        let selections = before_selection.selections.clone();
        let primary_index = before_selection.primary_index;

        let line_count = self.editor.line_index.line_count();
        if line_count == 0 {
            return Ok(CommandResult::Success);
        }

        let blocks = Self::selected_line_blocks(&selections);
        if blocks.is_empty() {
            return Ok(CommandResult::Success);
        }

        let doc_text = self.editor.piece_table.get_text();
        let doc_ends_with_newline = doc_text.ends_with('\n');

        struct Op {
            start_before: usize,
            start_after: usize,
            deleted_text: String,
            inserted_text: String,
            inserted_len: usize,
        }

        let mut ops: Vec<Op> = Vec::new();

        for (start_line, end_line) in blocks {
            if start_line >= line_count {
                continue;
            }
            let end_line = end_line.min(line_count - 1);

            let insertion_offset = if end_line + 1 < line_count {
                self.editor
                    .line_index
                    .position_to_char_offset(end_line + 1, 0)
            } else {
                before_char_count
            };

            let block_text = self.slice_text_for_lines(start_line, end_line);
            if block_text.is_empty() && before_char_count == 0 {
                continue;
            }

            let mut inserted_text = block_text;
            if insertion_offset == before_char_count
                && !doc_ends_with_newline
                && before_char_count > 0
            {
                inserted_text.insert(0, '\n');
            }

            let inserted_len = inserted_text.chars().count();
            if inserted_len == 0 {
                continue;
            }

            ops.push(Op {
                start_before: insertion_offset,
                start_after: insertion_offset,
                deleted_text: String::new(),
                inserted_text,
                inserted_len,
            });
        }

        if ops.is_empty() {
            return Ok(CommandResult::Success);
        }

        // Compute start_after using ascending order and delta accumulation.
        let mut asc_indices: Vec<usize> = (0..ops.len()).collect();
        asc_indices.sort_by_key(|&idx| ops[idx].start_before);

        let mut delta: i64 = 0;
        for &idx in &asc_indices {
            let op = &mut ops[idx];
            let effective_start = op.start_before as i64 + delta;
            if effective_start < 0 {
                return Err(CommandError::Other(
                    "DuplicateLines produced an invalid intermediate offset".to_string(),
                ));
            }
            op.start_after = effective_start as usize;
            delta += op.inserted_len as i64;
        }

        let apply_ops: Vec<(usize, usize, &str)> = ops
            .iter()
            .map(|op| (op.start_before, 0usize, op.inserted_text.as_str()))
            .collect();
        self.apply_text_ops(apply_ops)?;

        // Move selections/carets to the duplicated lines, VSCode-style.
        let mut mapped: Vec<Selection> = Vec::with_capacity(selections.len());

        // Precompute per-block cumulative shift (in lines) for blocks above.
        let mut block_info: Vec<(usize, usize, usize, usize)> = Vec::new(); // (start,end,size,shift_before)
        let mut cumulative = 0usize;
        let mut blocks = Self::selected_line_blocks(&selections);
        blocks.sort_by_key(|(s, _)| *s);
        for (s, e) in blocks {
            let size = e.saturating_sub(s) + 1;
            block_info.push((s, e, size, cumulative));
            cumulative = cumulative.saturating_add(size);
        }

        let line_index = &self.editor.line_index;
        for sel in selections {
            let mut start = sel.start;
            let mut end = sel.end;

            let map_line = |line: usize, info: &[(usize, usize, usize, usize)]| -> usize {
                // If inside a duplicated block, map to the duplicate copy (shift by block_size).
                for (s, e, size, shift_before) in info {
                    if line >= *s && line <= *e {
                        return line + *shift_before + *size;
                    }
                    if line < *s {
                        break;
                    }
                }

                // Otherwise, shift down by the number of duplicated lines above this line.
                let mut shift = 0usize;
                for (s, e, size, shift_before) in info {
                    let _ = shift_before;
                    if *e < line {
                        shift = shift.saturating_add(*size);
                    } else if line < *s {
                        break;
                    }
                }
                line + shift
            };

            start.line = map_line(start.line, &block_info);
            end.line = map_line(end.line, &block_info);

            start.column =
                Self::clamp_column_for_line_with_index(line_index, start.line, start.column);
            end.column = Self::clamp_column_for_line_with_index(line_index, end.line, end.column);

            mapped.push(Selection {
                start,
                end,
                direction: crate::selection_set::selection_direction(start, end),
            });
        }

        let (mapped, mapped_primary) =
            crate::selection_set::normalize_selections(mapped, primary_index);
        self.execute_cursor(CursorCommand::SetSelections {
            selections: mapped,
            primary_index: mapped_primary,
        })?;

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

        Ok(CommandResult::Success)
    }

    fn execute_delete_lines_command(&mut self) -> Result<CommandResult, CommandError> {
        self.undo_redo.end_group();

        let before_char_count = self.editor.piece_table.char_count();
        let before_selection = self.snapshot_selection_set();
        let selections = before_selection.selections.clone();
        let primary_selection = selections
            .get(before_selection.primary_index)
            .cloned()
            .unwrap_or_else(|| selections[0].clone());

        let line_count = self.editor.line_index.line_count();
        if line_count == 0 {
            return Ok(CommandResult::Success);
        }

        let blocks = Self::selected_line_blocks(&selections);
        if blocks.is_empty() {
            return Ok(CommandResult::Success);
        }

        struct Op {
            start_before: usize,
            start_after: usize,
            delete_len: usize,
            deleted_text: String,
        }

        let mut ops: Vec<Op> = Vec::new();
        let mut primary_op_index = 0usize;

        for (idx, (start_line, end_line)) in blocks.into_iter().enumerate() {
            if start_line >= line_count {
                continue;
            }

            let end_line = end_line.min(line_count - 1);
            let mut start_offset = self
                .editor
                .line_index
                .position_to_char_offset(start_line, 0);
            let end_offset = if end_line + 1 < line_count {
                self.editor
                    .line_index
                    .position_to_char_offset(end_line + 1, 0)
            } else {
                before_char_count
            };

            if end_line + 1 >= line_count && start_offset > 0 {
                // Deleting the last line: also remove the newline before it, if any.
                start_offset = start_offset.saturating_sub(1);
            }

            if end_offset <= start_offset {
                continue;
            }

            let delete_len = end_offset - start_offset;
            let deleted_text = self.editor.piece_table.get_range(start_offset, delete_len);

            if crate::selection_set::selection_contains_position_inclusive(
                &primary_selection,
                Position::new(start_line, 0),
            ) {
                primary_op_index = idx;
            }

            ops.push(Op {
                start_before: start_offset,
                start_after: start_offset,
                delete_len,
                deleted_text,
            });
        }

        if ops.is_empty() {
            return Ok(CommandResult::Success);
        }

        // Compute start_after using ascending order and delta accumulation.
        let mut asc_indices: Vec<usize> = (0..ops.len()).collect();
        asc_indices.sort_by_key(|&idx| ops[idx].start_before);

        let mut delta: i64 = 0;
        for &idx in &asc_indices {
            let op = &mut ops[idx];
            let effective_start = op.start_before as i64 + delta;
            if effective_start < 0 {
                return Err(CommandError::Other(
                    "DeleteLines produced an invalid intermediate offset".to_string(),
                ));
            }
            op.start_after = effective_start as usize;
            delta -= op.delete_len as i64;
        }

        let apply_ops: Vec<(usize, usize, &str)> = ops
            .iter()
            .map(|op| (op.start_before, op.delete_len, ""))
            .collect();
        self.apply_text_ops(apply_ops)?;

        // Collapse selection state to carets at the start of each deleted block.
        let mut new_carets: Vec<Selection> = Vec::with_capacity(ops.len());
        for op in &ops {
            let (line, column) = self
                .editor
                .line_index
                .char_offset_to_position(op.start_after);
            let pos = Position::new(line, column);
            new_carets.push(Selection {
                start: pos,
                end: pos,
                direction: SelectionDirection::Forward,
            });
        }

        let primary_index = primary_op_index.min(new_carets.len().saturating_sub(1));
        self.execute_cursor(CursorCommand::SetSelections {
            selections: new_carets,
            primary_index,
        })?;

        let after_selection = self.snapshot_selection_set();

        let edits: Vec<TextEdit> = ops
            .into_iter()
            .map(|op| TextEdit {
                start_before: op.start_before,
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

    fn execute_move_lines_command(&mut self, up: bool) -> Result<CommandResult, CommandError> {
        self.undo_redo.end_group();

        let before_char_count = self.editor.piece_table.char_count();
        let before_selection = self.snapshot_selection_set();
        let selections = before_selection.selections.clone();
        let primary_index = before_selection.primary_index;

        let line_count = self.editor.line_index.line_count();
        if line_count <= 1 {
            return Ok(CommandResult::Success);
        }

        let blocks = Self::selected_line_blocks(&selections);
        if blocks.is_empty() {
            return Ok(CommandResult::Success);
        }

        #[derive(Debug, Clone, Copy)]
        struct Block {
            start: usize,
            end: usize,
        }

        let mut moved_blocks: Vec<Block> = Vec::new();
        for (start, end) in blocks {
            let start = start.min(line_count - 1);
            let end = end.min(line_count - 1);
            if up {
                if start == 0 {
                    continue;
                }
            } else if end + 1 >= line_count {
                continue;
            }
            moved_blocks.push(Block { start, end });
        }

        if moved_blocks.is_empty() {
            return Ok(CommandResult::Success);
        }

        struct Op {
            start_before: usize,
            start_after: usize,
            delete_len: usize,
            deleted_text: String,
            inserted_text: String,
        }

        let mut ops: Vec<Op> = Vec::with_capacity(moved_blocks.len());

        for block in &moved_blocks {
            let (range_start_line, range_end_line) = if up {
                (block.start - 1, block.end)
            } else {
                (block.start, block.end + 1)
            };

            let start_offset = self
                .editor
                .line_index
                .position_to_char_offset(range_start_line, 0);
            let end_offset = if range_end_line + 1 < line_count {
                self.editor
                    .line_index
                    .position_to_char_offset(range_end_line + 1, 0)
            } else {
                before_char_count
            };

            if end_offset <= start_offset {
                continue;
            }

            let deleted_text = self
                .editor
                .piece_table
                .get_range(start_offset, end_offset - start_offset);

            let block_text = self.slice_text_for_lines(block.start, block.end);

            let inserted_text = if up {
                let above_text = self.slice_text_for_lines(block.start - 1, block.start - 1);
                format!("{}{}", block_text, above_text)
            } else {
                let below_text = self.slice_text_for_lines(block.end + 1, block.end + 1);
                format!("{}{}", below_text, block_text)
            };

            ops.push(Op {
                start_before: start_offset,
                start_after: start_offset,
                delete_len: end_offset - start_offset,
                deleted_text,
                inserted_text,
            });
        }

        if ops.is_empty() {
            return Ok(CommandResult::Success);
        }

        // start_after is stable here (equal-length replacements), but compute for consistency.
        let mut asc_indices: Vec<usize> = (0..ops.len()).collect();
        asc_indices.sort_by_key(|&idx| ops[idx].start_before);

        let mut delta: i64 = 0;
        for &idx in &asc_indices {
            let op = &mut ops[idx];
            let effective_start = op.start_before as i64 + delta;
            if effective_start < 0 {
                return Err(CommandError::Other(
                    "MoveLines produced an invalid intermediate offset".to_string(),
                ));
            }
            op.start_after = effective_start as usize;
            let inserted_len = op.inserted_text.chars().count() as i64;
            delta += inserted_len - op.delete_len as i64;
        }

        let apply_ops: Vec<(usize, usize, &str)> = ops
            .iter()
            .map(|op| (op.start_before, op.delete_len, op.inserted_text.as_str()))
            .collect();
        self.apply_text_ops(apply_ops)?;

        // Move selections with their line blocks (and adjust displaced neighbor line).
        let line_index = &self.editor.line_index;
        let mut mapped: Vec<Selection> = Vec::with_capacity(selections.len());

        for sel in selections {
            let mut start = sel.start;
            let mut end = sel.end;

            let map_line = |line: usize, moved_blocks: &[Block], up: bool| -> usize {
                for block in moved_blocks {
                    let size = block.end.saturating_sub(block.start) + 1;
                    if line >= block.start && line <= block.end {
                        return if up { line - 1 } else { line + 1 };
                    }
                    if up && line == block.start - 1 {
                        return line + size;
                    }
                    if !up && line == block.end + 1 {
                        return line.saturating_sub(size);
                    }
                }
                line
            };

            start.line = map_line(start.line, &moved_blocks, up);
            end.line = map_line(end.line, &moved_blocks, up);

            start.column =
                Self::clamp_column_for_line_with_index(line_index, start.line, start.column);
            end.column = Self::clamp_column_for_line_with_index(line_index, end.line, end.column);

            mapped.push(Selection {
                start,
                end,
                direction: crate::selection_set::selection_direction(start, end),
            });
        }

        let (mapped, mapped_primary) =
            crate::selection_set::normalize_selections(mapped, primary_index);
        self.execute_cursor(CursorCommand::SetSelections {
            selections: mapped,
            primary_index: mapped_primary,
        })?;

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

        Ok(CommandResult::Success)
    }

    fn execute_join_lines_command(&mut self) -> Result<CommandResult, CommandError> {
        self.undo_redo.end_group();

        let before_char_count = self.editor.piece_table.char_count();
        let before_selection = self.snapshot_selection_set();
        let selections = before_selection.selections.clone();

        let line_count = self.editor.line_index.line_count();
        if line_count <= 1 {
            return Ok(CommandResult::Success);
        }

        let mut join_lines: Vec<usize> = Vec::new();
        for sel in &selections {
            let (min_pos, max_pos) = crate::selection_set::selection_min_max(sel);
            if min_pos.line >= line_count {
                continue;
            }
            let last = max_pos.line.min(line_count - 1);
            if min_pos.line == last {
                join_lines.push(last);
            } else {
                for line in min_pos.line..last {
                    join_lines.push(line);
                }
            }
        }

        join_lines.sort_unstable();
        join_lines.dedup();
        join_lines.retain(|l| *l + 1 < line_count);

        if join_lines.is_empty() {
            return Ok(CommandResult::Success);
        }

        struct Op {
            start_before: usize,
            start_after: usize,
            delete_len: usize,
            deleted_text: String,
            inserted_text: String,
            inserted_len: usize,
        }

        let mut ops: Vec<Op> = Vec::with_capacity(join_lines.len());

        // Process from bottom to top to keep (line->offset) stable in the pre-edit document.
        join_lines.sort_by_key(|l| std::cmp::Reverse(*l));

        for line in join_lines {
            let line_text = self
                .editor
                .line_index
                .get_line_text(line)
                .unwrap_or_default();
            let next_text = self
                .editor
                .line_index
                .get_line_text(line + 1)
                .unwrap_or_default();

            let line_len = line_text.chars().count();
            let join_offset = self
                .editor
                .line_index
                .position_to_char_offset(line, line_len);
            let leading_ws = next_text
                .chars()
                .take_while(|c| *c == ' ' || *c == '\t')
                .count();
            let end_offset = self
                .editor
                .line_index
                .position_to_char_offset(line + 1, leading_ws);

            if end_offset <= join_offset {
                continue;
            }

            let left_ends_with_ws = line_text
                .chars()
                .last()
                .is_some_and(|c| c == ' ' || c == '\t');
            let right_trimmed_empty = next_text.chars().skip(leading_ws).next().is_none();
            let insert_space = !left_ends_with_ws && !line_text.is_empty() && !right_trimmed_empty;

            let inserted_text = if insert_space {
                " ".to_string()
            } else {
                String::new()
            };
            let inserted_len = inserted_text.chars().count();
            let delete_len = end_offset - join_offset;
            let deleted_text = self.editor.piece_table.get_range(join_offset, delete_len);

            ops.push(Op {
                start_before: join_offset,
                start_after: join_offset,
                delete_len,
                deleted_text,
                inserted_text,
                inserted_len,
            });
        }

        if ops.is_empty() {
            return Ok(CommandResult::Success);
        }

        ops.sort_by_key(|op| op.start_before);

        let mut delta: i64 = 0;
        for op in &mut ops {
            let effective_start = op.start_before as i64 + delta;
            if effective_start < 0 {
                return Err(CommandError::Other(
                    "JoinLines produced an invalid intermediate offset".to_string(),
                ));
            }
            op.start_after = effective_start as usize;
            delta += op.inserted_len as i64 - op.delete_len as i64;
        }

        let apply_ops: Vec<(usize, usize, &str)> = ops
            .iter()
            .map(|op| (op.start_before, op.delete_len, op.inserted_text.as_str()))
            .collect();
        self.apply_text_ops(apply_ops)?;

        // Collapse selection state to carets at each join point.
        let mut new_carets: Vec<Selection> = Vec::with_capacity(ops.len());
        for op in &ops {
            let caret_offset = op.start_after + op.inserted_len;
            let (line, column) = self.editor.line_index.char_offset_to_position(caret_offset);
            let pos = Position::new(line, column);
            new_carets.push(Selection {
                start: pos,
                end: pos,
                direction: SelectionDirection::Forward,
            });
        }

        let (new_carets, primary_index) = crate::selection_set::normalize_selections(new_carets, 0);
        self.execute_cursor(CursorCommand::SetSelections {
            selections: new_carets,
            primary_index,
        })?;

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

        Ok(CommandResult::Success)
    }

    fn execute_toggle_comment_command(
        &mut self,
        config: CommentConfig,
    ) -> Result<CommandResult, CommandError> {
        if !config.has_line() && !config.has_block() {
            return Err(CommandError::Other(
                "ToggleComment requires at least one comment token".to_string(),
            ));
        }

        self.undo_redo.end_group();

        let before_char_count = self.editor.piece_table.char_count();
        let before_selection = self.snapshot_selection_set();
        let selections = before_selection.selections.clone();
        let primary_index = before_selection.primary_index;

        let line_count = self.editor.line_index.line_count();
        if line_count == 0 {
            return Ok(CommandResult::Success);
        }

        let all_single_line_selections = selections.iter().all(|sel| {
            let (min_pos, max_pos) = crate::selection_set::selection_min_max(sel);
            min_pos.line == max_pos.line && min_pos != max_pos
        });

        if config.has_block()
            && all_single_line_selections
            && let (Some(block_start), Some(block_end)) =
                (config.block_start.as_deref(), config.block_end.as_deref())
        {
            return self.execute_toggle_block_comment_inline(
                block_start,
                block_end,
                before_char_count,
                before_selection,
                selections,
                primary_index,
            );
        }

        if config.has_line()
            && let Some(token) = config.line.as_deref()
        {
            return self.execute_toggle_line_comment(
                token,
                before_char_count,
                before_selection,
                selections,
                primary_index,
            );
        }

        if config.has_block()
            && let (Some(block_start), Some(block_end)) =
                (config.block_start.as_deref(), config.block_end.as_deref())
        {
            return self.execute_toggle_block_comment_lines(
                block_start,
                block_end,
                before_char_count,
                before_selection,
                selections,
                primary_index,
            );
        }

        Ok(CommandResult::Success)
    }

    fn execute_apply_text_edits_command(
        &mut self,
        mut edits: Vec<TextEditSpec>,
    ) -> Result<CommandResult, CommandError> {
        self.undo_redo.end_group();

        if edits.is_empty() {
            return Ok(CommandResult::Success);
        }

        let before_char_count = self.editor.piece_table.char_count();
        let before_selection = self.snapshot_selection_set();

        let max_offset = before_char_count;

        for edit in &mut edits {
            if edit.start > edit.end {
                return Err(CommandError::InvalidRange {
                    start: edit.start,
                    end: edit.end,
                });
            }
            if edit.end > max_offset {
                return Err(CommandError::InvalidRange {
                    start: edit.start,
                    end: edit.end,
                });
            }
            edit.text = crate::text::normalize_crlf_to_lf_string(edit.text.clone());
        }

        edits.sort_by_key(|e| (e.start, e.end));

        // Validate non-overlap (pre-edit coordinates).
        let mut prev_end = 0usize;
        for (idx, edit) in edits.iter().enumerate() {
            if idx > 0 && edit.start < prev_end {
                return Err(CommandError::Other(
                    "ApplyTextEdits requires non-overlapping edits".to_string(),
                ));
            }
            prev_end = prev_end.max(edit.end);
        }

        struct Op {
            start_before: usize,
            start_after: usize,
            delete_len: usize,
            deleted_text: String,
            inserted_text: String,
            inserted_len: usize,
        }

        let mut ops: Vec<Op> = Vec::with_capacity(edits.len());
        for edit in edits {
            let delete_len = edit.end.saturating_sub(edit.start);
            let deleted_text = if delete_len == 0 {
                String::new()
            } else {
                self.editor.piece_table.get_range(edit.start, delete_len)
            };

            let inserted_text = edit.text;
            let inserted_len = inserted_text.chars().count();

            ops.push(Op {
                start_before: edit.start,
                start_after: edit.start,
                delete_len,
                deleted_text,
                inserted_text,
                inserted_len,
            });
        }

        // Compute start_after using ascending order and delta accumulation.
        let mut delta: i64 = 0;
        for op in &mut ops {
            let effective_start = op.start_before as i64 + delta;
            if effective_start < 0 {
                return Err(CommandError::Other(
                    "ApplyTextEdits produced an invalid intermediate offset".to_string(),
                ));
            }
            op.start_after = effective_start as usize;
            delta += op.inserted_len as i64 - op.delete_len as i64;
        }

        let apply_ops: Vec<(usize, usize, &str)> = ops
            .iter()
            .map(|op| (op.start_before, op.delete_len, op.inserted_text.as_str()))
            .collect();
        self.apply_text_ops(apply_ops)?;

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

        Ok(CommandResult::Success)
    }

    fn execute_toggle_line_comment(
        &mut self,
        token: &str,
        before_char_count: usize,
        before_selection: SelectionSetSnapshot,
        selections: Vec<Selection>,
        _primary_index: usize,
    ) -> Result<CommandResult, CommandError> {
        let token = token.trim_end();
        if token.is_empty() {
            return Ok(CommandResult::Success);
        }

        let token_len = token.chars().count();
        let insert_text = format!("{} ", token);
        let insert_len = insert_text.chars().count();

        // Collect unique target lines.
        let mut lines: Vec<usize> = Vec::new();
        for sel in &selections {
            let (min_pos, max_pos) = crate::selection_set::selection_min_max(sel);
            for line in min_pos.line..=max_pos.line {
                lines.push(line);
            }
        }
        lines.sort_unstable();
        lines.dedup();
        lines.retain(|l| *l < self.editor.line_index.line_count());

        if lines.is_empty() {
            return Ok(CommandResult::Success);
        }

        // Decide whether to comment or uncomment.
        let mut non_empty = 0usize;
        let mut all_commented = true;
        for line in &lines {
            let line_text = self
                .editor
                .line_index
                .get_line_text(*line)
                .unwrap_or_default();
            let indent = line_text
                .chars()
                .take_while(|c| *c == ' ' || *c == '\t')
                .count();
            let indent_byte = byte_offset_for_char_column(&line_text, indent);
            let rest = line_text.get(indent_byte..).unwrap_or("");
            if rest.is_empty() {
                continue;
            }
            non_empty += 1;
            if !rest.starts_with(token) {
                all_commented = false;
                break;
            }
        }

        let should_uncomment = non_empty > 0 && all_commented;

        struct Op {
            start_before: usize,
            start_after: usize,
            delete_len: usize,
            deleted_text: String,
            inserted_text: String,
            inserted_len: usize,
            line: usize,
            indent_col: usize,
            col_delta: isize,
        }

        let mut ops: Vec<Op> = Vec::new();

        for line in lines {
            let line_text = self
                .editor
                .line_index
                .get_line_text(line)
                .unwrap_or_default();
            let indent = line_text
                .chars()
                .take_while(|c| *c == ' ' || *c == '\t')
                .count();
            let indent_byte = byte_offset_for_char_column(&line_text, indent);
            let rest = line_text.get(indent_byte..).unwrap_or("");

            let start_offset = self.editor.line_index.position_to_char_offset(line, indent);

            if should_uncomment {
                if rest.is_empty() || !rest.starts_with(token) {
                    continue;
                }

                let mut remove_len = token_len;
                if let Some(ch) = line_text.chars().nth(indent + token_len)
                    && ch == ' '
                {
                    remove_len += 1;
                }

                if remove_len == 0 {
                    continue;
                }

                let deleted_text = self.editor.piece_table.get_range(start_offset, remove_len);
                ops.push(Op {
                    start_before: start_offset,
                    start_after: start_offset,
                    delete_len: remove_len,
                    deleted_text,
                    inserted_text: String::new(),
                    inserted_len: 0,
                    line,
                    indent_col: indent,
                    col_delta: -(remove_len as isize),
                });
            } else {
                ops.push(Op {
                    start_before: start_offset,
                    start_after: start_offset,
                    delete_len: 0,
                    deleted_text: String::new(),
                    inserted_text: insert_text.clone(),
                    inserted_len: insert_len,
                    line,
                    indent_col: indent,
                    col_delta: insert_len as isize,
                });
            }
        }

        if ops.is_empty() {
            return Ok(CommandResult::Success);
        }

        // Compute start_after.
        let mut asc_indices: Vec<usize> = (0..ops.len()).collect();
        asc_indices.sort_by_key(|&idx| ops[idx].start_before);

        let mut delta: i64 = 0;
        for &idx in &asc_indices {
            let op = &mut ops[idx];
            let effective_start = op.start_before as i64 + delta;
            if effective_start < 0 {
                return Err(CommandError::Other(
                    "ToggleComment produced an invalid intermediate offset".to_string(),
                ));
            }
            op.start_after = effective_start as usize;
            delta += op.inserted_len as i64 - op.delete_len as i64;
        }

        let apply_ops: Vec<(usize, usize, &str)> = ops
            .iter()
            .map(|op| (op.start_before, op.delete_len, op.inserted_text.as_str()))
            .collect();
        self.apply_text_ops(apply_ops)?;

        // Shift cursor/selections for touched lines, but only for columns at/after the insertion point.
        use std::collections::HashMap;
        let mut line_deltas: HashMap<usize, (usize, isize)> = HashMap::new();
        for op in &ops {
            line_deltas.insert(op.line, (op.indent_col, op.col_delta));
        }

        let line_index = &self.editor.line_index;
        let apply_delta = |pos: &mut Position, deltas: &HashMap<usize, (usize, isize)>| {
            let Some((indent_col, delta)) = deltas.get(&pos.line) else {
                return;
            };
            if pos.column < *indent_col {
                return;
            }

            let new_col = if *delta >= 0 {
                pos.column.saturating_add(*delta as usize)
            } else {
                pos.column.saturating_sub((-*delta) as usize)
            };

            pos.column = Self::clamp_column_for_line_with_index(line_index, pos.line, new_col);
        };

        apply_delta(&mut self.editor.cursor_position, &line_deltas);
        if let Some(sel) = &mut self.editor.selection {
            apply_delta(&mut sel.start, &line_deltas);
            apply_delta(&mut sel.end, &line_deltas);
        }
        for sel in &mut self.editor.secondary_selections {
            apply_delta(&mut sel.start, &line_deltas);
            apply_delta(&mut sel.end, &line_deltas);
        }

        self.normalize_cursor_and_selection();
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

        Ok(CommandResult::Success)
    }

    fn execute_toggle_block_comment_inline(
        &mut self,
        block_start: &str,
        block_end: &str,
        before_char_count: usize,
        before_selection: SelectionSetSnapshot,
        selections: Vec<Selection>,
        primary_index: usize,
    ) -> Result<CommandResult, CommandError> {
        let start_len = block_start.chars().count();
        let end_len = block_end.chars().count();
        if start_len == 0 || end_len == 0 {
            return Ok(CommandResult::Success);
        }

        let mut selection_ranges: Vec<SearchMatch> = selections
            .iter()
            .map(|s| self.selection_char_range(s))
            .filter(|r| r.start < r.end)
            .collect();

        if selection_ranges.is_empty() {
            return Ok(CommandResult::Success);
        }

        selection_ranges.sort_by_key(|r| (r.start, r.end));

        #[derive(Debug, Clone, Copy, PartialEq, Eq)]
        enum TokenOpKind {
            Start,
            End,
        }

        // Decide per-selection whether it is already wrapped; then build ops.
        struct Op {
            start_before: usize,
            start_after: usize,
            delete_len: usize,
            deleted_text: String,
            inserted_text: String,
            inserted_len: usize,
            sel_id: usize,
            kind: TokenOpKind,
        }

        let mut ops: Vec<Op> = Vec::new();

        for (sel_id, range) in selection_ranges.iter().enumerate() {
            let start = range.start;
            let end = range.end;

            let already_wrapped = start >= start_len
                && end + end_len <= before_char_count
                && self
                    .editor
                    .piece_table
                    .get_range(start - start_len, start_len)
                    == block_start
                && self.editor.piece_table.get_range(end, end_len) == block_end;

            if already_wrapped {
                // Delete end token first (higher offset), then start token.
                let deleted_end = self.editor.piece_table.get_range(end, end_len);
                ops.push(Op {
                    start_before: end,
                    start_after: end,
                    delete_len: end_len,
                    deleted_text: deleted_end,
                    inserted_text: String::new(),
                    inserted_len: 0,
                    sel_id,
                    kind: TokenOpKind::End,
                });

                let start_token_offset = start - start_len;
                let deleted_start = self
                    .editor
                    .piece_table
                    .get_range(start_token_offset, start_len);
                ops.push(Op {
                    start_before: start_token_offset,
                    start_after: start_token_offset,
                    delete_len: start_len,
                    deleted_text: deleted_start,
                    inserted_text: String::new(),
                    inserted_len: 0,
                    sel_id,
                    kind: TokenOpKind::Start,
                });
            } else {
                // Insert end token first (higher offset), then start token.
                ops.push(Op {
                    start_before: end,
                    start_after: end,
                    delete_len: 0,
                    deleted_text: String::new(),
                    inserted_text: block_end.to_string(),
                    inserted_len: end_len,
                    sel_id,
                    kind: TokenOpKind::End,
                });
                ops.push(Op {
                    start_before: start,
                    start_after: start,
                    delete_len: 0,
                    deleted_text: String::new(),
                    inserted_text: block_start.to_string(),
                    inserted_len: start_len,
                    sel_id,
                    kind: TokenOpKind::Start,
                });
            }
        }

        if ops.is_empty() {
            return Ok(CommandResult::Success);
        }

        ops.sort_by_key(|op| op.start_before);

        let mut delta: i64 = 0;
        for op in &mut ops {
            let effective_start = op.start_before as i64 + delta;
            if effective_start < 0 {
                return Err(CommandError::Other(
                    "ToggleComment produced an invalid intermediate offset".to_string(),
                ));
            }
            op.start_after = effective_start as usize;
            delta += op.inserted_len as i64 - op.delete_len as i64;
        }

        let apply_ops: Vec<(usize, usize, &str)> = ops
            .iter()
            .map(|op| (op.start_before, op.delete_len, op.inserted_text.as_str()))
            .collect();
        self.apply_text_ops(apply_ops)?;

        // Keep selections around the inner text between tokens so toggling is repeatable.
        let mut new_starts: Vec<usize> = vec![0; selection_ranges.len()];
        let mut new_ends: Vec<usize> = vec![0; selection_ranges.len()];

        for op in &ops {
            match op.kind {
                TokenOpKind::Start => {
                    new_starts[op.sel_id] = if op.inserted_len > 0 {
                        op.start_after + start_len
                    } else {
                        op.start_after
                    };
                }
                TokenOpKind::End => {
                    new_ends[op.sel_id] = op.start_after;
                }
            }
        }

        let mut next_selections: Vec<Selection> = Vec::with_capacity(selection_ranges.len());
        for i in 0..selection_ranges.len() {
            let start = new_starts[i].min(new_ends[i]);
            let end = new_starts[i].max(new_ends[i]);
            let (start_line, start_col) = self.editor.line_index.char_offset_to_position(start);
            let (end_line, end_col) = self.editor.line_index.char_offset_to_position(end);
            next_selections.push(Selection {
                start: Position::new(start_line, start_col),
                end: Position::new(end_line, end_col),
                direction: SelectionDirection::Forward,
            });
        }

        self.execute_cursor(CursorCommand::SetSelections {
            selections: next_selections,
            primary_index: primary_index.min(selection_ranges.len().saturating_sub(1)),
        })?;

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

        Ok(CommandResult::Success)
    }

    fn execute_toggle_block_comment_lines(
        &mut self,
        block_start: &str,
        block_end: &str,
        before_char_count: usize,
        before_selection: SelectionSetSnapshot,
        selections: Vec<Selection>,
        primary_index: usize,
    ) -> Result<CommandResult, CommandError> {
        let start_len = block_start.chars().count();
        let end_len = block_end.chars().count();
        if start_len == 0 || end_len == 0 {
            return Ok(CommandResult::Success);
        }

        let mut ranges: Vec<(usize, usize)> = Vec::new();
        for sel in &selections {
            let (min_pos, max_pos) = crate::selection_set::selection_min_max(sel);
            let start_line = min_pos.line.min(self.editor.line_index.line_count() - 1);
            let end_line = max_pos.line.min(self.editor.line_index.line_count() - 1);

            let start = self
                .editor
                .line_index
                .position_to_char_offset(start_line, 0);
            let end_line_text = self
                .editor
                .line_index
                .get_line_text(end_line)
                .unwrap_or_default();
            let end = self
                .editor
                .line_index
                .position_to_char_offset(end_line, end_line_text.chars().count());
            if start < end {
                ranges.push((start, end));
            }
        }

        ranges.sort_unstable();
        ranges.dedup();

        if ranges.is_empty() {
            return Ok(CommandResult::Success);
        }

        // Unwrap if every range already starts/ends with the tokens.
        let mut all_wrapped = true;
        for (start, end) in &ranges {
            if *end < *start + start_len + end_len {
                all_wrapped = false;
                break;
            }
            let text = self.editor.piece_table.get_range(*start, end - start);
            if !text.starts_with(block_start) || !text.ends_with(block_end) {
                all_wrapped = false;
                break;
            }
        }

        struct Op {
            start_before: usize,
            start_after: usize,
            delete_len: usize,
            deleted_text: String,
            inserted_text: String,
            inserted_len: usize,
        }

        let mut ops: Vec<Op> = Vec::new();

        for (start, end) in &ranges {
            if all_wrapped {
                // Remove end token (at end-end_len) and start token (at start).
                let end_token_start = end.saturating_sub(end_len);
                let deleted_end = self.editor.piece_table.get_range(end_token_start, end_len);
                ops.push(Op {
                    start_before: end_token_start,
                    start_after: end_token_start,
                    delete_len: end_len,
                    deleted_text: deleted_end,
                    inserted_text: String::new(),
                    inserted_len: 0,
                });

                let deleted_start = self.editor.piece_table.get_range(*start, start_len);
                ops.push(Op {
                    start_before: *start,
                    start_after: *start,
                    delete_len: start_len,
                    deleted_text: deleted_start,
                    inserted_text: String::new(),
                    inserted_len: 0,
                });
            } else {
                // Insert end token then start token.
                ops.push(Op {
                    start_before: *end,
                    start_after: *end,
                    delete_len: 0,
                    deleted_text: String::new(),
                    inserted_text: block_end.to_string(),
                    inserted_len: end_len,
                });
                ops.push(Op {
                    start_before: *start,
                    start_after: *start,
                    delete_len: 0,
                    deleted_text: String::new(),
                    inserted_text: block_start.to_string(),
                    inserted_len: start_len,
                });
            }
        }

        ops.sort_by_key(|op| op.start_before);
        let mut delta: i64 = 0;
        for op in &mut ops {
            let effective_start = op.start_before as i64 + delta;
            if effective_start < 0 {
                return Err(CommandError::Other(
                    "ToggleComment produced an invalid intermediate offset".to_string(),
                ));
            }
            op.start_after = effective_start as usize;
            delta += op.inserted_len as i64 - op.delete_len as i64;
        }

        let apply_ops: Vec<(usize, usize, &str)> = ops
            .iter()
            .map(|op| (op.start_before, op.delete_len, op.inserted_text.as_str()))
            .collect();
        self.apply_text_ops(apply_ops)?;

        // Keep a single caret at the end of the primary range.
        let (primary_start, primary_end) = ranges
            .get(primary_index.min(ranges.len().saturating_sub(1)))
            .copied()
            .unwrap_or((0, 0));
        let caret_offset = primary_end.max(primary_start);
        let (line, column) = self.editor.line_index.char_offset_to_position(caret_offset);
        let pos = Position::new(line, column);
        self.execute_cursor(CursorCommand::SetSelections {
            selections: vec![Selection {
                start: pos,
                end: pos,
                direction: SelectionDirection::Forward,
            }],
            primary_index: 0,
        })?;

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

        Ok(CommandResult::Success)
    }

    fn is_word_char(ch: char) -> bool {
        ch == '_' || ch.is_alphanumeric()
    }

    fn word_range_in_line(line_text: &str, column: usize) -> Option<(usize, usize)> {
        if line_text.is_empty() {
            return None;
        }

        let mut parts: Vec<(usize, usize, &str)> = Vec::new();
        for (start, part) in line_text.split_word_bound_indices() {
            let end = start + part.len();
            parts.push((start, end, part));
        }
        if parts.is_empty() {
            return None;
        }

        let byte_pos =
            byte_offset_for_char_column(line_text, column.min(line_text.chars().count()));

        let mut part_idx = parts
            .iter()
            .position(|(s, e, _)| *s <= byte_pos && byte_pos < *e)
            .or_else(|| parts.iter().position(|(s, _, _)| *s == byte_pos))
            .unwrap_or_else(|| parts.len().saturating_sub(1));

        let pick_part = |idx: usize, parts: &[(usize, usize, &str)]| -> Option<(usize, usize)> {
            let (s, e, text) = parts.get(idx)?;
            if text.chars().any(Self::is_word_char) {
                Some((*s, *e))
            } else {
                None
            }
        };

        // Prefer the part under the caret.
        if let Some((s, e)) = pick_part(part_idx, &parts) {
            return Some((
                char_column_for_byte_offset(line_text, s),
                char_column_for_byte_offset(line_text, e),
            ));
        }

        // Search to the right.
        for idx in part_idx + 1..parts.len() {
            if let Some((s, e)) = pick_part(idx, &parts) {
                return Some((
                    char_column_for_byte_offset(line_text, s),
                    char_column_for_byte_offset(line_text, e),
                ));
            }
        }

        // Search to the left.
        while part_idx > 0 {
            part_idx -= 1;
            if let Some((s, e)) = pick_part(part_idx, &parts) {
                return Some((
                    char_column_for_byte_offset(line_text, s),
                    char_column_for_byte_offset(line_text, e),
                ));
            }
        }

        None
    }

    fn execute_select_line_command(&mut self) -> Result<CommandResult, CommandError> {
        let snapshot = self.snapshot_selection_set();
        let selections = snapshot.selections;
        let primary_index = snapshot.primary_index;

        let line_count = self.editor.line_index.line_count();
        if line_count == 0 {
            return Ok(CommandResult::Success);
        }

        let mut next: Vec<Selection> = Vec::with_capacity(selections.len());
        for sel in selections {
            let (min_pos, max_pos) = crate::selection_set::selection_min_max(&sel);
            let start_line = min_pos.line.min(line_count.saturating_sub(1));
            let end_line = max_pos.line.min(line_count.saturating_sub(1));

            let start = Position::new(start_line, 0);
            let end = if end_line + 1 < line_count {
                Position::new(end_line + 1, 0)
            } else {
                let line_text = self
                    .editor
                    .line_index
                    .get_line_text(end_line)
                    .unwrap_or_default();
                Position::new(end_line, line_text.chars().count())
            };

            next.push(Selection {
                start,
                end,
                direction: SelectionDirection::Forward,
            });
        }

        self.execute_cursor(CursorCommand::SetSelections {
            selections: next,
            primary_index,
        })?;
        Ok(CommandResult::Success)
    }

    fn execute_select_word_command(&mut self) -> Result<CommandResult, CommandError> {
        let snapshot = self.snapshot_selection_set();
        let selections = snapshot.selections;
        let primary_index = snapshot.primary_index;

        let line_count = self.editor.line_index.line_count();
        if line_count == 0 {
            return Ok(CommandResult::Success);
        }

        let mut next: Vec<Selection> = Vec::with_capacity(selections.len());

        for sel in selections {
            // If already a non-empty selection, keep it.
            if sel.start != sel.end {
                next.push(sel);
                continue;
            }

            let caret = sel.end;
            let line = caret.line.min(line_count.saturating_sub(1));
            let line_text = self
                .editor
                .line_index
                .get_line_text(line)
                .unwrap_or_default();
            let col = caret.column.min(line_text.chars().count());

            let Some((start_col, end_col)) = Self::word_range_in_line(&line_text, col) else {
                next.push(sel);
                continue;
            };

            let start = Position::new(line, start_col);
            let end = Position::new(line, end_col);

            next.push(Selection {
                start,
                end,
                direction: SelectionDirection::Forward,
            });
        }

        self.execute_cursor(CursorCommand::SetSelections {
            selections: next,
            primary_index,
        })?;
        Ok(CommandResult::Success)
    }

    fn execute_expand_selection_command(&mut self) -> Result<CommandResult, CommandError> {
        // Basic expand policy:
        // - empty selection => select word
        // - non-empty selection => select line(s)
        let snapshot = self.snapshot_selection_set();
        if snapshot.selections.iter().any(|s| s.start != s.end) {
            self.execute_select_line_command()
        } else {
            self.execute_select_word_command()
        }
    }

    fn execute_add_cursor_vertical_command(
        &mut self,
        above: bool,
    ) -> Result<CommandResult, CommandError> {
        let snapshot = self.snapshot_selection_set();
        let mut selections = snapshot.selections;
        let primary_index = snapshot.primary_index;

        let line_count = self.editor.line_index.line_count();
        if line_count == 0 {
            return Ok(CommandResult::Success);
        }

        let mut extra: Vec<Selection> = Vec::new();
        for sel in &selections {
            let caret = sel.end;
            let target_line = if above {
                if caret.line == 0 {
                    continue;
                }
                caret.line - 1
            } else {
                let next = caret.line + 1;
                if next >= line_count {
                    continue;
                }
                next
            };

            let col = self.clamp_column_for_line(target_line, caret.column);
            let pos = Position::new(target_line, col);
            extra.push(Selection {
                start: pos,
                end: pos,
                direction: SelectionDirection::Forward,
            });
        }

        if extra.is_empty() {
            return Ok(CommandResult::Success);
        }

        selections.extend(extra);

        self.execute_cursor(CursorCommand::SetSelections {
            selections,
            primary_index,
        })?;
        Ok(CommandResult::Success)
    }

    fn selection_query(
        &self,
        selections: &[Selection],
        primary_index: usize,
    ) -> Option<(String, Option<SearchMatch>)> {
        let primary = selections.get(primary_index)?;
        let range = self.selection_char_range(primary);

        if range.start != range.end {
            let len = range.end - range.start;
            return Some((
                self.editor.piece_table.get_range(range.start, len),
                Some(range),
            ));
        }

        let caret = primary.end;
        let line_text = self
            .editor
            .line_index
            .get_line_text(caret.line)
            .unwrap_or_default();
        let col = caret.column.min(line_text.chars().count());
        let (start_col, end_col) = Self::word_range_in_line(&line_text, col)?;
        if start_col == end_col {
            return None;
        }

        let start = self
            .editor
            .line_index
            .position_to_char_offset(caret.line, start_col);
        let end = self
            .editor
            .line_index
            .position_to_char_offset(caret.line, end_col);
        let range = SearchMatch {
            start,
            end: end.max(start),
        };
        Some((
            self.editor
                .piece_table
                .get_range(range.start, range.end.saturating_sub(range.start)),
            Some(range),
        ))
    }

    fn execute_add_next_occurrence_command(
        &mut self,
        options: SearchOptions,
    ) -> Result<CommandResult, CommandError> {
        let snapshot = self.snapshot_selection_set();
        let mut selections = snapshot.selections;
        let primary_index = snapshot.primary_index;

        let Some((query, primary_range)) = self.selection_query(&selections, primary_index) else {
            return Ok(CommandResult::Success);
        };
        if query.is_empty() {
            return Ok(CommandResult::Success);
        }

        // VSCode-like: if there is no active selection, first select the current word occurrence.
        if let Some(primary_range) = primary_range
            && primary_range.start != primary_range.end
        {
            let current = selections
                .get(primary_index)
                .map(|s| self.selection_char_range(s))
                .unwrap_or(SearchMatch { start: 0, end: 0 });
            if current.start == current.end {
                let (start_line, start_col) = self
                    .editor
                    .line_index
                    .char_offset_to_position(primary_range.start);
                let (end_line, end_col) = self
                    .editor
                    .line_index
                    .char_offset_to_position(primary_range.end);
                if let Some(sel) = selections.get_mut(primary_index) {
                    *sel = Selection {
                        start: Position::new(start_line, start_col),
                        end: Position::new(end_line, end_col),
                        direction: SelectionDirection::Forward,
                    };
                }
            }
        }

        let text = self.editor.piece_table.get_text();

        let mut ranges: Vec<SearchMatch> = selections
            .iter()
            .map(|s| self.selection_char_range(s))
            .filter(|r| r.start != r.end)
            .collect();

        if let Some(primary_range) = primary_range
            && primary_range.start != primary_range.end
            && !ranges
                .iter()
                .any(|r| r.start == primary_range.start && r.end == primary_range.end)
        {
            ranges.push(primary_range);
        }

        let mut existing: Vec<(usize, usize)> = ranges
            .iter()
            .map(|r| (r.start.min(r.end), r.end.max(r.start)))
            .collect();
        existing.sort_unstable();

        let from = existing.iter().map(|(_, end)| *end).max().unwrap_or(0);

        let mut search_from = from;
        let mut wrapped = false;
        let mut found: Option<SearchMatch> = None;

        loop {
            let next = find_next(&text, &query, options, search_from)
                .map_err(|err| CommandError::Other(err.to_string()))?;

            let Some(m) = next else {
                if wrapped {
                    break;
                }
                wrapped = true;
                search_from = 0;
                continue;
            };

            let overlaps = existing.iter().any(|(s, e)| m.start < *e && m.end > *s);

            if overlaps {
                if m.end >= text.chars().count() {
                    break;
                }
                search_from = m.end + 1;
                continue;
            }

            found = Some(m);
            break;
        }

        let Some(m) = found else {
            return Ok(CommandResult::Success);
        };

        let (start_line, start_col) = self.editor.line_index.char_offset_to_position(m.start);
        let (end_line, end_col) = self.editor.line_index.char_offset_to_position(m.end);

        selections.push(Selection {
            start: Position::new(start_line, start_col),
            end: Position::new(end_line, end_col),
            direction: SelectionDirection::Forward,
        });

        let new_primary_index = selections.len().saturating_sub(1);
        self.execute_cursor(CursorCommand::SetSelections {
            selections,
            primary_index: new_primary_index,
        })?;

        Ok(CommandResult::Success)
    }

    fn execute_add_all_occurrences_command(
        &mut self,
        options: SearchOptions,
    ) -> Result<CommandResult, CommandError> {
        let snapshot = self.snapshot_selection_set();
        let selections = snapshot.selections;
        let primary_index = snapshot.primary_index;

        let Some((query, primary_range)) = self.selection_query(&selections, primary_index) else {
            return Ok(CommandResult::Success);
        };
        if query.is_empty() {
            return Ok(CommandResult::Success);
        }

        let text = self.editor.piece_table.get_text();
        let matches =
            find_all(&text, &query, options).map_err(|err| CommandError::Other(err.to_string()))?;

        if matches.is_empty() {
            return Ok(CommandResult::Success);
        }

        let mut out: Vec<Selection> = Vec::with_capacity(matches.len());
        let mut next_primary = 0usize;
        let primary_range = primary_range.filter(|r| r.start != r.end);

        for (idx, m) in matches.iter().enumerate() {
            let (start_line, start_col) = self.editor.line_index.char_offset_to_position(m.start);
            let (end_line, end_col) = self.editor.line_index.char_offset_to_position(m.end);
            out.push(Selection {
                start: Position::new(start_line, start_col),
                end: Position::new(end_line, end_col),
                direction: SelectionDirection::Forward,
            });

            if let Some(pr) = primary_range
                && pr.start == m.start
                && pr.end == m.end
            {
                next_primary = idx;
            }
        }

        self.execute_cursor(CursorCommand::SetSelections {
            selections: out,
            primary_index: next_primary,
        })?;

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

        let text = crate::text::normalize_crlf_to_lf_string(text);
        let max_offset = self.editor.piece_table.char_count();
        if offset > max_offset {
            return Err(CommandError::InvalidOffset(offset));
        }

        let before_char_count = self.editor.piece_table.char_count();
        let before_selection = self.snapshot_selection_set();

        let affected_line = self.editor.line_index.char_offset_to_position(offset).0;
        let inserts_newline = text.contains('\n');
        let inserted_newlines = text.as_bytes().iter().filter(|b| **b == b'\n').count();

        // Execute insertion
        self.editor.piece_table.insert(offset, &text);

        // Update line index
        let updated_text = self.editor.piece_table.get_text();
        self.editor.line_index = LineIndex::from_text(&updated_text);
        if inserted_newlines > 0 {
            self.editor
                .folding_manager
                .apply_line_delta(affected_line, inserted_newlines as isize);
            self.editor
                .folding_manager
                .clamp_to_line_count(self.editor.line_index.line_count());
        }

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
        let deleted_newlines = deleted_text
            .as_bytes()
            .iter()
            .filter(|b| **b == b'\n')
            .count();
        let affected_line = self.editor.line_index.char_offset_to_position(start).0;

        // Execute deletion
        self.editor.piece_table.delete(start, length);

        // Update line index
        let updated_text = self.editor.piece_table.get_text();
        self.editor.line_index = LineIndex::from_text(&updated_text);
        if deleted_newlines > 0 {
            self.editor
                .folding_manager
                .apply_line_delta(affected_line, -(deleted_newlines as isize));
            self.editor
                .folding_manager
                .clamp_to_line_count(self.editor.line_index.line_count());
        }

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

        let text = crate::text::normalize_crlf_to_lf_string(text);
        let before_selection = self.snapshot_selection_set();

        let deleted_text = if length == 0 {
            String::new()
        } else {
            self.editor.piece_table.get_range(start, length)
        };
        let delta_deleted_text = deleted_text.clone();
        let delta_inserted_text = text.clone();

        let affected_line = self.editor.line_index.char_offset_to_position(start).0;
        let deleted_newlines = deleted_text
            .as_bytes()
            .iter()
            .filter(|b| **b == b'\n')
            .count();
        let inserted_newlines = text.as_bytes().iter().filter(|b| **b == b'\n').count();
        let line_delta = inserted_newlines as isize - deleted_newlines as isize;
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
        if line_delta != 0 {
            self.editor
                .folding_manager
                .apply_line_delta(affected_line, line_delta);
            self.editor
                .folding_manager
                .clamp_to_line_count(self.editor.line_index.line_count());
        }

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
        let inserted_text = crate::text::normalize_crlf_to_lf_string(inserted_text);

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

        let replacement = crate::text::normalize_crlf_to_lf_string(replacement);
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
                let inserted_text = crate::text::normalize_crlf_to_lf_string(inserted_text);
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

    fn execute_delete_to_prev_tab_stop_command(&mut self) -> Result<CommandResult, CommandError> {
        // Treat like a delete-like action: end any open insert coalescing group, even if it turns out
        // to be a no-op.
        self.undo_redo.end_group();

        let before_selection = self.snapshot_selection_set();
        let selections = before_selection.selections.clone();
        let primary_index = before_selection.primary_index;

        let tab_width = self.editor.layout_engine.tab_width().max(1);

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
                let caret = selection.end;
                let caret_offset = self.position_to_char_offset_clamped(caret);
                if caret_offset == 0 {
                    (0, 0)
                } else {
                    let line_text = self
                        .editor
                        .line_index
                        .get_line_text(caret.line)
                        .unwrap_or_default();
                    let line_char_len = line_text.chars().count();
                    let col = caret.column.min(line_char_len);

                    let in_leading_whitespace = line_text
                        .chars()
                        .take(col)
                        .all(|ch| ch == ' ' || ch == '\t');

                    if !in_leading_whitespace {
                        (caret_offset - 1, caret_offset)
                    } else {
                        let x_in_line = visual_x_for_column(&line_text, col, tab_width);
                        let back = if x_in_line == 0 {
                            0
                        } else {
                            let rem = x_in_line % tab_width;
                            if rem == 0 { tab_width } else { rem }
                        };
                        let target_x = x_in_line.saturating_sub(back);

                        let mut target_col = col;
                        while target_col > 0 {
                            let prev_col = target_col - 1;
                            let prev_x = visual_x_for_column(&line_text, prev_col, tab_width);
                            if prev_x < target_x {
                                break;
                            }
                            target_col = prev_col;
                            if prev_x == target_x {
                                break;
                            }
                        }

                        let target_offset = self
                            .editor
                            .line_index
                            .position_to_char_offset(caret.line, target_col);
                        (target_offset, caret_offset)
                    }
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

            let edit_line = self
                .editor
                .line_index
                .char_offset_to_position(op.start_offset)
                .0;
            let deleted_newlines = op
                .deleted_text
                .as_bytes()
                .iter()
                .filter(|b| **b == b'\n')
                .count();
            if deleted_newlines > 0 {
                self.editor
                    .folding_manager
                    .apply_line_delta(edit_line, -(deleted_newlines as isize));
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
        self.editor
            .folding_manager
            .clamp_to_line_count(self.editor.line_index.line_count());
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

        Ok(CommandResult::Success)
    }

    fn execute_delete_by_boundary_command(
        &mut self,
        forward: bool,
        boundary: TextBoundary,
    ) -> Result<CommandResult, CommandError> {
        // Any delete-like action should end an open insert coalescing group, even if it turns out
        // to be a no-op.
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
                let caret = selection.end;
                let caret_offset = self.position_to_char_offset_clamped(caret);
                let line_count = self.editor.line_index.line_count();
                let line = caret.line.min(line_count.saturating_sub(1));
                let line_text = self
                    .editor
                    .line_index
                    .get_line_text(line)
                    .unwrap_or_default();
                let line_char_len = line_text.chars().count();
                let col = caret.column.min(line_char_len);

                if forward {
                    if caret_offset >= doc_char_count {
                        (caret_offset, caret_offset)
                    } else if col >= line_char_len {
                        (caret_offset, (caret_offset + 1).min(doc_char_count))
                    } else {
                        let next_col = next_boundary_column(&line_text, col, boundary);
                        let start_offset =
                            self.editor.line_index.position_to_char_offset(line, col);
                        let end_offset = self
                            .editor
                            .line_index
                            .position_to_char_offset(line, next_col);
                        (start_offset, end_offset)
                    }
                } else if caret_offset == 0 {
                    (0, 0)
                } else if col == 0 {
                    (caret_offset - 1, caret_offset)
                } else {
                    let prev_col = prev_boundary_column(&line_text, col, boundary);
                    let start_offset = self
                        .editor
                        .line_index
                        .position_to_char_offset(line, prev_col);
                    let end_offset = self.editor.line_index.position_to_char_offset(line, col);
                    (start_offset, end_offset)
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

        Ok(CommandResult::Success)
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

            let edit_line = self.editor.line_index.char_offset_to_position(start).0;
            let deleted_text = if delete_len > 0 {
                self.editor.piece_table.get_range(start, delete_len)
            } else {
                String::new()
            };
            let deleted_newlines = deleted_text
                .as_bytes()
                .iter()
                .filter(|b| **b == b'\n')
                .count();
            let inserted_newlines = insert_text
                .as_bytes()
                .iter()
                .filter(|b| **b == b'\n')
                .count();
            let line_delta = inserted_newlines as isize - deleted_newlines as isize;
            if line_delta != 0 {
                self.editor
                    .folding_manager
                    .apply_line_delta(edit_line, line_delta);
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
        self.editor
            .folding_manager
            .clamp_to_line_count(self.editor.line_index.line_count());
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
                self.preferred_x_cells = self
                    .editor
                    .logical_position_to_visual(line, clamped_column)
                    .map(|(_, x)| x);
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
                self.preferred_x_cells = self
                    .editor
                    .logical_position_to_visual(new_line, clamped_column)
                    .map(|(_, x)| x);
                Ok(CommandResult::Success)
            }
            CursorCommand::MoveGraphemeLeft => {
                let line_count = self.editor.line_index.line_count();
                if line_count == 0 {
                    return Ok(CommandResult::Success);
                }

                let mut line = self
                    .editor
                    .cursor_position
                    .line
                    .min(line_count.saturating_sub(1));
                let mut line_text = self
                    .editor
                    .line_index
                    .get_line_text(line)
                    .unwrap_or_default();
                let mut line_char_len = line_text.chars().count();
                let mut col = self.editor.cursor_position.column.min(line_char_len);

                if col == 0 {
                    if line == 0 {
                        return Ok(CommandResult::Success);
                    }
                    line = line.saturating_sub(1);
                    line_text = self
                        .editor
                        .line_index
                        .get_line_text(line)
                        .unwrap_or_default();
                    line_char_len = line_text.chars().count();
                    col = line_char_len;
                } else {
                    col = prev_boundary_column(&line_text, col, TextBoundary::Grapheme);
                }

                self.editor.cursor_position = Position::new(line, col);
                self.preferred_x_cells = self
                    .editor
                    .logical_position_to_visual(line, col)
                    .map(|(_, x)| x);
                Ok(CommandResult::Success)
            }
            CursorCommand::MoveGraphemeRight => {
                let line_count = self.editor.line_index.line_count();
                if line_count == 0 {
                    return Ok(CommandResult::Success);
                }

                let line = self
                    .editor
                    .cursor_position
                    .line
                    .min(line_count.saturating_sub(1));
                let line_text = self
                    .editor
                    .line_index
                    .get_line_text(line)
                    .unwrap_or_default();
                let line_char_len = line_text.chars().count();
                let col = self.editor.cursor_position.column.min(line_char_len);

                let (line, col) = if col >= line_char_len {
                    if line + 1 >= line_count {
                        return Ok(CommandResult::Success);
                    }
                    (line + 1, 0)
                } else {
                    (
                        line,
                        next_boundary_column(&line_text, col, TextBoundary::Grapheme),
                    )
                };

                self.editor.cursor_position = Position::new(line, col);
                self.preferred_x_cells = self
                    .editor
                    .logical_position_to_visual(line, col)
                    .map(|(_, x)| x);
                Ok(CommandResult::Success)
            }
            CursorCommand::MoveWordLeft => {
                let line_count = self.editor.line_index.line_count();
                if line_count == 0 {
                    return Ok(CommandResult::Success);
                }

                let mut line = self
                    .editor
                    .cursor_position
                    .line
                    .min(line_count.saturating_sub(1));
                let mut line_text = self
                    .editor
                    .line_index
                    .get_line_text(line)
                    .unwrap_or_default();
                let mut line_char_len = line_text.chars().count();
                let mut col = self.editor.cursor_position.column.min(line_char_len);

                if col == 0 {
                    if line == 0 {
                        return Ok(CommandResult::Success);
                    }
                    line = line.saturating_sub(1);
                    line_text = self
                        .editor
                        .line_index
                        .get_line_text(line)
                        .unwrap_or_default();
                    line_char_len = line_text.chars().count();
                    col = line_char_len;
                } else {
                    col = prev_boundary_column(&line_text, col, TextBoundary::Word);
                }

                self.editor.cursor_position = Position::new(line, col);
                self.preferred_x_cells = self
                    .editor
                    .logical_position_to_visual(line, col)
                    .map(|(_, x)| x);
                Ok(CommandResult::Success)
            }
            CursorCommand::MoveWordRight => {
                let line_count = self.editor.line_index.line_count();
                if line_count == 0 {
                    return Ok(CommandResult::Success);
                }

                let line = self
                    .editor
                    .cursor_position
                    .line
                    .min(line_count.saturating_sub(1));
                let line_text = self
                    .editor
                    .line_index
                    .get_line_text(line)
                    .unwrap_or_default();
                let line_char_len = line_text.chars().count();
                let col = self.editor.cursor_position.column.min(line_char_len);

                let (line, col) = if col >= line_char_len {
                    if line + 1 >= line_count {
                        return Ok(CommandResult::Success);
                    }
                    (line + 1, 0)
                } else {
                    (
                        line,
                        next_boundary_column(&line_text, col, TextBoundary::Word),
                    )
                };

                self.editor.cursor_position = Position::new(line, col);
                self.preferred_x_cells = self
                    .editor
                    .logical_position_to_visual(line, col)
                    .map(|(_, x)| x);
                Ok(CommandResult::Success)
            }
            CursorCommand::MoveVisualBy { delta_rows } => {
                let Some((current_row, current_x)) = self.editor.logical_position_to_visual(
                    self.editor.cursor_position.line,
                    self.editor.cursor_position.column,
                ) else {
                    return Ok(CommandResult::Success);
                };

                let preferred_x = self.preferred_x_cells.unwrap_or(current_x);
                self.preferred_x_cells = Some(preferred_x);

                let total_visual = self.editor.visual_line_count();
                if total_visual == 0 {
                    return Ok(CommandResult::Success);
                }

                let target_row = if delta_rows >= 0 {
                    current_row.saturating_add(delta_rows as usize)
                } else {
                    current_row.saturating_sub((-delta_rows) as usize)
                }
                .min(total_visual.saturating_sub(1));

                let Some(pos) = self
                    .editor
                    .visual_position_to_logical(target_row, preferred_x)
                else {
                    return Ok(CommandResult::Success);
                };

                self.editor.cursor_position = pos;
                Ok(CommandResult::Success)
            }
            CursorCommand::MoveToVisual { row, x_cells } => {
                let Some(pos) = self.editor.visual_position_to_logical(row, x_cells) else {
                    return Ok(CommandResult::Success);
                };

                self.editor.cursor_position = pos;
                self.preferred_x_cells = Some(x_cells);
                // Treat as an absolute move (similar to `MoveTo`).
                self.editor.secondary_selections.clear();
                Ok(CommandResult::Success)
            }
            CursorCommand::MoveToLineStart => {
                let line = self.editor.cursor_position.line;
                self.editor.cursor_position = Position::new(line, 0);
                self.preferred_x_cells = Some(0);
                self.editor.secondary_selections.clear();
                Ok(CommandResult::Success)
            }
            CursorCommand::MoveToLineEnd => {
                let line = self.editor.cursor_position.line;
                let end_col = self.clamp_column_for_line(line, usize::MAX);
                self.editor.cursor_position = Position::new(line, end_col);
                self.preferred_x_cells = self
                    .editor
                    .logical_position_to_visual(line, end_col)
                    .map(|(_, x)| x);
                self.editor.secondary_selections.clear();
                Ok(CommandResult::Success)
            }
            CursorCommand::MoveToVisualLineStart => {
                let line = self.editor.cursor_position.line;
                let Some(layout) = self.editor.layout_engine.get_line_layout(line) else {
                    return Ok(CommandResult::Success);
                };

                let line_text = self
                    .editor
                    .line_index
                    .get_line_text(line)
                    .unwrap_or_default();
                let line_char_len = line_text.chars().count();
                let column = self.editor.cursor_position.column.min(line_char_len);

                let mut seg_start = 0usize;
                for wp in &layout.wrap_points {
                    if column >= wp.char_index {
                        seg_start = wp.char_index;
                    } else {
                        break;
                    }
                }

                self.editor.cursor_position = Position::new(line, seg_start);
                self.preferred_x_cells = self
                    .editor
                    .logical_position_to_visual(line, seg_start)
                    .map(|(_, x)| x);
                self.editor.secondary_selections.clear();
                Ok(CommandResult::Success)
            }
            CursorCommand::MoveToVisualLineEnd => {
                let line = self.editor.cursor_position.line;
                let Some(layout) = self.editor.layout_engine.get_line_layout(line) else {
                    return Ok(CommandResult::Success);
                };

                let line_text = self
                    .editor
                    .line_index
                    .get_line_text(line)
                    .unwrap_or_default();
                let line_char_len = line_text.chars().count();
                let column = self.editor.cursor_position.column.min(line_char_len);

                let mut seg_end = line_char_len;
                for wp in &layout.wrap_points {
                    if column < wp.char_index {
                        seg_end = wp.char_index;
                        break;
                    }
                }

                self.editor.cursor_position = Position::new(line, seg_end);
                self.preferred_x_cells = self
                    .editor
                    .logical_position_to_visual(line, seg_end)
                    .map(|(_, x)| x);
                self.editor.secondary_selections.clear();
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
            CursorCommand::SelectLine => self.execute_select_line_command(),
            CursorCommand::SelectWord => self.execute_select_word_command(),
            CursorCommand::ExpandSelection => self.execute_expand_selection_command(),
            CursorCommand::AddCursorAbove => self.execute_add_cursor_vertical_command(true),
            CursorCommand::AddCursorBelow => self.execute_add_cursor_vertical_command(false),
            CursorCommand::AddNextOccurrence { options } => {
                self.execute_add_next_occurrence_command(options)
            }
            CursorCommand::AddAllOccurrences { options } => {
                self.execute_add_all_occurrences_command(options)
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
            ViewCommand::SetWrapMode { mode } => {
                self.editor.layout_engine.set_wrap_mode(mode);
                Ok(CommandResult::Success)
            }
            ViewCommand::SetWrapIndent { indent } => {
                self.editor.layout_engine.set_wrap_indent(indent);
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
                let generator = SnapshotGenerator::from_text_with_layout_options(
                    &text,
                    self.editor.viewport_width,
                    self.editor.layout_engine.tab_width(),
                    self.editor.layout_engine.wrap_mode(),
                    self.editor.layout_engine.wrap_indent(),
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
