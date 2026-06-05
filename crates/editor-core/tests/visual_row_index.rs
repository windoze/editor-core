use editor_core::{Command, CommandExecutor, EditCommand, Position, StyleCommand};
use std::time::{Duration, Instant};

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
