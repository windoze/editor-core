use editor_core::{
    Command, CommandExecutor, CursorCommand, EditCommand, Position, Selection, SelectionDirection,
};

#[test]
fn test_undo_redo_insert_text_single_cursor() {
    let mut executor = CommandExecutor::empty(80);

    executor
        .execute(Command::Edit(EditCommand::InsertText {
            text: "a".to_string(),
        }))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "a");
    assert!(executor.can_undo());
    assert!(!executor.can_redo());

    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(executor.editor().get_text(), "");
    assert!(!executor.can_undo());
    assert!(executor.can_redo());

    executor.execute(Command::Edit(EditCommand::Redo)).unwrap();
    assert_eq!(executor.editor().get_text(), "a");
    assert!(executor.can_undo());
    assert!(!executor.can_redo());
}

#[test]
fn test_undo_group_coalesces_consecutive_inserts() {
    let mut executor = CommandExecutor::empty(80);

    for ch in ["a", "b", "c"] {
        executor
            .execute(Command::Edit(EditCommand::InsertText {
                text: ch.to_string(),
            }))
            .unwrap();
    }
    assert_eq!(executor.editor().get_text(), "abc");
    assert_eq!(executor.undo_depth(), 3);

    // One undo should revert the whole coalesced group.
    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(executor.editor().get_text(), "");
    assert_eq!(executor.undo_depth(), 0);
    assert_eq!(executor.redo_depth(), 3);

    // One redo should re-apply the whole group.
    executor.execute(Command::Edit(EditCommand::Redo)).unwrap();
    assert_eq!(executor.editor().get_text(), "abc");
    assert_eq!(executor.undo_depth(), 3);
    assert_eq!(executor.redo_depth(), 0);
}

#[test]
fn test_end_undo_group_breaks_coalescing() {
    let mut executor = CommandExecutor::empty(80);

    executor
        .execute(Command::Edit(EditCommand::InsertText {
            text: "a".to_string(),
        }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::EndUndoGroup))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::InsertText {
            text: "b".to_string(),
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "ab");

    // Undo should only remove "b".
    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(executor.editor().get_text(), "a");

    // Undo again removes "a".
    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(executor.editor().get_text(), "");
}

#[test]
fn test_undo_redo_restores_multi_selection() {
    let mut executor = CommandExecutor::new("one\ntwo\nthree\n", 80);

    let selections = vec![
        Selection {
            start: Position::new(0, 0),
            end: Position::new(0, 0),
            direction: SelectionDirection::Forward,
        },
        Selection {
            start: Position::new(1, 0),
            end: Position::new(1, 0),
            direction: SelectionDirection::Forward,
        },
        Selection {
            start: Position::new(2, 0),
            end: Position::new(2, 0),
            direction: SelectionDirection::Forward,
        },
    ];

    executor
        .execute(Command::Cursor(CursorCommand::SetSelections {
            selections,
            primary_index: 1,
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::InsertText {
            text: "X".to_string(),
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "Xone\nXtwo\nXthree\n");
    assert_eq!(executor.editor().cursor_position(), Position::new(1, 1));
    assert_eq!(executor.editor().secondary_selections().len(), 2);

    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();

    assert_eq!(executor.editor().get_text(), "one\ntwo\nthree\n");
    assert_eq!(executor.editor().cursor_position(), Position::new(1, 0));
    let secondary: Vec<Position> = executor
        .editor()
        .secondary_selections()
        .iter()
        .map(|s| s.end)
        .collect();
    assert_eq!(secondary, vec![Position::new(0, 0), Position::new(2, 0)]);

    executor.execute(Command::Edit(EditCommand::Redo)).unwrap();

    assert_eq!(executor.editor().get_text(), "Xone\nXtwo\nXthree\n");
    assert_eq!(executor.editor().cursor_position(), Position::new(1, 1));
    let secondary: Vec<Position> = executor
        .editor()
        .secondary_selections()
        .iter()
        .map(|s| s.end)
        .collect();
    assert_eq!(secondary, vec![Position::new(0, 1), Position::new(2, 1)]);
}

#[test]
fn test_backspace_and_delete_forward_are_undoable_and_restore_caret() {
    let mut executor = CommandExecutor::new("ab", 80);

    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 2,
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::Backspace))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "a");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 1));

    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(executor.editor().get_text(), "ab");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 2));

    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 0,
        }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::DeleteForward))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "b");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 0));

    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(executor.editor().get_text(), "ab");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 0));
}
