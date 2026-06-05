use editor_core::processing::ProcessingEdit;
use editor_core::{DiagnosticSeverity, LineIndex, StyleLayerId};
use editor_core_lsp::{
    LspDiagnostic, LspDiagnosticSeverity, LspDocument, LspEvent, LspNotification, LspPosition,
    LspPublishDiagnosticsParams, LspRange, LspSession, LspSessionStartOptions,
    lsp_diagnostics_to_processing_edits,
};
use serde_json::json;
use std::process::{Command, Stdio};
use std::thread;
use std::time::Duration;

const TEST_URI: &str = "file:///tmp/diagnostics-version-test.rs";

fn framed_message_script(body: &str) -> String {
    format!(
        "body='{}'; printf 'Content-Length: %s\r\n\r\n%s' \"${{#body}}\" \"$body\"",
        body
    )
}

fn shell_command(script: &str) -> Command {
    let mut cmd = Command::new("/bin/sh");
    cmd.arg("-c").arg(script).stderr(Stdio::null());
    cmd
}

fn diagnostic_notification(version: Option<i32>) -> String {
    let mut message = json!({
        "jsonrpc": "2.0",
        "method": "textDocument/publishDiagnostics",
        "params": {
            "uri": TEST_URI,
            "diagnostics": [{
                "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 1 }
                },
                "severity": 1,
                "source": "unit-test",
                "message": "diagnostic"
            }]
        }
    });

    if let Some(version) = version {
        message["params"]["version"] = json!(version);
    }

    message.to_string()
}

fn start_diagnostics_session(notification: String, document_version: i32) -> LspSession {
    let initialize =
        framed_message_script(r#"{"jsonrpc":"2.0","id":1,"result":{"capabilities":{}}}"#);
    let diagnostics = framed_message_script(&notification);
    let script = format!("{initialize}; sleep 0.05; {diagnostics}; sleep 30");

    LspSession::start(LspSessionStartOptions {
        cmd: shell_command(&script),
        workspace_folders: Vec::new(),
        initialize_params: json!({}),
        initialize_timeout: Duration::from_secs(1),
        document: LspDocument {
            uri: TEST_URI.to_string(),
            language_id: "rust".to_string(),
            version: document_version,
        },
        initial_text: "abc\n".to_string(),
    })
    .expect("session starts")
}

fn poll_until_diagnostics_event(
    session: &mut LspSession,
    line_index: &LineIndex,
) -> (Vec<ProcessingEdit>, LspPublishDiagnosticsParams) {
    let mut all_edits = Vec::new();

    for _ in 0..50 {
        let edits = session
            .poll_edits_with_line_index(line_index)
            .expect("poll succeeds");
        all_edits.extend(edits);

        for event in session.drain_events() {
            if let LspEvent::Notification(LspNotification::PublishDiagnostics(diagnostics)) = event
            {
                return (all_edits, diagnostics);
            }
        }

        thread::sleep(Duration::from_millis(20));
    }

    panic!("diagnostics notification was not observed");
}

fn has_diagnostics_style_layer(edits: &[ProcessingEdit]) -> bool {
    edits.iter().any(|edit| {
        matches!(
            edit,
            ProcessingEdit::ReplaceStyleLayer {
                layer: StyleLayerId::DIAGNOSTICS,
                ..
            }
        )
    })
}

fn has_replace_diagnostics(edits: &[ProcessingEdit]) -> bool {
    edits
        .iter()
        .any(|edit| matches!(edit, ProcessingEdit::ReplaceDiagnostics { .. }))
}

#[test]
fn test_lsp_diagnostics_to_processing_edits_utf16_ranges() {
    let text = "a👋b\n";
    let line_index = LineIndex::from_text(text);

    // "a👋b"
    // char offsets: a=0, 👋=1, b=2
    // utf-16 offsets: a=0..1, 👋=1..3, b=3..4
    let diagnostic = LspDiagnostic {
        range: LspRange::new(
            LspPosition {
                line: 0,
                character: 1,
            },
            LspPosition {
                line: 0,
                character: 3,
            },
        ),
        severity: Some(LspDiagnosticSeverity::Error),
        code: Some(json!(123)),
        source: Some("unit-test".to_string()),
        message: "emoji".to_string(),
        related_information: Some(json!([{ "note": "x" }])),
        data: Some(json!({ "k": 1 })),
    };

    let params = LspPublishDiagnosticsParams {
        uri: "file:///test".to_string(),
        diagnostics: vec![diagnostic],
        version: Some(1),
    };

    let edits = lsp_diagnostics_to_processing_edits(&line_index, &params);
    assert_eq!(edits.len(), 2);

    match &edits[0] {
        ProcessingEdit::ReplaceStyleLayer { layer, intervals } => {
            assert_eq!(*layer, StyleLayerId::DIAGNOSTICS);
            assert_eq!(intervals.len(), 1);
            assert_eq!(intervals[0].start, 1);
            assert_eq!(intervals[0].end, 2);
            // LSP diagnostics style id encoding: 0x0400_0100 | severity
            assert_eq!(intervals[0].style_id, 0x0400_0100 | 1);
        }
        other => panic!("unexpected edit: {:?}", other),
    }

    match &edits[1] {
        ProcessingEdit::ReplaceDiagnostics { diagnostics } => {
            assert_eq!(diagnostics.len(), 1);
            let diag = &diagnostics[0];
            assert_eq!(diag.range.start, 1);
            assert_eq!(diag.range.end, 2);
            assert_eq!(diag.severity, Some(DiagnosticSeverity::Error));
            assert_eq!(diag.code.as_deref(), Some("123"));
            assert_eq!(diag.source.as_deref(), Some("unit-test"));
            assert_eq!(diag.message, "emoji");

            let related = diag
                .related_information_json
                .as_ref()
                .expect("related info json");
            assert_eq!(
                serde_json::from_str::<serde_json::Value>(related).unwrap(),
                json!([{ "note": "x" }])
            );

            let data = diag.data_json.as_ref().expect("data json");
            assert_eq!(
                serde_json::from_str::<serde_json::Value>(data).unwrap(),
                json!({ "k": 1 })
            );
        }
        other => panic!("unexpected edit: {:?}", other),
    }
}

#[test]
fn stale_version_diagnostics_are_observable_but_do_not_apply() {
    let line_index = LineIndex::from_text("abc\n");
    let mut session = start_diagnostics_session(diagnostic_notification(Some(1)), 2);

    let (edits, diagnostics) = poll_until_diagnostics_event(&mut session, &line_index);

    assert_eq!(diagnostics.version, Some(1));
    assert!(!has_diagnostics_style_layer(&edits));
    assert!(!has_replace_diagnostics(&edits));
}

#[test]
fn current_version_diagnostics_produce_processing_edits() {
    let line_index = LineIndex::from_text("abc\n");
    let mut session = start_diagnostics_session(diagnostic_notification(Some(2)), 2);

    let (edits, diagnostics) = poll_until_diagnostics_event(&mut session, &line_index);

    assert_eq!(diagnostics.version, Some(2));
    assert!(has_diagnostics_style_layer(&edits));
    assert!(has_replace_diagnostics(&edits));
}

#[test]
fn unversioned_diagnostics_still_apply_for_legacy_servers() {
    let line_index = LineIndex::from_text("abc\n");
    let mut session = start_diagnostics_session(diagnostic_notification(None), 2);

    let (edits, diagnostics) = poll_until_diagnostics_event(&mut session, &line_index);

    assert_eq!(diagnostics.version, None);
    assert!(has_diagnostics_style_layer(&edits));
    assert!(has_replace_diagnostics(&edits));
}
