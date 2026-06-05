//! Minimal JSON-RPC/LSP client over stdio.
//!
//! This module intentionally stays runtime-agnostic (no async runtime required) and is
//! feature-gated behind `lsp` to avoid pulling in JSON dependencies for consumers that
//! only need the core editor engine.

use crate::lsp_transport::{read_lsp_message, write_lsp_message};
use serde_json::Value;
use std::io::{self, BufReader, BufWriter};
use std::process::{Child, Command as ProcessCommand, Stdio};
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

/// Default time to wait for an LSP `shutdown` response before forcing termination.
pub const DEFAULT_SHUTDOWN_TIMEOUT: Duration = Duration::from_millis(250);

/// Default time to wait for the process to exit after sending an LSP `exit` notification.
pub const DEFAULT_EXIT_TIMEOUT: Duration = Duration::from_millis(250);

#[derive(Debug)]
/// Outbound messages sent to the LSP server.
pub enum LspOutbound {
    /// A raw JSON-RPC message value (already shaped as request/notification/response).
    Message(Value),
}

#[derive(Debug)]
/// Inbound messages received from the LSP server.
pub enum LspInbound {
    /// A raw JSON-RPC message value.
    Message(Value),
    /// An I/O error produced by the background reader/writer threads.
    IoError(String),
}

/// A minimal JSON-RPC/LSP client implemented on top of stdio pipes.
pub struct LspClient {
    child: Child,
    tx: mpsc::Sender<LspOutbound>,
    rx: mpsc::Receiver<LspInbound>,
    next_id: u64,
    workspace_folders: Vec<Value>,
}

impl LspClient {
    /// Spawn an LSP server process and connect via its stdio.
    ///
    /// Notes:
    /// - This overrides `stdin` / `stdout` to be piped.
    /// - Callers may configure `stderr` before passing `cmd` (e.g. `Stdio::null()` for TUIs).
    pub fn spawn(mut cmd: ProcessCommand, workspace_folders: Vec<Value>) -> io::Result<Self> {
        cmd.stdin(Stdio::piped()).stdout(Stdio::piped());
        let child = cmd.spawn()?;
        Self::from_child(child, workspace_folders)
    }

    /// Create a client from an already-spawned process child.
    pub fn from_child(mut child: Child, workspace_folders: Vec<Value>) -> io::Result<Self> {
        let stdin = child
            .stdin
            .take()
            .ok_or_else(|| io::Error::other("Failed to open LSP server stdin"))?;
        let stdout = child
            .stdout
            .take()
            .ok_or_else(|| io::Error::other("Failed to open LSP server stdout"))?;

        let (tx_out, rx_out) = mpsc::channel::<LspOutbound>();
        let (tx_in, rx_in) = mpsc::channel::<LspInbound>();

        {
            let tx_in = tx_in.clone();
            thread::spawn(move || lsp_write_loop(stdin, rx_out, tx_in));
        }
        thread::spawn(move || lsp_read_loop(stdout, tx_in));

        Ok(Self {
            child,
            tx: tx_out,
            rx: rx_in,
            next_id: 1,
            workspace_folders,
        })
    }

    /// Return the OS process id of the connected LSP server.
    pub fn process_id(&self) -> u32 {
        self.child.id()
    }

    /// Send a JSON-RPC notification to the server.
    pub fn notify(&self, method: &str, params: Value) -> io::Result<()> {
        self.send_message(json_rpc_notification(method, params))
    }

    /// Send a JSON-RPC request to the server and return the allocated request id.
    pub fn request(&mut self, method: &str, params: Value) -> io::Result<u64> {
        let id = self.next_id;
        self.next_id = self.next_id.saturating_add(1);

        self.send_message(json_rpc_request(id, method, params))?;
        Ok(id)
    }

    /// Send a successful JSON-RPC response for a server-initiated request.
    pub fn respond(&self, id: u64, result: Value) -> io::Result<()> {
        self.send_message(json_rpc_response(id, result))
    }

    /// Send an error JSON-RPC response for a server-initiated request.
    pub fn respond_error(
        &self,
        id: u64,
        code: i64,
        message: impl Into<String>,
        data: Option<Value>,
    ) -> io::Result<()> {
        self.send_message(json_rpc_error_response(id, code, message.into(), data))
    }

    fn send_message(&self, message: Value) -> io::Result<()> {
        self.tx
            .send(LspOutbound::Message(message))
            .map_err(|_| io::Error::new(io::ErrorKind::BrokenPipe, "LSP writer thread stopped"))
    }

    /// Gracefully shut down the LSP server and reap the child process.
    ///
    /// The sequence is: send `shutdown`, wait briefly for the response, send `exit`, then wait for
    /// process exit. If the server does not respond or does not exit, the child is killed and
    /// waited on so it cannot remain as a zombie process.
    pub fn shutdown(&mut self, shutdown_timeout: Duration) -> io::Result<()> {
        self.shutdown_with_timeouts(shutdown_timeout, DEFAULT_EXIT_TIMEOUT)
    }

    /// Gracefully shut down the server with explicit request and exit timeouts.
    pub fn shutdown_with_timeouts(
        &mut self,
        shutdown_timeout: Duration,
        exit_timeout: Duration,
    ) -> io::Result<()> {
        if self.reap_if_exited()? {
            return Ok(());
        }

        let shutdown_result = self
            .request("shutdown", Value::Null)
            .and_then(|id| self.wait_for_response(id, shutdown_timeout).map(|_| ()));

        if shutdown_result.is_ok() {
            return self.exit(exit_timeout);
        }

        self.terminate()
    }

    /// Send an LSP `exit` notification, wait briefly, then force termination if needed.
    pub fn exit(&mut self, exit_timeout: Duration) -> io::Result<()> {
        if self.reap_if_exited()? {
            return Ok(());
        }

        let _ = self.notify("exit", Value::Null);
        if self.wait_for_process_exit(exit_timeout)? {
            return Ok(());
        }

        self.terminate()
    }

    /// Kill the child process if it is still running, then wait for it.
    pub fn terminate(&mut self) -> io::Result<()> {
        if self.reap_if_exited()? {
            return Ok(());
        }

        match self.child.kill() {
            Ok(()) => {}
            Err(err) if err.kind() == io::ErrorKind::InvalidInput => {}
            Err(err) => return Err(err),
        }

        let _ = self.child.wait()?;
        Ok(())
    }

    fn reap_if_exited(&mut self) -> io::Result<bool> {
        if self.child.try_wait()?.is_some() {
            let _ = self.child.wait()?;
            return Ok(true);
        }
        Ok(false)
    }

    fn wait_for_process_exit(&mut self, timeout: Duration) -> io::Result<bool> {
        let deadline = Instant::now() + timeout;
        loop {
            if self.reap_if_exited()? {
                return Ok(true);
            }

            let now = Instant::now();
            if now >= deadline {
                return Ok(false);
            }

            thread::sleep((deadline - now).min(Duration::from_millis(10)));
        }
    }

    /// Try to receive the next inbound message without blocking.
    pub fn try_recv(&self) -> Option<LspInbound> {
        self.rx.try_recv().ok()
    }

    /// Wait for a matching JSON-RPC response message `{ id: request_id, ... }`.
    ///
    /// While waiting, this also answers common server->client requests (e.g. `workspace/configuration`)
    /// via [`Self::handle_server_request`], to avoid deadlocks.
    pub fn wait_for_response(&mut self, request_id: u64, timeout: Duration) -> io::Result<Value> {
        let deadline = Instant::now() + timeout;

        loop {
            let now = Instant::now();
            if now >= deadline {
                return Err(io::Error::new(
                    io::ErrorKind::TimedOut,
                    format!("Timed out waiting for LSP response id={}", request_id),
                ));
            }

            let remaining = deadline - now;
            let inbound = self
                .rx
                .recv_timeout(remaining)
                .map_err(|err| io::Error::new(io::ErrorKind::TimedOut, err))?;

            match inbound {
                LspInbound::IoError(err) => {
                    return Err(io::Error::new(io::ErrorKind::BrokenPipe, err));
                }
                LspInbound::Message(msg) => {
                    if msg.get("id").and_then(|v| v.as_u64()) == Some(request_id) {
                        return Ok(msg);
                    }

                    // Handle server requests while waiting, otherwise some servers may block.
                    if msg.get("method").is_some() && msg.get("id").is_some() {
                        self.handle_server_request(&msg)?;
                    }
                }
            }
        }
    }

    /// Respond to common server->client requests with safe defaults.
    ///
    /// If the message is not a request (missing `id`), this is a no-op.
    pub fn handle_server_request(&mut self, msg: &Value) -> io::Result<()> {
        let Some(id) = msg.get("id").and_then(|v| v.as_u64()) else {
            return Ok(());
        };
        let method = msg.get("method").and_then(|v| v.as_str()).unwrap_or("");

        let result = match method {
            "workspace/configuration" => {
                let item_count = msg
                    .get("params")
                    .and_then(|p| p.get("items"))
                    .and_then(|items| items.as_array())
                    .map(|items| items.len())
                    .unwrap_or(0);

                Value::Array(std::iter::repeat_n(Value::Null, item_count).collect())
            }
            "workspace/workspaceFolders" => Value::Array(self.workspace_folders.clone()),
            "client/registerCapability" => Value::Null,
            // The following methods are "necessary but headless" in many integrations:
            // reply with safe defaults so servers don't block waiting for UI.
            "window/workDoneProgress/create" => Value::Null,
            "window/showMessageRequest" => Value::Null,
            "workspace/semanticTokens/refresh" => Value::Null,
            "workspace/inlayHint/refresh" => Value::Null,
            "workspace/codeLens/refresh" => Value::Null,
            "workspace/diagnostic/refresh" => Value::Null,
            "workspace/applyEdit" => serde_json::json!({
                "applied": false,
                "failureReason": "editor-core-lsp: workspace/applyEdit is headless; host must apply edits",
            }),
            _ => Value::Null,
        };

        self.respond(id, result)
    }
}

impl Drop for LspClient {
    fn drop(&mut self) {
        let _ = self.terminate();
    }
}

fn json_rpc_notification(method: &str, params: Value) -> Value {
    let mut obj = serde_json::Map::new();
    obj.insert("jsonrpc".to_string(), Value::String("2.0".to_string()));
    obj.insert("method".to_string(), Value::String(method.to_string()));
    obj.insert("params".to_string(), params);
    Value::Object(obj)
}

fn json_rpc_request(id: u64, method: &str, params: Value) -> Value {
    let mut obj = serde_json::Map::new();
    obj.insert("jsonrpc".to_string(), Value::String("2.0".to_string()));
    obj.insert("id".to_string(), Value::Number(id.into()));
    obj.insert("method".to_string(), Value::String(method.to_string()));
    obj.insert("params".to_string(), params);
    Value::Object(obj)
}

fn json_rpc_response(id: u64, result: Value) -> Value {
    let mut obj = serde_json::Map::new();
    obj.insert("jsonrpc".to_string(), Value::String("2.0".to_string()));
    obj.insert("id".to_string(), Value::Number(id.into()));
    obj.insert("result".to_string(), result);
    Value::Object(obj)
}

fn json_rpc_error_response(id: u64, code: i64, message: String, data: Option<Value>) -> Value {
    let mut error = serde_json::Map::new();
    error.insert("code".to_string(), Value::Number(code.into()));
    error.insert("message".to_string(), Value::String(message));
    if let Some(data) = data {
        error.insert("data".to_string(), data);
    }

    let mut obj = serde_json::Map::new();
    obj.insert("jsonrpc".to_string(), Value::String("2.0".to_string()));
    obj.insert("id".to_string(), Value::Number(id.into()));
    obj.insert("error".to_string(), Value::Object(error));
    Value::Object(obj)
}

fn lsp_write_loop(
    stdin: std::process::ChildStdin,
    rx: mpsc::Receiver<LspOutbound>,
    tx_in: mpsc::Sender<LspInbound>,
) {
    let mut writer = BufWriter::new(stdin);
    for msg in rx {
        match msg {
            LspOutbound::Message(value) => {
                if let Err(err) = write_lsp_message(&mut writer, &value) {
                    let _ = tx_in.send(LspInbound::IoError(err.to_string()));
                    break;
                }
            }
        }
    }
}

fn lsp_read_loop(stdout: std::process::ChildStdout, tx: mpsc::Sender<LspInbound>) {
    let mut reader = BufReader::new(stdout);
    loop {
        match read_lsp_message(&mut reader) {
            Ok(Some(value)) => {
                if tx.send(LspInbound::Message(value)).is_err() {
                    break;
                }
            }
            Ok(None) => break,
            Err(err) => {
                let _ = tx.send(LspInbound::IoError(err.to_string()));
                break;
            }
        }
    }
}
