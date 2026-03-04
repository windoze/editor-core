use editor_core::{Command, CursorCommand, EditorStateManager, Position, ViewCommand};

#[test]
fn word_boundary_config_affects_select_word() {
    let mut state = EditorStateManager::new("foo-bar", 80);

    // Default behavior: '-' is a boundary, so selecting at "foo" selects only "foo".
    state
        .execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::SelectWord))
        .unwrap();
    let s1 = state.get_cursor_state().selection.expect("non-empty selection");
    assert_eq!(s1.start, Position::new(0, 0));
    assert_eq!(s1.end, Position::new(0, 3));

    // Reconfigure boundaries so '-' is treated as a word char.
    state
        .execute(Command::View(ViewCommand::SetWordBoundaryAsciiBoundaryChars {
            boundary_chars: ".".to_string(),
        }))
        .unwrap();

    // Clear selection so SelectWord will re-run.
    state
        .execute(Command::Cursor(CursorCommand::ClearSelection))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::SelectWord))
        .unwrap();

    let s2 = state.get_cursor_state().selection.expect("non-empty selection");
    assert_eq!(s2.start, Position::new(0, 0));
    assert_eq!(s2.end, Position::new(0, 7));
}

#[test]
fn word_boundary_config_can_be_reset_to_defaults() {
    let mut state = EditorStateManager::new("foo-bar", 80);

    state
        .execute(Command::View(ViewCommand::SetWordBoundaryAsciiBoundaryChars {
            boundary_chars: ".".to_string(),
        }))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::SelectWord))
        .unwrap();
    let s1 = state.get_cursor_state().selection.expect("non-empty selection");
    assert_eq!(s1.start, Position::new(0, 0));
    assert_eq!(s1.end, Position::new(0, 7));

    // Reset: '-' becomes a boundary again.
    state
        .execute(Command::View(ViewCommand::ResetWordBoundaryDefaults))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::ClearSelection))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::SelectWord))
        .unwrap();
    let s2 = state.get_cursor_state().selection.expect("non-empty selection");
    assert_eq!(s2.start, Position::new(0, 0));
    assert_eq!(s2.end, Position::new(0, 3));
}

