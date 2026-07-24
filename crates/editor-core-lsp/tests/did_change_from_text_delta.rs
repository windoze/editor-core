//! End-to-end test for [`LspSession::did_change_from_text_delta`].
//!
//! Uses a minimal shell-scripted "server" that only answers `initialize` and then idles, so we can
//! exercise the real session send path (version bump + internal mirror advance) without depending
//! on a language server binary.

use editor_core::{
    AutoPairsConfig, Command, CursorCommand, EditCommand, EditorStateManager, ViewCommand,
};
use editor_core_lsp::{LspDocument, LspSession, LspSessionStartOptions};
use serde_json::json;
use std::process::{Command as ProcessCommand, Stdio};
use std::time::Duration;

const TEST_URI: &str = "file:///tmp/did-change-delta-test.rs";
const INITIAL_TEXT: &str = "()";

fn framed_message_script(body: &str) -> String {
    format!(
        "body='{}'; printf 'Content-Length: %s\r\n\r\n%s' \"${{#body}}\" \"$body\"",
        body
    )
}

fn idle_server_script() -> String {
    let initialize =
        framed_message_script(r#"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}"#);
    // Answer initialize, then stay alive so didChange notifications have a live pipe to write to.
    format!("{initialize}; sleep 30")
}

fn start_session() -> LspSession {
    let mut cmd = ProcessCommand::new("/bin/sh");
    cmd.arg("-c")
        .arg(idle_server_script())
        .stderr(Stdio::null());
    LspSession::start(LspSessionStartOptions {
        cmd,
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
    .expect("session starts")
}

#[test]
fn did_change_from_text_delta_handles_auto_pair_deletion_end_to_end() {
    let mut session = start_session();
    assert_eq!(session.mirror_char_count(), 2, "mirror starts at '()'");
    assert_eq!(session.document().version, 1);

    // Editor with auto-pairs; backspace between "()" deletes both characters at once.
    let mut manager = EditorStateManager::new(INITIAL_TEXT, 80);
    manager
        .execute(Command::View(ViewCommand::SetAutoPairsConfig {
            config: AutoPairsConfig {
                enabled: true,
                ..AutoPairsConfig::default()
            },
        }))
        .unwrap();
    manager
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1,
        }))
        .unwrap();
    manager
        .execute(Command::Edit(EditCommand::Backspace))
        .unwrap();
    assert_eq!(manager.editor().get_text(), "");

    let delta = manager.take_last_text_delta().expect("delta produced");
    session
        .did_change_from_text_delta(&delta)
        .expect("didChange sends");

    // Version advanced once, and the mirror now matches the (empty) editor buffer.
    assert_eq!(session.document().version, 2);
    assert_eq!(session.mirror_char_count(), 0);
    assert_eq!(session.mirror_char_count(), manager.editor().char_count());
}

#[test]
fn did_change_from_text_delta_is_noop_for_empty_delta() {
    let mut session = start_session();
    let mut manager = EditorStateManager::new(INITIAL_TEXT, 80);
    // A no-op command (cursor move) produces an empty text delta; forwarding it must not bump the
    // version or the mirror.
    manager
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1,
        }))
        .unwrap();
    if let Some(delta) = manager.take_last_text_delta() {
        session
            .did_change_from_text_delta(&delta)
            .expect("noop send");
    }
    assert_eq!(session.document().version, 1);
    assert_eq!(session.mirror_char_count(), 2);
}
