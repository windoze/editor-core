use editor_core::{DecorationKind, DecorationLayerId, DecorationPlacement, LineIndex};
use editor_core_lsp::{lsp_inlay_hints_to_decorations, lsp_inlay_hints_to_processing_edit};
use serde_json::json;

#[test]
fn test_inlay_hints_convert_utf16_positions_to_char_offsets() {
    let text = "a👋b\n";
    let line_index = LineIndex::from_text(text);

    // Inlay hint after 👋: UTF-16 position is 3 (a=1, 👋=2 units).
    let result = json!([
        {
            "position": { "line": 0, "character": 3 },
            "label": ": u32",
            "paddingLeft": true,
            "tooltip": { "kind": "markdown", "value": "hint" }
        }
    ]);

    let decorations = lsp_inlay_hints_to_decorations(&line_index, &result);
    assert_eq!(decorations.len(), 1);
    let deco = &decorations[0];
    assert_eq!(deco.range.start, 2);
    assert_eq!(deco.range.end, 2);
    assert_eq!(deco.kind, DecorationKind::InlayHint);
    assert_eq!(deco.placement, DecorationPlacement::After);
    assert_eq!(deco.text.as_deref(), Some(" : u32"));
    assert_eq!(deco.tooltip.as_deref(), Some("hint"));
    assert!(deco.data_json.as_ref().unwrap().contains("\"label\""));

    let edit = lsp_inlay_hints_to_processing_edit(&line_index, &result);
    match edit {
        editor_core::ProcessingEdit::ReplaceDecorations { layer, decorations } => {
            assert_eq!(layer, DecorationLayerId::INLAY_HINTS);
            assert_eq!(decorations.len(), 1);
        }
        other => panic!("unexpected edit: {:?}", other),
    }
}
