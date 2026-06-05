use std::time::{Duration, Instant};

use editor_core::{
    Command, CommandExecutor, CommentConfig, CursorCommand, EditCommand, Position, Selection,
    SelectionDirection,
};

fn selection(start: Position, end: Position) -> Selection {
    Selection {
        start,
        end,
        direction: SelectionDirection::Forward,
    }
}

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
fn test_toggle_line_comment_unicode_multiline_with_empty_line() {
    let mut ex = CommandExecutor::new("  你\n\n\t🙂", 80);

    ex.execute(Command::Cursor(CursorCommand::SetSelection {
        start: Position::new(0, 0),
        end: Position::new(2, 0),
    }))
    .unwrap();

    ex.execute(Command::Edit(EditCommand::ToggleComment {
        config: CommentConfig::line("//"),
    }))
    .unwrap();

    assert_eq!(ex.editor().get_text(), "  // 你\n// \n\t// 🙂");

    ex.execute(Command::Edit(EditCommand::ToggleComment {
        config: CommentConfig::line("//"),
    }))
    .unwrap();

    assert_eq!(ex.editor().get_text(), "  你\n\n\t🙂");
}

#[test]
fn test_toggle_line_comment_cjk_emoji_tab_and_space_indents() {
    let original = "\t  你\n    🙂\n\t\tvalue";
    let mut ex = CommandExecutor::new(original, 80);

    ex.execute(Command::Cursor(CursorCommand::SetSelection {
        start: Position::new(0, 0),
        end: Position::new(2, 0),
    }))
    .unwrap();

    ex.execute(Command::Edit(EditCommand::ToggleComment {
        config: CommentConfig::line("#"),
    }))
    .unwrap();

    assert_eq!(ex.editor().get_text(), "\t  # 你\n    # 🙂\n\t\t# value");

    ex.execute(Command::Edit(EditCommand::ToggleComment {
        config: CommentConfig::line("#"),
    }))
    .unwrap();

    assert_eq!(ex.editor().get_text(), original);
}

#[test]
fn test_toggle_line_comment_long_multiselection_has_no_quadratic_column_scan() {
    let indent = " ".repeat(2048);
    let line = format!("{indent}🙂 value");
    let original = vec![line; 256].join("\n");
    let mut ex = CommandExecutor::new(&original, 80);

    ex.execute(Command::Cursor(CursorCommand::SetSelections {
        selections: vec![
            selection(Position::new(0, 0), Position::new(127, 0)),
            selection(Position::new(128, 0), Position::new(255, 0)),
        ],
        primary_index: 0,
    }))
    .unwrap();

    let start = Instant::now();
    ex.execute(Command::Edit(EditCommand::ToggleComment {
        config: CommentConfig::line("//"),
    }))
    .unwrap();
    assert!(
        ex.editor()
            .get_text()
            .starts_with(&format!("{indent}// 🙂 value"))
    );

    ex.execute(Command::Edit(EditCommand::ToggleComment {
        config: CommentConfig::line("//"),
    }))
    .unwrap();
    let elapsed = start.elapsed();

    assert_eq!(ex.editor().get_text(), original);
    assert!(
        elapsed < Duration::from_secs(10),
        "long multi-selection toggle comment took {elapsed:?}"
    );
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
