use editor_core::{
    Command, CommandResult, CursorCommand, EditorStateManager, Position, SearchOptions, ViewCommand,
};

#[test]
fn word_boundary_config_affects_select_word() {
    let mut state = EditorStateManager::new("foo-bar", 80);

    // Default behavior: '-' is a boundary, so selecting at "foo" selects only "foo".
    state
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1,
        }))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::SelectWord))
        .unwrap();
    let s1 = state
        .get_cursor_state()
        .selection
        .expect("non-empty selection");
    assert_eq!(s1.start, Position::new(0, 0));
    assert_eq!(s1.end, Position::new(0, 3));

    // Reconfigure boundaries so '-' is treated as a word char.
    state
        .execute(Command::View(
            ViewCommand::SetWordBoundaryAsciiBoundaryChars {
                boundary_chars: ".".to_string(),
            },
        ))
        .unwrap();

    // Clear selection so SelectWord will re-run.
    state
        .execute(Command::Cursor(CursorCommand::ClearSelection))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1,
        }))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::SelectWord))
        .unwrap();

    let s2 = state
        .get_cursor_state()
        .selection
        .expect("non-empty selection");
    assert_eq!(s2.start, Position::new(0, 0));
    assert_eq!(s2.end, Position::new(0, 7));
}

#[test]
fn word_boundary_config_can_be_reset_to_defaults() {
    let mut state = EditorStateManager::new("foo-bar", 80);

    state
        .execute(Command::View(
            ViewCommand::SetWordBoundaryAsciiBoundaryChars {
                boundary_chars: ".".to_string(),
            },
        ))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1,
        }))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::SelectWord))
        .unwrap();
    let s1 = state
        .get_cursor_state()
        .selection
        .expect("non-empty selection");
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
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1,
        }))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::SelectWord))
        .unwrap();
    let s2 = state
        .get_cursor_state()
        .selection
        .expect("non-empty selection");
    assert_eq!(s2.start, Position::new(0, 0));
    assert_eq!(s2.end, Position::new(0, 3));
}

#[test]
fn word_boundary_config_affects_whole_word_find() {
    let mut state = EditorStateManager::new("foo-bar bar", 80);
    let options = SearchOptions {
        case_sensitive: true,
        whole_word: true,
        regex: false,
    };

    state
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 0,
        }))
        .unwrap();
    let default_result = state
        .execute(Command::Cursor(CursorCommand::FindNext {
            query: "bar".to_string(),
            options,
        }))
        .unwrap();
    assert_search_match(default_result, 4, 7);

    state
        .execute(Command::View(
            ViewCommand::SetWordBoundaryAsciiBoundaryChars {
                boundary_chars: ".".to_string(),
            },
        ))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::ClearSelection))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 0,
        }))
        .unwrap();
    let configured_result = state
        .execute(Command::Cursor(CursorCommand::FindNext {
            query: "bar".to_string(),
            options,
        }))
        .unwrap();
    assert_search_match(configured_result, 8, 11);

    state
        .execute(Command::View(ViewCommand::ResetWordBoundaryDefaults))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::ClearSelection))
        .unwrap();
    state
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 0,
        }))
        .unwrap();
    let reset_result = state
        .execute(Command::Cursor(CursorCommand::FindNext {
            query: "bar".to_string(),
            options,
        }))
        .unwrap();
    assert_search_match(reset_result, 4, 7);
}

fn assert_search_match(result: CommandResult, expected_start: usize, expected_end: usize) {
    match result {
        CommandResult::SearchMatch { start, end } => {
            assert_eq!((start, end), (expected_start, expected_end));
        }
        other => panic!("expected SearchMatch, got {other:?}"),
    }
}
