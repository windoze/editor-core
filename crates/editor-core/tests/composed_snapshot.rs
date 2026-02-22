use editor_core::{
    ComposedCellSource, ComposedLineKind, Decoration, DecorationKind, DecorationLayerId,
    DecorationPlacement, DecorationRange, EditorStateManager, ProcessingEdit,
};

fn line_to_string(line: &editor_core::ComposedLine) -> String {
    line.cells.iter().map(|c| c.ch).collect()
}

#[test]
fn test_composed_snapshot_injects_inline_virtual_text() {
    let mut manager = EditorStateManager::new("abc\n", 80);

    manager.apply_processing_edits(vec![ProcessingEdit::ReplaceDecorations {
        layer: DecorationLayerId::INLAY_HINTS,
        decorations: vec![Decoration {
            range: DecorationRange::new(1, 1),
            placement: DecorationPlacement::After,
            kind: DecorationKind::InlayHint,
            text: Some(":t".to_string()),
            styles: vec![42],
            tooltip: None,
            data_json: None,
        }],
    }]);

    let grid = manager.get_viewport_content_composed(0, 1);
    assert_eq!(grid.actual_line_count(), 1);

    let line = &grid.lines[0];
    assert_eq!(
        line.kind,
        ComposedLineKind::Document {
            logical_line: 0,
            visual_in_logical: 0
        }
    );
    assert_eq!(line_to_string(line), "a:tbc");

    // "a" (doc 0), ":t" (virtual @1), "b"(doc 1), "c"(doc 2)
    assert_eq!(line.cells.len(), 5);
    assert_eq!(
        line.cells[0].source,
        ComposedCellSource::Document { offset: 0 }
    );
    assert_eq!(
        line.cells[1].source,
        ComposedCellSource::Virtual { anchor_offset: 1 }
    );
    assert_eq!(
        line.cells[2].source,
        ComposedCellSource::Virtual { anchor_offset: 1 }
    );
    assert_eq!(
        line.cells[3].source,
        ComposedCellSource::Document { offset: 1 }
    );
    assert_eq!(
        line.cells[4].source,
        ComposedCellSource::Document { offset: 2 }
    );

    assert_eq!(line.cells[1].styles, vec![42]);
    assert_eq!(line.cells[2].styles, vec![42]);
}

#[test]
fn test_composed_snapshot_injects_above_line_virtual_text() {
    let mut manager = EditorStateManager::new("line1\nline2\n", 80);
    let anchor = manager.editor().line_index.position_to_char_offset(1, 0);

    manager.apply_processing_edits(vec![ProcessingEdit::ReplaceDecorations {
        layer: DecorationLayerId::CODE_LENS,
        decorations: vec![Decoration {
            range: DecorationRange::new(anchor, anchor),
            placement: DecorationPlacement::AboveLine,
            kind: DecorationKind::CodeLens,
            text: Some("Lens".to_string()),
            styles: vec![7],
            tooltip: None,
            data_json: None,
        }],
    }]);

    let grid = manager.get_viewport_content_composed(0, 10);
    assert_eq!(grid.actual_line_count(), 4);

    assert_eq!(
        grid.lines[0].kind,
        ComposedLineKind::Document {
            logical_line: 0,
            visual_in_logical: 0
        }
    );
    assert_eq!(line_to_string(&grid.lines[0]), "line1");

    assert_eq!(
        grid.lines[1].kind,
        ComposedLineKind::VirtualAboveLine { logical_line: 1 }
    );
    assert_eq!(line_to_string(&grid.lines[1]), "Lens");
    assert!(grid.lines[1].cells.iter().all(|c| c.source
        == ComposedCellSource::Virtual {
            anchor_offset: anchor
        }));

    assert_eq!(
        grid.lines[2].kind,
        ComposedLineKind::Document {
            logical_line: 1,
            visual_in_logical: 0
        }
    );
    assert_eq!(line_to_string(&grid.lines[2]), "line2");
    assert_eq!(
        grid.lines[2].cells[0].source,
        ComposedCellSource::Document { offset: anchor }
    );

    assert_eq!(
        grid.lines[3].kind,
        ComposedLineKind::Document {
            logical_line: 2,
            visual_in_logical: 0
        }
    );
    assert_eq!(line_to_string(&grid.lines[3]), "");
}
