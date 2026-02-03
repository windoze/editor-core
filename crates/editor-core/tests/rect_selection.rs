use editor_core::{
    Command, CommandExecutor, CursorCommand, EditCommand, Position, Selection, SelectionDirection,
};

#[test]
fn test_set_rect_selection_expands_per_line_and_sets_primary() {
    let mut executor = CommandExecutor::new("abc\ndef\nghi", 80);

    executor
        .execute(Command::Cursor(CursorCommand::SetRectSelection {
            anchor: Position::new(0, 1),
            active: Position::new(2, 3),
        }))
        .unwrap();

    // Primary is the active-line selection.
    assert_eq!(executor.editor().cursor_position(), Position::new(2, 3));
    let primary = executor.editor().selection().cloned().unwrap();
    assert_eq!(
        primary,
        Selection {
            start: Position::new(2, 1),
            end: Position::new(2, 3),
            direction: SelectionDirection::Forward,
        }
    );

    let secondary = executor.editor().secondary_selections();
    assert_eq!(secondary.len(), 2);
    assert_eq!(secondary[0].start, Position::new(0, 1));
    assert_eq!(secondary[0].end, Position::new(0, 3));
    assert_eq!(secondary[1].start, Position::new(1, 1));
    assert_eq!(secondary[1].end, Position::new(1, 3));
}

#[test]
fn test_insert_text_with_rect_carets_pads_virtual_columns() {
    let mut executor = CommandExecutor::new("a\nbbb\ncc\n", 80);

    executor
        .execute(Command::Cursor(CursorCommand::SetRectSelection {
            anchor: Position::new(0, 5),
            active: Position::new(2, 5),
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::InsertText {
            text: "X".to_string(),
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "a    X\nbbb  X\ncc   X\n");

    // After typing, selections collapse to carets and all carets move right by 1.
    assert_eq!(executor.editor().cursor_position(), Position::new(2, 6));
    assert!(executor.editor().selection().is_none());
    let secondary = executor.editor().secondary_selections();
    assert_eq!(secondary.len(), 2);
    assert_eq!(secondary[0].start, Position::new(0, 6));
    assert_eq!(secondary[0].end, Position::new(0, 6));
    assert_eq!(secondary[1].start, Position::new(1, 6));
    assert_eq!(secondary[1].end, Position::new(1, 6));
}

#[test]
fn test_multi_cursor_insert_text_replaces_each_selection() {
    let mut executor = CommandExecutor::new("hello\nhello\nhello\n", 80);

    let selections = vec![
        Selection {
            start: Position::new(0, 0),
            end: Position::new(0, 5),
            direction: SelectionDirection::Forward,
        },
        Selection {
            start: Position::new(1, 0),
            end: Position::new(1, 5),
            direction: SelectionDirection::Forward,
        },
        Selection {
            start: Position::new(2, 0),
            end: Position::new(2, 5),
            direction: SelectionDirection::Forward,
        },
    ];

    executor
        .execute(Command::Cursor(CursorCommand::SetSelections {
            selections,
            primary_index: 2,
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::InsertText {
            text: "hi".to_string(),
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "hi\nhi\nhi\n");
    assert_eq!(executor.editor().cursor_position(), Position::new(2, 2));
    assert!(executor.editor().selection().is_none());
    assert_eq!(executor.editor().secondary_selections().len(), 2);
}

#[test]
fn test_set_selections_normalizes_duplicates_and_overlaps() {
    let mut executor = CommandExecutor::new("abcdef", 80);

    let selections = vec![
        Selection {
            start: Position::new(0, 0),
            end: Position::new(0, 2),
            direction: SelectionDirection::Forward,
        },
        Selection {
            start: Position::new(0, 1),
            end: Position::new(0, 1),
            direction: SelectionDirection::Forward,
        },
        Selection {
            start: Position::new(0, 1),
            end: Position::new(0, 1),
            direction: SelectionDirection::Forward,
        },
    ];

    executor
        .execute(Command::Cursor(CursorCommand::SetSelections {
            selections,
            primary_index: 1,
        }))
        .unwrap();

    assert!(executor.editor().secondary_selections().is_empty());
    let primary = executor.editor().selection().cloned().unwrap();
    assert_eq!(primary.start, Position::new(0, 0));
    assert_eq!(primary.end, Position::new(0, 2));
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 2));
}
