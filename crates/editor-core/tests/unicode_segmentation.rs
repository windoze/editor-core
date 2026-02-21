use editor_core::{Command, CommandExecutor, CursorCommand, EditCommand, Position};

#[test]
fn test_move_grapheme_left_right_with_combining_mark() {
    // "e\u{301}" is "e" + combining acute accent; one extended grapheme cluster.
    let mut executor = CommandExecutor::new("e\u{301}x", 80);

    executor
        .execute(Command::Cursor(CursorCommand::MoveGraphemeRight))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 2));

    executor
        .execute(Command::Cursor(CursorCommand::MoveGraphemeRight))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 3));

    executor
        .execute(Command::Cursor(CursorCommand::MoveGraphemeLeft))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 2));

    executor
        .execute(Command::Cursor(CursorCommand::MoveGraphemeLeft))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 0));
}

#[test]
fn test_delete_grapheme_deletes_emoji_cluster() {
    // "👍🏽" is one grapheme cluster (two Unicode scalars).
    let mut executor = CommandExecutor::new("a👍🏽b", 80);

    // After "a👍🏽" => column 3 (a=1, 👍=1, 🏽=1).
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 3,
        }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::DeleteGraphemeBack))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "ab");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 1));

    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(executor.editor().get_text(), "a👍🏽b");
}

#[test]
fn test_move_word_left_right_uses_unicode_word_boundaries() {
    let mut executor = CommandExecutor::new("hello world", 80);

    executor
        .execute(Command::Cursor(CursorCommand::MoveWordRight))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 5));

    executor
        .execute(Command::Cursor(CursorCommand::MoveWordRight))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 6));

    executor
        .execute(Command::Cursor(CursorCommand::MoveWordRight))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 11));

    executor
        .execute(Command::Cursor(CursorCommand::MoveWordLeft))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 6));

    executor
        .execute(Command::Cursor(CursorCommand::MoveWordLeft))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 5));

    executor
        .execute(Command::Cursor(CursorCommand::MoveWordLeft))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 0));
}

#[test]
fn test_delete_word_back_and_forward() {
    let mut executor = CommandExecutor::new("hello world", 80);

    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 11,
        }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::DeleteWordBack))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "hello ");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 6));

    executor
        .execute(Command::Edit(EditCommand::DeleteWordBack))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "hello");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 5));

    let mut executor = CommandExecutor::new("hello world", 80);
    executor
        .execute(Command::Edit(EditCommand::DeleteWordForward))
        .unwrap();
    assert_eq!(executor.editor().get_text(), " world");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 0));
}
