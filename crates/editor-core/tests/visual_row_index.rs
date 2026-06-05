use editor_core::{
    Command, CommandExecutor, ComposedLineKind, CursorCommand, Decoration, DecorationKind,
    DecorationLayerId, DecorationPlacement, DecorationRange, EditCommand, EditorStateManager,
    Position, ProcessingEdit, StyleCommand,
};
use std::time::{Duration, Instant};

fn composed_line_text(line: &editor_core::ComposedLine) -> String {
    line.cells.iter().map(|cell| cell.ch).collect()
}

fn fold_two_regions(executor: &mut CommandExecutor) {
    executor
        .execute(Command::Style(StyleCommand::Fold {
            start_line: 1,
            end_line: 2,
        }))
        .expect("first fold should succeed");
    executor
        .execute(Command::Style(StyleCommand::Fold {
            start_line: 4,
            end_line: 5,
        }))
        .expect("second fold should succeed");
}

fn assert_visual_rows(executor: &CommandExecutor, expected: &[(usize, usize)]) {
    assert_eq!(executor.editor().visual_line_count(), expected.len());
    for (row, expected_mapping) in expected.iter().copied().enumerate() {
        assert_eq!(
            executor.editor().visual_to_logical_line(row),
            expected_mapping
        );
        assert_eq!(
            executor
                .editor()
                .logical_position_to_visual(expected_mapping.0, 0)
                .map(|(visual_row, _)| visual_row),
            Some(row)
        );
    }
}

#[test]
fn folding_updates_cached_visual_row_index() {
    let mut executor = CommandExecutor::new("l0\nl1\nl2\nl3\nl4", 80);

    assert_eq!(executor.editor().visual_line_count(), 5);

    executor
        .execute(Command::Style(StyleCommand::Fold {
            start_line: 1,
            end_line: 3,
        }))
        .expect("fold should succeed");

    assert_eq!(executor.editor().visual_line_count(), 3);
    assert_eq!(executor.editor().visual_to_logical_line(0), (0, 0));
    assert_eq!(executor.editor().visual_to_logical_line(1), (1, 0));
    assert_eq!(executor.editor().visual_to_logical_line(2), (4, 0));

    executor
        .execute(Command::Style(StyleCommand::Unfold { start_line: 1 }))
        .expect("unfold should succeed");

    assert_eq!(executor.editor().visual_line_count(), 5);
    assert_eq!(executor.editor().visual_to_logical_line(3), (3, 0));
}

#[test]
fn soft_wrap_folding_and_unicode_round_trip() {
    let mut executor = CommandExecutor::new("abcdef\n你好🙂ab\nhidden one\nhidden two\nlast", 4);
    executor
        .execute(Command::Style(StyleCommand::Fold {
            start_line: 1,
            end_line: 3,
        }))
        .expect("fold should succeed");

    let editor = executor.editor();
    let samples = [
        Position::new(0, 0),
        Position::new(0, 4),
        Position::new(1, 0),
        Position::new(1, 2),
        Position::new(1, 4),
        Position::new(4, 0),
        Position::new(4, 4),
    ];

    for sample in samples {
        let (visual_row, x) = editor
            .logical_position_to_visual(sample.line, sample.column)
            .expect("visible logical position should map to visual coordinates");
        let round_trip = editor
            .visual_position_to_logical(visual_row, x)
            .expect("visual position should map back to logical coordinates");
        assert_eq!(round_trip, sample);
        assert_eq!(editor.visual_to_logical_line(visual_row).0, sample.line);
    }
}

#[test]
fn insert_newline_updates_cached_folds_before_visual_row_sync() {
    let mut executor = CommandExecutor::new("a\nb\nc\nd\ne\nf\ng", 80);
    fold_two_regions(&mut executor);
    assert_visual_rows(&executor, &[(0, 0), (1, 0), (3, 0), (4, 0), (6, 0)]);

    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1,
        }))
        .expect("move should succeed");
    executor
        .execute(Command::Edit(EditCommand::InsertNewline {
            auto_indent: false,
        }))
        .expect("insert newline should succeed");

    assert_visual_rows(&executor, &[(0, 0), (1, 0), (2, 0), (4, 0), (5, 0), (7, 0)]);
}

#[test]
fn delete_newline_commands_update_cached_folds_before_visual_row_sync() {
    let cases = [
        ("delete forward", EditCommand::DeleteForward, 0, 1),
        ("backspace", EditCommand::Backspace, 1, 0),
        (
            "boundary delete forward",
            EditCommand::DeleteGraphemeForward,
            0,
            1,
        ),
    ];

    for (name, command, line, column) in cases {
        let mut executor = CommandExecutor::new("a\nb\nc\nd\ne\nf\ng", 80);
        fold_two_regions(&mut executor);
        assert_visual_rows(&executor, &[(0, 0), (1, 0), (3, 0), (4, 0), (6, 0)]);

        executor
            .execute(Command::Cursor(CursorCommand::MoveTo { line, column }))
            .unwrap_or_else(|err| panic!("{name}: move should succeed: {err}"));
        executor
            .execute(Command::Edit(command))
            .unwrap_or_else(|err| panic!("{name}: delete should succeed: {err}"));

        assert_visual_rows(&executor, &[(0, 0), (2, 0), (3, 0), (5, 0)]);
    }
}

#[test]
fn adjacent_folds_soft_wrap_and_tail_empty_line_use_cached_index() {
    let mut executor = CommandExecutor::new("abcdef\nbb\ncc\ndd\nee\nff\n", 3);
    executor
        .execute(Command::Style(StyleCommand::Fold {
            start_line: 1,
            end_line: 2,
        }))
        .expect("first fold should succeed");
    executor
        .execute(Command::Style(StyleCommand::Fold {
            start_line: 3,
            end_line: 4,
        }))
        .expect("adjacent fold should succeed");

    assert_eq!(executor.editor().visual_line_count(), 6);
    assert_eq!(executor.editor().visual_to_logical_line(0), (0, 0));
    assert_eq!(executor.editor().visual_to_logical_line(1), (0, 1));
    assert_eq!(executor.editor().visual_to_logical_line(2), (1, 0));
    assert_eq!(executor.editor().visual_to_logical_line(3), (3, 0));
    assert_eq!(executor.editor().visual_to_logical_line(4), (5, 0));
    assert_eq!(executor.editor().visual_to_logical_line(5), (6, 0));
    assert_eq!(
        executor.editor().logical_position_to_visual(6, 0),
        Some((5, 0))
    );
}

#[test]
fn direct_fold_mutation_can_rebuild_cached_visual_row_index() {
    let mut state = EditorStateManager::new("l0\nl1\nl2\nl3\nl4", 80);
    state
        .execute(Command::Style(StyleCommand::Fold {
            start_line: 1,
            end_line: 3,
        }))
        .expect("fold should succeed");
    state
        .execute(Command::Cursor(editor_core::CursorCommand::MoveTo {
            line: 1,
            column: 0,
        }))
        .expect("cursor move should succeed");

    assert_eq!(state.total_visual_lines(), 3);
    assert!(state.toggle_fold_at_current_line());

    assert_eq!(state.total_visual_lines(), 5);
    assert_eq!(state.visual_to_logical_line(3), (3, 0));
}

#[test]
fn tail_visual_queries_stay_fast_after_single_line_edits() {
    let text = (0..100_000usize)
        .map(|idx| format!("line {idx}"))
        .collect::<Vec<_>>()
        .join("\n");
    let mut executor = CommandExecutor::new(&text, 80);

    assert_eq!(executor.editor().visual_line_count(), 100_000);

    let start = Instant::now();
    for iteration in 0..200usize {
        executor
            .execute(Command::Edit(EditCommand::Insert {
                offset: iteration,
                text: "x".to_string(),
            }))
            .expect("single-line insert should succeed");

        let tail = executor.editor().visual_line_count().saturating_sub(1);
        assert_eq!(executor.editor().visual_to_logical_line(tail), (99_999, 0));
    }

    assert!(
        start.elapsed() < Duration::from_secs(10),
        "tail visual-row queries after single-line edits should not rebuild the whole document each time"
    );
}

#[test]
fn composed_tail_viewport_with_virtual_text_stays_fast_and_mapped() {
    let text = (0..100_000usize)
        .map(|idx| format!("line {idx}"))
        .collect::<Vec<_>>()
        .join("\n");
    let mut manager = EditorStateManager::new(&text, 80);
    let tail_line = 99_999usize;
    let tail_start = manager
        .editor()
        .line_index()
        .position_to_char_offset(tail_line, 0);
    let inline_anchor = manager
        .editor()
        .line_index()
        .position_to_char_offset(tail_line, 4);

    manager.apply_processing_edits(vec![ProcessingEdit::ReplaceDecorations {
        layer: DecorationLayerId::CODE_LENS,
        decorations: vec![
            Decoration {
                range: DecorationRange::new(tail_start, tail_start),
                placement: DecorationPlacement::AboveLine,
                kind: DecorationKind::CodeLens,
                text: Some("Lens".to_string()),
                styles: vec![7],
                tooltip: None,
                data_json: None,
            },
            Decoration {
                range: DecorationRange::new(inline_anchor, inline_anchor),
                placement: DecorationPlacement::After,
                kind: DecorationKind::InlayHint,
                text: Some(":hint".to_string()),
                styles: vec![8],
                tooltip: None,
                data_json: None,
            },
        ],
    }]);

    let start = Instant::now();
    for _ in 0..100usize {
        let grid = manager.get_viewport_content_composed(tail_line, 3);
        assert_eq!(grid.actual_line_count(), 2);
        assert_eq!(
            grid.lines[0].kind,
            ComposedLineKind::VirtualAboveLine {
                logical_line: tail_line
            }
        );
        assert_eq!(composed_line_text(&grid.lines[0]), "Lens");
        assert_eq!(
            grid.lines[1].kind,
            ComposedLineKind::Document {
                logical_line: tail_line,
                visual_in_logical: 0
            }
        );
        assert_eq!(composed_line_text(&grid.lines[1]), "line:hint 99999");
    }

    assert!(
        start.elapsed() < Duration::from_secs(10),
        "tail composed viewport queries with virtual text should not scan from the document head"
    );
}
