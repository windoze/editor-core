use editor_core::processing::ProcessingEdit;
use editor_core::{LineIndex, StyleLayerId};
use editor_core_lsp::{
    LspCoordinateConverter, LspDiagnostic, LspDiagnosticSeverity, LspNotification, LspPosition,
    LspPublishDiagnosticsParams, LspRange, encode_semantic_style_id,
    lsp_diagnostics_to_processing_edits, semantic_tokens_to_intervals,
};
use serde_json::json;

type CharRanges = Vec<(usize, usize)>;

fn diagnostic_params(range: LspRange) -> LspPublishDiagnosticsParams {
    LspPublishDiagnosticsParams {
        uri: "file:///utf16.rs".to_string(),
        diagnostics: vec![LspDiagnostic {
            range,
            severity: Some(LspDiagnosticSeverity::Error),
            code: None,
            source: None,
            message: "utf16".to_string(),
            related_information: None,
            data: None,
        }],
        version: Some(1),
    }
}

fn diagnostic_ranges(edits: &[ProcessingEdit]) -> (CharRanges, CharRanges) {
    let mut style_ranges = Vec::new();
    let mut diagnostic_ranges = Vec::new();

    for edit in edits {
        match edit {
            ProcessingEdit::ReplaceStyleLayer { layer, intervals }
                if *layer == StyleLayerId::DIAGNOSTICS =>
            {
                style_ranges.extend(
                    intervals
                        .iter()
                        .map(|interval| (interval.start, interval.end)),
                );
            }
            ProcessingEdit::ReplaceDiagnostics { diagnostics } => {
                diagnostic_ranges.extend(
                    diagnostics
                        .iter()
                        .map(|diagnostic| (diagnostic.range.start, diagnostic.range.end)),
                );
            }
            _ => {}
        }
    }

    (style_ranges, diagnostic_ranges)
}

#[test]
fn utf16_offsets_inside_surrogate_pair_clamp_to_scalar_start() {
    let text = "a👋b";

    assert_eq!(LspCoordinateConverter::utf16_to_char_offset(text, 0), 0);
    assert_eq!(LspCoordinateConverter::utf16_to_char_offset(text, 1), 1);
    assert_eq!(LspCoordinateConverter::utf16_to_char_offset(text, 2), 1);
    assert_eq!(LspCoordinateConverter::utf16_to_char_offset(text, 3), 2);
    assert_eq!(LspCoordinateConverter::utf16_to_char_offset(text, 4), 3);
    assert_eq!(
        LspCoordinateConverter::lsp_to_char_offset(text, u32::MAX),
        3
    );
}

#[test]
fn half_surrogate_diagnostic_range_does_not_extend_past_scalar_start() {
    let line_index = LineIndex::from_text("a👋b\n");
    let range = LspRange::new(LspPosition::new(0, 1), LspPosition::new(0, 2));

    let edits = lsp_diagnostics_to_processing_edits(&line_index, &diagnostic_params(range));
    let (style_ranges, diagnostic_ranges) = diagnostic_ranges(&edits);

    assert!(style_ranges.is_empty());
    assert!(diagnostic_ranges.is_empty());
}

#[test]
fn oversized_diagnostic_character_clamps_to_line_end() {
    let line_index = LineIndex::from_text("a👋b\n");
    let params = json!({
        "uri": "file:///utf16.rs",
        "diagnostics": [{
            "range": {
                "start": { "line": 0, "character": 3 },
                "end": { "line": 0, "character": u64::from(u32::MAX) + 99 }
            },
            "severity": 1,
            "message": "oversized"
        }]
    });

    let LspNotification::PublishDiagnostics(params) =
        LspNotification::from_method_and_params("textDocument/publishDiagnostics", &params)
            .expect("diagnostics parse")
    else {
        panic!("unexpected notification");
    };

    assert_eq!(params.diagnostics[0].range.end.character, u32::MAX);

    let edits = lsp_diagnostics_to_processing_edits(&line_index, &params);
    let (style_ranges, diagnostic_ranges) = diagnostic_ranges(&edits);

    assert_eq!(style_ranges, vec![(2, 3)]);
    assert_eq!(diagnostic_ranges, vec![(2, 3)]);
}

#[test]
fn oversized_diagnostic_line_clamps_to_document_end() {
    let line_index = LineIndex::from_text("a👋b\n");
    let range = LspRange::new(
        LspPosition::new(u32::MAX, 0),
        LspPosition::new(u32::MAX, u32::MAX),
    );

    let edits = lsp_diagnostics_to_processing_edits(&line_index, &diagnostic_params(range));
    let (style_ranges, diagnostic_ranges) = diagnostic_ranges(&edits);

    assert!(style_ranges.is_empty());
    assert!(diagnostic_ranges.is_empty());
}

#[test]
fn semantic_tokens_use_same_half_surrogate_boundary_policy() {
    let line_index = LineIndex::from_text("a👋b\n");

    let half_surrogate = vec![0, 1, 1, 1, 0];
    let intervals =
        semantic_tokens_to_intervals(&half_surrogate, &line_index, encode_semantic_style_id)
            .expect("semantic tokens convert");
    assert!(intervals.is_empty());

    let whole_emoji = vec![0, 1, 2, 1, 0];
    let intervals =
        semantic_tokens_to_intervals(&whole_emoji, &line_index, encode_semantic_style_id)
            .expect("semantic tokens convert");
    assert_eq!(intervals.len(), 1);
    assert_eq!(intervals[0].start, 1);
    assert_eq!(intervals[0].end, 2);
}
