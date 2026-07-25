//! Multi-document derived-state routing through `LspWorkspaceSync`.
//!
//! Verifies that `refresh_derived_state_for_all_documents` + `poll_workspace` request semantic
//! tokens per URI and apply each response to the correct buffer, driven by one shared session.

use editor_core::{ViewId, Workspace};
use editor_core_lsp::workspace_sync::LspWorkspaceSync;
use editor_core_lsp::{LspDocument, LspSession, LspSessionStartOptions};
use serde_json::json;
use std::process::{Command as ProcessCommand, Stdio};
use std::thread;
use std::time::Duration;

const URI_A: &str = "file:///tmp/ws-multidoc-a.rs";
const URI_B: &str = "file:///tmp/ws-multidoc-b.rs";
const TEXT_A: &str = "fn a() {}\n";
const TEXT_B: &str = "fn b() {}\n";

fn framed_message_script(body: &str) -> String {
    format!(
        "body='{}'; printf 'Content-Length: %s\r\n\r\n%s' \"${{#body}}\" \"$body\"",
        body
    )
}

fn shell_command(script: &str) -> ProcessCommand {
    let mut cmd = ProcessCommand::new("/bin/sh");
    cmd.arg("-c").arg(script).stderr(Stdio::null());
    cmd
}

/// Fake server advertising a semantic-tokens legend (no delta), replying to the first two
/// `semanticTokens/full` requests (ids 2 and 3) with one token each, then idling.
///
/// A single token is 5 ints: `[deltaLine, deltaStart, length, tokenType, tokenModifiers]`.
fn semantic_server_script() -> String {
    let initialize = framed_message_script(
        r#"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"semanticTokensProvider":{"legend":{"tokenTypes":["keyword"],"tokenModifiers":[]},"full":true}}}}"#,
    );
    // id=2 → first refreshed document; id=3 → second. Both cover the leading "fn" keyword.
    let tokens_first = framed_message_script(
        r#"{"jsonrpc":"2.0","id":2,"result":{"resultId":"1","data":[0,0,2,0,0]}}"#,
    );
    let tokens_second = framed_message_script(
        r#"{"jsonrpc":"2.0","id":3,"result":{"resultId":"1","data":[0,0,2,0,0]}}"#,
    );
    format!("{initialize}; sleep 0.050; {tokens_first}; {tokens_second}; sleep 30")
}

fn start_sync() -> (LspWorkspaceSync, Workspace, ViewId, ViewId) {
    let session = LspSession::start(LspSessionStartOptions {
        cmd: shell_command(&semantic_server_script()),
        workspace_folders: Vec::new(),
        initialize_params: json!({}),
        initialize_timeout: Duration::from_secs(1),
        document: LspDocument {
            uri: URI_A.to_string(),
            language_id: "rust".to_string(),
            version: 1,
        },
        initial_text: TEXT_A.to_string(),
    })
    .expect("session starts");

    // Disable the single-active auto-refresh so it doesn't race the per-URI manual requests.
    let mut sync = LspWorkspaceSync::new(session);
    let mut opts = sync.session().auto_refresh_options();
    opts.semantic_tokens = false;
    opts.folding_ranges = false;
    sync.session_mut().set_auto_refresh_options(opts);

    let mut workspace = Workspace::new();
    let view_a = workspace
        .open_buffer(Some(URI_A.to_string()), TEXT_A, 80)
        .expect("open buffer A")
        .view_id;
    let view_b = workspace
        .open_buffer(Some(URI_B.to_string()), TEXT_B, 80)
        .expect("open buffer B")
        .view_id;

    (sync, workspace, view_a, view_b)
}

/// Returns `true` if any cell on the first visual row carries a style (semantic tokens applied).
fn first_row_has_style(workspace: &mut Workspace, view: ViewId) -> bool {
    let grid = workspace
        .get_viewport_content_styled(view, 0, 1)
        .expect("styled grid");
    grid.lines
        .iter()
        .flat_map(|line| line.cells.iter())
        .any(|cell| !cell.styles.is_empty())
}

#[test]
fn semantic_tokens_are_routed_per_uri_to_their_buffers() {
    let (mut sync, mut workspace, view_a, view_b) = start_sync();

    // `LspWorkspaceSync::new` starts with empty per-document state, so explicitly track both
    // documents (A is already open on the session; B is opened here).
    let id_a = workspace.buffer_id_for_uri(URI_A).expect("buffer A id");
    sync.open_workspace_document(&workspace, id_a, "rust")
        .expect("track A");
    let id_b = workspace.buffer_id_for_uri(URI_B).expect("buffer B id");
    sync.open_workspace_document(&workspace, id_b, "rust")
        .expect("track B");

    // Fan out semantic-token requests to every tracked document.
    sync.refresh_derived_state_for_all_documents(&workspace)
        .expect("refresh all");

    // Poll until both responses have been routed and applied.
    for _ in 0..50 {
        sync.poll_workspace(&mut workspace).expect("poll workspace");
        if first_row_has_style(&mut workspace, view_a)
            && first_row_has_style(&mut workspace, view_b)
        {
            break;
        }
        thread::sleep(Duration::from_millis(20));
    }

    assert!(
        first_row_has_style(&mut workspace, view_a),
        "document A should have received its semantic tokens"
    );
    assert!(
        first_row_has_style(&mut workspace, view_b),
        "document B should have received its semantic tokens"
    );
}
