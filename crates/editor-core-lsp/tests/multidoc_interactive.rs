//! Multi-document interactive requests over a single shared session.
//!
//! Verifies the per-URI request API (`*_for_uri`) and that responses carry their source URI so a
//! shared `LspSession` can serve N documents' interactive features without a single active
//! document. Uses the same `/bin/sh` fake-server harness as the other integration tests.

use editor_core::LineIndex;
use editor_core_lsp::{LspDocument, LspEvent, LspResponse, LspSession, LspSessionStartOptions};
use serde_json::json;
use std::process::{Command as ProcessCommand, Stdio};
use std::thread;
use std::time::Duration;

const URI_A: &str = "file:///tmp/multidoc-a.rs";
const URI_B: &str = "file:///tmp/multidoc-b.rs";
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

/// A fake server that:
/// - replies to `initialize` (id=1) advertising hover/completion/semanticTokens support,
/// - replies to id=2 as a hover result tagged "A",
/// - replies to id=3 as a completion result tagged "B",
/// - then emits a `window/logMessage` sentinel so the test knows all replies were sent.
///
/// Request ids are globally monotonic (initialize=1), so the test must issue hover then completion
/// to line up with id=2 then id=3.
fn interactive_server_script() -> String {
    let initialize = framed_message_script(
        r#"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"hoverProvider":true,"completionProvider":{}}}}"#,
    );
    let hover = framed_message_script(
        r#"{"jsonrpc":"2.0","id":2,"result":{"contents":{"kind":"plaintext","value":"doc-A"}}}"#,
    );
    let completion = framed_message_script(
        r#"{"jsonrpc":"2.0","id":3,"result":{"isIncomplete":false,"items":[{"label":"doc-B"}]}}"#,
    );
    let signal = framed_message_script(
        &json!({
            "jsonrpc": "2.0",
            "method": "window/logMessage",
            "params": { "type": 3, "message": "replies-sent" }
        })
        .to_string(),
    );

    format!("{initialize}; sleep 0.050; {hover}; {completion}; {signal}; sleep 30")
}

fn start_session(script: String) -> LspSession {
    LspSession::start(LspSessionStartOptions {
        cmd: shell_command(&script),
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
    .expect("session starts")
}

/// Poll until the sentinel log message is observed, collecting all `Response` events seen.
fn poll_until_signal(session: &mut LspSession, line_index: &LineIndex) -> Vec<LspResponse> {
    let mut responses = Vec::new();
    let mut saw_signal = false;

    for _ in 0..50 {
        session
            .poll_edits_with_line_index(line_index)
            .expect("poll succeeds");

        for event in session.drain_events() {
            match event {
                LspEvent::Response(resp) => responses.push(resp),
                LspEvent::Notification(
                    editor_core_lsp::LspNotification::LogMessage(params),
                ) if params.message == "replies-sent" => saw_signal = true,
                _ => {}
            }
        }

        // Keep polling a couple ticks after the signal so late responses are drained.
        if saw_signal && responses.len() >= 2 {
            return responses;
        }
        thread::sleep(Duration::from_millis(20));
    }

    responses
}

#[test]
fn interactive_requests_carry_their_source_uri() {
    let mut session = start_session(interactive_server_script());
    let line_index = LineIndex::from_text(TEXT_A);

    // Track a second document on the same session.
    session
        .open_document(
            LspDocument {
                uri: URI_B.to_string(),
                language_id: "rust".to_string(),
                version: 1,
            },
            TEXT_B.to_string(),
        )
        .expect("open second document");

    // Issue hover for A (→ id=2) then completion for B (→ id=3).
    let hover_id = session
        .request_hover_for_uri(URI_A, &line_index, 0, 3)
        .expect("hover for A");
    let completion_id = session
        .request_completion_for_uri(URI_B, &line_index, 0, 3)
        .expect("completion for B");

    // Issuing a request for B must NOT switch the active document or drop A's state.
    assert_eq!(session.document().uri, URI_A);

    let responses = poll_until_signal(&mut session, &line_index);

    let hover = responses
        .iter()
        .find(|r| r.id == hover_id)
        .expect("hover response");
    assert_eq!(hover.uri.as_deref(), Some(URI_A));
    assert_eq!(hover.method, "textDocument/hover");

    let completion = responses
        .iter()
        .find(|r| r.id == completion_id)
        .expect("completion response");
    assert_eq!(completion.uri.as_deref(), Some(URI_B));
    assert_eq!(completion.method, "textDocument/completion");
}

#[test]
fn per_uri_request_for_untracked_document_returns_err() {
    let mut session = start_session(interactive_server_script());
    let line_index = LineIndex::from_text(TEXT_A);

    let result = session.request_hover_for_uri("file:///tmp/not-open.rs", &line_index, 0, 0);
    assert!(result.is_err(), "expected Err for untracked uri");
    assert!(
        result.unwrap_err().contains("not-open.rs"),
        "error should name the missing uri"
    );
}

#[test]
fn legacy_no_uri_request_targets_active_document_and_tags_its_uri() {
    let mut session = start_session(interactive_server_script());
    let line_index = LineIndex::from_text(TEXT_A);

    // The legacy method targets the active document; it delegates to the per-URI path, so the
    // response is tagged with the active document's URI (accurate routing info for consumers).
    let hover_id = session
        .request_hover(&line_index, 0, 3)
        .expect("hover on active document");

    let responses = poll_until_signal(&mut session, &line_index);
    let hover = responses
        .iter()
        .find(|r| r.id == hover_id)
        .expect("hover response");
    assert_eq!(hover.uri.as_deref(), Some(URI_A));
}
