use editor_core::processing::ProcessingEdit;
use editor_core::{Command, EditCommand, EditorStateManager, FoldRegion, LineIndex};
use editor_core_lsp::{LspDocument, LspEvent, LspNotification, LspSession, LspSessionStartOptions};
use serde_json::json;
use std::process::{Command as ProcessCommand, Stdio};
use std::thread;
use std::time::Duration;

const TEST_URI: &str = "file:///tmp/folding-version-test.rs";
const INITIAL_TEXT: &str = "a\nb\nc\nd\ne\nf";

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

fn folding_response_script(delay_ms: u64, log_message: &str) -> String {
    let initialize = framed_message_script(
        r#"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{"foldingRangeProvider":true}}}"#,
    );
    let folding_response = framed_message_script(
        r#"{"jsonrpc":"2.0","id":2,"result":[{"startLine":0,"endLine":1},{"startLine":3,"endLine":4,"kind":"imports"}]}"#,
    );
    let signal = framed_message_script(
        &json!({
            "jsonrpc": "2.0",
            "method": "window/logMessage",
            "params": { "type": 3, "message": log_message }
        })
        .to_string(),
    );

    format!("{initialize}; sleep 0.{delay_ms:03}; {folding_response}; {signal}; sleep 30")
}

fn start_folding_session(script: String) -> LspSession {
    LspSession::start(LspSessionStartOptions {
        cmd: shell_command(&script),
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

fn collapsed_region(start_line: usize, end_line: usize) -> FoldRegion {
    let mut region = FoldRegion::new(start_line, end_line);
    region.collapse();
    region
}

fn poll_until_log_message(
    session: &mut LspSession,
    line_index: &LineIndex,
    expected_message: &str,
) -> Vec<ProcessingEdit> {
    let mut all_edits = Vec::new();

    for _ in 0..50 {
        let edits = session
            .poll_edits_with_line_index(line_index)
            .expect("poll succeeds");
        all_edits.extend(edits);

        let saw_signal = session.drain_events().into_iter().any(|event| {
            matches!(
                event,
                LspEvent::Notification(LspNotification::LogMessage(params))
                    if params.message == expected_message
            )
        });
        if saw_signal {
            return all_edits;
        }

        thread::sleep(Duration::from_millis(20));
    }

    panic!("folding response signal was not observed");
}

fn has_replace_folding_regions(edits: &[ProcessingEdit]) -> bool {
    edits
        .iter()
        .any(|edit| matches!(edit, ProcessingEdit::ReplaceFoldingRegions { .. }))
}

#[test]
fn current_version_folding_response_produces_processing_edit() {
    let mut session = start_folding_session(folding_response_script(50, "current-folding"));
    let line_index = LineIndex::from_text(INITIAL_TEXT);

    let initial_edits = session
        .poll_edits_with_line_index(&line_index)
        .expect("initial poll sends folding request");
    assert!(!has_replace_folding_regions(&initial_edits));

    let edits = poll_until_log_message(&mut session, &line_index, "current-folding");

    let replace = edits
        .iter()
        .find_map(|edit| match edit {
            ProcessingEdit::ReplaceFoldingRegions {
                regions,
                preserve_collapsed,
            } => Some((regions, preserve_collapsed)),
            _ => None,
        })
        .expect("folding response produces ReplaceFoldingRegions");

    assert_eq!(replace.0.len(), 2);
    assert!(*replace.1);
}

#[test]
fn stale_folding_response_after_edit_does_not_replace_shifted_state() {
    let mut session = start_folding_session(folding_response_script(200, "stale-folding"));
    let mut state = EditorStateManager::new(INITIAL_TEXT, 80);
    state.replace_folding_regions(vec![collapsed_region(1, 2), collapsed_region(4, 5)], false);

    let initial_edits = session
        .poll_edits_with_line_index(&state.editor().line_index)
        .expect("initial poll sends folding request");
    assert!(!has_replace_folding_regions(&initial_edits));

    let change = session.content_change_for_offsets(&state.editor().line_index, 0, 0, "\n");
    session
        .did_change(change)
        .expect("didChange bumps document version");
    state
        .execute(Command::Edit(EditCommand::Insert {
            offset: 0,
            text: "\n".to_string(),
        }))
        .expect("local edit shifts fold regions");

    let edits = poll_until_log_message(&mut session, &state.editor().line_index, "stale-folding");
    assert!(!has_replace_folding_regions(&edits));

    state.apply_processing_edits(edits);
    let derived = state.editor().folding_manager.derived_regions();
    assert_eq!(derived.len(), 2);
    assert_eq!((derived[0].start_line, derived[0].end_line), (2, 3));
    assert!(derived[0].is_collapsed);
    assert_eq!((derived[1].start_line, derived[1].end_line), (5, 6));
    assert!(derived[1].is_collapsed);
}
