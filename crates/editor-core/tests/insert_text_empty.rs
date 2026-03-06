use editor_core::{
    Command, CommandExecutor, CursorCommand, EditCommand, Position, Selection, SelectionDirection,
};

#[test]
fn insert_text_empty_deletes_non_empty_selections_only() {
    let mut executor = CommandExecutor::new("one two three", 80);

    // Selections: "one", caret, "three".
    let selections = vec![
        Selection {
            start: Position::new(0, 0),
            end: Position::new(0, 3),
            direction: SelectionDirection::Forward,
        },
        Selection {
            start: Position::new(0, 4),
            end: Position::new(0, 4),
            direction: SelectionDirection::Forward,
        },
        Selection {
            start: Position::new(0, 8),
            end: Position::new(0, 13),
            direction: SelectionDirection::Forward,
        },
    ];
    executor
        .execute(Command::Cursor(CursorCommand::SetSelections {
            selections,
            primary_index: 0,
        }))
        .unwrap();

    // Replacing with empty string should delete the selected ranges while leaving carets intact.
    executor
        .execute(Command::Edit(EditCommand::InsertText {
            text: String::new(),
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), " two ");
    assert!(executor.editor().selection().is_none());
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 0));
    assert_eq!(executor.editor().secondary_selections().len(), 2);
    assert!(executor
        .editor()
        .secondary_selections()
        .iter()
        .all(|s| s.start == s.end));
}

#[test]
fn insert_text_empty_is_noop_when_there_is_no_selection() {
    let mut executor = CommandExecutor::new("abc", 80);
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::InsertText {
            text: String::new(),
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "abc");
    assert!(!executor.can_undo(), "expected no undo step for a no-op insert");
}

