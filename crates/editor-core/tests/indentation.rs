use editor_core::{Command, CommandExecutor, CursorCommand, EditCommand, Position, ViewCommand};

#[test]
fn test_indent_and_outdent_single_line_tab_mode() {
    let mut executor = CommandExecutor::new("line1\nline2\n", 80);

    // Indent line 2.
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 1,
            column: 0,
        }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::Indent))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "line1\n\tline2\n");
    assert_eq!(executor.editor().cursor_position(), Position::new(1, 1));

    // Outdent the same line.
    executor
        .execute(Command::Edit(EditCommand::Outdent))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "line1\nline2\n");
    assert_eq!(executor.editor().cursor_position(), Position::new(1, 0));
}

#[test]
fn test_auto_indent_newline_copies_leading_whitespace() {
    let mut executor = CommandExecutor::new("    let x = 1;", 80);

    // Place cursor at end of the line.
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1000,
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::InsertNewline {
            auto_indent: true,
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "    let x = 1;\n    ");
    assert_eq!(executor.editor().cursor_position(), Position::new(1, 4));
}

#[test]
fn test_indent_respects_spaces_mode() {
    let mut executor = CommandExecutor::new("x\n", 80);

    executor
        .execute(Command::View(ViewCommand::SetTabWidth { width: 2 }))
        .unwrap();
    executor
        .execute(Command::View(ViewCommand::SetTabKeyBehavior {
            behavior: editor_core::TabKeyBehavior::Spaces,
        }))
        .unwrap();

    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 0,
        }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::Indent))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "  x\n");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 2));
}

#[test]
fn test_delete_to_prev_tab_stop_in_leading_spaces() {
    let mut executor = CommandExecutor::new("      x", 80);

    executor
        .execute(Command::View(ViewCommand::SetTabWidth { width: 4 }))
        .unwrap();
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 6,
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::DeleteToPrevTabStop))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "    x");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 4));

    executor
        .execute(Command::Edit(EditCommand::DeleteToPrevTabStop))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "x");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 0));

    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(executor.editor().get_text(), "    x");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 4));
}

#[test]
fn test_delete_to_prev_tab_stop_falls_back_to_backspace() {
    let mut executor = CommandExecutor::new("  foo", 80);

    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 5,
        }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::DeleteToPrevTabStop))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "  fo");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 4));
}

#[test]
fn test_delete_to_prev_tab_stop_with_tab_indentation() {
    let mut executor = CommandExecutor::new("\tfoo", 80);

    executor
        .execute(Command::View(ViewCommand::SetTabWidth { width: 4 }))
        .unwrap();
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1,
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::DeleteToPrevTabStop))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "foo");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 0));
}

#[test]
fn test_auto_indent_newline_copies_tabs_too() {
    let mut executor = CommandExecutor::new("\t\tlet x = 1;", 80);
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1000,
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::InsertNewline {
            auto_indent: true,
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "\t\tlet x = 1;\n\t\t");
    assert_eq!(executor.editor().cursor_position(), Position::new(1, 2));
}

#[test]
fn test_indent_outdent_multi_line_selection() {
    let mut executor = CommandExecutor::new("a\nb\nc\n", 80);

    executor
        .execute(Command::Cursor(CursorCommand::SetSelection {
            start: Position::new(0, 0),
            end: Position::new(1, 1),
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::Indent))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "\ta\n\tb\nc\n");

    executor
        .execute(Command::Edit(EditCommand::Outdent))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "a\nb\nc\n");
}
