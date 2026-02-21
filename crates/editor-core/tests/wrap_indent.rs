use editor_core::{
    Command, CommandExecutor, CommandResult, CursorCommand, Position, ViewCommand, WrapIndent,
};

#[test]
fn test_wrapped_indent_affects_snapshot_and_cursor_mapping() {
    // With viewport width 6 and wrap indent = SameAsLineIndent (4 spaces), this wraps into:
    // row 0: "    ab"
    // row 1: "    cd"
    // row 2: "    ef"
    // row 3: "    gh"
    let mut executor = CommandExecutor::new("    abcdefgh", 6);
    executor
        .execute(Command::View(ViewCommand::SetWrapIndent {
            indent: WrapIndent::SameAsLineIndent,
        }))
        .unwrap();

    let grid = match executor
        .execute(Command::View(ViewCommand::GetViewport {
            start_row: 0,
            count: 8,
        }))
        .unwrap()
    {
        CommandResult::Viewport(grid) => grid,
        other => panic!("expected viewport result, got {other:?}"),
    };

    assert_eq!(grid.actual_line_count(), 4);
    let lines: Vec<String> = grid
        .lines
        .iter()
        .map(|l| l.cells.iter().map(|c| c.ch).collect::<String>())
        .collect();
    assert_eq!(lines, vec!["    ab", "    cd", "    ef", "    gh"]);

    // Segment start of row 1 is column 6 ("c"). Wrap indent is 4 cells.
    assert_eq!(
        executor.editor().logical_position_to_visual(0, 6),
        Some((1, 4))
    );

    // x within wrap-indent maps to the segment start (column 6).
    executor
        .execute(Command::Cursor(CursorCommand::MoveToVisual {
            row: 1,
            x_cells: 0,
        }))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 6));

    executor
        .execute(Command::Cursor(CursorCommand::MoveToVisual {
            row: 1,
            x_cells: 4,
        }))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 6));

    // After wrap indent, x=5 lands on the next char ("d") at column 7.
    executor
        .execute(Command::Cursor(CursorCommand::MoveToVisual {
            row: 1,
            x_cells: 5,
        }))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 7));
}
