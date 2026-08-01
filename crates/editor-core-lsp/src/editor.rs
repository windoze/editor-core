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

use crate::lsp_client::{DEFAULT_EXIT_TIMEOUT, DEFAULT_SHUTDOWN_TIMEOUT, LspClient, LspInbound};
use crate::lsp_events::{
    LspEvent, LspNotification, LspResponse, LspResponseError, LspServerRequest,
    LspServerRequestPolicy,
};
use crate::lsp_sync::{
    DeltaCalculator, LspCoordinateConverter, LspPosition, LspRange, TextChange,
    canonical_semantic_token_modifier_bit, canonical_semantic_token_type_index,
    encode_semantic_style_id, semantic_tokens_to_intervals, text_changes_for_text_delta,
};
use crate::lsp_text_edits::{apply_text_edits, workspace_edit_text_edits_for_uri};
use editor_core::processing::{DocumentProcessor, ProcessingEdit};
use editor_core::{
    DecorationLayerId, Diagnostic, DiagnosticRange, DiagnosticSeverity, EditorStateManager,
    FoldRegion, Interval, LineIndex, StyleId, StyleLayerId, TextDelta,
};
use serde_json::{Value, json};
use std::collections::{HashMap, VecDeque};
use std::io;
use std::path::Path;
use std::process::Command as ProcessCommand;
use std::time::{Duration, Instant};

/// Clear LSP-derived state in the editor:
/// - `StyleLayerId::SEMANTIC_TOKENS`
/// - `StyleLayerId::DIAGNOSTICS`
/// - `StyleLayerId::DOCUMENT_HIGHLIGHTS`
/// - `DecorationLayerId::INLAY_HINTS`
/// - `DecorationLayerId::CODE_LENS`
/// - `DecorationLayerId::DOCUMENT_LINKS`
/// - all folding regions (typically sourced from LSP `foldingRange`)
pub fn lsp_clear_edits() -> Vec<ProcessingEdit> {
    vec![
        ProcessingEdit::ClearStyleLayer {
            layer: StyleLayerId::SEMANTIC_TOKENS,
        },
        ProcessingEdit::ClearStyleLayer {
            layer: StyleLayerId::DIAGNOSTICS,
        },
        ProcessingEdit::ClearStyleLayer {
            layer: StyleLayerId::DOCUMENT_HIGHLIGHTS,
        },
        ProcessingEdit::ClearDiagnostics,
        ProcessingEdit::ClearDecorations {
            layer: DecorationLayerId::INLAY_HINTS,
        },
        ProcessingEdit::ClearDecorations {
            layer: DecorationLayerId::CODE_LENS,
        },
        ProcessingEdit::ClearDecorations {
            layer: DecorationLayerId::DOCUMENT_LINKS,
        },
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

#[derive(Debug, Clone, PartialEq, Eq)]
/// A user-facing snapshot of the LSP server identity and spawn command.
///
/// This is intended for UI status bars and logs. It is best-effort:
/// - `name` prefers the server-reported `initialize` response, falling back to the spawn command.
/// - `command` / `args` reflect what the host used to spawn the process.
pub struct LspServerStatus {
    /// Best-effort server name (e.g. `"rust-analyzer"`).
    pub name: String,
    /// Optional server version string (if provided by the server).
    pub version: Option<String>,
    /// Program used to spawn the LSP server.
    pub command: String,
    /// Arguments passed to the LSP server.
    pub args: Vec<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// High-level LSP session "work state" suitable for a status bar.
pub enum LspWorkState {
    /// Connected and currently idle (no active `$/progress` work).
    Ready,
    /// The server appears to be indexing (best-effort heuristic based on `$/progress` titles).
    Indexing,
    /// The server is busy (has active `$/progress` work), but it does not look like indexing.
    Busy,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Best-effort "what the server is doing right now" derived from `$/progress`.
pub struct LspActivity {
    /// A short activity title (e.g. `"Indexing"`).
    pub title: String,
    /// Optional activity message (server-specific).
    pub message: Option<String>,
    /// Optional progress percentage (0..=100).
    pub percentage: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// A compact snapshot of commonly-used server capabilities.
pub struct LspSessionCapabilities {
    /// Server advertises `semanticTokensProvider`.
    pub semantic_tokens: bool,
    /// Server supports semantic tokens delta requests.
    pub semantic_tokens_delta: bool,
    /// Server advertises `completionProvider.resolveProvider`.
    pub completion_item_resolve: bool,
    /// Server advertises `foldingRangeProvider`.
    pub folding_ranges: bool,
    /// Server advertises `documentOnTypeFormattingProvider`.
    pub on_type_formatting: bool,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// A user-facing snapshot of the current LSP session status.
pub struct LspSessionStatus {
    /// Server identity and spawn command.
    pub server: LspServerStatus,
    /// High-level work state (ready/indexing/busy).
    pub state: LspWorkState,
    /// Optional active work details derived from `$/progress`.
    pub activity: Option<LspActivity>,
    /// A compact snapshot of feature support from server capabilities.
    pub capabilities: LspSessionCapabilities,
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

#[derive(Debug, Clone)]
enum PendingLspRequest {
    SemanticTokens { uri: String, version: i32 },
    FoldingRanges { uri: String, version: i32 },
}

impl PendingLspRequest {
    fn uri(&self) -> &str {
        match self {
            PendingLspRequest::SemanticTokens { uri, .. }
            | PendingLspRequest::FoldingRanges { uri, .. } => uri,
        }
    }
}

/// Bookkeeping for a client-initiated request awaiting a response.
///
/// Tracks the method (so the emitted [`LspResponse`] carries it) and the source document URI for
/// requests issued via a `*_for_uri` API (so responses can be routed per document).
#[derive(Debug, Clone)]
struct PendingClientRequest {
    method: String,
    uri: Option<String>,
}

#[derive(Debug, Clone)]
struct WorkDoneProgressItem {
    title: String,
    message: Option<String>,
    percentage: Option<u32>,
    seq: u64,
}

#[derive(Debug, Default)]
struct WorkDoneProgressTracker {
    seq: u64,
    active: HashMap<String, WorkDoneProgressItem>,
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

    /// Mirror of the active document's text, kept in lockstep with what has been sent to the
    /// server via `didChange`. Used to translate a [`TextDelta`] into LSP ranges without the
    /// caller having to infer them. Only tracks the active document.
    change_calculator: DeltaCalculator,

    server_command: String,
    server_args: Vec<String>,
    server_info: Option<LspServerInfo>,
    server_capabilities: Value,

    semantic_legend: Option<SemanticTokensLegend>,
    supports_semantic_tokens: bool,
    supports_semantic_tokens_delta: bool,
    supports_folding_range: bool,

    work_done: WorkDoneProgressTracker,

    pending: HashMap<u64, PendingLspRequest>,
    pending_client_requests: HashMap<u64, PendingClientRequest>,
    shutdown_requested: bool,
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

fn encode_semantic_style_id_from_server_legend(
    token_type: u32,
    token_modifiers: u32,
    legend: Option<&SemanticTokensLegend>,
) -> StyleId {
    let Some(legend) = legend else {
        return encode_semantic_style_id(token_type, token_modifiers);
    };

    let Some(token_type_idx) = usize::try_from(token_type).ok() else {
        return encode_semantic_style_id(token_type, token_modifiers);
    };
    let token_type_name = match legend.token_types.get(token_type_idx) {
        Some(s) => s.as_str(),
        None => return encode_semantic_style_id(token_type, token_modifiers),
    };

    let canonical_token_type =
        canonical_semantic_token_type_index(token_type_name).unwrap_or(token_type);

    let mut canonical_modifier_bits: u32 = 0;
    for bit in 0..32u32 {
        let mask = 1u32 << bit;
        if (token_modifiers & mask) == 0 {
            continue;
        }
        let Some(bit_idx) = usize::try_from(bit).ok() else {
            continue;
        };
        let Some(name) = legend.token_modifiers.get(bit_idx) else {
            continue;
        };
        canonical_modifier_bits |= canonical_semantic_token_modifier_bit(name.as_str());
    }

    encode_semantic_style_id(canonical_token_type, canonical_modifier_bits)
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

        let server_command = cmd.get_program().to_string_lossy().into_owned();
        let server_args = cmd
            .get_args()
            .map(|a| a.to_string_lossy().into_owned())
            .collect::<Vec<_>>();

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

        let change_calculator = DeltaCalculator::from_text(&initial_text);

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
            change_calculator,
            server_command,
            server_args,
            server_info,
            server_capabilities,
            semantic_legend,
            supports_semantic_tokens,
            supports_semantic_tokens_delta,
            supports_folding_range,
            work_done: WorkDoneProgressTracker::default(),
            pending: HashMap::new(),
            pending_client_requests: HashMap::new(),
            shutdown_requested: false,
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

    /// Return a user-facing snapshot of the current LSP session status.
    ///
    /// This is intended for simple UIs (e.g. status bars) that want to show:
    /// - whether the server is idle vs. working (indexing/busy)
    /// - the LSP server name/version
    /// - a short activity title/message from `$/progress`
    pub fn status(&self) -> LspSessionStatus {
        fn command_basename(cmd: &str) -> String {
            Path::new(cmd)
                .file_name()
                .and_then(|s| s.to_str())
                .map(|s| s.to_string())
                .unwrap_or_else(|| cmd.to_string())
        }

        fn is_indexing_title(title: &str) -> bool {
            let lower = title.to_ascii_lowercase();
            lower.contains("index")
                || lower.contains("indexing")
                || lower.contains("crate graph")
                || lower.contains("building crate graph")
        }

        let server_name = self
            .server_info
            .as_ref()
            .map(|s| s.name.clone())
            .unwrap_or_else(|| command_basename(self.server_command.as_str()));
        let server_version = self.server_info.as_ref().and_then(|s| s.version.clone());

        let mut best: Option<&WorkDoneProgressItem> = None;
        let mut best_is_indexing = false;
        for item in self.work_done.active.values() {
            let item_is_indexing = is_indexing_title(item.title.as_str())
                || item.message.as_deref().is_some_and(is_indexing_title);

            match best {
                None => {
                    best = Some(item);
                    best_is_indexing = item_is_indexing;
                }
                Some(prev) => {
                    // Prefer "indexing" items. Otherwise pick the most recently updated one.
                    if item_is_indexing && !best_is_indexing {
                        best = Some(item);
                        best_is_indexing = true;
                    } else if item_is_indexing == best_is_indexing && item.seq > prev.seq {
                        best = Some(item);
                        best_is_indexing = item_is_indexing;
                    }
                }
            }
        }

        let activity = best.map(|item| LspActivity {
            title: item.title.clone(),
            message: item.message.clone(),
            percentage: item.percentage,
        });

        let state = if best.is_some() {
            if best_is_indexing {
                LspWorkState::Indexing
            } else {
                LspWorkState::Busy
            }
        } else {
            LspWorkState::Ready
        };

        LspSessionStatus {
            server: LspServerStatus {
                name: server_name,
                version: server_version,
                command: self.server_command.clone(),
                args: self.server_args.clone(),
            },
            state,
            activity,
            capabilities: LspSessionCapabilities {
                semantic_tokens: self.supports_semantic_tokens,
                semantic_tokens_delta: self.supports_semantic_tokens_delta,
                completion_item_resolve: parse_supports_completion_item_resolve(
                    &self.server_capabilities,
                ),
                folding_ranges: self.supports_folding_range,
                on_type_formatting: self.supports_on_type_formatting(),
            },
        }
    }

    /// Get a reference to the underlying stdio JSON-RPC client.
    pub fn client(&self) -> &LspClient {
        &self.client
    }

    /// Wait for a specific JSON-RPC response id and return the raw message as JSON.
    ///
    /// This is a low-level helper intended for "explicit user actions" that prefer a blocking
    /// request/response workflow (e.g. formatting, rename, code actions).
    ///
    /// Notes:
    /// - While waiting, the underlying client will still respond to common server->client requests
    ///   (e.g. `workspace/configuration`) to avoid deadlocks.
    /// - Other responses and notifications received during the wait remain queued for polling.
    pub fn wait_for_response(
        &mut self,
        request_id: u64,
        timeout: Duration,
    ) -> Result<Value, String> {
        self.client
            .wait_for_response(request_id, timeout)
            .map_err(|e| e.to_string())
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
        self.request_for_uri(method, None, params)
    }

    /// Send a JSON-RPC/LSP request, tagging the resulting [`LspResponse`] with a source `uri`.
    ///
    /// `uri` is `None` for active-document / workspace-level requests and `Some(_)` for requests
    /// issued via a `*_for_uri` API, so consumers can route the response to the correct document.
    fn request_for_uri(
        &mut self,
        method: &str,
        uri: Option<String>,
        params: Value,
    ) -> Result<u64, String> {
        let id = self
            .client
            .request(method, params)
            .map_err(|err| format!("LSP request 失败 ({}): {}", method, err))?;

        self.pending_client_requests.insert(
            id,
            PendingClientRequest {
                method: method.to_string(),
                uri,
            },
        );
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

    /// Return whether a `publishDiagnostics` payload matches the tracked document version.
    pub(crate) fn diagnostics_version_matches(
        &self,
        params: &crate::lsp_events::LspPublishDiagnosticsParams,
    ) -> bool {
        match (params.version, self.document_for_uri(&params.uri)) {
            // Older servers may omit the version; keep accepting those diagnostics for compatibility.
            (None, _) => true,
            (Some(version), Some(document)) => version == document.version,
            (Some(_), None) => false,
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

    /// Parse `documentOnTypeFormattingProvider` from the server capabilities.
    ///
    /// This is commonly used for "auto-indent" behavior (e.g. requesting formatting on `"\n"`).
    pub fn on_type_formatting_options(
        &self,
    ) -> Option<crate::lsp_indentation::LspOnTypeFormattingOptions> {
        crate::lsp_indentation::on_type_formatting_options_from_capabilities(
            &self.server_capabilities,
        )
    }

    /// Returns `true` if the server advertises `documentOnTypeFormattingProvider`.
    pub fn supports_on_type_formatting(&self) -> bool {
        self.on_type_formatting_options().is_some()
    }

    /// Returns `true` if `ch` is a trigger character for on-type formatting.
    pub fn supports_on_type_formatting_trigger(&self, ch: &str) -> bool {
        self.on_type_formatting_options()
            .is_some_and(|opts| opts.is_trigger_character(ch))
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
        self.did_change_many(vec![change])
    }

    /// Send `textDocument/didChange` for the active document with multiple changes.
    ///
    /// On success the internal [`DeltaCalculator`] mirror is advanced by the same changes so it
    /// stays aligned with the server regardless of whether callers drive edits through this manual
    /// range API or through [`did_change_from_text_delta`](Self::did_change_from_text_delta).
    pub fn did_change_many(&mut self, changes: Vec<LspContentChange>) -> Result<(), String> {
        if changes.is_empty() {
            return Ok(());
        }

        self.send_active_did_change(&changes)?;

        // Keep the mirror in sync with what we just told the server (changes apply in order).
        for change in &changes {
            self.change_calculator.apply_change(&TextChange {
                range: change.range,
                text: change.text.clone(),
            });
        }
        Ok(())
    }

    /// Send a `textDocument/didChange` for the active document without touching the internal
    /// mirror. Callers are responsible for advancing `change_calculator` exactly once per change
    /// set (either before or after calling this).
    fn send_active_did_change(&mut self, changes: &[LspContentChange]) -> Result<(), String> {
        // Compute the next version but only commit it after the notification is sent, so a send
        // failure does not leave the tracked version ahead of what the server actually received.
        let next_version = self.document.version.saturating_add(1);

        let content_changes = changes
            .iter()
            .map(|change| {
                json!({
                    "range": lsp_range_to_json(&change.range),
                    "text": change.text,
                })
            })
            .collect::<Vec<_>>();

        let params = json!({
            "textDocument": {
                "uri": self.document.uri.as_str(),
                "version": next_version,
            },
            "contentChanges": content_changes,
        });

        if let Err(err) = self.client.notify("textDocument/didChange", params) {
            return Err(format!("LSP didChange 失败，已禁用: {}", err));
        }

        self.document.version = next_version;
        self.schedule_refresh(self.auto_refresh.delay);
        Ok(())
    }

    /// Send `textDocument/didChange` for the active document from the [`TextDelta`] a single edit
    /// actually produced.
    ///
    /// Unlike [`did_change_many`](Self::did_change_many) — which requires the caller to infer the
    /// changed range — this consumes the result of
    /// `EditorStateManager::take_last_text_delta()` directly, so multi-character deletions (e.g.
    /// auto-pair deletion removing two characters at once), multi-cursor edits, and re-indentation
    /// are all handled correctly.
    ///
    /// `delta.before_char_count` must equal the current mirror character count, i.e. the caller
    /// must take and forward a delta after every edit without skipping any.
    ///
    /// The internal mirror only tracks the session's *active* document and is not reset when the
    /// active document changes ([`set_active_document`](Self::set_active_document) /
    /// [`open_document`](Self::open_document)). This method is therefore intended for
    /// single-document sessions; for multi-document editing drive changes through
    /// [`crate::workspace_sync::LspWorkspaceSync`], which keeps a per-URI mirror.
    pub fn did_change_from_text_delta(&mut self, delta: &TextDelta) -> Result<(), String> {
        if delta.is_empty() {
            return Ok(());
        }

        debug_assert_eq!(
            delta.before_char_count,
            self.change_calculator.char_count(),
            "TextDelta before_char_count must match the LSP mirror; a delta was skipped or applied out of order"
        );

        // `text_changes_for_text_delta` advances `change_calculator` by exactly one delta, so the
        // send path below must not touch the mirror again. If the send then fails, the mirror is
        // left one step ahead of the server — but a send failure means the server pipe is dead and
        // the session is disabled (see `send_active_did_change`), so no further didChange follows
        // and the drift is inert.
        let changes = text_changes_for_text_delta(&mut self.change_calculator, delta);
        let content_changes = changes
            .into_iter()
            .map(|c| LspContentChange {
                range: c.range,
                text: c.text,
            })
            .collect::<Vec<_>>();

        self.send_active_did_change(&content_changes)
    }

    /// Character count of the internal `didChange` mirror for the active document.
    ///
    /// Intended for consistency checks: after each edit is forwarded via
    /// [`did_change_from_text_delta`](Self::did_change_from_text_delta) or
    /// [`did_change_many`](Self::did_change_many), this should equal the source buffer's
    /// `EditorStateManager::char_count()`.
    pub fn mirror_char_count(&self) -> usize {
        self.change_calculator.char_count()
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
        self.drop_pending_for_inactive_document();
        self.schedule_refresh(Duration::from_millis(0));
        Ok(())
    }

    /// Drop in-flight semantic-token / folding requests that target a document other than the
    /// currently active one. Their late responses would otherwise be matched by version number
    /// alone (versions are per-document and can collide) and applied to the wrong document, or
    /// keep `maybe_refresh` from ever issuing a request for the new active document.
    fn drop_pending_for_inactive_document(&mut self) {
        let active = self.document.uri.clone();
        self.pending.retain(|_, req| req.uri() == active);
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
                self.drop_pending_for_inactive_document();
                self.schedule_refresh(Duration::from_millis(0));
            }
        } else {
            self.extra_documents.remove(uri);
        }

        // Drop any in-flight requests targeting the closed document regardless of which document
        // is now active.
        self.pending.retain(|_, req| req.uri() != uri);

        Ok(())
    }

    /// Send `textDocument/didChange` for a specific document URI.
    pub fn did_change_for_uri(
        &mut self,
        uri: &str,
        change: LspContentChange,
    ) -> Result<(), String> {
        self.did_change_for_uri_many(uri, vec![change])
    }

    /// Send `textDocument/didChange` for a specific document URI with multiple changes.
    pub fn did_change_for_uri_many(
        &mut self,
        uri: &str,
        changes: Vec<LspContentChange>,
    ) -> Result<(), String> {
        if changes.is_empty() {
            return Ok(());
        }

        if self.document.uri == uri {
            return self.did_change_many(changes);
        }

        let (doc_uri, version) = {
            let Some(doc) = self.extra_documents.get_mut(uri) else {
                return Err(format!("LSP document not found for uri={}", uri));
            };
            doc.version = doc.version.saturating_add(1);
            (doc.uri.clone(), doc.version)
        };

        let content_changes = changes
            .into_iter()
            .map(|change| {
                json!({
                    "range": lsp_range_to_json(&change.range),
                    "text": change.text,
                })
            })
            .collect::<Vec<_>>();

        self.notify(
            "textDocument/didChange",
            json!({
                "textDocument": { "uri": doc_uri.as_str(), "version": version },
                "contentChanges": content_changes,
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
        let uri = self.document.uri.clone();
        self.will_save_for_uri(&uri, reason)
    }

    /// Send `textDocument/willSave` for a specific document URI.
    pub fn will_save_for_uri(&mut self, uri: &str, reason: i32) -> Result<(), String> {
        self.ensure_tracked(uri)?;
        self.notify(
            "textDocument/willSave",
            json!({
                "textDocument": { "uri": uri },
                "reason": reason,
            }),
        )
    }

    /// Request `textDocument/willSaveWaitUntil` for the active document.
    ///
    /// The response (an array of `TextEdit`) is delivered via [`LspEvent::Response`].
    pub fn request_will_save_wait_until(&mut self, reason: i32) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_will_save_wait_until_for_uri(&uri, reason)
    }

    /// Request `textDocument/willSaveWaitUntil` for a specific document URI.
    pub fn request_will_save_wait_until_for_uri(
        &mut self,
        uri: &str,
        reason: i32,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        self.request_for_uri(
            "textDocument/willSaveWaitUntil",
            Some(uri.to_string()),
            json!({
                "textDocument": { "uri": uri },
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

    /// Low-level graceful shutdown request.
    ///
    /// The response is delivered via [`LspEvent::Response`], after which the host can call
    /// [`LspSession::exit`] to send `exit` and reap the server process.
    pub fn shutdown(&mut self) -> Result<u64, String> {
        let id = self.request("shutdown", Value::Null)?;
        self.shutdown_requested = true;
        Ok(id)
    }

    /// Gracefully exit the LSP server and ensure its child process is reaped.
    pub fn exit(&mut self) -> Result<(), String> {
        let result = if self.shutdown_requested {
            self.client.exit(DEFAULT_EXIT_TIMEOUT)
        } else {
            self.client.shutdown(DEFAULT_SHUTDOWN_TIMEOUT)
        };

        result.map_err(|err| format!("LSP exit 失败: {}", err))
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

    /// Return `Err` if `uri` is not a document tracked by this session (active or extra).
    ///
    /// Used by the `*_for_uri` request APIs so callers get an early, descriptive error instead of
    /// the server later rejecting an "unknown document".
    fn ensure_tracked(&self, uri: &str) -> Result<(), String> {
        if self.document_for_uri(uri).is_some() {
            Ok(())
        } else {
            Err(format!("LSP document not found for uri={}", uri))
        }
    }

    fn text_document_position_params_for_uri(
        &self,
        uri: &str,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Value {
        let pos = self.lsp_position_for_editor_position(line_index, line, column);
        json!({
            "textDocument": { "uri": uri },
            "position": { "line": pos.line, "character": pos.character },
        })
    }

    fn text_document_range_params_for_uri(&self, uri: &str, range: &LspRange) -> Value {
        json!({
            "textDocument": { "uri": uri },
            "range": lsp_range_to_json(range),
        })
    }

    /// Hover (`textDocument/hover`) for the active document.
    pub fn request_hover(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_hover_for_uri(&uri, line_index, line, column)
    }

    /// Hover (`textDocument/hover`) for a specific document URI.
    pub fn request_hover_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let params = self.text_document_position_params_for_uri(uri, line_index, line, column);
        self.request_for_uri("textDocument/hover", Some(uri.to_string()), params)
    }

    /// Go to definition (`textDocument/definition`) for the active document.
    pub fn request_definition(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_definition_for_uri(&uri, line_index, line, column)
    }

    /// Go to definition (`textDocument/definition`) for a specific document URI.
    pub fn request_definition_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let params = self.text_document_position_params_for_uri(uri, line_index, line, column);
        self.request_for_uri("textDocument/definition", Some(uri.to_string()), params)
    }

    /// Go to declaration (`textDocument/declaration`) for the active document.
    pub fn request_declaration(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_declaration_for_uri(&uri, line_index, line, column)
    }

    /// Go to declaration (`textDocument/declaration`) for a specific document URI.
    pub fn request_declaration_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let params = self.text_document_position_params_for_uri(uri, line_index, line, column);
        self.request_for_uri("textDocument/declaration", Some(uri.to_string()), params)
    }

    /// Go to type definition (`textDocument/typeDefinition`) for the active document.
    pub fn request_type_definition(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_type_definition_for_uri(&uri, line_index, line, column)
    }

    /// Go to type definition (`textDocument/typeDefinition`) for a specific document URI.
    pub fn request_type_definition_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let params = self.text_document_position_params_for_uri(uri, line_index, line, column);
        self.request_for_uri("textDocument/typeDefinition", Some(uri.to_string()), params)
    }

    /// Go to implementation (`textDocument/implementation`) for the active document.
    pub fn request_implementation(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_implementation_for_uri(&uri, line_index, line, column)
    }

    /// Go to implementation (`textDocument/implementation`) for a specific document URI.
    pub fn request_implementation_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let params = self.text_document_position_params_for_uri(uri, line_index, line, column);
        self.request_for_uri("textDocument/implementation", Some(uri.to_string()), params)
    }

    /// Find references (`textDocument/references`) for the active document.
    pub fn request_references(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
        include_declaration: bool,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_references_for_uri(&uri, line_index, line, column, include_declaration)
    }

    /// Find references (`textDocument/references`) for a specific document URI.
    pub fn request_references_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        line: usize,
        column: usize,
        include_declaration: bool,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let mut params = self.text_document_position_params_for_uri(uri, line_index, line, column);
        if let Some(obj) = params.as_object_mut() {
            obj.insert(
                "context".to_string(),
                json!({ "includeDeclaration": include_declaration }),
            );
        }
        self.request_for_uri("textDocument/references", Some(uri.to_string()), params)
    }

    /// Document highlights (`textDocument/documentHighlight`) for the active document.
    pub fn request_document_highlight(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_document_highlight_for_uri(&uri, line_index, line, column)
    }

    /// Document highlights (`textDocument/documentHighlight`) for a specific document URI.
    pub fn request_document_highlight_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let params = self.text_document_position_params_for_uri(uri, line_index, line, column);
        self.request_for_uri(
            "textDocument/documentHighlight",
            Some(uri.to_string()),
            params,
        )
    }

    /// Call hierarchy prepare (`textDocument/prepareCallHierarchy`) for the active document.
    pub fn request_prepare_call_hierarchy(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_prepare_call_hierarchy_for_uri(&uri, line_index, line, column)
    }

    /// Call hierarchy prepare (`textDocument/prepareCallHierarchy`) for a specific document URI.
    pub fn request_prepare_call_hierarchy_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let params = self.text_document_position_params_for_uri(uri, line_index, line, column);
        self.request_for_uri(
            "textDocument/prepareCallHierarchy",
            Some(uri.to_string()),
            params,
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

    /// Type hierarchy prepare (`textDocument/prepareTypeHierarchy`) for the active document.
    pub fn request_prepare_type_hierarchy(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_prepare_type_hierarchy_for_uri(&uri, line_index, line, column)
    }

    /// Type hierarchy prepare (`textDocument/prepareTypeHierarchy`) for a specific document URI.
    pub fn request_prepare_type_hierarchy_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let params = self.text_document_position_params_for_uri(uri, line_index, line, column);
        self.request_for_uri(
            "textDocument/prepareTypeHierarchy",
            Some(uri.to_string()),
            params,
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

    /// Completion list (`textDocument/completion`) for the active document.
    pub fn request_completion(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_completion_for_uri(&uri, line_index, line, column)
    }

    /// Completion list (`textDocument/completion`) for a specific document URI.
    pub fn request_completion_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let params = self.text_document_position_params_for_uri(uri, line_index, line, column);
        self.request_for_uri("textDocument/completion", Some(uri.to_string()), params)
    }

    /// Completion item resolve (`completionItem/resolve`).
    pub fn request_completion_item_resolve(&mut self, item: Value) -> Result<u64, String> {
        self.request("completionItem/resolve", item)
    }

    /// Signature help (`textDocument/signatureHelp`) for the active document.
    pub fn request_signature_help(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_signature_help_for_uri(&uri, line_index, line, column)
    }

    /// Signature help (`textDocument/signatureHelp`) for a specific document URI.
    pub fn request_signature_help_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let params = self.text_document_position_params_for_uri(uri, line_index, line, column);
        self.request_for_uri("textDocument/signatureHelp", Some(uri.to_string()), params)
    }

    /// Inlay hints (`textDocument/inlayHint`) for the active document.
    pub fn request_inlay_hints(
        &mut self,
        line_index: &LineIndex,
        start_offset: usize,
        end_offset: usize,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_inlay_hints_for_uri(&uri, line_index, start_offset, end_offset)
    }

    /// Inlay hints (`textDocument/inlayHint`) for a specific document URI.
    pub fn request_inlay_hints_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        start_offset: usize,
        end_offset: usize,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let range = self.lsp_range_for_editor_offsets(line_index, start_offset, end_offset);
        let params = self.text_document_range_params_for_uri(uri, &range);
        self.request_for_uri("textDocument/inlayHint", Some(uri.to_string()), params)
    }

    /// Inlay hint resolve (`inlayHint/resolve`).
    pub fn request_inlay_hint_resolve(&mut self, hint: Value) -> Result<u64, String> {
        self.request("inlayHint/resolve", hint)
    }

    /// Document symbols (`textDocument/documentSymbol`) for the active document.
    pub fn request_document_symbols(&mut self) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_document_symbols_for_uri(&uri)
    }

    /// Document symbols (`textDocument/documentSymbol`) for a specific document URI.
    pub fn request_document_symbols_for_uri(&mut self, uri: &str) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        self.request_for_uri(
            "textDocument/documentSymbol",
            Some(uri.to_string()),
            json!({ "textDocument": { "uri": uri } }),
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

    /// Rename (`textDocument/rename`) for the active document.
    pub fn request_rename(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
        new_name: impl Into<String>,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_rename_for_uri(&uri, line_index, line, column, new_name)
    }

    /// Rename (`textDocument/rename`) for a specific document URI.
    pub fn request_rename_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        line: usize,
        column: usize,
        new_name: impl Into<String>,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let mut params = self.text_document_position_params_for_uri(uri, line_index, line, column);
        if let Some(obj) = params.as_object_mut() {
            obj.insert("newName".to_string(), Value::String(new_name.into()));
        }
        self.request_for_uri("textDocument/rename", Some(uri.to_string()), params)
    }

    /// Prepare rename (`textDocument/prepareRename`) for the active document.
    pub fn request_prepare_rename(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_prepare_rename_for_uri(&uri, line_index, line, column)
    }

    /// Prepare rename (`textDocument/prepareRename`) for a specific document URI.
    pub fn request_prepare_rename_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let params = self.text_document_position_params_for_uri(uri, line_index, line, column);
        self.request_for_uri("textDocument/prepareRename", Some(uri.to_string()), params)
    }

    /// Code actions (`textDocument/codeAction`) for the active document.
    ///
    /// `context` should follow LSP `CodeActionContext` shape.
    pub fn request_code_action(
        &mut self,
        line_index: &LineIndex,
        start_offset: usize,
        end_offset: usize,
        context: Value,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_code_action_for_uri(&uri, line_index, start_offset, end_offset, context)
    }

    /// Code actions (`textDocument/codeAction`) for a specific document URI.
    ///
    /// `context` should follow LSP `CodeActionContext` shape.
    pub fn request_code_action_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        start_offset: usize,
        end_offset: usize,
        context: Value,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let range = self.lsp_range_for_editor_offsets(line_index, start_offset, end_offset);
        let mut params = self.text_document_range_params_for_uri(uri, &range);
        if let Some(obj) = params.as_object_mut() {
            obj.insert("context".to_string(), context);
        }
        self.request_for_uri("textDocument/codeAction", Some(uri.to_string()), params)
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

    /// Code lens (`textDocument/codeLens`) for the active document.
    pub fn request_code_lens(&mut self) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_code_lens_for_uri(&uri)
    }

    /// Code lens (`textDocument/codeLens`) for a specific document URI.
    pub fn request_code_lens_for_uri(&mut self, uri: &str) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        self.request_for_uri(
            "textDocument/codeLens",
            Some(uri.to_string()),
            json!({ "textDocument": { "uri": uri } }),
        )
    }

    /// Code lens resolve (`codeLens/resolve`).
    pub fn request_code_lens_resolve(&mut self, lens: Value) -> Result<u64, String> {
        self.request("codeLens/resolve", lens)
    }

    /// Document formatting (`textDocument/formatting`) for the active document.
    ///
    /// `options` should follow LSP `FormattingOptions`.
    pub fn request_formatting(&mut self, options: Value) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_formatting_for_uri(&uri, options)
    }

    /// Document formatting (`textDocument/formatting`) for a specific document URI.
    ///
    /// `options` should follow LSP `FormattingOptions`.
    pub fn request_formatting_for_uri(&mut self, uri: &str, options: Value) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        self.request_for_uri(
            "textDocument/formatting",
            Some(uri.to_string()),
            json!({
                "textDocument": { "uri": uri },
                "options": options,
            }),
        )
    }

    /// Range formatting (`textDocument/rangeFormatting`) for the active document.
    pub fn request_range_formatting(
        &mut self,
        line_index: &LineIndex,
        start_offset: usize,
        end_offset: usize,
        options: Value,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_range_formatting_for_uri(&uri, line_index, start_offset, end_offset, options)
    }

    /// Range formatting (`textDocument/rangeFormatting`) for a specific document URI.
    pub fn request_range_formatting_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        start_offset: usize,
        end_offset: usize,
        options: Value,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let range = self.lsp_range_for_editor_offsets(line_index, start_offset, end_offset);
        let mut params = self.text_document_range_params_for_uri(uri, &range);
        if let Some(obj) = params.as_object_mut() {
            obj.insert("options".to_string(), options);
        }
        self.request_for_uri(
            "textDocument/rangeFormatting",
            Some(uri.to_string()),
            params,
        )
    }

    /// On-type formatting (`textDocument/onTypeFormatting`) for the active document.
    pub fn request_on_type_formatting(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
        ch: impl Into<String>,
        options: Value,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_on_type_formatting_for_uri(&uri, line_index, line, column, ch, options)
    }

    /// On-type formatting (`textDocument/onTypeFormatting`) for a specific document URI.
    pub fn request_on_type_formatting_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        line: usize,
        column: usize,
        ch: impl Into<String>,
        options: Value,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let pos = self.lsp_position_for_editor_position(line_index, line, column);
        self.request_for_uri(
            "textDocument/onTypeFormatting",
            Some(uri.to_string()),
            json!({
                "textDocument": { "uri": uri },
                "position": { "line": pos.line, "character": pos.character },
                "ch": ch.into(),
                "options": options,
            }),
        )
    }

    /// Semantic tokens full (`textDocument/semanticTokens/full`) for the active document.
    ///
    /// Unlike the session's built-in auto-refresh, this manual request delivers its result via
    /// [`LspEvent::Response`] (tagged with the source URI when the `*_for_uri` variant is used)
    /// and does not touch the session's semantic-token cache.
    pub fn request_semantic_tokens_full(&mut self) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_semantic_tokens_full_for_uri(&uri)
    }

    /// Semantic tokens full (`textDocument/semanticTokens/full`) for a specific document URI.
    pub fn request_semantic_tokens_full_for_uri(&mut self, uri: &str) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        self.request_for_uri(
            "textDocument/semanticTokens/full",
            Some(uri.to_string()),
            json!({ "textDocument": { "uri": uri } }),
        )
    }

    /// Semantic tokens delta (`textDocument/semanticTokens/full/delta`) for the active document.
    pub fn request_semantic_tokens_delta(
        &mut self,
        previous_result_id: Option<String>,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_semantic_tokens_delta_for_uri(&uri, previous_result_id)
    }

    /// Semantic tokens delta (`textDocument/semanticTokens/full/delta`) for a specific document URI.
    pub fn request_semantic_tokens_delta_for_uri(
        &mut self,
        uri: &str,
        previous_result_id: Option<String>,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let mut params = json!({ "textDocument": { "uri": uri } });
        if let Some(prev) = previous_result_id
            && let Some(obj) = params.as_object_mut()
        {
            obj.insert("previousResultId".to_string(), Value::String(prev));
        }
        self.request_for_uri(
            "textDocument/semanticTokens/full/delta",
            Some(uri.to_string()),
            params,
        )
    }

    /// Semantic tokens range (`textDocument/semanticTokens/range`) for the active document.
    pub fn request_semantic_tokens_range(&mut self, range: &LspRange) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_semantic_tokens_range_for_uri(&uri, range)
    }

    /// Semantic tokens range (`textDocument/semanticTokens/range`) for a specific document URI.
    pub fn request_semantic_tokens_range_for_uri(
        &mut self,
        uri: &str,
        range: &LspRange,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        self.request_for_uri(
            "textDocument/semanticTokens/range",
            Some(uri.to_string()),
            json!({
                "textDocument": { "uri": uri },
                "range": lsp_range_to_json(range),
            }),
        )
    }

    /// Folding ranges (`textDocument/foldingRange`) for the active document.
    ///
    /// Unlike the session's built-in auto-refresh, this manual request delivers its result via
    /// [`LspEvent::Response`] (tagged with the source URI when the `*_for_uri` variant is used).
    pub fn request_folding_ranges(&mut self) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_folding_ranges_for_uri(&uri)
    }

    /// Folding ranges (`textDocument/foldingRange`) for a specific document URI.
    pub fn request_folding_ranges_for_uri(&mut self, uri: &str) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        self.request_for_uri(
            "textDocument/foldingRange",
            Some(uri.to_string()),
            json!({ "textDocument": { "uri": uri } }),
        )
    }

    /// Selection range (`textDocument/selectionRange`) for the active document.
    ///
    /// `positions` are editor (line,column) pairs where column is a char offset within the line.
    pub fn request_selection_range(
        &mut self,
        line_index: &LineIndex,
        positions: &[(usize, usize)],
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_selection_range_for_uri(&uri, line_index, positions)
    }

    /// Selection range (`textDocument/selectionRange`) for a specific document URI.
    pub fn request_selection_range_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        positions: &[(usize, usize)],
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let lsp_positions = positions
            .iter()
            .map(|(line, col)| {
                let pos = self.lsp_position_for_editor_position(line_index, *line, *col);
                json!({ "line": pos.line, "character": pos.character })
            })
            .collect::<Vec<_>>();

        self.request_for_uri(
            "textDocument/selectionRange",
            Some(uri.to_string()),
            json!({
                "textDocument": { "uri": uri },
                "positions": lsp_positions,
            }),
        )
    }

    /// Linked editing range (`textDocument/linkedEditingRange`) for the active document.
    pub fn request_linked_editing_range(
        &mut self,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_linked_editing_range_for_uri(&uri, line_index, line, column)
    }

    /// Linked editing range (`textDocument/linkedEditingRange`) for a specific document URI.
    pub fn request_linked_editing_range_for_uri(
        &mut self,
        uri: &str,
        line_index: &LineIndex,
        line: usize,
        column: usize,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let params = self.text_document_position_params_for_uri(uri, line_index, line, column);
        self.request_for_uri(
            "textDocument/linkedEditingRange",
            Some(uri.to_string()),
            params,
        )
    }

    /// Document links (`textDocument/documentLink`) for the active document.
    pub fn request_document_links(&mut self) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_document_links_for_uri(&uri)
    }

    /// Document links (`textDocument/documentLink`) for a specific document URI.
    pub fn request_document_links_for_uri(&mut self, uri: &str) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        self.request_for_uri(
            "textDocument/documentLink",
            Some(uri.to_string()),
            json!({ "textDocument": { "uri": uri } }),
        )
    }

    /// Document link resolve (`documentLink/resolve`).
    pub fn request_document_link_resolve(&mut self, link: Value) -> Result<u64, String> {
        self.request("documentLink/resolve", link)
    }

    /// Pull diagnostics: document (`textDocument/diagnostic`) for the active document.
    pub fn request_document_diagnostic(
        &mut self,
        previous_result_id: Option<String>,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_document_diagnostic_for_uri(&uri, previous_result_id)
    }

    /// Pull diagnostics: document (`textDocument/diagnostic`) for a specific document URI.
    pub fn request_document_diagnostic_for_uri(
        &mut self,
        uri: &str,
        previous_result_id: Option<String>,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        let mut params = json!({ "textDocument": { "uri": uri } });
        if let Some(prev) = previous_result_id
            && let Some(obj) = params.as_object_mut()
        {
            obj.insert("previousResultId".to_string(), Value::String(prev));
        }
        self.request_for_uri("textDocument/diagnostic", Some(uri.to_string()), params)
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

    /// Color provider (`textDocument/documentColor`) for the active document.
    pub fn request_document_color(&mut self) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_document_color_for_uri(&uri)
    }

    /// Color provider (`textDocument/documentColor`) for a specific document URI.
    pub fn request_document_color_for_uri(&mut self, uri: &str) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        self.request_for_uri(
            "textDocument/documentColor",
            Some(uri.to_string()),
            json!({ "textDocument": { "uri": uri } }),
        )
    }

    /// Color presentation (`textDocument/colorPresentation`) for the active document.
    pub fn request_color_presentation(
        &mut self,
        range: &LspRange,
        color: Value,
    ) -> Result<u64, String> {
        let uri = self.document.uri.clone();
        self.request_color_presentation_for_uri(&uri, range, color)
    }

    /// Color presentation (`textDocument/colorPresentation`) for a specific document URI.
    pub fn request_color_presentation_for_uri(
        &mut self,
        uri: &str,
        range: &LspRange,
        color: Value,
    ) -> Result<u64, String> {
        self.ensure_tracked(uri)?;
        self.request_for_uri(
            "textDocument/colorPresentation",
            Some(uri.to_string()),
            json!({
                "textDocument": { "uri": uri },
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

    /// Poll the LSP connection and return derived-state edits (semantic tokens, folding ranges),
    /// using an explicit [`LineIndex`].
    ///
    /// This is useful when integrating with workspace models that store buffer state outside of
    /// [`EditorStateManager`] (e.g. split panes / multiple views into the same buffer).
    pub fn poll_edits_with_line_index(
        &mut self,
        line_index: &LineIndex,
    ) -> Result<Vec<ProcessingEdit>, String> {
        self.poll_edits_with_line_index_and_handler(line_index, |_| {})
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
        on_unhandled_message: F,
    ) -> Result<Vec<ProcessingEdit>, String>
    where
        F: FnMut(Value),
    {
        self.poll_edits_with_handlers(state, on_unhandled_message, |_| {})
    }

    /// Poll the LSP connection, returning derived-state edits, using an explicit [`LineIndex`].
    pub fn poll_edits_with_line_index_and_handler<F>(
        &mut self,
        line_index: &LineIndex,
        on_unhandled_message: F,
    ) -> Result<Vec<ProcessingEdit>, String>
    where
        F: FnMut(Value),
    {
        self.poll_edits_with_line_index_and_handlers(line_index, on_unhandled_message, |_| {})
    }

    /// Poll the LSP connection, returning derived-state edits (semantic tokens, folding ranges).
    ///
    /// This is like [`LspSession::poll_edits_with_handler`], but also exposes each parsed
    /// [`LspNotification`] to the caller.
    pub fn poll_edits_with_handlers<F, G>(
        &mut self,
        state: &EditorStateManager,
        on_unhandled_message: F,
        on_notification: G,
    ) -> Result<Vec<ProcessingEdit>, String>
    where
        F: FnMut(Value),
        G: FnMut(&LspNotification),
    {
        self.poll_edits_with_line_index_and_handlers(
            state.editor().line_index(),
            on_unhandled_message,
            on_notification,
        )
    }

    /// Poll the LSP connection, returning derived-state edits, using an explicit [`LineIndex`].
    pub fn poll_edits_with_line_index_and_handlers<F, G>(
        &mut self,
        line_index: &LineIndex,
        mut on_unhandled_message: F,
        mut on_notification: G,
    ) -> Result<Vec<ProcessingEdit>, String>
    where
        F: FnMut(Value),
        G: FnMut(&LspNotification),
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
                        } else {
                            on_unhandled_message(msg);
                        }
                        continue;
                    }

                    let maybe_id = msg.get("id").and_then(Value::as_u64);
                    if let Some(id) = maybe_id {
                        if let Some(pending) = self.pending.remove(&id) {
                            self.handle_pending_response(line_index, pending, &msg, &mut edits)?;
                            continue;
                        }

                        if let Some(PendingClientRequest { method, uri }) =
                            self.pending_client_requests.remove(&id)
                        {
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
                                uri,
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
                            self.observe_notification(&notification);
                            on_notification(&notification);

                            if let LspNotification::PublishDiagnostics(diags) = &notification
                                && diags.uri == self.document.uri
                                && self.diagnostics_version_matches(diags)
                            {
                                edits
                                    .extend(lsp_diagnostics_to_processing_edits(line_index, diags));
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

    fn observe_notification(&mut self, notification: &LspNotification) {
        let LspNotification::Progress(params) = notification else {
            return;
        };

        fn token_key(token: &Value) -> String {
            match token {
                Value::String(s) => s.clone(),
                Value::Number(n) => n.to_string(),
                other => other.to_string(),
            }
        }

        let key = token_key(&params.token);
        let Some(kind) = params.value.get("kind").and_then(Value::as_str) else {
            return;
        };

        match kind {
            "begin" => {
                let title = params
                    .value
                    .get("title")
                    .and_then(Value::as_str)
                    .unwrap_or("Working")
                    .to_string();
                let message = params
                    .value
                    .get("message")
                    .and_then(Value::as_str)
                    .map(|s| s.to_string());
                let percentage = params
                    .value
                    .get("percentage")
                    .and_then(Value::as_u64)
                    .and_then(|p| u32::try_from(p).ok())
                    .map(|p| p.min(100));

                self.work_done.seq = self.work_done.seq.saturating_add(1);
                self.work_done.active.insert(
                    key,
                    WorkDoneProgressItem {
                        title,
                        message,
                        percentage,
                        seq: self.work_done.seq,
                    },
                );
            }
            "report" => {
                let title = params
                    .value
                    .get("title")
                    .and_then(Value::as_str)
                    .map(|s| s.to_string());
                let message = params
                    .value
                    .get("message")
                    .and_then(Value::as_str)
                    .map(|s| s.to_string());
                let percentage = params
                    .value
                    .get("percentage")
                    .and_then(Value::as_u64)
                    .and_then(|p| u32::try_from(p).ok())
                    .map(|p| p.min(100));

                self.work_done.seq = self.work_done.seq.saturating_add(1);
                self.work_done
                    .active
                    .entry(key)
                    .and_modify(|item| {
                        if let Some(title) = title.clone() {
                            item.title = title;
                        }
                        if message.is_some() {
                            item.message = message.clone();
                        }
                        if percentage.is_some() {
                            item.percentage = percentage;
                        }
                        item.seq = self.work_done.seq;
                    })
                    .or_insert_with(|| WorkDoneProgressItem {
                        title: title.unwrap_or_else(|| "Working".to_string()),
                        message,
                        percentage,
                        seq: self.work_done.seq,
                    });
            }
            "end" => {
                self.work_done.active.remove(&key);
            }
            _ => {}
        }
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
        // A delta response with no baseline (or a malformed/out-of-range delta) yields `None`;
        // reset the cache so the next refresh issues a full request.
        let Some(update) = semantic_tokens_result_to_update(
            result,
            &self.semantic_tokens_data,
            self.semantic_legend.as_ref(),
            line_index,
        ) else {
            // Only reset when this was a delta we couldn't apply; a completely unrecognized
            // response leaves the cache untouched.
            if result.get("edits").and_then(Value::as_array).is_some() {
                self.clear_semantic_tokens_cache();
            }
            return;
        };

        self.semantic_tokens_result_id = update.result_id;
        self.semantic_tokens_data = update.data;
        if let Some(edit) = update.edit {
            edits.push(edit);
        }
    }

    fn handle_pending_response(
        &mut self,
        line_index: &LineIndex,
        pending: PendingLspRequest,
        msg: &Value,
        edits: &mut Vec<ProcessingEdit>,
    ) -> Result<(), String> {
        match pending {
            PendingLspRequest::SemanticTokens { uri, version } => {
                // Reject responses for a different document (versions are per-document and can
                // collide across documents) or a stale version of the active document.
                if uri != self.document.uri || version != self.document.version {
                    return Ok(());
                }

                let result = msg.get("result").cloned().unwrap_or(Value::Null);
                self.handle_semantic_tokens_result(&result, line_index, edits);
            }
            PendingLspRequest::FoldingRanges { uri, version } => {
                // Folding regions are line-indexed, so stale/cross-document responses must not
                // enter core state.
                if uri != self.document.uri || version != self.document.version {
                    return Ok(());
                }

                edits.push(folding_ranges_result_to_processing_edit(
                    msg.get("result").unwrap_or(&Value::Null),
                ));
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
                    PendingLspRequest::SemanticTokens { uri, version } if *uri == doc_uri && *version == self.document.version
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
                                uri: doc_uri.clone(),
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
                    PendingLspRequest::FoldingRanges { uri, version } if *uri == doc_uri && *version == self.document.version
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
                                uri: doc_uri.clone(),
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

fn parse_supports_completion_item_resolve(capabilities: &Value) -> bool {
    capabilities
        .get("completionProvider")
        .and_then(|provider| provider.get("resolveProvider"))
        .and_then(Value::as_bool)
        .unwrap_or(false)
}

fn lsp_position_for_offset(line_index: &LineIndex, offset: usize) -> LspPosition {
    let (line, col) = line_index.char_offset_to_position(offset);
    let line_text = line_index.get_line_text(line).unwrap_or_default();
    LspCoordinateConverter::position_to_lsp(&line_text, line, col)
}

fn lsp_range_to_json(range: &LspRange) -> Value {
    json!({
        "start": { "line": range.start.line, "character": range.start.character },
        "end": { "line": range.end.line, "character": range.end.character },
    })
}

/// Outcome of applying a `textDocument/semanticTokens/*` response against a caller-held baseline.
///
/// Returned by [`semantic_tokens_result_to_update`]. The caller owns the per-document baseline
/// (`result_id` + `data`) and should store the returned values for the next delta request.
#[derive(Debug, Clone)]
pub struct SemanticTokensUpdate {
    /// The new `resultId` to send as `previousResultId` on the next delta request.
    pub result_id: Option<String>,
    /// The new full token data, to be used as the baseline for the next delta.
    pub data: Vec<u32>,
    /// The style-layer edit to apply, if the tokens could be resolved to intervals.
    pub edit: Option<ProcessingEdit>,
}

/// Convert a `textDocument/semanticTokens/{full,range,full/delta}` response into a
/// [`SemanticTokensUpdate`], without touching any session state.
///
/// This is the multi-document counterpart to the session's built-in single-active-document
/// auto-refresh: the caller (e.g. a workspace synchronizer) holds a per-URI baseline and passes
/// it in as `baseline`.
///
/// - **Full / range** responses (`{ data: [...] }`) replace the baseline entirely.
/// - **Delta** responses (`{ edits: [...] }`) are applied on top of `baseline`. If `baseline` is
///   empty or the delta is malformed/out-of-range, returns `None` — the caller should then issue a
///   full request and drop its stored baseline.
pub fn semantic_tokens_result_to_update(
    result: &Value,
    baseline: &[u32],
    legend: Option<&SemanticTokensLegend>,
    line_index: &LineIndex,
) -> Option<SemanticTokensUpdate> {
    let data = if result.get("data").and_then(Value::as_array).is_some() {
        semantic_tokens_full_data(result)
    } else if result.get("edits").and_then(Value::as_array).is_some() {
        semantic_tokens_apply_delta(result, baseline)?
    } else {
        return None;
    };

    let result_id = result
        .get("resultId")
        .and_then(Value::as_str)
        .map(|s| s.to_string());

    let edit = semantic_tokens_to_intervals(&data, line_index, |token_type, token_modifiers| {
        encode_semantic_style_id_from_server_legend(token_type, token_modifiers, legend)
    })
    .ok()
    .map(|intervals| ProcessingEdit::ReplaceStyleLayer {
        layer: StyleLayerId::SEMANTIC_TOKENS,
        intervals,
    });

    Some(SemanticTokensUpdate {
        result_id,
        data,
        edit,
    })
}

/// Parse the `data` array of a full/range semantic-tokens response into `u32`s.
fn semantic_tokens_full_data(result: &Value) -> Vec<u32> {
    let Some(data_arr) = result.get("data").and_then(Value::as_array) else {
        return Vec::new();
    };
    let mut data = Vec::with_capacity(data_arr.len());
    for v in data_arr {
        if let Some(n) = v.as_u64() {
            data.push(u32::try_from(n).unwrap_or(u32::MAX));
        }
    }
    data
}

/// Apply a semantic-tokens delta response on top of `baseline`, returning the new full data.
///
/// Returns `None` if `baseline` is empty (no baseline to apply against) or the delta is malformed
/// or references out-of-range indices — the caller should fall back to a full request.
fn semantic_tokens_apply_delta(result: &Value, baseline: &[u32]) -> Option<Vec<u32>> {
    let delta_edits = result.get("edits").and_then(Value::as_array)?;
    if baseline.is_empty() {
        return None;
    }

    struct DeltaEdit {
        start: usize,
        delete_count: usize,
        data: Vec<u32>,
    }

    let mut parsed = Vec::<DeltaEdit>::new();
    for edit in delta_edits {
        let start = edit.get("start").and_then(Value::as_u64)?;
        let delete_count = edit.get("deleteCount").and_then(Value::as_u64)?;
        let data = edit
            .get("data")
            .and_then(Value::as_array)
            .map(|arr| {
                arr.iter()
                    .filter_map(Value::as_u64)
                    .map(|n| u32::try_from(n).unwrap_or(u32::MAX))
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();

        parsed.push(DeltaEdit {
            start: usize::try_from(start).ok()?,
            delete_count: usize::try_from(delete_count).ok()?,
            data,
        });
    }

    // Apply in descending order to keep indices stable even if servers send unsorted edits.
    parsed.sort_by_key(|e| std::cmp::Reverse(e.start));

    let mut data = baseline.to_vec();
    for edit in parsed {
        if edit.start > data.len() {
            return None;
        }
        let end = edit.start.saturating_add(edit.delete_count);
        if end > data.len() {
            return None;
        }
        data.splice(edit.start..end, edit.data);
    }

    Some(data)
}

/// Convert a `textDocument/foldingRange` response into a [`ProcessingEdit`] that replaces the
/// folding regions (preserving collapsed state), without touching any session state.
///
/// This is the multi-document counterpart to the session's built-in folding auto-refresh.
pub fn folding_ranges_result_to_processing_edit(result: &Value) -> ProcessingEdit {
    ProcessingEdit::ReplaceFoldingRegions {
        regions: folding_regions_from_lsp_value(result),
        preserve_collapsed: true,
    }
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
        let Some(start) = usize::try_from(start).ok() else {
            continue;
        };
        let Some(end) = usize::try_from(end).ok() else {
            continue;
        };

        if start >= end {
            continue;
        }

        let mut region = FoldRegion::new(start, end);
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
    //
    // Note: 0x0400_0001..0x0400_0003 are reserved for LSP `documentHighlight` style ids.
    // Keep diagnostics in a non-overlapping sub-range.
    const BASE: StyleId = 0x0400_0100;
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
    LspCoordinateConverter::lsp_position_to_char_offset(line_index, pos)
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

#[cfg(test)]
mod pending_request_tests {
    //! Regression tests for P1-7: pending semantic-token / folding requests are keyed by URI, so
    //! switching or closing documents drops their in-flight requests (whose versions could
    //! otherwise collide with another document's per-document version counter).
    use super::*;
    use std::process::{Command as ProcessCommand, Stdio};
    use std::time::Duration;

    const URI_A: &str = "file:///tmp/pending-a.rs";
    const URI_B: &str = "file:///tmp/pending-b.rs";

    fn idle_server() -> ProcessCommand {
        // Answer `initialize`, then idle.
        let script = "body='{\"jsonrpc\":\"2.0\",\"id\":1,\"result\":{\"capabilities\":{}}}'; \
             printf 'Content-Length: %s\r\n\r\n%s' \"${#body}\" \"$body\"; sleep 30";
        let mut cmd = ProcessCommand::new("/bin/sh");
        cmd.arg("-c").arg(script).stderr(Stdio::null());
        cmd
    }

    fn start_session() -> LspSession {
        LspSession::start(LspSessionStartOptions {
            cmd: idle_server(),
            workspace_folders: Vec::new(),
            initialize_params: json!({}),
            initialize_timeout: Duration::from_secs(1),
            document: LspDocument {
                uri: URI_A.to_string(),
                language_id: "rust".to_string(),
                version: 1,
            },
            initial_text: "a\n".to_string(),
        })
        .expect("session starts")
    }

    #[test]
    fn set_active_document_drops_pending_for_previous_document() {
        let mut session = start_session();
        session
            .open_document(
                LspDocument {
                    uri: URI_B.to_string(),
                    language_id: "rust".to_string(),
                    version: 1,
                },
                "b\n".to_string(),
            )
            .expect("open second document");

        // Simulate an in-flight semantic-tokens request against document A, version 1.
        session.pending.insert(
            42,
            PendingLspRequest::SemanticTokens {
                uri: URI_A.to_string(),
                version: 1,
            },
        );

        // Switching to B must discard A's in-flight request so a late, same-version response from
        // A cannot be applied to B (and so maybe_refresh will issue a fresh request for B).
        session.set_active_document(URI_B).expect("switch active");

        assert!(
            session.pending.values().all(|p| p.uri() == URI_B),
            "pending requests for the previous document must be dropped"
        );
        assert!(!session.pending.contains_key(&42));
    }

    #[test]
    fn close_document_drops_its_pending_requests() {
        let mut session = start_session();
        session
            .open_document(
                LspDocument {
                    uri: URI_B.to_string(),
                    language_id: "rust".to_string(),
                    version: 1,
                },
                "b\n".to_string(),
            )
            .expect("open second document");

        session.pending.insert(
            7,
            PendingLspRequest::FoldingRanges {
                uri: URI_B.to_string(),
                version: 1,
            },
        );

        // Closing B (a non-active document) must drop its in-flight request.
        session.close_document(URI_B).expect("close document");

        assert!(!session.pending.contains_key(&7));
        assert!(session.pending.values().all(|p| p.uri() != URI_B));
    }
}
