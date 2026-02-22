use editor_core::{Command, CommandExecutor, CommentConfig, CursorCommand, EditCommand, Position};

#[test]
fn test_toggle_line_comment_single_line() {
    let mut ex = CommandExecutor::new("let x = 1;", 80);
    ex.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 0,
        column: 0,
    }))
    .unwrap();

    ex.execute(Command::Edit(EditCommand::ToggleComment {
        config: CommentConfig::line("//"),
    }))
    .unwrap();

    assert_eq!(ex.editor().get_text(), "// let x = 1;");
    assert_eq!(ex.editor().cursor_position(), Position::new(0, 3));

    ex.execute(Command::Edit(EditCommand::ToggleComment {
        config: CommentConfig::line("//"),
    }))
    .unwrap();

    assert_eq!(ex.editor().get_text(), "let x = 1;");
    assert_eq!(ex.editor().cursor_position(), Position::new(0, 0));
}

#[test]
fn test_toggle_line_comment_multi_line_selection() {
    let mut ex = CommandExecutor::new("a\n  b\nc", 80);

    ex.execute(Command::Cursor(CursorCommand::SetSelection {
        start: Position::new(0, 0),
        end: Position::new(2, 0),
    }))
    .unwrap();

    ex.execute(Command::Edit(EditCommand::ToggleComment {
        config: CommentConfig::line("//"),
    }))
    .unwrap();

    assert_eq!(ex.editor().get_text(), "// a\n  // b\n// c");

    ex.execute(Command::Edit(EditCommand::ToggleComment {
        config: CommentConfig::line("//"),
    }))
    .unwrap();

    assert_eq!(ex.editor().get_text(), "a\n  b\nc");
}

#[test]
fn test_toggle_block_comment_inline_single_line_selection() {
    let mut ex = CommandExecutor::new("abc", 80);

    ex.execute(Command::Cursor(CursorCommand::SetSelection {
        start: Position::new(0, 1),
        end: Position::new(0, 2),
    }))
    .unwrap();

    ex.execute(Command::Edit(EditCommand::ToggleComment {
        config: CommentConfig::block("/*", "*/"),
    }))
    .unwrap();

    assert_eq!(ex.editor().get_text(), "a/*b*/c");

    ex.execute(Command::Edit(EditCommand::ToggleComment {
        config: CommentConfig::block("/*", "*/"),
    }))
    .unwrap();

    assert_eq!(ex.editor().get_text(), "abc");
}
