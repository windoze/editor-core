use editor_core::{
    Command, CursorCommand, EditorStateManager, ExpandSelectionDirection, ExpandSelectionUnit,
    Position,
};

#[test]
fn expand_selection_by_character_expands_only_and_allows_direction_changes() {
    let mut state = EditorStateManager::new("abcd", 80);

    // Place caret after "ab" (column 2).
    state
        .execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 2 }))
        .unwrap();

    // Expand forward by 1 character => selects "c".
    state
        .execute(Command::Cursor(CursorCommand::ExpandSelectionBy {
            unit: ExpandSelectionUnit::Character,
            count: 1,
            direction: ExpandSelectionDirection::Forward,
        }))
        .unwrap();

    let s1 = state.get_cursor_state().selection.expect("non-empty selection");
    assert_eq!(s1.start, Position::new(0, 2));
    assert_eq!(s1.end, Position::new(0, 3));

    // Change direction: expand backward by 2 characters => expands start only (does not reset).
    state
        .execute(Command::Cursor(CursorCommand::ExpandSelectionBy {
            unit: ExpandSelectionUnit::Character,
            count: 2,
            direction: ExpandSelectionDirection::Backward,
        }))
        .unwrap();

    let s2 = state.get_cursor_state().selection.expect("non-empty selection");
    assert_eq!(s2.start, Position::new(0, 0));
    assert_eq!(s2.end, Position::new(0, 3));
}

#[test]
fn expand_selection_by_word_steps_over_whitespace_and_punctuation() {
    let mut state = EditorStateManager::new("one two three", 80);
    state
        .execute(Command::Cursor(CursorCommand::MoveTo { line: 0, column: 4 })) // at "two"
        .unwrap();

    // Expand forward by 1 word => selects "two".
    state
        .execute(Command::Cursor(CursorCommand::ExpandSelectionBy {
            unit: ExpandSelectionUnit::Word,
            count: 1,
            direction: ExpandSelectionDirection::Forward,
        }))
        .unwrap();
    let s1 = state.get_cursor_state().selection.expect("non-empty selection");
    assert_eq!(s1.start, Position::new(0, 4));
    assert_eq!(s1.end, Position::new(0, 7));

    // Expand forward by 1 more word => extends through "three" (including the space).
    state
        .execute(Command::Cursor(CursorCommand::ExpandSelectionBy {
            unit: ExpandSelectionUnit::Word,
            count: 1,
            direction: ExpandSelectionDirection::Forward,
        }))
        .unwrap();
    let s2 = state.get_cursor_state().selection.expect("non-empty selection");
    assert_eq!(s2.start, Position::new(0, 4));
    assert_eq!(s2.end, Position::new(0, 13));

    // Direction change: expand backward by 1 word => extends to "one".
    state
        .execute(Command::Cursor(CursorCommand::ExpandSelectionBy {
            unit: ExpandSelectionUnit::Word,
            count: 1,
            direction: ExpandSelectionDirection::Backward,
        }))
        .unwrap();
    let s3 = state.get_cursor_state().selection.expect("non-empty selection");
    assert_eq!(s3.start, Position::new(0, 0));
    assert_eq!(s3.end, Position::new(0, 13));
}

#[test]
fn expand_selection_by_line_expands_to_line_starts() {
    let mut state = EditorStateManager::new("aa\nbb\ncc", 80);
    state
        .execute(Command::Cursor(CursorCommand::MoveTo { line: 1, column: 1 })) // inside "bb"
        .unwrap();

    state
        .execute(Command::Cursor(CursorCommand::ExpandSelectionBy {
            unit: ExpandSelectionUnit::Line,
            count: 1,
            direction: ExpandSelectionDirection::Forward,
        }))
        .unwrap();

    let s1 = state.get_cursor_state().selection.expect("non-empty selection");
    assert_eq!(s1.start, Position::new(1, 1));
    assert_eq!(s1.end, Position::new(2, 0)); // start of next line

    state
        .execute(Command::Cursor(CursorCommand::ExpandSelectionBy {
            unit: ExpandSelectionUnit::Line,
            count: 1,
            direction: ExpandSelectionDirection::Backward,
        }))
        .unwrap();

    let s2 = state.get_cursor_state().selection.expect("non-empty selection");
    assert_eq!(s2.start, Position::new(0, 0));
    assert_eq!(s2.end, Position::new(2, 0));
}

