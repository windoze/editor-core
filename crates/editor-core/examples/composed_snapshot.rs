use editor_core::{
    Decoration, DecorationKind, DecorationLayerId, DecorationPlacement, DecorationRange,
    EditorStateManager, ProcessingEdit,
};

fn main() {
    let mut manager = EditorStateManager::new("fn main() {\n    let x = 1;\n}\n", 80);

    let line_1_start = manager.editor().line_index.position_to_char_offset(1, 0);
    let after_x = manager.editor().line_index.position_to_char_offset(1, 9);

    let code_lens = Decoration {
        range: DecorationRange::new(line_1_start, line_1_start),
        placement: DecorationPlacement::AboveLine,
        kind: DecorationKind::CodeLens,
        text: Some("Run | Debug".to_string()),
        styles: vec![1002],
        tooltip: None,
        data_json: None,
    };

    let inlay_hint = Decoration {
        range: DecorationRange::new(after_x, after_x),
        placement: DecorationPlacement::After,
        kind: DecorationKind::InlayHint,
        text: Some(": i32".to_string()),
        styles: vec![1001],
        tooltip: None,
        data_json: None,
    };

    manager.apply_processing_edits(vec![
        ProcessingEdit::ReplaceDecorations {
            layer: DecorationLayerId::CODE_LENS,
            decorations: vec![code_lens],
        },
        ProcessingEdit::ReplaceDecorations {
            layer: DecorationLayerId::INLAY_HINTS,
            decorations: vec![inlay_hint],
        },
    ]);

    let grid = manager.get_viewport_content_composed(0, 20);
    for line in &grid.lines {
        let text: String = line.cells.iter().map(|c| c.ch).collect();
        println!("{:?}: {}", line.kind, text);
    }
}
