//! Headless LSP event + deferred-request types.
//!
//! `editor-core-lsp` is intentionally UI-agnostic. However, many LSP servers emit "UX-ish"
//! notifications (e.g. `window/logMessage`) and may send server->client requests that must be
//! answered to avoid stalling the protocol (e.g. `window/showMessageRequest`).
//!
//! This module provides small, typed wrappers so frontends can:
//! - observe those messages as events
//! - (optionally) defer answering server->client requests until the UI is ready

use crate::lsp_sync::{LspPosition, LspRange};
use serde_json::Value;

/// LSP `MessageType` used by `window/showMessage` and `window/logMessage`.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LspMessageType {
    /// An error message.
    Error,
    /// A warning message.
    Warning,
    /// An informational message.
    Info,
    /// A log message (lowest severity).
    Log,
}

impl LspMessageType {
    /// Convert the numeric LSP `MessageType` into an enum.
    pub fn from_u64(value: u64) -> Option<Self> {
        match value {
            1 => Some(Self::Error),
            2 => Some(Self::Warning),
            3 => Some(Self::Info),
            4 => Some(Self::Log),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parameters for `window/showMessage`.
pub struct LspShowMessageParams {
    /// Message severity.
    pub typ: LspMessageType,
    /// Message text.
    pub message: String,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Parameters for `window/logMessage`.
pub struct LspLogMessageParams {
    /// Message severity.
    pub typ: LspMessageType,
    /// Message text.
    pub message: String,
}

#[derive(Debug, Clone)]
/// Parameters for `$/progress`.
pub struct LspProgressParams {
    /// Progress token (opaque to the client).
    pub token: Value,
    /// Progress payload.
    pub value: Value,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// Severity levels for `textDocument/publishDiagnostics`.
pub enum LspDiagnosticSeverity {
    /// Error diagnostics.
    Error,
    /// Warning diagnostics.
    Warning,
    /// Informational diagnostics.
    Information,
    /// Hint diagnostics.
    Hint,
}

impl LspDiagnosticSeverity {
    /// Convert the numeric LSP `DiagnosticSeverity` into an enum.
    pub fn from_u64(value: u64) -> Option<Self> {
        match value {
            1 => Some(Self::Error),
            2 => Some(Self::Warning),
            3 => Some(Self::Information),
            4 => Some(Self::Hint),
            _ => None,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
/// A single LSP diagnostic item.
pub struct LspDiagnostic {
    /// Diagnostic range.
    pub range: LspRange,
    /// Optional severity.
    pub severity: Option<LspDiagnosticSeverity>,
    /// Optional diagnostic code (number or string).
    pub code: Option<Value>,
    /// Optional diagnostic source (e.g. "rust-analyzer").
    pub source: Option<String>,
    /// Diagnostic message.
    pub message: String,
    /// Optional related information (server-specific JSON).
    pub related_information: Option<Value>,
    /// Optional extra data (server-specific JSON).
    pub data: Option<Value>,
}

#[derive(Debug, Clone, PartialEq)]
/// Parameters for `textDocument/publishDiagnostics`.
pub struct LspPublishDiagnosticsParams {
    /// Document URI (e.g. `file:///...`).
    pub uri: String,
    /// Diagnostics for the document.
    pub diagnostics: Vec<LspDiagnostic>,
    /// Optional document version.
    pub version: Option<i32>,
}

fn lsp_position_from_value(value: &Value) -> Option<LspPosition> {
    let line = value.get("line")?.as_u64()? as u32;
    let character = value.get("character")?.as_u64()? as u32;
    Some(LspPosition { line, character })
}

fn lsp_range_from_value(value: &Value) -> Option<LspRange> {
    let start = lsp_position_from_value(value.get("start")?)?;
    let end = lsp_position_from_value(value.get("end")?)?;
    Some(LspRange { start, end })
}

/// A server->client JSON-RPC request that the host may choose to answer later.
#[derive(Debug, Clone)]
pub struct LspServerRequest {
    /// JSON-RPC request id.
    pub id: u64,
    /// JSON-RPC method name.
    pub method: String,
    /// JSON-RPC params payload.
    pub params: Value,
}

impl LspServerRequest {
    /// Parse a server->client request from a raw JSON-RPC message value.
    pub fn from_json(msg: &Value) -> Option<Self> {
        let id = msg.get("id")?.as_u64()?;
        let method = msg.get("method")?.as_str()?.to_string();
        let params = msg.get("params").cloned().unwrap_or(Value::Null);
        Some(Self { id, method, params })
    }
}

#[derive(Debug, Clone)]
/// A typed subset of server->client LSP notifications commonly needed by UIs.
pub enum LspNotification {
    /// `window/showMessage`
    ShowMessage(LspShowMessageParams),
    /// `window/logMessage`
    LogMessage(LspLogMessageParams),
    /// `$/progress`
    Progress(LspProgressParams),
    /// `telemetry/event`
    Telemetry(Value),
    /// `textDocument/publishDiagnostics`
    PublishDiagnostics(LspPublishDiagnosticsParams),
}

impl LspNotification {
    /// Parse a notification by method name and `params` payload.
    pub fn from_method_and_params(method: &str, params: &Value) -> Option<Self> {
        match method {
            "window/showMessage" => {
                let typ = params
                    .get("type")?
                    .as_u64()
                    .and_then(LspMessageType::from_u64)?;
                let message = params.get("message")?.as_str()?.to_string();
                Some(Self::ShowMessage(LspShowMessageParams { typ, message }))
            }
            "window/logMessage" => {
                let typ = params
                    .get("type")?
                    .as_u64()
                    .and_then(LspMessageType::from_u64)?;
                let message = params.get("message")?.as_str()?.to_string();
                Some(Self::LogMessage(LspLogMessageParams { typ, message }))
            }
            "$/progress" => {
                let token = params.get("token").cloned().unwrap_or(Value::Null);
                let value = params.get("value").cloned().unwrap_or(Value::Null);
                Some(Self::Progress(LspProgressParams { token, value }))
            }
            "telemetry/event" => Some(Self::Telemetry(params.clone())),
            "textDocument/publishDiagnostics" => {
                let uri = params.get("uri")?.as_str()?.to_string();
                let version = params
                    .get("version")
                    .and_then(|v| v.as_i64())
                    .map(|v| v as i32);

                let diagnostics = params
                    .get("diagnostics")
                    .and_then(Value::as_array)
                    .map(|arr| {
                        arr.iter()
                            .filter_map(|d| {
                                let range = lsp_range_from_value(d.get("range")?)?;
                                let severity = d
                                    .get("severity")
                                    .and_then(Value::as_u64)
                                    .and_then(LspDiagnosticSeverity::from_u64);
                                let code = d.get("code").cloned();
                                let source = d
                                    .get("source")
                                    .and_then(Value::as_str)
                                    .map(|s| s.to_string());
                                let message = d
                                    .get("message")
                                    .and_then(Value::as_str)
                                    .unwrap_or("")
                                    .to_string();
                                let related_information = d.get("relatedInformation").cloned();
                                let data = d.get("data").cloned();

                                Some(LspDiagnostic {
                                    range,
                                    severity,
                                    code,
                                    source,
                                    message,
                                    related_information,
                                    data,
                                })
                            })
                            .collect::<Vec<_>>()
                    })
                    .unwrap_or_default();

                Some(Self::PublishDiagnostics(LspPublishDiagnosticsParams {
                    uri,
                    diagnostics,
                    version,
                }))
            }
            _ => None,
        }
    }
}

#[derive(Debug, Clone)]
/// A high-level LSP event produced by a headless session.
pub enum LspEvent {
    /// A parsed server->client notification.
    Notification(LspNotification),
    /// A server->client request that was deferred for the host to answer.
    DeferredRequest(LspServerRequest),
    /// A JSON-RPC response for a client-initiated request.
    Response(LspResponse),
}

#[derive(Debug, Clone, PartialEq)]
/// A JSON-RPC response error object.
pub struct LspResponseError {
    /// Error code.
    pub code: i64,
    /// Human-readable message.
    pub message: String,
    /// Optional structured error data.
    pub data: Option<Value>,
}

#[derive(Debug, Clone, PartialEq)]
/// A parsed JSON-RPC response message.
pub struct LspResponse {
    /// Response id (matches the request id).
    pub id: u64,
    /// Method name (if known / tracked by the session).
    pub method: String,
    /// Result payload (if successful).
    pub result: Option<Value>,
    /// Error payload (if failed).
    pub error: Option<LspResponseError>,
}

/// How to handle server->client requests (`{ id, method, params }`).
///
/// Important: deferring a request without later responding can deadlock an LSP server.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum LspServerRequestMode {
    /// Always respond immediately with built-in safe defaults.
    AutoReply,
    /// Defer only the explicitly listed request methods; auto-reply all others.
    DeferListed,
    /// Defer all server->client requests (host must respond).
    DeferAll,
}

#[derive(Debug, Clone, PartialEq, Eq)]
/// Policy for how a host should handle server->client requests.
pub struct LspServerRequestPolicy {
    /// Request handling mode.
    pub mode: LspServerRequestMode,
    /// Only used when `mode == DeferListed`.
    pub deferred_methods: Vec<String>,
}

impl LspServerRequestPolicy {
    /// Create a policy that always auto-replies with built-in safe defaults.
    pub fn auto_reply() -> Self {
        Self {
            mode: LspServerRequestMode::AutoReply,
            deferred_methods: Vec::new(),
        }
    }

    /// Create a policy that defers all server->client requests.
    pub fn defer_all() -> Self {
        Self {
            mode: LspServerRequestMode::DeferAll,
            deferred_methods: Vec::new(),
        }
    }

    /// Create a policy that defers only the listed request methods.
    pub fn defer_listed(methods: impl IntoIterator<Item = impl Into<String>>) -> Self {
        Self {
            mode: LspServerRequestMode::DeferListed,
            deferred_methods: methods.into_iter().map(Into::into).collect(),
        }
    }

    /// Returns `true` if the given request `method` should be deferred.
    pub fn should_defer(&self, method: &str) -> bool {
        match self.mode {
            LspServerRequestMode::AutoReply => false,
            LspServerRequestMode::DeferAll => true,
            LspServerRequestMode::DeferListed => self.deferred_methods.iter().any(|m| m == method),
        }
    }
}

impl Default for LspServerRequestPolicy {
    fn default() -> Self {
        Self::auto_reply()
    }
}
