use editor_core::{
    Command, Decoration, DecorationKind, DecorationLayerId, DecorationPlacement, DecorationRange,
    ProcessingEdit, StyleCommand,
};
use tauri_editor::EditorBackend;
use tauri_editor::composed_row_index::ComposedRowIndex;
use tauri_editor::snapshot::{
    LINE_KIND_DOCUMENT, LINE_KIND_VIRTUAL_ABOVE_LINE, SOURCE_KIND_DOCUMENT, SOURCE_KIND_VIRTUAL,
};

#[test]
fn composed_rows_include_above_line_virtual_rows() {
    let mut backend = EditorBackend::open_text(None, "a\nb\nc", 80).unwrap();

    let view_id = backend.view_id();
    let buffer_id = backend.workspace().buffer_id_for_view(view_id).unwrap();
    let index = backend.workspace().buffer_line_index(buffer_id).unwrap();

    let line1 = index.position_to_char_offset(1, 0);
    let line2 = index.position_to_char_offset(2, 0);

    let decorations = vec![
        Decoration {
            range: DecorationRange::new(line1, line1),
            placement: DecorationPlacement::AboveLine,
            kind: DecorationKind::CodeLens,
            text: Some("lens-1".to_string()),
            styles: vec![],
            tooltip: None,
            data_json: None,
        },
        Decoration {
            range: DecorationRange::new(line2, line2),
            placement: DecorationPlacement::AboveLine,
            kind: DecorationKind::CodeLens,
            text: Some("lens-2".to_string()),
            styles: vec![],
            tooltip: None,
            data_json: None,
        },
    ];

    backend
        .workspace_mut()
        .apply_processing_edits(
            buffer_id,
            [ProcessingEdit::ReplaceDecorations {
                layer: DecorationLayerId::CODE_LENS,
                decorations,
            }],
        )
        .unwrap();

    let snapshot = backend.viewport_snapshot(0, 64).unwrap();
    assert_eq!(snapshot.total_rows, 5);
    assert_eq!(snapshot.lines.len(), 5);

    assert_eq!(snapshot.lines[0].row, 0);
    assert_eq!(snapshot.lines[0].kind, LINE_KIND_DOCUMENT);

    assert_eq!(snapshot.lines[1].row, 1);
    assert_eq!(snapshot.lines[1].kind, LINE_KIND_VIRTUAL_ABOVE_LINE);

    assert_eq!(snapshot.lines[2].row, 2);
    assert_eq!(snapshot.lines[2].kind, LINE_KIND_DOCUMENT);

    assert_eq!(snapshot.lines[3].row, 3);
    assert_eq!(snapshot.lines[3].kind, LINE_KIND_VIRTUAL_ABOVE_LINE);

    assert_eq!(snapshot.lines[4].row, 4);
    assert_eq!(snapshot.lines[4].kind, LINE_KIND_DOCUMENT);

    let (doc1_to_composed, doc2_to_composed) = backend
        .workspace_mut()
        .with_editor_for_view(view_id, |ed| {
            let idx = ComposedRowIndex::build(ed);
            (
                idx.doc_row_to_composed_row(ed, 1),
                idx.doc_row_to_composed_row(ed, 2),
            )
        })
        .unwrap();

    // doc rows: [a,b,c] => 0,1,2
    // composed rows: [a, lens-1, b, lens-2, c] => 0,1,2,3,4
    assert_eq!(doc1_to_composed, 2);
    assert_eq!(doc2_to_composed, 4);

    let (c1, c2, c3, c4) = backend
        .workspace_mut()
        .with_editor_for_view(view_id, |ed| {
            let idx = ComposedRowIndex::build(ed);
            (
                idx.composed_row_to_doc_row(1),
                idx.composed_row_to_doc_row(2),
                idx.composed_row_to_doc_row(3),
                idx.composed_row_to_doc_row(4),
            )
        })
        .unwrap();

    assert_eq!(c1, None); // lens-1
    assert_eq!(c2, Some(1)); // b
    assert_eq!(c3, None); // lens-2
    assert_eq!(c4, Some(2)); // c
}

#[test]
fn runs_are_grouped_by_style_set_and_source() {
    let mut backend = EditorBackend::open_text(None, "abc", 80).unwrap();
    let view_id = backend.view_id();

    backend
        .workspace_mut()
        .execute(
            view_id,
            Command::Style(StyleCommand::AddStyle {
                start: 1,
                end: 2,
                style_id: 0x2222_0001,
            }),
        )
        .unwrap();

    let snapshot = backend.viewport_snapshot(0, 8).unwrap();
    assert_eq!(snapshot.lines.len(), 1);

    let line = &snapshot.lines[0];
    assert_eq!(line.kind, LINE_KIND_DOCUMENT);
    assert_eq!(line.runs.len(), 3);

    let run_a = &line.runs[0];
    assert_eq!(run_a.source_kind(), SOURCE_KIND_DOCUMENT);
    assert_eq!(run_a.source_offset(), 0);
    assert_eq!(run_a.cells(), 1);
    assert_eq!(run_a.text(), "a");

    let run_b = &line.runs[1];
    assert_eq!(run_b.source_kind(), SOURCE_KIND_DOCUMENT);
    assert_eq!(run_b.source_offset(), 1);
    assert_eq!(run_b.cells(), 1);
    assert_eq!(run_b.text(), "b");

    let run_c = &line.runs[2];
    assert_eq!(run_c.source_kind(), SOURCE_KIND_DOCUMENT);
    assert_eq!(run_c.source_offset(), 2);
    assert_eq!(run_c.cells(), 1);
    assert_eq!(run_c.text(), "c");

    let style_set_id = run_b.style_set_id() as usize;
    assert_eq!(snapshot.style_sets[0], Vec::<u32>::new());
    assert_eq!(snapshot.style_sets[style_set_id], vec![0x2222_0001]);
}

#[test]
fn inline_virtual_text_breaks_document_runs() {
    let mut backend = EditorBackend::open_text(None, "ab", 80).unwrap();
    let view_id = backend.view_id();
    let buffer_id = backend.workspace().buffer_id_for_view(view_id).unwrap();

    backend
        .workspace_mut()
        .apply_processing_edits(
            buffer_id,
            [ProcessingEdit::ReplaceDecorations {
                layer: DecorationLayerId::INLAY_HINTS,
                decorations: vec![Decoration {
                    range: DecorationRange::new(1, 1),
                    placement: DecorationPlacement::Before,
                    kind: DecorationKind::InlayHint,
                    text: Some("X".to_string()),
                    styles: vec![],
                    tooltip: None,
                    data_json: None,
                }],
            }],
        )
        .unwrap();

    let snapshot = backend.viewport_snapshot(0, 8).unwrap();
    let line = &snapshot.lines[0];
    assert_eq!(line.runs.len(), 3);

    let r0 = &line.runs[0];
    assert_eq!(r0.source_kind(), SOURCE_KIND_DOCUMENT);
    assert_eq!(r0.source_offset(), 0);
    assert_eq!(r0.cells(), 1);
    assert_eq!(r0.text(), "a");

    let r1 = &line.runs[1];
    assert_eq!(r1.source_kind(), SOURCE_KIND_VIRTUAL);
    assert_eq!(r1.source_offset(), 1);
    assert_eq!(r1.cells(), 1);
    assert_eq!(r1.text(), "X");

    let r2 = &line.runs[2];
    assert_eq!(r2.source_kind(), SOURCE_KIND_DOCUMENT);
    assert_eq!(r2.source_offset(), 1);
    assert_eq!(r2.cells(), 1);
    assert_eq!(r2.text(), "b");
}

#[test]
fn wide_chars_are_not_merged_into_neighbors() {
    let mut backend = EditorBackend::open_text(None, "中a", 80).unwrap();

    let snapshot = backend.viewport_snapshot(0, 8).unwrap();
    let line = &snapshot.lines[0];

    // 关键：CJK（width=2）必须拆成单独的 run，否则 caret 边界会被字体 fallback 破坏。
    assert_eq!(line.runs.len(), 2);
    assert_eq!(line.runs[0].text(), "中");
    assert_eq!(line.runs[0].cells(), 2);
    assert_eq!(line.runs[1].text(), "a");
    assert_eq!(line.runs[1].cells(), 1);
}
