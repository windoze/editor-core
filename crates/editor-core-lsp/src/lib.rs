#![warn(missing_docs)]
//! `editor-core-lsp` - LSP integration for `editor-core`.
//!
//! This crate contains LSP-specific utilities (UTF-16 coordinate conversion, semantic tokens
//! decoding, JSON-RPC stdio framing) plus optional higher-level helpers for wiring an
//! `editor_core::EditorStateManager` to an LSP server.

pub mod editor;
pub mod lsp_client;
pub mod lsp_completion;
pub mod lsp_decorations;
pub mod lsp_events;
pub mod lsp_highlights;
pub mod lsp_locations;
pub mod lsp_sync;
pub mod lsp_text_edits;
pub mod lsp_transport;
pub mod lsp_uri;
pub mod workspace_sync;

pub use editor::{
    LspContentChange, LspDocument, LspServerInfo, LspSession, LspSessionStartOptions,
    SemanticTokensLegend, clear_lsp_state, lsp_clear_edits, lsp_diagnostics_to_processing_edits,
};
pub use lsp_client::{LspClient, LspInbound, LspOutbound};
pub use lsp_completion::{
    CompletionTextEditMode, apply_completion_item, completion_item_to_text_edit_specs,
};
pub use lsp_decorations::{
    lsp_code_lens_to_decorations, lsp_code_lens_to_processing_edit,
    lsp_document_links_to_decorations, lsp_document_links_to_processing_edit,
    lsp_inlay_hints_to_decorations, lsp_inlay_hints_to_processing_edit,
};
pub use lsp_events::{
    LspDiagnostic, LspDiagnosticSeverity, LspEvent, LspLogMessageParams, LspMessageType,
    LspNotification, LspProgressParams, LspPublishDiagnosticsParams, LspResponse, LspResponseError,
    LspServerRequest, LspServerRequestMode, LspServerRequestPolicy, LspShowMessageParams,
};
pub use lsp_highlights::{
    lsp_document_highlights_to_intervals, lsp_document_highlights_to_processing_edit,
};
pub use lsp_locations::{LspLocation, locations_from_value};
pub use lsp_sync::{
    DeltaCalculator, LspCoordinateConverter, LspPosition, LspRange, SemanticToken,
    SemanticTokensError, SemanticTokensManager, TextChange, decode_semantic_style_id,
    encode_semantic_style_id, semantic_tokens_to_intervals,
};
pub use lsp_text_edits::{
    LspTextEdit, apply_text_edits, char_offsets_for_lsp_range, text_edits_from_value,
    workspace_edit_text_edits, workspace_edit_text_edits_for_uri,
};
pub use lsp_transport::{read_lsp_message, write_lsp_message};
pub use lsp_uri::{file_uri_to_path, path_to_file_uri, percent_decode_path, percent_encode_path};
pub use workspace_sync::{
    AppliedWorkspaceEditDocument, ApplyWorkspaceEditResult, LspWorkspaceSync,
};
