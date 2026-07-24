//! Regression tests for C-5: `workspace/applyEdit` must honor the
//! `documentChanges[].textDocument.version` guard and reject stale edits (all-or-nothing).

use editor_core::Workspace;
use editor_core_lsp::workspace_sync::LspWorkspaceSync;
use editor_core_lsp::{LspDocument, LspSession, LspSessionStartOptions};
use serde_json::json;
use std::process::{Command as ProcessCommand, Stdio};
use std::time::Duration;

const TEST_URI: &str = "file:///tmp/ws-edit-version-test.rs";
const INITIAL_TEXT: &str = "abc\n";

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

/// A server that just answers `initialize` and then idles.
fn idle_server_script() -> String {
    let initialize = framed_message_script(
        r#"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}"#,
    );
    format!("{initialize}; sleep 30")
}

fn start_sync() -> (LspWorkspaceSync, Workspace) {
    let session = LspSession::start(LspSessionStartOptions {
        cmd: shell_command(&idle_server_script()),
        workspace_folders: Vec::new(),
        initialize_params: json!({}),
        initialize_timeout: Duration::from_secs(1),
        document: LspDocument {
            uri: TEST_URI.to_string(),
            language_id: "rust".to_string(),
            version: 1,
        },
        initial_text: INITIAL_TEXT.to_string(),
    })
    .expect("session starts");

    let sync = LspWorkspaceSync::new(session);

    let mut workspace = Workspace::new();
    workspace
        .open_buffer(Some(TEST_URI.to_string()), INITIAL_TEXT, 80)
        .expect("open buffer");

    (sync, workspace)
}

fn edit_with_version(version: Option<i64>) -> serde_json::Value {
    let text_document = match version {
        Some(v) => json!({ "uri": TEST_URI, "version": v }),
        None => json!({ "uri": TEST_URI, "version": null }),
    };
    json!({
        "documentChanges": [
            {
                "textDocument": text_document,
                "edits": [
                    {
                        "range": {
                            "start": { "line": 0, "character": 0 },
                            "end": { "line": 0, "character": 0 }
                        },
                        "newText": ">>"
                    }
                ]
            }
        ]
    })
}

#[test]
fn stale_workspace_edit_is_rejected_and_buffer_unchanged() {
    let (mut sync, mut workspace) = start_sync();
    let buffer_id = workspace.buffer_id_for_uri(TEST_URI).expect("buffer id");

    // Session tracks version 1; the edit claims it was generated against version 5.
    let edit = edit_with_version(Some(5));
    let result = sync.apply_workspace_edit(&mut workspace, &edit);

    assert!(
        result.is_err(),
        "stale workspace edit should be rejected, got {result:?}"
    );
    assert_eq!(
        workspace.buffer_text(buffer_id).unwrap(),
        INITIAL_TEXT,
        "buffer must be unchanged after a rejected edit"
    );
}

#[test]
fn matching_version_workspace_edit_applies() {
    let (mut sync, mut workspace) = start_sync();
    let buffer_id = workspace.buffer_id_for_uri(TEST_URI).expect("buffer id");

    let edit = edit_with_version(Some(1));
    let result = sync
        .apply_workspace_edit(&mut workspace, &edit)
        .expect("matching-version edit applies");

    assert_eq!(result.applied.len(), 1);
    assert_eq!(workspace.buffer_text(buffer_id).unwrap(), ">>abc\n");
}

#[test]
fn null_version_workspace_edit_applies_without_constraint() {
    let (mut sync, mut workspace) = start_sync();
    let buffer_id = workspace.buffer_id_for_uri(TEST_URI).expect("buffer id");

    let edit = edit_with_version(None);
    let result = sync
        .apply_workspace_edit(&mut workspace, &edit)
        .expect("null-version edit applies");

    assert_eq!(result.applied.len(), 1);
    assert_eq!(workspace.buffer_text(buffer_id).unwrap(), ">>abc\n");
}
