//! C/FFI bridge for `editor-core` and integration crates.
//!
//! This crate exposes a C ABI focused on native host integrations (Windows/macOS/Linux).
//! Complex payloads use UTF-8 JSON strings for forward-compatible schema evolution.

use editor_core::commands::{
    Command, CommandResult, CursorCommand, EditCommand, ExpandSelectionDirection,
    ExpandSelectionUnit, Position, Selection, SelectionDirection, StyleCommand, TabKeyBehavior,
    TextEditSpec, ViewCommand,
};
use editor_core::decorations::{
    Decoration, DecorationKind, DecorationLayerId, DecorationPlacement, DecorationRange,
};
use editor_core::diagnostics::{Diagnostic, DiagnosticRange, DiagnosticSeverity};
use editor_core::processing::{DocumentProcessor, ProcessingEdit};
use editor_core::snapshot::{
    Cell, ComposedCell, ComposedCellSource, ComposedGrid, ComposedLine, ComposedLineKind,
    HeadlessGrid, HeadlessLine, MinimapGrid, MinimapLine,
};
use editor_core::state::{
    CursorState, DecorationsState, DiagnosticsState, DocumentState, EditorState,
    EditorStateManager, FoldingState, StyleState, UndoRedoState, ViewportState,
};
use editor_core::symbols::{
    DocumentOutline, DocumentSymbol, SymbolKind, SymbolLocation, SymbolRange, Utf16Position,
    Utf16Range, WorkspaceSymbol,
};
use editor_core::workspace::{
    BufferId, OpenBufferResult, ViewId, ViewSmoothScrollState, Workspace, WorkspaceSearchResult,
    WorkspaceViewportState,
};
use editor_core::{
    AutoPair, AutoPairsConfig, FoldRegion, IndentStyle, IndentationConfig, Interval, LineEnding,
    SearchMatch, SearchOptions, StyleLayerId, WrapIndent, WrapMode,
};
use editor_core_lsp::{
    CompletionTextEditMode, LspCoordinateConverter, apply_completion_item, apply_text_edits,
    completion_item_to_text_edit_specs, decode_semantic_style_id, encode_semantic_style_id,
    file_uri_to_path, locations_from_value, lsp_code_lens_to_processing_edit,
    lsp_diagnostics_to_processing_edits, lsp_document_highlights_to_processing_edit,
    lsp_document_links_to_processing_edit, lsp_document_symbols_to_processing_edit,
    lsp_formatting_options, lsp_formatting_options_for_indentation_config,
    lsp_inlay_hints_to_processing_edit, lsp_workspace_symbols_to_results, path_to_file_uri,
    percent_decode_path, percent_encode_path, semantic_tokens_to_intervals, text_edits_from_value,
};
use editor_core_sublime::{SublimeProcessor, SublimeScopeMapper, SublimeSyntaxSet};
use editor_core_treesitter::{
    TreeSitterIndenter, TreeSitterIndenterConfig, TreeSitterLanguage, TreeSitterProcessor,
    TreeSitterProcessorConfig, TreeSitterUpdateMode,
};
use serde::Deserialize;
use serde_json::{Value, json};
use std::cell::RefCell;
use std::collections::BTreeMap;
use std::ffi::{CStr, CString, c_char};
use std::mem::size_of;
use std::path::Path;
use std::ptr;
use std::slice;

mod json_bridge;
use json_bridge::*;
mod abi_features;
mod binary_abi;
mod editor_state_abi;
mod lsp_abi;
mod processors_abi;
mod support;
mod types;
mod viewport_blob;
mod workspace_abi;

pub(crate) use support::*;
pub use types::*;
pub(crate) use viewport_blob::*;

pub use abi_features::*;
pub use binary_abi::*;
pub use editor_state_abi::*;
pub use lsp_abi::*;
pub use processors_abi::*;
pub use workspace_abi::*;
