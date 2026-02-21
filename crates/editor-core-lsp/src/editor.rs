//! High-level LSP session integration for `editor-core`.
//!
//! This module provides [`LspSession`], a small runtime-agnostic helper that:
//! - spawns an LSP server over stdio
//! - drives `initialize` / `initialized` / document open/change/save notifications
//! - polls server messages and converts semantic tokens / folding ranges into
//!   [`editor_core::processing::ProcessingEdit`] values
//!
//! The API intentionally uses `serde_json::Value` instead of `lsp-types` to keep the dependency
//! surface small and allow consumers to shape payloads as needed.

use crate::lsp_client::{LspClient, LspInbound};
use crate::lsp_events::{
    LspEvent, LspNotification, LspResponse, LspResponseError, LspServerRequest,
    LspServerRequestPolicy,
};
use crate::lsp_sync::{
    LspCoordinateConverter, LspPosition, LspRange, encode_semantic_style_id,
    semantic_tokens_to_intervals,
};
use crate::lsp_text_edits::{apply_text_edits, workspace_edit_text_edits_for_uri};
use editor_core::intervals::{FoldRegion, Interval, StyleId};
use editor_core::processing::{DocumentProcessor, ProcessingEdit};
use editor_core::{
    Diagnostic, DiagnosticRange, DiagnosticSeverity, EditorStateManager, LineIndex, StyleLayerId,
};
use serde_json::{Value, json};
use std::collections::{HashMap, VecDeque};
use std::io;
use std::process::Command as ProcessCommand;
use std::time::{Duration, Instant};

/// Clear LSP-derived state in the editor:
/// - `StyleLayerId::SEMANTIC_TOKENS`
/// - `StyleLayerId::DIAGNOSTICS`
/// - all folding regions (typically sourced from LSP `foldingRange`)
pub fn lsp_clear_edits() -> Vec<ProcessingEdit> {
    vec![
        ProcessingEdit::ClearStyleLayer {
            layer: StyleLayerId::SEMANTIC_TOKENS,
        },
        ProcessingEdit::ClearStyleLayer {
            layer: StyleLayerId::DIAGNOSTICS,
        },
        ProcessingEdit::ClearDiagnostics,
        ProcessingEdit::ClearFoldingRegions,
    ]
}

/// Apply [`lsp_clear_edits`] to the given editor state manager.
pub fn clear_lsp_state(state_manager: &mut EditorStateManager) {
    state_manager.apply_processing_edits(lsp_clear_edits());
}

#[derive(Debug, Clone)]
/// Semantic tokens legend returned by the server during `initialize`.
pub struct SemanticTokensLegend {
    /// Token type names, indexed by `token_type` in `semanticTokens` data.
    pub token_types: Vec<String>,
    /// Token modifier names, indexed by bit position in `token_modifiers`.
    pub token_modifiers: Vec<String>,
}

#[derive(Debug, Clone)]
/// A document tracked by the LSP session.
pub struct LspDocument {
    /// Document URI (e.g. `file:///...`).
    pub uri: String,
    /// LSP `languageId` (e.g. `"rust"`).
    pub language_id: String,
    /// Document version used for `didOpen` / `didChange`.
    pub version: i32,
}

#[derive(Debug, Clone)]
/// Information about the connected LSP server (from `initialize` response).
pub struct LspServerInfo {
    /// Server name.
    pub name: String,
    /// Optional server version string.
    pub version: Option<String>,
}

#[derive(Debug, Clone)]
/// A single `textDocument/didChange` content change (range + replacement text).
pub struct LspContentChange {
    /// Changed range.
    pub range: LspRange,
    /// Replacement text.
    pub text: String,
}

#[derive(Debug, Clone, Copy)]
/// Options controlling automatic background refreshes.
pub struct LspAutoRefreshOptions {
    /// If `true`, refresh semantic tokens after edits.
    pub semantic_tokens: bool,
    /// If `true`, refresh folding ranges after edits.
    pub folding_ranges: bool,
    /// Delay between an edit and issuing refresh requests.
    pub delay: Duration,
}

impl Default for LspAutoRefreshOptions {
    fn default() -> Self {
        Self {
            semantic_tokens: true,
            folding_ranges: true,
            delay: Duration::from_millis(150),
        }
    }
}

#[derive(Debug)]
/// Options used to spawn and initialize an [`LspSession`].
pub struct LspSessionStartOptions {
    /// Server command to spawn (caller-configured; include args/env/stderr as desired).
    pub cmd: ProcessCommand,
    /// Workspace folders returned by `workspace/workspaceFolders` (used by `LspClient` request
    /// handling). This does not automatically update `initialize_params`.
    pub workspace_folders: Vec<Value>,
    /// The exact JSON params for the `initialize` request.
    pub initialize_params: Value,
    /// Timeout for waiting for the `initialize` response.
    pub initialize_timeout: Duration,
    /// The document to open.
    pub document: LspDocument,
    /// Initial full text to send in `textDocument/didOpen`.
    pub initial_text: String,
}

#[derive(Debug, Clone, Copy)]
enum PendingLspRequest {
    SemanticTokens { version: i32 },
    FoldingRanges { version: i32 },
}

/// A small, runtime-agnostic LSP integration for `editor-core`.
///
/// This is designed to be generic across LSP servers:
/// - the caller provides `initialize` parameters (capabilities, rootUri, workspace folders, etc.)
/// - semantic token legend is read from the server's `initialize` response
pub struct LspSession {
    client: LspClient,
    document: LspDocument,
    extra_documents: HashMap<String, LspDocument>,

    server_info: Option<LspServerInfo>,
    server_capabilities: Value,

    semantic_legend: Option<SemanticTokensLegend>,
    supports_semantic_tokens: bool,
    supports_semantic_tokens_delta: bool,
    supports_folding_range: bool,

    pending: HashMap<u64, PendingLspRequest>,
    pending_client_requests: HashMap<u64, String>,
    refresh_due: Option<Instant>,
    auto_refresh: LspAutoRefreshOptions,

    semantic_tokens_result_id: Option<String>,
    semantic_tokens_data: Vec<u32>,

    // Headless UX + deferred server->client requests.
    events: VecDeque<LspEvent>,
    event_queue_capacity: usize,
    server_request_policy: LspServerRequestPolicy,
    deferred_requests: HashMap<u64, LspServerRequest>,
}

impl LspSession {
    /// Spawn an LSP server, run `initialize`, and send `textDocument/didOpen`.
    ///
    /// This is a convenience entry point for starting a session. The exact `initialize` payload is
    /// supplied by the caller via [`LspSessionStartOptions::initialize_params`].
    pub fn start(opts: LspSessionStartOptions) -> io::Result<Self> {
        let LspSessionStartOptions {
            cmd,
            workspace_folders,
            initialize_params,
            initialize_timeout,
            document,
            initial_text,
        } = opts;

        let mut client = LspClient::spawn(cmd, workspace_folders)?;

        let init_id = client.request("initialize", initialize_params)?;
        let init_resp = client.wait_for_response(init_id, initialize_timeout)?;

        let result = init_resp.get("result").cloned().unwrap_or(Value::Null);
        let server_info = parse_server_info(&result);
        let server_capabilities = result.get("capabilities").cloned().unwrap_or(Value::Null);

        let (supports_semantic_tokens, semantic_legend) =
            parse_semantic_tokens_legend(&server_capabilities);
        let supports_semantic_tokens_delta =
            parse_supports_semantic_tokens_delta(&server_capabilities);
        let supports_folding_range = parse_supports_folding_range(&server_capabilities);

        client.notify("initialized", json!({}))?;

        client.notify(
            "textDocument/didOpen",
            json!({
                "textDocument": {
                    "uri": document.uri.clone(),
                    "languageId": document.language_id.clone(),
                    "version": document.version,
                    "text": initial_text,
                }
            }),
        )?;

        let mut session = Self {
            client,
            document,
            extra_documents: HashMap::new(),
            server_info,
            server_capabilities,
            semantic_legend,
            supports_semantic_tokens,
            supports_semantic_tokens_delta,
            supports_folding_range,
            pending: HashMap::new(),
            pending_client_requests: HashMap::new(),
            refresh_due: None,
            auto_refresh: LspAutoRefreshOptions::default(),
            semantic_tokens_result_id: None,
            semantic_tokens_data: Vec::new(),
            events: VecDeque::new(),
            event_queue_capacity: 256,
            server_request_policy: LspServerRequestPolicy::default(),
            deferred_requests: HashMap::new(),
        };

        session.schedule_refresh(Duration::from_millis(0));
        Ok(session)
    }

    /// Get a reference to the underlying stdio JSON-RPC client.
    pub fn client(&self) -> &LspClient {
        &self.client
    }

    /// Get a mutable reference to the underlying stdio JSON-RPC client.
    pub fn client_mut(&mut self) -> &mut LspClient {
        &mut self.client
    }

    /// Send a JSON-RPC/LSP notification to the server.
    pub fn notify(&mut self, method: &str, params: Value) -> Result<(), String> {
        self.client
            .notify(method, params)
            .map_err(|err| format!("LSP notify 失败 ({}): {}", method, err))
    }

    /// Send a JSON-RPC/LSP request to the server, returning its request id.
    ///
    /// The eventual response is delivered via [`LspEvent::Response`] and can be consumed by
    /// calling [`LspSession::drain_events`].
    pub fn request(&mut self, method: &str, params: Value) -> Result<u64, String> {
        let id = self
            .client
            .request(method, params)
            .map_err(|err| format!("LSP request 失败 ({}): {}", method, err))?;

        self.pending_client_requests.insert(id, method.to_string());
        Ok(id)
    }

    /// Get the active document tracked by this session.
    pub fn document(&self) -> &LspDocument {
        &self.document
    }

    /// Iterate over all documents tracked by this session (active + extra).
    pub fn documents(&self) -> impl Iterator<Item = &LspDocument> {
        std::iter::once(&self.document).chain(self.extra_documents.values())
    }

    /// Look up a tracked document by URI.
    pub fn document_for_uri(&self, uri: &str) -> Option<&LspDocument> {
        if self.document.uri == uri {
            Some(&self.document)
        } else {
            self.extra_documents.get(uri)
        }
    }

    /// Server information parsed from the `initialize` response.
    pub fn server_info(&self) -> Option<&LspServerInfo> {
        self.server_info.as_ref()
    }

    /// Raw `capabilities` JSON from the `initialize` response.
    pub fn server_capabilities(&self) -> &Value {
        &self.server_capabilities
    }

    /// Semantic tokens legend (if supported by the server).
    pub fn semantic_legend(&self) -> Option<&SemanticTokensLegend> {
        self.semantic_legend.as_ref()
    }

    /// The last semantic tokens `resultId` received from the server (for delta requests).
    pub fn semantic_tokens_result_id(&self) -> Option<&str> {
        self.semantic_tokens_result_id.as_deref()
    }

    /// Returns `true` if the server advertises `semanticTokensProvider`.
    pub fn supports_semantic_tokens(&self) -> bool {
        self.supports_semantic_tokens
    }

    /// Returns `true` if the server supports semantic tokens delta requests.
    pub fn supports_semantic_tokens_delta(&self) -> bool {
        self.supports_semantic_tokens_delta
    }

    /// Returns `true` if the server supports folding ranges.
    pub fn supports_folding_range(&self) -> bool {
        self.supports_folding_range
    }

    /// Get the current auto-refresh options.
    pub fn auto_refresh_options(&self) -> LspAutoRefreshOptions {
        self.auto_refresh
    }

    /// Set auto-refresh options (semantic tokens and folding ranges).
    pub fn set_auto_refresh_options(&mut self, opts: LspAutoRefreshOptions) {
        self.auto_refresh = opts;
    }

    /// Configure how server->client requests are handled.
    ///
    /// - The default is [`LspServerRequestPolicy::auto_reply`], which responds immediately with
    ///   safe defaults.
    /// - Deferring requests without responding later can deadlock an LSP server.
    pub fn set_server_request_policy(&mut self, policy: LspServerRequestPolicy) {
        self.server_request_policy = policy;
    }

    /// Get the current server->client request policy.
    pub fn server_request_policy(&self) -> &LspServerRequestPolicy {
        &self.server_request_policy
    }

    /// Set the maximum number of queued [`LspEvent`] items.
    ///
    /// When the queue is full, the oldest events are dropped.
    /// Set to `0` to disable event capture.
    pub fn set_event_queue_capacity(&mut self, capacity: usize) {
        self.event_queue_capacity = capacity;
        while self.events.len() > self.event_queue_capacity {
            self.events.pop_front();
        }
    }

    /// Get the maximum number of queued [`LspEvent`] values.
    pub fn event_queue_capacity(&self) -> usize {
        self.event_queue_capacity
    }

    /// Drain captured LSP events (UX notifications + deferred server requests).
    pub fn drain_events(&mut self) -> Vec<LspEvent> {
        let mut out = Vec::with_capacity(self.events.len());
        while let Some(event) = self.events.pop_front() {
            out.push(event);
        }
        out
    }

    /// Respond to a deferred server->client request with a JSON result.
    pub fn respond_to_server_request(&mut self, id: u64, result: Value) -> Result<(), String> {
        self.deferred_requests.remove(&id);
        self.client
            .respond(id, result)
            .map_err(|err| format!("LSP respond 失败: {}", err))
    }

    /// Respond to a deferred server->client request with an error response.
    pub fn respond_to_server_request_error(
        &mut self,
        id: u64,
        code: i64,
        message: impl Into<String>,
        data: Option<Value>,
    ) -> Result<(), String> {
        self.deferred_requests.remove(&id);
        self.client
            .respond_error(id, code, message, data)
            .map_err(|err| format!("LSP respond_error 失败: {}", err))
    }

    /// Schedule a background refresh (semantic tokens / folding ranges) after `delay`.
    pub fn schedule_refresh(&mut self, delay: Duration) {
        self.refresh_due = Some(Instant::now() + delay);
    }

    /// Construct an [`LspContentChange`] from character offsets in the document.
    pub fn content_change_for_offsets(
        &self,
        line_index: &LineIndex,
        start_offset: usize,
        end_offset: usize,
        text: impl Into<String>,
    ) -> LspContentChange {
        let start_pos = lsp_position_for_offset(line_index, start_offset);
        let end_pos = lsp_position_for_offset(line_index, end_offset);
        LspContentChange {
            range: LspRange::new(start_pos, end_pos),
            text: text.into(),
        }
    }

    /// Construct a full-document replacement change.
    pub fn full_document_change(
        &self,
        line_index: &LineIndex,
        old_char_count: usize,
        new_text: impl Into<String>,
    ) -> LspContentChange {
        self.content_change_for_offsets(line_index, 0, old_char_count, new_text)
    }

    /// Send `textDocument/didChange` for the active document.
    pub fn did_change(&mut self, change: LspContentChange) -> Result<(), String> {
        self.document.version = self.document.version.saturating_add(1);

        let params = json!({
            "textDocument": {
                "uri": self.document.uri.as_str(),
                "version": self.document.version,
            },
            "contentChanges": [{
                "range": lsp_range_to_json(&change.range),
                "text": change.text,
            }],
        });

        if let Err(err) = self.client.notify("textDocument/didChange", params) {
            return Err(format!("LSP didChange 失败，已禁用: {}", err));
        }

        self.schedule_refresh(self.auto_refresh.delay);
        Ok(())
    }

    /// Send `textDocument/didOpen` for a new document and track its version.
    ///
    /// This enables multi-document LSP sessions while keeping a single "active" document
    /// (accessible via [`LspSession::document`]).
    pub fn open_document(
        &mut self,
        document: LspDocument,
        initial_text: String,
    ) -> Result<(), String> {
        self.notify(
            "textDocument/didOpen",
            json!({
                "textDocument": {
                    "uri": document.uri.clone(),
                    "languageId": document.language_id.clone(),
                    "version": document.version,
                    "text": initial_text,
                }
            }),
        )?;

        if document.uri == self.document.uri {
            self.document = document;
        } else {
            self.extra_documents.insert(document.uri.clone(), document);
        }

        Ok(())
    }

    /// Switch the "active" document tracked by this session.
    ///
    /// Note: auto-refresh features (semantic tokens, folding ranges) run against the active
    /// document.
    pub fn set_active_document(&mut self, uri: &str) -> Result<(), String> {
        if self.document.uri == uri {
            return Ok(());
        }

        let Some(next) = self.extra_documents.remove(uri) else {
            return Err(format!("LSP document not found for uri={}", uri));
        };

        let prev = std::mem::replace(&mut self.document, next);
        self.extra_documents.insert(prev.uri.clone(), prev);
        self.clear_semantic_tokens_cache();
        self.schedule_refresh(Duration::from_millis(0));
        Ok(())
    }

    /// Send `textDocument/didClose` for a document.
    pub fn close_document(&mut self, uri: &str) -> Result<(), String> {
        self.notify(
            "textDocument/didClose",
            json!({ "textDocument": { "uri": uri } }),
        )?;

        if self.document.uri == uri {
            if let Some((next_uri, _)) = self.extra_documents.iter().next() {
                let next_uri = next_uri.clone();
                let next = self.extra_documents.remove(&next_uri).expect("checked");
                self.document = next;
                self.clear_semantic_tokens_cache();
                self.schedule_refresh(Duration::from_millis(0));
            }
        } else {
            self.extra_documents.remove(uri);
        }

        Ok(())
    }

    /// Send `textDocument/didChange` for a specific document URI.
    pub fn did_change_for_uri(
        &mut self,
        uri: &str,
        change: LspContentChange,
    ) -> Result<(), String> {
        if self.document.uri == uri {
            return self.did_change(change);
        }

        let (doc_uri, version) = {
            let Some(doc) = self.extra_documents.get_mut(uri) else {
                return Err(format!("LSP document not found for uri={}", uri));
            };
            doc.version = doc.version.saturating_add(1);
            (doc.uri.clone(), doc.version)
        };

        self.notify(
            "textDocument/didChange",
            json!({
                "textDocument": { "uri": doc_uri.as_str(), "version": version },
                "contentChanges": [{ "range": lsp_range_to_json(&change.range), "text": change.text }],
            }),
        )?;

        Ok(())
    }

    /// Send `textDocument/didSave` for a document (active by default).
    pub fn did_save(&mut self, text: Option<String>) -> Result<(), String> {
        let uri = self.document.uri.clone();
        self.did_save_for_uri(uri.as_str(), text)
    }

    /// Send `textDocument/didSave` for a specific document URI.
    pub fn did_save_for_uri(&mut self, uri: &str, text: Option<String>) -> Result<(), String> {
        let mut obj = serde_json::Map::new();
        obj.insert(
            "textDocument".to_string(),
            json!({
                "uri": uri,
            }),
        );
        if let Some(text) = text {
            obj.insert("text".to_string(), Value::String(text));
        }

        self.notify("textDocument/didSave", Value::Object(obj))
    }

    /// Send `textDocument/willSave` for a document (active by default).
    ///
    /// `reason` values are per LSP spec:
    /// - 1: Manual
    /// - 2: AfterDelay
    /// - 3: FocusOut
    pub fn will_save(&mut self, reason: i32) -> Result<(), String> {
        self.notify(
            "textDocument/willSave",
            json!({
                "textDocument": { "uri": self.document.uri.as_str() },
                "reason": reason,
            }),
        )
    }

    /// Request `textDocument/willSaveWaitUntil` for the active document.
    ///
    /// The response (an array of `TextEdit`) is delivered via [`LspEvent::Response`].
    pub fn request_will_save_wait_until(&mut self, reason: i32) -> Result<u64, String> {
        self.request(
            "textDocument/willSaveWaitUntil",
            json!({
                "textDocument": { "uri": self.document.uri.as_str() },
                "reason": reason,
            }),
        )
    }

    /// Notify `workspace/didChangeWatchedFiles`.
    ///
    /// `changes` items must be objects: `{ uri: string, type: 1|2|3 }`.
    pub fn did_change_watched_files(&mut self, changes: Vec<Value>) -> Result<(), String> {
        self.notify(
            "workspace/didChangeWatchedFiles",
            json!({
                "changes": changes,
            }),
        )
    }

    /// Notify `workspace/didChangeWorkspaceFolders`.
    ///
    /// `added`/`removed` items should follow the LSP `WorkspaceFolder` shape:
    /// `{ uri: string, name: string }`.
    pub fn did_change_workspace_folders(
        &mut self,
        added: Vec<Value>,
        removed: Vec<Value>,
    ) -> Result<(), String> {
        self.notify(
            "workspace/didChangeWorkspaceFolders",
            json!({
                "event": { "added": added, "removed": removed }
            }),
        )
    }

    /// Notify `workspace/didChangeConfiguration`.
    pub fn did_change_configuration(&mut self, settings: Value) -> Result<(), String> {
        self.notify(
            "workspace/didChangeConfiguration",
            json!({
                "settings": settings,
            }),
        )
    }

    /// Client-side request cancellation (`$/cancelRequest`).
    pub fn cancel_request(&mut self, request_id: u64) -> Result<(), String> {
        self.notify("$/cancelRequest", json!({ "id": request_id }))
    }

    /// Graceful shutdown: send `shutdown` request.
    ///
    /// The response is delivered via [`LspEvent::Response`], after which the host should call
    /// [`LspSession::exit`] (and terminate the server process if needed).
    pub fn shutdown(&mut self) -> Result<u64, String> {
        self.request("shutdown", Value::Null)
    }

    /// Graceful shutdown: send `exit` notification.
    pub fn exit(&mut self) -> Result<(), String> {
        self.notify("exit", Value::Null)
    }

    /// Apply an LSP `WorkspaceEdit` to the active document (best-effort).
    ///
    /// This is useful for implementing:
    /// - server->client `workspace/applyEdit`
    /// - code actions / rename / formatting that return `WorkspaceEdit`
    pub fn apply_workspace_edit(
        &mut self,
        state_manager: &mut EditorStateManager,
        workspace_edit: &Value,
    ) -> Result<Vec<(usize, usize)>, String> {
        let edits = workspace_edit_text_edits_for_uri(workspace_edit, self.document.uri.as_str());
        apply_text_edits(state_manager, &edits)
    }

    /// Convert an editor logical position (line/column) into an LSP UTF-16 position.
    pub fn lsp_position_for_editor_position(
        &self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> LspPosition {
        let line_text = line_index.get_line_text(line).unwrap_or_default();
        LspCoordinateConverter::position_to_lsp(&line_text, line, column)
    }

    /// Convert a character-offset range into an LSP range.
    pub fn lsp_range_for_editor_offsets(
        &self,
        line_index: &LineIndex,
        start_offset: usize,
        end_offset: usize,
    ) -> LspRange {
        let start_pos = lsp_position_for_offset(line_index, start_offset);
        let end_pos = lsp_position_for_offset(line_index, end_offset);
        LspRange::new(start_pos, end_pos)
    }

    fn text_document_position_params(
        &self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Value {
        let pos = self.lsp_position_for_editor_position(line_index, line, column);
        json!({
            "textDocument": { "uri": self.document.uri.as_str() },
            "position": { "line": pos.line, "character": pos.character },
        })
    }

    fn text_document_range_params(&self, range: &LspRange) -> Value {
        json!({
            "textDocument": { "uri": self.document.uri.as_str() },
            "range": lsp_range_to_json(range),
        })
    }

    /// Hover (`textDocument/hover`).
    pub fn request_hover(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.request(
            "textDocument/hover",
            self.text_document_position_params(line_index, line, column),
        )
    }

    /// Go to definition (`textDocument/definition`).
    pub fn request_definition(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.request(
            "textDocument/definition",
            self.text_document_position_params(line_index, line, column),
        )
    }

    /// Go to declaration (`textDocument/declaration`).
    pub fn request_declaration(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.request(
            "textDocument/declaration",
            self.text_document_position_params(line_index, line, column),
        )
    }

    /// Go to type definition (`textDocument/typeDefinition`).
    pub fn request_type_definition(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.request(
            "textDocument/typeDefinition",
            self.text_document_position_params(line_index, line, column),
        )
    }

    /// Go to implementation (`textDocument/implementation`).
    pub fn request_implementation(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.request(
            "textDocument/implementation",
            self.text_document_position_params(line_index, line, column),
        )
    }

    /// Find references (`textDocument/references`).
    pub fn request_references(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
        include_declaration: bool,
    ) -> Result<u64, String> {
        let mut params = self.text_document_position_params(line_index, line, column);
        if let Some(obj) = params.as_object_mut() {
            obj.insert(
                "context".to_string(),
                json!({ "includeDeclaration": include_declaration }),
            );
        }
        self.request("textDocument/references", params)
    }

    /// Document highlights (`textDocument/documentHighlight`).
    pub fn request_document_highlight(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.request(
            "textDocument/documentHighlight",
            self.text_document_position_params(line_index, line, column),
        )
    }

    /// Call hierarchy prepare (`textDocument/prepareCallHierarchy`).
    pub fn request_prepare_call_hierarchy(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.request(
            "textDocument/prepareCallHierarchy",
            self.text_document_position_params(line_index, line, column),
        )
    }

    /// Call hierarchy incoming calls (`callHierarchy/incomingCalls`).
    pub fn request_call_hierarchy_incoming_calls(&mut self, item: Value) -> Result<u64, String> {
        self.request("callHierarchy/incomingCalls", json!({ "item": item }))
    }

    /// Call hierarchy outgoing calls (`callHierarchy/outgoingCalls`).
    pub fn request_call_hierarchy_outgoing_calls(&mut self, item: Value) -> Result<u64, String> {
        self.request("callHierarchy/outgoingCalls", json!({ "item": item }))
    }

    /// Type hierarchy prepare (`textDocument/prepareTypeHierarchy`).
    pub fn request_prepare_type_hierarchy(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.request(
            "textDocument/prepareTypeHierarchy",
            self.text_document_position_params(line_index, line, column),
        )
    }

    /// Type hierarchy supertypes (`typeHierarchy/supertypes`).
    pub fn request_type_hierarchy_supertypes(&mut self, item: Value) -> Result<u64, String> {
        self.request("typeHierarchy/supertypes", json!({ "item": item }))
    }

    /// Type hierarchy subtypes (`typeHierarchy/subtypes`).
    pub fn request_type_hierarchy_subtypes(&mut self, item: Value) -> Result<u64, String> {
        self.request("typeHierarchy/subtypes", json!({ "item": item }))
    }

    /// Completion list (`textDocument/completion`).
    pub fn request_completion(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.request(
            "textDocument/completion",
            self.text_document_position_params(line_index, line, column),
        )
    }

    /// Completion item resolve (`completionItem/resolve`).
    pub fn request_completion_item_resolve(&mut self, item: Value) -> Result<u64, String> {
        self.request("completionItem/resolve", item)
    }

    /// Signature help (`textDocument/signatureHelp`).
    pub fn request_signature_help(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.request(
            "textDocument/signatureHelp",
            self.text_document_position_params(line_index, line, column),
        )
    }

    /// Inlay hints (`textDocument/inlayHint`).
    pub fn request_inlay_hints(
        &mut self,
        line_index: &LineIndex,
        start_offset: usize,
        end_offset: usize,
    ) -> Result<u64, String> {
        let range = self.lsp_range_for_editor_offsets(line_index, start_offset, end_offset);
        self.request(
            "textDocument/inlayHint",
            self.text_document_range_params(&range),
        )
    }

    /// Inlay hint resolve (`inlayHint/resolve`).
    pub fn request_inlay_hint_resolve(&mut self, hint: Value) -> Result<u64, String> {
        self.request("inlayHint/resolve", hint)
    }

    /// Document symbols (`textDocument/documentSymbol`).
    pub fn request_document_symbols(&mut self) -> Result<u64, String> {
        self.request(
            "textDocument/documentSymbol",
            json!({ "textDocument": { "uri": self.document.uri.as_str() } }),
        )
    }

    /// Workspace symbol search (`workspace/symbol`).
    pub fn request_workspace_symbol(&mut self, query: impl Into<String>) -> Result<u64, String> {
        self.request("workspace/symbol", json!({ "query": query.into() }))
    }

    /// Workspace symbol resolve (`workspaceSymbol/resolve`).
    pub fn request_workspace_symbol_resolve(&mut self, item: Value) -> Result<u64, String> {
        self.request("workspaceSymbol/resolve", item)
    }

    /// Rename (`textDocument/rename`).
    pub fn request_rename(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
        new_name: impl Into<String>,
    ) -> Result<u64, String> {
        let mut params = self.text_document_position_params(line_index, line, column);
        if let Some(obj) = params.as_object_mut() {
            obj.insert("newName".to_string(), Value::String(new_name.into()));
        }
        self.request("textDocument/rename", params)
    }

    /// Prepare rename (`textDocument/prepareRename`).
    pub fn request_prepare_rename(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.request(
            "textDocument/prepareRename",
            self.text_document_position_params(line_index, line, column),
        )
    }

    /// Code actions (`textDocument/codeAction`).
    ///
    /// `context` should follow LSP `CodeActionContext` shape.
    pub fn request_code_action(
        &mut self,
        line_index: &LineIndex,
        start_offset: usize,
        end_offset: usize,
        context: Value,
    ) -> Result<u64, String> {
        let range = self.lsp_range_for_editor_offsets(line_index, start_offset, end_offset);
        let mut params = self.text_document_range_params(&range);
        if let Some(obj) = params.as_object_mut() {
            obj.insert("context".to_string(), context);
        }
        self.request("textDocument/codeAction", params)
    }

    /// Code action resolve (`codeAction/resolve`).
    pub fn request_code_action_resolve(&mut self, action: Value) -> Result<u64, String> {
        self.request("codeAction/resolve", action)
    }

    /// Execute command (`workspace/executeCommand`).
    pub fn request_execute_command(
        &mut self,
        command: impl Into<String>,
        arguments: Vec<Value>,
    ) -> Result<u64, String> {
        self.request(
            "workspace/executeCommand",
            json!({
                "command": command.into(),
                "arguments": arguments,
            }),
        )
    }

    /// Code lens (`textDocument/codeLens`).
    pub fn request_code_lens(&mut self) -> Result<u64, String> {
        self.request(
            "textDocument/codeLens",
            json!({ "textDocument": { "uri": self.document.uri.as_str() } }),
        )
    }

    /// Code lens resolve (`codeLens/resolve`).
    pub fn request_code_lens_resolve(&mut self, lens: Value) -> Result<u64, String> {
        self.request("codeLens/resolve", lens)
    }

    /// Document formatting (`textDocument/formatting`).
    ///
    /// `options` should follow LSP `FormattingOptions`.
    pub fn request_formatting(&mut self, options: Value) -> Result<u64, String> {
        self.request(
            "textDocument/formatting",
            json!({
                "textDocument": { "uri": self.document.uri.as_str() },
                "options": options,
            }),
        )
    }

    /// Range formatting (`textDocument/rangeFormatting`).
    pub fn request_range_formatting(
        &mut self,
        line_index: &LineIndex,
        start_offset: usize,
        end_offset: usize,
        options: Value,
    ) -> Result<u64, String> {
        let range = self.lsp_range_for_editor_offsets(line_index, start_offset, end_offset);
        let mut params = self.text_document_range_params(&range);
        if let Some(obj) = params.as_object_mut() {
            obj.insert("options".to_string(), options);
        }
        self.request("textDocument/rangeFormatting", params)
    }

    /// On-type formatting (`textDocument/onTypeFormatting`).
    pub fn request_on_type_formatting(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
        ch: impl Into<String>,
        options: Value,
    ) -> Result<u64, String> {
        let pos = self.lsp_position_for_editor_position(line_index, line, column);
        self.request(
            "textDocument/onTypeFormatting",
            json!({
                "textDocument": { "uri": self.document.uri.as_str() },
                "position": { "line": pos.line, "character": pos.character },
                "ch": ch.into(),
                "options": options,
            }),
        )
    }

    /// Semantic tokens delta (`textDocument/semanticTokens/full/delta`).
    pub fn request_semantic_tokens_delta(
        &mut self,
        previous_result_id: Option<String>,
    ) -> Result<u64, String> {
        let mut params = json!({ "textDocument": { "uri": self.document.uri.as_str() } });
        if let Some(prev) = previous_result_id
            && let Some(obj) = params.as_object_mut()
        {
            obj.insert("previousResultId".to_string(), Value::String(prev));
        }
        self.request("textDocument/semanticTokens/full/delta", params)
    }

    /// Semantic tokens range (`textDocument/semanticTokens/range`).
    pub fn request_semantic_tokens_range(&mut self, range: &LspRange) -> Result<u64, String> {
        self.request(
            "textDocument/semanticTokens/range",
            json!({
                "textDocument": { "uri": self.document.uri.as_str() },
                "range": lsp_range_to_json(range),
            }),
        )
    }

    /// Selection range (`textDocument/selectionRange`).
    ///
    /// `positions` are editor (line,column) pairs where column is a char offset within the line.
    pub fn request_selection_range(
        &mut self,
        line_index: &LineIndex,
        positions: &[(usize, usize)],
    ) -> Result<u64, String> {
        let lsp_positions = positions
            .iter()
            .map(|(line, col)| {
                let pos = self.lsp_position_for_editor_position(line_index, *line, *col);
                json!({ "line": pos.line, "character": pos.character })
            })
            .collect::<Vec<_>>();

        self.request(
            "textDocument/selectionRange",
            json!({
                "textDocument": { "uri": self.document.uri.as_str() },
                "positions": lsp_positions,
            }),
        )
    }

    /// Linked editing range (`textDocument/linkedEditingRange`).
    pub fn request_linked_editing_range(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.request(
            "textDocument/linkedEditingRange",
            self.text_document_position_params(line_index, line, column),
        )
    }

    /// Document links (`textDocument/documentLink`).
    pub fn request_document_links(&mut self) -> Result<u64, String> {
        self.request(
            "textDocument/documentLink",
            json!({ "textDocument": { "uri": self.document.uri.as_str() } }),
        )
    }

    /// Document link resolve (`documentLink/resolve`).
    pub fn request_document_link_resolve(&mut self, link: Value) -> Result<u64, String> {
        self.request("documentLink/resolve", link)
    }

    /// Pull diagnostics: document (`textDocument/diagnostic`).
    pub fn request_document_diagnostic(
        &mut self,
        previous_result_id: Option<String>,
    ) -> Result<u64, String> {
        let mut params = json!({ "textDocument": { "uri": self.document.uri.as_str() } });
        if let Some(prev) = previous_result_id
            && let Some(obj) = params.as_object_mut()
        {
            obj.insert("previousResultId".to_string(), Value::String(prev));
        }
        self.request("textDocument/diagnostic", params)
    }

    /// Pull diagnostics: workspace (`workspace/diagnostic`).
    pub fn request_workspace_diagnostic(
        &mut self,
        previous_result_ids: Vec<Value>,
    ) -> Result<u64, String> {
        self.request(
            "workspace/diagnostic",
            json!({ "previousResultIds": previous_result_ids }),
        )
    }

    /// Color provider (`textDocument/documentColor`).
    pub fn request_document_color(&mut self) -> Result<u64, String> {
        self.request(
            "textDocument/documentColor",
            json!({ "textDocument": { "uri": self.document.uri.as_str() } }),
        )
    }

    /// Color presentation (`textDocument/colorPresentation`).
    pub fn request_color_presentation(
        &mut self,
        range: &LspRange,
        color: Value,
    ) -> Result<u64, String> {
        self.request(
            "textDocument/colorPresentation",
            json!({
                "textDocument": { "uri": self.document.uri.as_str() },
                "range": lsp_range_to_json(range),
                "color": color,
            }),
        )
    }

    /// Poll the LSP connection and apply derived-state edits into `state_manager`.
    pub fn poll(&mut self, state_manager: &mut EditorStateManager) -> Result<(), String> {
        self.poll_with_handler(state_manager, |_| {})
    }

    /// Poll the LSP connection and apply derived-state edits into `state_manager`.
    ///
    /// This is a convenience wrapper around [`LspSession::poll_edits_with_handler`].
    pub fn poll_with_handler<F>(
        &mut self,
        state_manager: &mut EditorStateManager,
        on_unhandled_message: F,
    ) -> Result<(), String>
    where
        F: FnMut(Value),
    {
        let edits = self.poll_edits_with_handler(&*state_manager, on_unhandled_message)?;
        state_manager.apply_processing_edits(edits);
        Ok(())
    }

    /// Poll the LSP connection and return derived-state edits (semantic tokens, folding ranges).
    pub fn poll_edits(
        &mut self,
        state: &EditorStateManager,
    ) -> Result<Vec<ProcessingEdit>, String> {
        self.poll_edits_with_handler(state, |_| {})
    }

    /// Poll the LSP connection, returning derived-state edits (semantic tokens, folding ranges).
    ///
    /// `on_unhandled_message` receives any messages that are not:
    /// - server->client requests handled by `LspClient::handle_server_request`
    /// - responses to this session's own refresh requests (semanticTokens/foldingRange)
    ///
    /// Returns `Err(reason)` when the session should be considered unusable and disabled.
    pub fn poll_edits_with_handler<F>(
        &mut self,
        state: &EditorStateManager,
        mut on_unhandled_message: F,
    ) -> Result<Vec<ProcessingEdit>, String>
    where
        F: FnMut(Value),
    {
        let mut edits = Vec::<ProcessingEdit>::new();

        while let Some(inbound) = self.client.try_recv() {
            match inbound {
                LspInbound::IoError(err) => return Err(format!("LSP 连接已断开: {}", err)),
                LspInbound::Message(msg) => {
                    // server->client request: may be auto-replied or deferred.
                    if msg.get("method").is_some() && msg.get("id").is_some() {
                        if let Some(request) = LspServerRequest::from_json(&msg) {
                            if self.server_request_policy.should_defer(&request.method) {
                                self.deferred_requests.insert(request.id, request.clone());
                                self.push_event(LspEvent::DeferredRequest(request));
                                on_unhandled_message(msg);
                            } else if let Err(err) = self.client.handle_server_request(&msg) {
                                return Err(format!("LSP request 处理失败: {}", err));
                            } else {
                                // Some requests imply a follow-up client action.
                                if request.method.as_str() == "workspace/semanticTokens/refresh" {
                                    self.schedule_refresh(Duration::from_millis(0));
                                }
                            }
                        } else if let Err(err) = self.client.handle_server_request(&msg) {
                            return Err(format!("LSP request 处理失败: {}", err));
                        }
                        continue;
                    }

                    let maybe_id = msg.get("id").and_then(Value::as_u64);
                    if let Some(id) = maybe_id {
                        if let Some(pending) = self.pending.remove(&id) {
                            self.handle_pending_response(state, pending, &msg, &mut edits)?;
                            continue;
                        }

                        if let Some(method) = self.pending_client_requests.remove(&id) {
                            let result = msg.get("result").cloned();
                            let error = msg.get("error").and_then(|e| {
                                Some(LspResponseError {
                                    code: e.get("code")?.as_i64()?,
                                    message: e
                                        .get("message")
                                        .and_then(Value::as_str)
                                        .unwrap_or("")
                                        .to_string(),
                                    data: e.get("data").cloned(),
                                })
                            });

                            self.push_event(LspEvent::Response(LspResponse {
                                id,
                                method,
                                result,
                                error,
                            }));
                            continue;
                        }
                    }

                    // notifications: capture common UX-ish messages into the event queue.
                    if let Some(method) = msg.get("method").and_then(Value::as_str) {
                        let params = msg.get("params").unwrap_or(&Value::Null);
                        if let Some(notification) =
                            LspNotification::from_method_and_params(method, params)
                        {
                            if let LspNotification::PublishDiagnostics(diags) = &notification
                                && diags.uri == self.document.uri
                            {
                                edits.extend(lsp_diagnostics_to_processing_edits(
                                    &state.editor().line_index,
                                    diags,
                                ));
                            }
                            self.push_event(LspEvent::Notification(notification));
                        }
                    }

                    on_unhandled_message(msg);
                }
            }
        }

        self.maybe_refresh(&mut edits)?;
        Ok(edits)
    }

    fn push_event(&mut self, event: LspEvent) {
        if self.event_queue_capacity == 0 {
            return;
        }
        if self.events.len() == self.event_queue_capacity {
            self.events.pop_front();
        }
        self.events.push_back(event);
    }

    fn clear_semantic_tokens_cache(&mut self) {
        self.semantic_tokens_result_id = None;
        self.semantic_tokens_data.clear();
    }

    fn handle_semantic_tokens_result(
        &mut self,
        result: &Value,
        line_index: &LineIndex,
        edits: &mut Vec<ProcessingEdit>,
    ) {
        // Full response: { resultId?, data: u32[] }
        if let Some(data_arr) = result.get("data").and_then(Value::as_array) {
            let mut data = Vec::with_capacity(data_arr.len());
            for v in data_arr {
                if let Some(n) = v.as_u64() {
                    data.push(n as u32);
                }
            }

            self.semantic_tokens_result_id = result
                .get("resultId")
                .and_then(Value::as_str)
                .map(|s| s.to_string());
            self.semantic_tokens_data = data;

            if let Ok(intervals) = semantic_tokens_to_intervals(
                &self.semantic_tokens_data,
                line_index,
                encode_semantic_style_id,
            ) {
                edits.push(ProcessingEdit::ReplaceStyleLayer {
                    layer: StyleLayerId::SEMANTIC_TOKENS,
                    intervals,
                });
            }

            return;
        }

        // Delta response: { resultId?, edits: [{ start, deleteCount, data? }] }
        let Some(delta_edits) = result.get("edits").and_then(Value::as_array) else {
            return;
        };
        if self.semantic_tokens_data.is_empty() {
            // No baseline to apply the delta to; fall back to requesting full next refresh.
            self.clear_semantic_tokens_cache();
            return;
        }

        #[derive(Debug)]
        struct DeltaEdit {
            start: usize,
            delete_count: usize,
            data: Vec<u32>,
        }

        let mut parsed = Vec::<DeltaEdit>::new();
        for edit in delta_edits {
            let Some(start) = edit.get("start").and_then(Value::as_u64) else {
                continue;
            };
            let Some(delete_count) = edit.get("deleteCount").and_then(Value::as_u64) else {
                continue;
            };
            let data = edit
                .get("data")
                .and_then(Value::as_array)
                .map(|arr| {
                    arr.iter()
                        .filter_map(Value::as_u64)
                        .map(|n| n as u32)
                        .collect::<Vec<_>>()
                })
                .unwrap_or_default();

            parsed.push(DeltaEdit {
                start: start as usize,
                delete_count: delete_count as usize,
                data,
            });
        }

        // Apply in descending order to keep indices stable even if servers send unsorted edits.
        parsed.sort_by_key(|e| std::cmp::Reverse(e.start));

        let mut data = self.semantic_tokens_data.clone();
        for edit in parsed {
            if edit.start > data.len() {
                self.clear_semantic_tokens_cache();
                return;
            }
            let end = edit.start.saturating_add(edit.delete_count);
            if end > data.len() {
                self.clear_semantic_tokens_cache();
                return;
            }
            data.splice(edit.start..end, edit.data);
        }

        self.semantic_tokens_result_id = result
            .get("resultId")
            .and_then(Value::as_str)
            .map(|s| s.to_string());
        self.semantic_tokens_data = data;

        if let Ok(intervals) = semantic_tokens_to_intervals(
            &self.semantic_tokens_data,
            line_index,
            encode_semantic_style_id,
        ) {
            edits.push(ProcessingEdit::ReplaceStyleLayer {
                layer: StyleLayerId::SEMANTIC_TOKENS,
                intervals,
            });
        }
    }

    fn handle_pending_response(
        &mut self,
        state: &EditorStateManager,
        pending: PendingLspRequest,
        msg: &Value,
        edits: &mut Vec<ProcessingEdit>,
    ) -> Result<(), String> {
        match pending {
            PendingLspRequest::SemanticTokens { version } => {
                if version != self.document.version {
                    return Ok(());
                }

                let result = msg.get("result").cloned().unwrap_or(Value::Null);
                self.handle_semantic_tokens_result(&result, &state.editor().line_index, edits);
            }
            PendingLspRequest::FoldingRanges { version } => {
                if version != self.document.version {
                    return Ok(());
                }

                let regions =
                    folding_regions_from_lsp_value(msg.get("result").unwrap_or(&Value::Null));
                edits.push(ProcessingEdit::ReplaceFoldingRegions {
                    regions,
                    preserve_collapsed: true,
                });
            }
        }

        Ok(())
    }

    fn maybe_refresh(&mut self, edits: &mut Vec<ProcessingEdit>) -> Result<(), String> {
        let Some(due) = self.refresh_due else {
            return Ok(());
        };
        if Instant::now() < due {
            return Ok(());
        }

        self.refresh_due = None;

        let doc_uri = self.document.uri.clone();

        if self.auto_refresh.semantic_tokens {
            let has_pending_tokens = self.pending.values().any(|p| {
                    matches!(
                        p,
                    PendingLspRequest::SemanticTokens { version, .. } if *version == self.document.version
                    )
                });
            if self.supports_semantic_tokens && !has_pending_tokens {
                let (method, params) = if self.supports_semantic_tokens_delta
                    && self.semantic_tokens_result_id.is_some()
                {
                    (
                        "textDocument/semanticTokens/full/delta",
                        json!({
                            "textDocument": { "uri": doc_uri.clone() },
                            "previousResultId": self.semantic_tokens_result_id.clone().unwrap_or_default(),
                        }),
                    )
                } else {
                    (
                        "textDocument/semanticTokens/full",
                        json!({ "textDocument": { "uri": doc_uri.clone() } }),
                    )
                };

                match self.client.request(method, params) {
                    Ok(id) => {
                        self.pending.insert(
                            id,
                            PendingLspRequest::SemanticTokens {
                                version: self.document.version,
                            },
                        );
                    }
                    Err(err) => return Err(format!("LSP semanticTokens 请求失败: {}", err)),
                }
            }
        }

        if self.auto_refresh.folding_ranges {
            let has_pending_folds = self.pending.values().any(|p| {
                matches!(
                    p,
                    PendingLspRequest::FoldingRanges { version } if *version == self.document.version
                )
            });
            if self.supports_folding_range && !has_pending_folds {
                match self.client.request(
                    "textDocument/foldingRange",
                    json!({ "textDocument": { "uri": doc_uri.clone() } }),
                ) {
                    Ok(id) => {
                        self.pending.insert(
                            id,
                            PendingLspRequest::FoldingRanges {
                                version: self.document.version,
                            },
                        );
                    }
                    Err(err) => return Err(format!("LSP foldingRange 请求失败: {}", err)),
                }
            }
        }

        // If the server doesn't support folding ranges, don't keep stale regions around.
        if !self.supports_folding_range {
            edits.push(ProcessingEdit::ClearFoldingRegions);
        }

        Ok(())
    }
}

impl DocumentProcessor for LspSession {
    type Error = String;

    fn process(&mut self, state: &EditorStateManager) -> Result<Vec<ProcessingEdit>, Self::Error> {
        self.poll_edits(state)
    }
}

fn parse_server_info(result: &Value) -> Option<LspServerInfo> {
    let server_info = result.get("serverInfo")?;
    let name = server_info.get("name").and_then(Value::as_str)?;
    let version = server_info
        .get("version")
        .and_then(Value::as_str)
        .map(|s| s.to_string());

    Some(LspServerInfo {
        name: name.to_string(),
        version,
    })
}

fn parse_semantic_tokens_legend(capabilities: &Value) -> (bool, Option<SemanticTokensLegend>) {
    let semantic_provider = capabilities.get("semanticTokensProvider");
    let supports_semantic_tokens =
        semantic_provider.is_some() && !semantic_provider.is_some_and(Value::is_null);

    let semantic_legend = semantic_provider
        .and_then(|p| p.get("legend"))
        .and_then(|legend| {
            let token_types = legend
                .get("tokenTypes")
                .and_then(Value::as_array)
                .map(|arr| {
                    arr.iter()
                        .filter_map(Value::as_str)
                        .map(|s| s.to_string())
                        .collect::<Vec<_>>()
                })?;

            let token_modifiers =
                legend
                    .get("tokenModifiers")
                    .and_then(Value::as_array)
                    .map(|arr| {
                        arr.iter()
                            .filter_map(Value::as_str)
                            .map(|s| s.to_string())
                            .collect::<Vec<_>>()
                    })?;

            Some(SemanticTokensLegend {
                token_types,
                token_modifiers,
            })
        });

    (supports_semantic_tokens, semantic_legend)
}

fn parse_supports_semantic_tokens_delta(capabilities: &Value) -> bool {
    let Some(provider) = capabilities.get("semanticTokensProvider") else {
        return false;
    };
    let Some(provider) = provider.as_object() else {
        return false;
    };

    let Some(full) = provider.get("full") else {
        return false;
    };

    // `full` can be:
    // - `true` (supported, but no delta info)
    // - an object `{ delta?: bool }`
    match full {
        Value::Object(obj) => obj.get("delta").and_then(Value::as_bool).unwrap_or(false),
        _ => false,
    }
}

fn parse_supports_folding_range(capabilities: &Value) -> bool {
    match capabilities.get("foldingRangeProvider") {
        Some(Value::Bool(v)) => *v,
        Some(Value::Object(_)) => true,
        _ => false,
    }
}

fn lsp_position_for_offset(line_index: &LineIndex, offset: usize) -> LspPosition {
    let (line, col) = line_index.char_offset_to_position(offset);
    let line_text = line_index.get_line_text(line).unwrap_or_default();
    let utf16 = LspCoordinateConverter::char_offset_to_utf16(&line_text, col) as u32;
    LspPosition::new(line as u32, utf16)
}

fn lsp_range_to_json(range: &LspRange) -> Value {
    json!({
        "start": { "line": range.start.line, "character": range.start.character },
        "end": { "line": range.end.line, "character": range.end.character },
    })
}

fn folding_regions_from_lsp_value(value: &Value) -> Vec<FoldRegion> {
    let ranges = value.as_array();
    let mut regions = Vec::<FoldRegion>::new();

    let Some(ranges) = ranges else {
        return regions;
    };

    for range in ranges {
        let Some(start) = range.get("startLine").and_then(Value::as_u64) else {
            continue;
        };
        let Some(end) = range.get("endLine").and_then(Value::as_u64) else {
            continue;
        };
        if start as usize >= end as usize {
            continue;
        }

        let mut region = FoldRegion::new(start as usize, end as usize);
        if let Some(kind) = range.get("kind").and_then(Value::as_str) {
            region.placeholder = match kind {
                "comment" => "/*...*/".to_string(),
                "imports" => "use ...".to_string(),
                _ => "[...]".to_string(),
            };
        }

        regions.push(region);
    }

    regions
}

fn diagnostic_style_id(severity: Option<crate::lsp_events::LspDiagnosticSeverity>) -> StyleId {
    // Headless encoding:
    // - keep it stable and easy for UIs to map
    // - low bits store severity (1..=4), 0 means "unspecified"
    const BASE: StyleId = 0x0400_0000;
    let sev_bits = match severity {
        Some(crate::lsp_events::LspDiagnosticSeverity::Error) => 1,
        Some(crate::lsp_events::LspDiagnosticSeverity::Warning) => 2,
        Some(crate::lsp_events::LspDiagnosticSeverity::Information) => 3,
        Some(crate::lsp_events::LspDiagnosticSeverity::Hint) => 4,
        None => 0,
    };
    BASE | sev_bits
}

fn char_offset_for_lsp_position(line_index: &LineIndex, pos: LspPosition) -> usize {
    let line = pos.line as usize;
    let line_text = line_index.get_line_text(line).unwrap_or_default();
    let char_in_line =
        LspCoordinateConverter::utf16_to_char_offset(&line_text, pos.character as usize);
    line_index.position_to_char_offset(line, char_in_line)
}

fn diagnostics_to_style_edit(
    line_index: &LineIndex,
    params: &crate::lsp_events::LspPublishDiagnosticsParams,
) -> Option<ProcessingEdit> {
    let mut intervals = Vec::<Interval>::with_capacity(params.diagnostics.len());

    for diag in &params.diagnostics {
        let start = char_offset_for_lsp_position(line_index, diag.range.start);
        let end = char_offset_for_lsp_position(line_index, diag.range.end);
        if start >= end {
            continue;
        }
        intervals.push(Interval::new(
            start,
            end,
            diagnostic_style_id(diag.severity),
        ));
    }

    Some(ProcessingEdit::ReplaceStyleLayer {
        layer: StyleLayerId::DIAGNOSTICS,
        intervals,
    })
}

fn diagnostic_severity(
    severity: Option<crate::lsp_events::LspDiagnosticSeverity>,
) -> Option<DiagnosticSeverity> {
    match severity {
        Some(crate::lsp_events::LspDiagnosticSeverity::Error) => Some(DiagnosticSeverity::Error),
        Some(crate::lsp_events::LspDiagnosticSeverity::Warning) => {
            Some(DiagnosticSeverity::Warning)
        }
        Some(crate::lsp_events::LspDiagnosticSeverity::Information) => {
            Some(DiagnosticSeverity::Information)
        }
        Some(crate::lsp_events::LspDiagnosticSeverity::Hint) => Some(DiagnosticSeverity::Hint),
        None => None,
    }
}

fn diagnostic_code(code: &Option<Value>) -> Option<String> {
    match code.as_ref() {
        Some(Value::String(s)) => Some(s.clone()),
        Some(Value::Number(n)) => Some(n.to_string()),
        _ => None,
    }
}

/// Convert an LSP `publishDiagnostics` payload into `editor-core` processing edits.
///
/// The resulting edits include:
/// - `StyleLayerId::DIAGNOSTICS` underline intervals (for rendering)
/// - `ProcessingEdit::ReplaceDiagnostics` structured diagnostics (for UX / panels)
pub fn lsp_diagnostics_to_processing_edits(
    line_index: &LineIndex,
    params: &crate::lsp_events::LspPublishDiagnosticsParams,
) -> Vec<ProcessingEdit> {
    let style_edit = diagnostics_to_style_edit(line_index, params);

    let mut diagnostics = Vec::<Diagnostic>::with_capacity(params.diagnostics.len());
    for diag in &params.diagnostics {
        let start = char_offset_for_lsp_position(line_index, diag.range.start);
        let end = char_offset_for_lsp_position(line_index, diag.range.end);
        let (start, end) = (start.min(end), start.max(end));
        if start == end {
            continue;
        }

        diagnostics.push(Diagnostic {
            range: DiagnosticRange::new(start, end),
            severity: diagnostic_severity(diag.severity),
            code: diagnostic_code(&diag.code),
            source: diag.source.clone(),
            message: diag.message.clone(),
            related_information_json: diag.related_information.as_ref().map(|v| v.to_string()),
            data_json: diag.data.as_ref().map(|v| v.to_string()),
        });
    }

    let mut out = Vec::<ProcessingEdit>::with_capacity(2);
    if let Some(style_edit) = style_edit {
        out.push(style_edit);
    }
    out.push(ProcessingEdit::ReplaceDiagnostics { diagnostics });
    out
}
