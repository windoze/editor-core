use editor_core::{
    Command, CommandExecutor, CursorCommand, EditCommand, Position, Selection, SelectionDirection,
};

fn caret(line: usize, column: usize) -> Selection {
    let pos = Position::new(line, column);
    Selection {
        start: pos,
        end: pos,
        direction: SelectionDirection::Forward,
    }
}

#[test]
fn test_duplicate_lines_single_cursor_moves_to_duplicate() {
    let mut ex = CommandExecutor::new("a\nb\nc", 80);

    ex.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 1,
        column: 0,
    }))
    .unwrap();

    ex.execute(Command::Edit(EditCommand::DuplicateLines))
        .unwrap();

    assert_eq!(ex.editor().get_text(), "a\nb\nb\nc");
    assert_eq!(ex.editor().cursor_position(), Position::new(2, 0));
    assert!(ex.editor().secondary_selections().is_empty());
}

#[test]
fn test_duplicate_lines_multi_cursor_disjoint_blocks() {
    let mut ex = CommandExecutor::new("a\nb\nc", 80);

    ex.execute(Command::Cursor(CursorCommand::SetSelections {
        selections: vec![caret(0, 0), caret(2, 0)],
        primary_index: 0,
    }))
    .unwrap();

    ex.execute(Command::Edit(EditCommand::DuplicateLines))
        .unwrap();

    assert_eq!(ex.editor().get_text(), "a\na\nb\nc\nc");

    // Primary caret moves to the duplicate of line 0 => line 1.
    assert_eq!(ex.editor().cursor_position(), Position::new(1, 0));

    // Secondary caret moves to the duplicate of line 2 => last line.
    let secondary = ex.editor().secondary_selections();
    assert_eq!(secondary.len(), 1);
    assert_eq!(secondary[0].end, Position::new(4, 0));
}

#[test]
fn test_delete_lines_removes_selected_line() {
    let mut ex = CommandExecutor::new("a\nb\nc", 80);
    ex.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 1,
        column: 0,
    }))
    .unwrap();

    ex.execute(Command::Edit(EditCommand::DeleteLines)).unwrap();

    assert_eq!(ex.editor().get_text(), "a\nc");
    assert_eq!(ex.editor().cursor_position(), Position::new(1, 0));
}

#[test]
fn test_delete_lines_last_line_removes_prev_newline() {
    let mut ex = CommandExecutor::new("a\nb", 80);
    ex.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 1,
        column: 0,
    }))
    .unwrap();

    ex.execute(Command::Edit(EditCommand::DeleteLines)).unwrap();

    assert_eq!(ex.editor().get_text(), "a");
    assert_eq!(ex.editor().cursor_position(), Position::new(0, 1));
}

#[test]
fn test_move_lines_up_down_swaps_with_neighbor() {
    let mut ex = CommandExecutor::new("a\nb\nc", 80);

    ex.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 1,
        column: 0,
    }))
    .unwrap();
    ex.execute(Command::Edit(EditCommand::MoveLinesUp)).unwrap();
    assert_eq!(ex.editor().get_text(), "b\na\nc");
    assert_eq!(ex.editor().cursor_position(), Position::new(0, 0));

    ex.execute(Command::Edit(EditCommand::MoveLinesDown))
        .unwrap();
    assert_eq!(ex.editor().get_text(), "a\nb\nc");
    assert_eq!(ex.editor().cursor_position(), Position::new(1, 0));
}

#[test]
fn test_join_lines_trims_leading_ws_and_inserts_space() {
    let mut ex = CommandExecutor::new("a\n  b\nc", 80);
    ex.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 0,
        column: 0,
    }))
    .unwrap();

    ex.execute(Command::Edit(EditCommand::JoinLines)).unwrap();

    assert_eq!(ex.editor().get_text(), "a b\nc");
    assert_eq!(ex.editor().cursor_position(), Position::new(0, 2));
}

#[test]
fn test_select_line_selects_full_line_including_newline() {
    let mut ex = CommandExecutor::new("abc\ndef", 80);
    ex.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 0,
        column: 2,
    }))
    .unwrap();

    ex.execute(Command::Cursor(CursorCommand::SelectLine))
        .unwrap();

    let sel = ex.editor().selection().cloned().expect("selection exists");
    assert_eq!(sel.start, Position::new(0, 0));
    assert_eq!(sel.end, Position::new(1, 0));
}

#[test]
fn test_add_cursor_above_adds_secondary_caret() {
    let mut ex = CommandExecutor::new("a\nb\nc", 80);
    ex.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 1,
        column: 0,
    }))
    .unwrap();

    ex.execute(Command::Cursor(CursorCommand::AddCursorAbove))
        .unwrap();

    assert_eq!(ex.editor().cursor_position(), Position::new(1, 0));
    let secondary = ex.editor().secondary_selections();
    assert_eq!(secondary.len(), 1);
    assert_eq!(secondary[0].end, Position::new(0, 0));
}

#[test]
fn test_add_next_occurrence_selects_word_then_adds_next() {
    let mut ex = CommandExecutor::new("foo foo foo", 80);
    ex.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 0,
        column: 0,
    }))
    .unwrap();

    ex.execute(Command::Cursor(CursorCommand::AddNextOccurrence {
        options: editor_core::SearchOptions::default(),
    }))
    .unwrap();

    let sel = ex.editor().selection().cloned().expect("primary selection");
    // Primary becomes the newly added match (the second "foo").
    assert_eq!(sel.start, Position::new(0, 4));
    assert_eq!(sel.end, Position::new(0, 7));

    let secondary = ex.editor().secondary_selections();
    assert_eq!(secondary.len(), 1);
    assert_eq!(secondary[0].start, Position::new(0, 0));
    assert_eq!(secondary[0].end, Position::new(0, 3));
}

#[test]
fn test_add_all_occurrences_selects_all_matches() {
    let mut ex = CommandExecutor::new("foo foo foo", 80);
    ex.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 0,
        column: 0,
    }))
    .unwrap();

    ex.execute(Command::Cursor(CursorCommand::AddAllOccurrences {
        options: editor_core::SearchOptions::default(),
    }))
    .unwrap();

    let sel = ex.editor().selection().cloned().expect("primary selection");
    assert_eq!(sel.start, Position::new(0, 0));
    assert_eq!(sel.end, Position::new(0, 3));

    let secondary = ex.editor().secondary_selections();
    assert_eq!(secondary.len(), 2);
    assert_eq!(secondary[0].start, Position::new(0, 4));
    assert_eq!(secondary[0].end, Position::new(0, 7));
    assert_eq!(secondary[1].start, Position::new(0, 8));
    assert_eq!(secondary[1].end, Position::new(0, 11));
}
