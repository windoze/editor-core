use editor_core::{Command, CommandExecutor, CursorCommand, Position};

#[test]
fn test_move_to_visual_in_wrapped_line() {
    // With viewport width 5, this single logical line wraps into:
    // row 0: "abcde"
    // row 1: "fghij"
    let mut executor = CommandExecutor::new("abcdefghij", 5);

    executor
        .execute(Command::Cursor(CursorCommand::MoveToVisual {
            row: 1,
            x_cells: 1,
        }))
        .unwrap();

    // Second segment starts at column 5 ("f"), plus x=1 => column 6.
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 6));
}

#[test]
fn test_move_visual_by_sticky_x_across_visual_rows() {
    // Visual rows with width=5:
    // row 0: "abcde"
    // row 1: "fghij"
    // row 2: "123"
    let mut executor = CommandExecutor::new("abcdefghij\n123", 5);

    // Start at column 4 (x=4) in row 0.
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 4,
        }))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 4));

    // Down one visual row: should land in row 1 at the same x within the segment.
    executor
        .execute(Command::Cursor(CursorCommand::MoveVisualBy {
            delta_rows: 1,
        }))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 9));

    // Down one more: row 2 is shorter ("123"), so clamp to end-of-line (column 3).
    executor
        .execute(Command::Cursor(CursorCommand::MoveVisualBy {
            delta_rows: 1,
        }))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(1, 3));

    // Up one: should return to row 1 and restore the preferred x (column 9).
    executor
        .execute(Command::Cursor(CursorCommand::MoveVisualBy {
            delta_rows: -1,
        }))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 9));
}

#[test]
fn test_move_to_visual_line_start_end() {
    let mut executor = CommandExecutor::new("abcdefghij", 5);

    executor
        .execute(Command::Cursor(CursorCommand::MoveToVisual {
            row: 1,
            x_cells: 2,
        }))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 7));

    executor
        .execute(Command::Cursor(CursorCommand::MoveToVisualLineStart))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 5));

    executor
        .execute(Command::Cursor(CursorCommand::MoveToVisualLineEnd))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 10));
}
