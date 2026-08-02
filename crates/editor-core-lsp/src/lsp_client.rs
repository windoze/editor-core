//! Minimal JSON-RPC/LSP client over stdio.
//!
//! This module intentionally stays runtime-agnostic (no async runtime required) and is
//! feature-gated behind `lsp` to avoid pulling in JSON dependencies for consumers that
//! only need the core editor engine.

use crate::lsp_transport::{read_lsp_message, write_lsp_message};
use serde_json::Value;
use std::cell::RefCell;
use std::collections::VecDeque;
use std::io::{self, BufReader, BufWriter, Read};
use std::process::ChildStderr;
use std::process::{Child, Command as ProcessCommand, ExitStatus, Stdio};
use std::sync::{Arc, Mutex, mpsc};
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
    deferred_inbound: RefCell<VecDeque<LspInbound>>,
    next_id: u64,
    workspace_folders: Vec<Value>,
    stderr_tail: Option<Arc<Mutex<StderrTail>>>,
}

enum WaitInbound {
    Matched(Value),
    Deferred(LspInbound),
    HandledServerRequest,
}

#[derive(Debug)]
struct StderrTail {
    bytes: Vec<u8>,
    max_bytes: usize,
}

impl StderrTail {
    fn new(max_bytes: usize) -> Self {
        Self {
            bytes: Vec::new(),
            max_bytes,
        }
    }

    fn push(&mut self, chunk: &[u8]) {
        self.bytes.extend_from_slice(chunk);
        if self.bytes.len() > self.max_bytes {
            let overflow = self.bytes.len() - self.max_bytes;
            self.bytes.drain(0..overflow);
        }
    }

    fn snapshot(&self) -> Option<String> {
        if self.bytes.is_empty() {
            return None;
        }
        Some(String::from_utf8_lossy(&self.bytes).into_owned())
    }
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
        let stderr = child.stderr.take();

        let (tx_out, rx_out) = mpsc::channel::<LspOutbound>();
        let (tx_in, rx_in) = mpsc::channel::<LspInbound>();
        let stderr_tail = stderr.map(|stderr| {
            let tail = Arc::new(Mutex::new(StderrTail::new(8 * 1024)));
            let thread_tail = tail.clone();
            thread::spawn(move || lsp_stderr_loop(stderr, thread_tail));
            tail
        });

        {
            let tx_in = tx_in.clone();
            thread::spawn(move || lsp_write_loop(stdin, rx_out, tx_in));
        }
        thread::spawn(move || lsp_read_loop(stdout, tx_in));

        Ok(Self {
            child,
            tx: tx_out,
            rx: rx_in,
            deferred_inbound: RefCell::new(VecDeque::new()),
            next_id: 1,
            workspace_folders,
            stderr_tail,
        })
    }

    /// Return the OS process id of the connected LSP server.
    pub fn process_id(&self) -> u32 {
        self.child.id()
    }

    /// Return the LSP server process exit status if it has already exited.
    pub fn try_exit_status(&mut self) -> io::Result<Option<ExitStatus>> {
        self.child.try_wait()
    }

    /// Return a bounded tail of stderr captured from the LSP server, if stderr was piped.
    pub fn stderr_tail(&self) -> Option<String> {
        self.stderr_tail
            .as_ref()
            .and_then(|tail| tail.lock().ok())
            .and_then(|tail| tail.snapshot())
    }

    /// Return the current client-side workspace folder list used for
    /// `workspace/workspaceFolders` responses.
    pub fn workspace_folders(&self) -> &[Value] {
        &self.workspace_folders
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

    /// Apply a workspace folder change to the client-side folder list used when a server asks
    /// `workspace/workspaceFolders`.
    pub fn apply_workspace_folder_change(&mut self, added: &[Value], removed: &[Value]) {
        for removed_uri in removed.iter().filter_map(workspace_folder_uri) {
            self.workspace_folders
                .retain(|folder| workspace_folder_uri(folder) != Some(removed_uri));
        }

        for folder in added {
            let Some(uri) = workspace_folder_uri(folder) else {
                continue;
            };
            self.workspace_folders
                .retain(|existing| workspace_folder_uri(existing) != Some(uri));
            self.workspace_folders.push(folder.clone());
        }
    }

    /// Return only the workspace folder changes that would mutate the current client-side folder
    /// list.
    pub fn effective_workspace_folder_change(
        &self,
        added: &[Value],
        removed: &[Value],
    ) -> (Vec<Value>, Vec<Value>) {
        let effective_removed = removed
            .iter()
            .filter_map(|folder| {
                let uri = workspace_folder_uri(folder)?;
                self.workspace_folders
                    .iter()
                    .any(|existing| workspace_folder_uri(existing) == Some(uri))
                    .then(|| folder.clone())
            })
            .collect::<Vec<_>>();

        let effective_added = added
            .iter()
            .filter_map(|folder| {
                let uri = workspace_folder_uri(folder)?;
                let already_present = self.workspace_folders.iter().any(|existing| {
                    workspace_folder_uri(existing) == Some(uri)
                        && !effective_removed
                            .iter()
                            .any(|removed| workspace_folder_uri(removed) == Some(uri))
                });
                (!already_present).then(|| folder.clone())
            })
            .collect::<Vec<_>>();

        (effective_added, effective_removed)
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
        if let Some(inbound) = self.deferred_inbound.borrow_mut().pop_front() {
            return Some(inbound);
        }

        self.rx.try_recv().ok()
    }

    /// Wait for a matching JSON-RPC response message `{ id: request_id, ... }`.
    ///
    /// While waiting, this also answers common server->client requests (e.g. `workspace/configuration`)
    /// via [`Self::handle_server_request`] to avoid deadlocks. Other inbound messages are deferred
    /// and remain visible to later [`Self::try_recv`] calls.
    pub fn wait_for_response(&mut self, request_id: u64, timeout: Duration) -> io::Result<Value> {
        let deadline = Instant::now() + timeout;
        let mut deferred = self.take_deferred_inbound();

        let mut cached = std::mem::take(&mut deferred);
        while let Some(inbound) = cached.pop_front() {
            let outcome = match self.handle_wait_inbound(inbound, request_id) {
                Ok(outcome) => outcome,
                Err(err) => {
                    deferred.extend(cached);
                    self.restore_deferred_inbound(deferred);
                    return Err(err);
                }
            };

            match outcome {
                WaitInbound::Matched(msg) => {
                    deferred.extend(cached);
                    self.restore_deferred_inbound(deferred);
                    return Ok(msg);
                }
                WaitInbound::Deferred(inbound) => deferred.push_back(inbound),
                WaitInbound::HandledServerRequest => {}
            }
        }

        loop {
            let now = Instant::now();
            if now >= deadline {
                self.restore_deferred_inbound(deferred);
                return Err(io::Error::new(
                    io::ErrorKind::TimedOut,
                    format!("Timed out waiting for LSP response id={}", request_id),
                ));
            }

            let remaining = deadline - now;
            let inbound = self.rx.recv_timeout(remaining).map_err(|err| {
                self.restore_deferred_inbound(std::mem::take(&mut deferred));
                io::Error::new(io::ErrorKind::TimedOut, err)
            })?;

            let outcome = match self.handle_wait_inbound(inbound, request_id) {
                Ok(outcome) => outcome,
                Err(err) => {
                    self.restore_deferred_inbound(deferred);
                    return Err(err);
                }
            };

            match outcome {
                WaitInbound::Matched(msg) => {
                    self.restore_deferred_inbound(deferred);
                    return Ok(msg);
                }
                WaitInbound::Deferred(inbound) => deferred.push_back(inbound),
                WaitInbound::HandledServerRequest => {}
            }
        }
    }

    fn take_deferred_inbound(&self) -> VecDeque<LspInbound> {
        std::mem::take(&mut *self.deferred_inbound.borrow_mut())
    }

    fn restore_deferred_inbound(&self, mut deferred: VecDeque<LspInbound>) {
        if deferred.is_empty() {
            return;
        }

        let mut cached = self.deferred_inbound.borrow_mut();
        if cached.is_empty() {
            *cached = deferred;
        } else {
            deferred.append(&mut cached);
            *cached = deferred;
        }
    }

    fn handle_wait_inbound(
        &mut self,
        inbound: LspInbound,
        request_id: u64,
    ) -> io::Result<WaitInbound> {
        match inbound {
            LspInbound::IoError(err) => Err(io::Error::new(io::ErrorKind::BrokenPipe, err)),
            LspInbound::Message(msg) => {
                if msg.get("method").is_some() && msg.get("id").is_some() {
                    if msg.get("id").and_then(Value::as_u64).is_some() {
                        self.handle_server_request(&msg)?;
                        return Ok(WaitInbound::HandledServerRequest);
                    }

                    return Ok(WaitInbound::Deferred(LspInbound::Message(msg)));
                }

                if msg.get("id").and_then(Value::as_u64) == Some(request_id) {
                    return Ok(WaitInbound::Matched(msg));
                }

                Ok(WaitInbound::Deferred(LspInbound::Message(msg)))
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

fn workspace_folder_uri(folder: &Value) -> Option<&str> {
    folder.get("uri").and_then(Value::as_str)
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

fn lsp_stderr_loop(stderr: ChildStderr, tail: Arc<Mutex<StderrTail>>) {
    let mut reader = BufReader::new(stderr);
    let mut buf = [0_u8; 4096];
    loop {
        match reader.read(&mut buf) {
            Ok(0) => break,
            Ok(n) => {
                if let Ok(mut tail) = tail.lock() {
                    tail.push(&buf[..n]);
                } else {
                    break;
                }
            }
            Err(_) => break,
        }
    }
}
