use editor_core::{Command, CommandExecutor, CommandResult, StyleCommand, ViewCommand};

fn viewport(
    executor: &mut CommandExecutor,
    start_row: usize,
    count: usize,
) -> editor_core::HeadlessGrid {
    let result = executor
        .execute(Command::View(ViewCommand::GetViewport { start_row, count }))
        .expect("GetViewport should succeed");
    let CommandResult::Viewport(grid) = result else {
        panic!("expected viewport result");
    };
    grid
}

#[test]
fn test_headless_line_metadata_for_wrapped_segments() {
    let mut executor = CommandExecutor::new("abcdef", 3);
    let grid = viewport(&mut executor, 0, 10);
    assert_eq!(grid.actual_line_count(), 2);

    let line0 = &grid.lines[0];
    assert_eq!(line0.logical_line_index, 0);
    assert_eq!(line0.visual_in_logical, 0);
    assert_eq!(line0.char_offset_start, 0);
    assert_eq!(line0.char_offset_end, 3);
    assert_eq!(line0.segment_x_start_cells, 0);
    assert!(!line0.is_fold_placeholder_appended);

    let line1 = &grid.lines[1];
    assert_eq!(line1.logical_line_index, 0);
    assert_eq!(line1.visual_in_logical, 1);
    assert_eq!(line1.char_offset_start, 3);
    assert_eq!(line1.char_offset_end, 6);
    assert_eq!(line1.segment_x_start_cells, 0);
    assert!(!line1.is_fold_placeholder_appended);
}

#[test]
fn test_fold_placeholder_sets_metadata_flag() {
    let mut executor = CommandExecutor::new("line1\nline2\nline3\n", 80);
    executor
        .execute(Command::Style(StyleCommand::Fold {
            start_line: 0,
            end_line: 2,
        }))
        .expect("fold should succeed");

    let grid = viewport(&mut executor, 0, 10);
    assert_eq!(grid.actual_line_count(), 2);
    assert_eq!(grid.lines[0].logical_line_index, 0);
    assert!(grid.lines[0].is_fold_placeholder_appended);
    assert_eq!(grid.lines[1].logical_line_index, 3);
}

#[test]
fn test_minimap_grid_summarizes_style_density() {
    let mut executor = CommandExecutor::new("abc def\n", 80);
    executor
        .execute(Command::Style(StyleCommand::AddStyle {
            start: 0,
            end: 3,
            style_id: 7,
        }))
        .expect("style insertion should succeed");

    let minimap = executor.editor().get_minimap_grid(0, 1);
    assert_eq!(minimap.actual_line_count(), 1);
    let line = &minimap.lines[0];
    assert_eq!(line.logical_line_index, 0);
    assert_eq!(line.visual_in_logical, 0);
    assert_eq!(line.char_offset_start, 0);
    assert_eq!(line.char_offset_end, 7);
    assert_eq!(line.dominant_style, Some(7));
    assert!(line.total_cells >= line.non_whitespace_cells);
}
