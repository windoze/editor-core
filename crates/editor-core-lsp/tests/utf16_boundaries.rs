use editor_core::processing::ProcessingEdit;
use editor_core::{LineIndex, StyleLayerId, Workspace};
use editor_core_lsp::workspace_sync::apply_workspace_edit_to_workspace;
use editor_core_lsp::{
    DeltaCalculator, LspCoordinateConverter, LspDiagnostic, LspDiagnosticSeverity, LspNotification,
    LspParameterLabel, LspPosition, LspPublishDiagnosticsParams, LspRange, TextChange,
    encode_semantic_style_id, lsp_diagnostics_to_processing_edits, semantic_tokens_to_intervals,
    signature_help_from_value,
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

fn calc_text(calc: &DeltaCalculator) -> String {
    (0..calc.line_count())
        .map(|line| calc.get_line(line).unwrap_or_default())
        .collect::<Vec<_>>()
        .join("\n")
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

#[test]
fn oversized_workspace_edit_range_clamps_before_delta_calculator_sync() {
    let mut workspace = Workspace::new();
    let opened = workspace
        .open_buffer(Some("file:///utf16.rs".to_string()), "a👋b\n", 80)
        .expect("open buffer");
    let workspace_edit = json!({
        "changes": {
            "file:///utf16.rs": [{
                "range": {
                    "start": { "line": u64::from(u32::MAX) + 99, "character": u64::MAX },
                    "end": { "line": u64::from(u32::MAX) + 99, "character": u64::MAX }
                },
                "newText": "!"
            }]
        }
    });

    let result = apply_workspace_edit_to_workspace(&mut workspace, &workspace_edit)
        .expect("apply workspace edit");
    let text_after_workspace = workspace
        .buffer_text(opened.buffer_id)
        .expect("workspace text");

    assert_eq!(text_after_workspace, "a👋b\n!");
    assert_eq!(result.applied.len(), 1);
    assert_eq!(result.applied[0].changed_char_ranges, vec![(4, 4)]);
    assert_eq!(result.applied[0].lsp_changes.len(), 1);

    let change = &result.applied[0].lsp_changes[0];
    assert_eq!(change.range.start, LspPosition::new(1, 0));
    assert_eq!(change.range.end, LspPosition::new(1, 0));
    assert_eq!(change.text, "!");

    let mut calc = DeltaCalculator::from_text("a👋b\n");
    calc.apply_change(&TextChange {
        range: change.range,
        text: change.text.clone(),
    });
    assert_eq!(calc_text(&calc), text_after_workspace);
}

#[test]
fn delta_calculator_oversized_line_with_zero_character_inserts_at_document_end() {
    let mut calc = DeltaCalculator::from_text("a👋b\nlast");
    let end = LspPosition::new(u32::MAX, 0);

    calc.apply_change(&TextChange {
        range: LspRange::new(end, end),
        text: "!".to_string(),
    });

    assert_eq!(calc_text(&calc), "a👋b\nlast!");
}

#[test]
fn delta_calculator_oversized_line_with_huge_character_clamps_to_document_end() {
    let mut calc = DeltaCalculator::from_text("a👋b\n");
    let start = LspPosition::new(u32::MAX, 0);
    let end = LspPosition::new(u32::MAX, u32::MAX);

    calc.apply_change(&TextChange {
        range: LspRange::new(start, end),
        text: "!".to_string(),
    });

    assert_eq!(calc_text(&calc), "a👋b\n!");
}

#[test]
fn delta_calculator_reversed_range_with_oversized_line_uses_document_end() {
    let mut calc = DeltaCalculator::from_text("abc\ndef");

    calc.apply_change(&TextChange {
        range: LspRange::new(LspPosition::new(u32::MAX, 0), LspPosition::new(0, 1)),
        text: "!".to_string(),
    });

    assert_eq!(calc_text(&calc), "a!");
}

#[test]
fn delta_calculator_half_surrogate_range_clamps_to_scalar_start() {
    let mut calc = DeltaCalculator::from_text("a👋b");

    calc.apply_change(&TextChange {
        range: LspRange::new(LspPosition::new(0, 2), LspPosition::new(0, 3)),
        text: "X".to_string(),
    });

    assert_eq!(calc_text(&calc), "aXb");
}

#[test]
fn legal_workspace_edit_keeps_did_change_range_and_text() {
    let mut workspace = Workspace::new();
    let opened = workspace
        .open_buffer(Some("file:///utf16.rs".to_string()), "a👋b\n", 80)
        .expect("open buffer");
    let workspace_edit = json!({
        "changes": {
            "file:///utf16.rs": [{
                "range": {
                    "start": { "line": 0, "character": 1 },
                    "end": { "line": 0, "character": 3 }
                },
                "newText": "X"
            }]
        }
    });

    let result = apply_workspace_edit_to_workspace(&mut workspace, &workspace_edit)
        .expect("apply workspace edit");
    let text_after_workspace = workspace
        .buffer_text(opened.buffer_id)
        .expect("workspace text");

    assert_eq!(text_after_workspace, "aXb\n");
    assert_eq!(result.applied[0].changed_char_ranges, vec![(1, 2)]);

    let change = &result.applied[0].lsp_changes[0];
    assert_eq!(change.range.start, LspPosition::new(0, 1));
    assert_eq!(change.range.end, LspPosition::new(0, 3));
    assert_eq!(change.text, "X");

    let mut calc = DeltaCalculator::from_text("a👋b\n");
    calc.apply_change(&TextChange {
        range: change.range,
        text: change.text.clone(),
    });
    assert_eq!(calc_text(&calc), text_after_workspace);
}

#[test]
fn signature_help_oversized_offsets_and_indexes_do_not_wrap() {
    let too_large = u64::from(u32::MAX) + 1;
    let value = json!({
        "signatures": [{
            "label": "call(a)",
            "parameters": [{ "label": [too_large, u64::MAX] }]
        }],
        "activeSignature": too_large,
        "activeParameter": too_large
    });

    let help = signature_help_from_value(&value).expect("signature help");

    assert_eq!(help.active_signature, Some(u32::MAX));
    assert_eq!(help.active_parameter, Some(u32::MAX));
    assert_eq!(help.to_compact_string(), None);
    assert_eq!(
        help.signatures[0].parameters[0].label,
        Some(LspParameterLabel::Offsets(u32::MAX, u32::MAX))
    );
}
