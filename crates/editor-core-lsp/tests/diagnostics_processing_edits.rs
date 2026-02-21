use editor_core::processing::ProcessingEdit;
use editor_core::{DiagnosticSeverity, LineIndex, StyleLayerId};
use editor_core_lsp::{
    LspDiagnostic, LspDiagnosticSeverity, LspPosition, LspPublishDiagnosticsParams, LspRange,
    lsp_diagnostics_to_processing_edits,
};
use serde_json::json;

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
            assert_eq!(intervals[0].style_id, 0x0400_0000 | 1);
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
