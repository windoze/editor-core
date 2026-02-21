#![warn(missing_docs)]
//! Editor Core - Industrial-Grade Headless Code Editor Kernel
//!
//! # Overview
//!
//! `editor-core` is a headless code editor kernel focused on state management, text metrics, and coordinate transformations.
//! It does not involve the rendering process, assuming the upper layer provides a"text grid"(Text Grid)based view renderer, Support Unicode wide characters.
//!
//! # Core Features
//!
//! - **Efficient Text Storage**: based Piece Table  O(1) insertion/deletion
//! - **Fast Line Index**: based Rope  O(log n) line access
//! - **Soft Wrapping Support**: Headless layout engine, supporting arbitrary container widths
//! - **Style Management**: Interval tree structure, O(log n + k) query complexity
//! - **Code Folding**: Supports arbitrary levels of code folding
//! - **State Tracking**: Version number mechanism and Change Notifications system
//!
//! # Architecture Layers
//!
//! ```text
//! ┌─────────────────────────────────────────────┐
//! │  Command Interface & State Management       │  ← Public API
//! ├─────────────────────────────────────────────┤
//! │  Snapshot API (HeadlessGrid)                │  ← Rendering Data
//! ├─────────────────────────────────────────────┤
//! │  Intervals & Visibility (Styles + Folding)  │  ← Visual Enhancement
//! ├─────────────────────────────────────────────┤
//! │  Layout Engine (Soft Wrapping)              │  ← Text Layout
//! ├─────────────────────────────────────────────┤
//! │  Line Index (Rope-based)                    │  ← Line Access
//! ├─────────────────────────────────────────────┤
//! │  Piece Table Storage                        │  ← Text Storage
//! └─────────────────────────────────────────────┘
//! ```
//!
//! # Quick Start
//!
//! ## Using Command Interface
//!
//! ```rust
//! use editor_core::{CommandExecutor, Command, EditCommand, CursorCommand, Position};
//!
//! let mut executor = CommandExecutor::empty(80);
//!
//! // Insert text
//! executor.execute(Command::Edit(EditCommand::Insert {
//!     offset: 0,
//!     text: "fn main() {\n    println!(\"Hello\");\n}\n".to_string(),
//! })).unwrap();
//!
//! // Move cursor
//! executor.execute(Command::Cursor(CursorCommand::MoveTo {
//!     line: 1,
//!     column: 4,
//! })).unwrap();
//!
//! assert_eq!(executor.editor().cursor_position(), Position::new(1, 4));
//! ```
//!
//! ## Using State Management
//!
//! ```rust
//! use editor_core::{EditorStateManager, StateChangeType};
//!
//! let mut manager = EditorStateManager::new("Initial text", 80);
//!
//! // Subscribe toState changed
//! manager.subscribe(|change| {
//!     println!("State changed: {:?}", change.change_type);
//! });
//!
//! // Query state
//! let doc_state = manager.get_document_state();
//! println!("Line count: {}, Characters: {}", doc_state.line_count, doc_state.char_count);
//! ```
//!
//! # Module Description
//!
//! - [`storage`] - Piece Table text storage layer
//! - [`line_index`] - Rope based line index
//! - [`layout`] - soft wrappinglayout engine
//! - [`intervals`] - Style interval tree andcode foldingmanagement
//! - [`snapshot`] - Headless snapshot API (HeadlessGrid)
//! - [`commands`] - Unified command interface
//! - [`state`] - State management and query interface
//!
//! # Performance Goals
//!
//! - **Loading**: 1000 line document < 100ms
//! - **insertion**: 100 random insertions < 100ms
//! - **line access**: 1000 line accesses < 10ms
//! - **Memory**: 100 modifications, memory growth limited to AddBuffer size
//!
//! # Unicode Support
//!
//! - UTF-8 internal encoding
//! - Proper handling of CJK double-width characters
//! - Support Grapheme Clusters (Emoji combinations)
//! - via `editor-core-lsp` provides UTF-16 code unit coordinate conversion (for upper-layer protocols/integrations)
//! - via `editor-core-sublime` provides `.sublime-syntax` syntax highlighting and folding (optional integration)

pub mod commands;
pub mod decorations;
pub mod delta;
pub mod diagnostics;
pub mod intervals;
pub mod layout;
pub mod line_ending;
pub mod line_index;
pub mod processing;
pub mod search;
mod selection_set;
pub mod snapshot;
pub mod state;
pub mod storage;
mod text;

pub use commands::{
    Command, CommandError, CommandExecutor, CommandResult, CursorCommand, EditCommand, EditorCore,
    Position, Selection, SelectionDirection, StyleCommand, TabKeyBehavior, ViewCommand,
};
pub use decorations::{
    Decoration, DecorationKind, DecorationLayerId, DecorationPlacement, DecorationRange,
};
pub use delta::{TextDelta, TextDeltaEdit};
pub use diagnostics::{Diagnostic, DiagnosticRange, DiagnosticSeverity};
pub use intervals::{FOLD_PLACEHOLDER_STYLE_ID, FoldingManager, IntervalTree, StyleLayerId};
pub use layout::{LayoutEngine, WrapIndent, WrapMode};
pub use line_ending::LineEnding;
pub use line_index::LineIndex;
pub use processing::{DocumentProcessor, ProcessingEdit};
pub use search::{SearchError, SearchMatch, SearchOptions};
pub use snapshot::{Cell, HeadlessGrid, HeadlessLine, SnapshotGenerator};
pub use state::{
    CursorState, DecorationsState, DiagnosticsState, DocumentState, EditorState,
    EditorStateManager, FoldingState, StateChange, StateChangeCallback, StateChangeType,
    StyleState, UndoRedoState, ViewportState,
};
pub use storage::PieceTable;
