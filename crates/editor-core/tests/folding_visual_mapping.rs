use editor_core::{Command, CommandExecutor, FoldRegion, FoldingManager, Position, StyleCommand};
use std::collections::BTreeSet;

fn collapsed_region(start_line: usize, end_line: usize) -> FoldRegion {
    let mut region = FoldRegion::new(start_line, end_line);
    region.collapse();
    region
}

#[test]
fn folding_manager_round_trips_multiple_non_overlapping_and_adjacent_regions() {
    let mut manager = FoldingManager::new();
    manager.add_region(collapsed_region(1, 2));
    manager.add_region(collapsed_region(3, 4));
    manager.add_region(collapsed_region(7, 9));

    let expected_visible = [0, 1, 3, 5, 6, 7, 10, 11];
    for (visual, logical) in expected_visible.into_iter().enumerate() {
        assert_eq!(manager.visual_to_logical(visual, 0), logical);
        assert_eq!(manager.logical_to_visual(logical, 0), Some(visual));
    }

    for hidden in [2, 4, 8, 9] {
        assert_eq!(manager.logical_to_visual(hidden, 0), None);
    }
}

#[test]
fn folding_manager_treats_overlapping_collapsed_regions_as_one_hidden_union() {
    let mut manager = FoldingManager::new();
    manager.add_region(collapsed_region(5, 10));
    manager.add_region(collapsed_region(8, 12));

    assert_eq!(manager.logical_to_visual(5, 10), Some(15));
    assert_eq!(manager.logical_to_visual(8, 10), None);
    assert_eq!(manager.logical_to_visual(12, 10), None);
    assert_eq!(manager.logical_to_visual(13, 10), Some(16));

    assert_eq!(manager.visual_to_logical(15, 10), 5);
    assert_eq!(manager.visual_to_logical(16, 10), 13);
    assert_eq!(manager.visual_to_logical(17, 10), 14);
}

#[test]
fn editor_core_round_trips_multiple_folds_with_soft_wrap_and_viewport_rows() {
    let mut executor = CommandExecutor::new(
        "abcdef\nfold one\nfold two\n你好🙂abcd\nfold three\nfold four\nlastwide",
        4,
    );

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

    let editor = executor.editor();
    let total_visual = editor.visual_line_count();
    assert!(total_visual > editor.line_count());

    let mut visible_lines = BTreeSet::new();
    for visual_row in 0..total_visual {
        let (logical_line, visual_in_logical) = editor.visual_to_logical_line(visual_row);
        visible_lines.insert(logical_line);

        let position = editor
            .visual_position_to_logical(visual_row, 0)
            .expect("visual row should map to a logical position");
        assert_eq!(position.line, logical_line);

        let (round_trip_row, _) = editor
            .logical_position_to_visual(position.line, position.column)
            .expect("visible logical position should map back to visual coordinates");
        assert_eq!(round_trip_row, visual_row);

        let start = editor
            .logical_position_to_visual(logical_line, 0)
            .expect("visible logical line should have a visual start");
        assert_eq!(start.0 + visual_in_logical, visual_row);
    }

    assert!(visible_lines.contains(&1));
    assert!(visible_lines.contains(&4));
    assert!(!visible_lines.contains(&2));
    assert!(!visible_lines.contains(&5));

    let grid = editor.get_headless_grid_styled(0, total_visual);
    assert_eq!(grid.lines.len(), total_visual);
    for (visual_row, line) in grid.lines.iter().enumerate() {
        let (logical_line, visual_in_logical) = editor.visual_to_logical_line(visual_row);
        assert_eq!(line.logical_line_index, logical_line);
        assert_eq!(line.visual_in_logical, visual_in_logical);
    }

    let (visual_row, _) = editor
        .logical_position_to_visual(6, 0)
        .expect("last visible logical line should map to a visual row");
    assert_eq!(
        editor.visual_position_to_logical(visual_row, 0),
        Some(Position::new(6, 0))
    );
}
