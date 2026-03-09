use editor_core::{
    CODE_LENS_STYLE_ID, DOCUMENT_LINK_STYLE_ID, DecorationKind, DecorationLayerId,
    DecorationPlacement, LineIndex, StyleLayerId,
};
use editor_core_lsp::{
    lsp_code_lens_to_decorations, lsp_code_lens_to_processing_edit,
    lsp_document_links_to_decorations, lsp_document_links_to_processing_edit,
    lsp_document_links_to_processing_edits, lsp_document_links_to_style_intervals,
};
use serde_json::json;

#[test]
fn test_document_links_convert_utf16_ranges_to_char_offsets() {
    let text = "a👋b\n";
    let line_index = LineIndex::from_text(text);

    let result = json!([
        {
            "range": { "start": { "line": 0, "character": 3 }, "end": { "line": 0, "character": 4 } },
            "target": "https://example.com",
            "tooltip": "go"
        }
    ]);

    let decorations = lsp_document_links_to_decorations(&line_index, &result);
    assert_eq!(decorations.len(), 1);
    let deco = &decorations[0];
    assert_eq!(deco.range.start, 2);
    assert_eq!(deco.range.end, 3);
    assert_eq!(deco.kind, DecorationKind::DocumentLink);
    assert_eq!(deco.placement, DecorationPlacement::After);
    assert_eq!(deco.tooltip.as_deref(), Some("go"));
    assert!(deco.data_json.as_ref().unwrap().contains("\"target\""));

    let edit = lsp_document_links_to_processing_edit(&line_index, &result);
    match edit {
        editor_core::ProcessingEdit::ReplaceDecorations { layer, decorations } => {
            assert_eq!(layer, DecorationLayerId::DOCUMENT_LINKS);
            assert_eq!(decorations.len(), 1);
        }
        other => panic!("unexpected edit: {:?}", other),
    }

    let intervals = lsp_document_links_to_style_intervals(&line_index, &result);
    assert_eq!(intervals.len(), 1);
    assert_eq!(intervals[0].start, 2);
    assert_eq!(intervals[0].end, 3);
    assert_eq!(intervals[0].style_id, DOCUMENT_LINK_STYLE_ID);

    let edits = lsp_document_links_to_processing_edits(&line_index, &result);
    assert_eq!(edits.len(), 2);
    assert!(edits.iter().any(|e| matches!(
        e,
        editor_core::ProcessingEdit::ReplaceDecorations {
            layer: DecorationLayerId::DOCUMENT_LINKS,
            ..
        }
    )));
    assert!(edits.iter().any(|e| matches!(
        e,
        editor_core::ProcessingEdit::ReplaceStyleLayer {
            layer: StyleLayerId::DOCUMENT_LINKS,
            ..
        }
    )));
}

#[test]
fn test_code_lens_maps_to_above_line_decorations() {
    let text = "line1\nline2\n";
    let line_index = LineIndex::from_text(text);

    let result = json!([
        {
            "range": { "start": { "line": 1, "character": 0 }, "end": { "line": 1, "character": 0 } },
            "command": { "title": "Run tests", "command": "runTests" }
        }
    ]);

    let decorations = lsp_code_lens_to_decorations(&line_index, &result);
    assert_eq!(decorations.len(), 1);
    let deco = &decorations[0];
    assert_eq!(deco.kind, DecorationKind::CodeLens);
    assert_eq!(deco.placement, DecorationPlacement::AboveLine);
    assert_eq!(deco.text.as_deref(), Some("Run tests"));
    assert_eq!(deco.styles, vec![CODE_LENS_STYLE_ID]);

    let expected_offset = line_index.position_to_char_offset(1, 0);
    assert_eq!(deco.range.start, expected_offset);
    assert_eq!(deco.range.end, expected_offset);

    let edit = lsp_code_lens_to_processing_edit(&line_index, &result);
    match edit {
        editor_core::ProcessingEdit::ReplaceDecorations { layer, decorations } => {
            assert_eq!(layer, DecorationLayerId::CODE_LENS);
            assert_eq!(decorations.len(), 1);
        }
        other => panic!("unexpected edit: {:?}", other),
    }
}
