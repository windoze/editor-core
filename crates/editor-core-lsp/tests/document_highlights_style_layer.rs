use editor_core::{
    DOCUMENT_HIGHLIGHT_READ_STYLE_ID, DOCUMENT_HIGHLIGHT_TEXT_STYLE_ID,
    DOCUMENT_HIGHLIGHT_WRITE_STYLE_ID, LineIndex, StyleLayerId,
};
use editor_core_lsp::{
    lsp_document_highlights_to_intervals, lsp_document_highlights_to_processing_edit,
};
use serde_json::json;

#[test]
fn test_document_highlights_convert_utf16_ranges_to_char_intervals() {
    let text = "a👋b\n";
    let line_index = LineIndex::from_text(text);

    // UTF-16 positions on line 0:
    // - "a" occupies 1 unit
    // - "👋" occupies 2 units
    // - "b" starts at 3, ends at 4
    let result = json!([
        {
            "range": { "start": { "line": 0, "character": 3 }, "end": { "line": 0, "character": 4 } },
            "kind": 2
        },
        {
            "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 1 } },
            "kind": 3
        },
        {
            "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 3 } }
        }
    ]);

    let mut intervals = lsp_document_highlights_to_intervals(&line_index, &result);
    intervals.sort_by_key(|i| (i.start, i.end, i.style_id));

    assert_eq!(intervals.len(), 3);
    assert_eq!(intervals[0].start, 0);
    assert_eq!(intervals[0].end, 1);
    assert_eq!(intervals[0].style_id, DOCUMENT_HIGHLIGHT_WRITE_STYLE_ID);

    assert_eq!(intervals[1].start, 1);
    assert_eq!(intervals[1].end, 2);
    assert_eq!(intervals[1].style_id, DOCUMENT_HIGHLIGHT_TEXT_STYLE_ID);

    assert_eq!(intervals[2].start, 2);
    assert_eq!(intervals[2].end, 3);
    assert_eq!(intervals[2].style_id, DOCUMENT_HIGHLIGHT_READ_STYLE_ID);

    let edit = lsp_document_highlights_to_processing_edit(&line_index, &result);
    match edit {
        editor_core::ProcessingEdit::ReplaceStyleLayer { layer, intervals } => {
            assert_eq!(layer, StyleLayerId::DOCUMENT_HIGHLIGHTS);
            assert_eq!(intervals.len(), 3);
        }
        other => panic!("unexpected edit: {:?}", other),
    }
}
