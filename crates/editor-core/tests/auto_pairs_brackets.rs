use editor_core::{
    AutoPairsConfig, Command, CommandExecutor, CursorCommand, EditCommand,
    MATCH_HIGHLIGHT_STYLE_ID, Position, Selection, SelectionDirection, StyleCommand, StyleLayerId,
    ViewCommand,
};

#[test]
fn type_char_auto_closes_brackets_and_places_caret_between() {
    let mut executor = CommandExecutor::empty(80);
    executor
        .execute(Command::View(ViewCommand::SetAutoPairsEnabled {
            enabled: true,
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::TypeChar { ch: '(' }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "()");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 1));
    assert!(executor.editor().selection().is_none());
}

#[test]
fn type_char_auto_closes_quotes() {
    let mut executor = CommandExecutor::empty(80);
    executor
        .execute(Command::View(ViewCommand::SetAutoPairsEnabled {
            enabled: true,
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::TypeChar { ch: '"' }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "\"\"");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 1));
}

#[test]
fn type_char_wraps_selection_when_enabled() {
    let mut executor = CommandExecutor::new("abc", 80);
    executor
        .execute(Command::View(ViewCommand::SetAutoPairsEnabled {
            enabled: true,
        }))
        .unwrap();

    executor
        .execute(Command::Cursor(CursorCommand::SetSelection {
            start: Position::new(0, 1),
            end: Position::new(0, 2),
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::TypeChar { ch: '(' }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "a(b)c");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 3));
    assert_eq!(
        executor.editor().selection().cloned(),
        Some(Selection {
            start: Position::new(0, 2),
            end: Position::new(0, 3),
            direction: SelectionDirection::Forward,
        })
    );
}

#[test]
fn type_char_skips_over_existing_closing_delimiter_without_creating_undo_step() {
    let mut executor = CommandExecutor::new("()", 80);
    executor
        .execute(Command::View(ViewCommand::SetAutoPairsEnabled {
            enabled: true,
        }))
        .unwrap();
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1,
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::TypeChar { ch: ')' }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "()");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 2));
    assert!(
        !executor.can_undo(),
        "expected skip-over to be a no-op edit"
    );
    assert!(
        executor.take_last_text_delta().is_none(),
        "expected no text delta for skip-over"
    );
}

#[test]
fn backspace_deletes_pair_when_between_matching_delimiters() {
    let mut executor = CommandExecutor::new("()", 80);
    executor
        .execute(Command::View(ViewCommand::SetAutoPairsEnabled {
            enabled: true,
        }))
        .unwrap();
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1,
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::Backspace))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 0));
    assert!(executor.can_undo(), "expected pair deletion to be undoable");
}

#[test]
fn delete_forward_deletes_pair_when_between_matching_delimiters() {
    let mut executor = CommandExecutor::new("()", 80);
    executor
        .execute(Command::View(ViewCommand::SetAutoPairsEnabled {
            enabled: true,
        }))
        .unwrap();
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1,
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::DeleteForward))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "");
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 0));
}

#[test]
fn move_to_matching_bracket_jumps_to_pair() {
    let mut executor = CommandExecutor::new("(a[b]c)", 80);
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1,
        }))
        .unwrap();

    executor
        .execute(Command::Cursor(CursorCommand::MoveToMatchingBracket))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 6));

    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 7,
        }))
        .unwrap();
    executor
        .execute(Command::Cursor(CursorCommand::MoveToMatchingBracket))
        .unwrap();
    assert_eq!(executor.editor().cursor_position(), Position::new(0, 0));
}

#[test]
fn move_to_matching_bracket_handles_nested_mixed_brackets_in_fixture() {
    let text = include_str!("fixtures/bracket_matching.txt");
    let line = text.lines().next().expect("fixture should have 1+ line");
    let open_col = line.find('(').expect("fixture should include '('");
    let close_col = line.find(')').expect("fixture should include ')'");

    let mut executor = CommandExecutor::new(text, 120);
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: open_col + 1,
        }))
        .unwrap();
    executor
        .execute(Command::Cursor(CursorCommand::MoveToMatchingBracket))
        .unwrap();

    assert_eq!(
        executor.editor().cursor_position(),
        Position::new(0, close_col)
    );
}

#[test]
fn bracket_match_highlights_update_and_clear_style_layer() {
    let mut executor = CommandExecutor::new("(a)", 80);
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 1,
        }))
        .unwrap();

    executor
        .execute(Command::Style(StyleCommand::UpdateBracketMatchHighlights))
        .unwrap();

    let tree = executor
        .editor()
        .style_layer(StyleLayerId::BRACKET_MATCHES)
        .expect("expected BRACKET_MATCHES style layer");
    assert_eq!(tree.len(), 2);
    assert!(
        tree.query_point(0)
            .iter()
            .any(|i| i.style_id == MATCH_HIGHLIGHT_STYLE_ID),
        "expected match highlight at opening bracket"
    );
    assert!(
        tree.query_point(2)
            .iter()
            .any(|i| i.style_id == MATCH_HIGHLIGHT_STYLE_ID),
        "expected match highlight at closing bracket"
    );

    executor
        .execute(Command::Style(StyleCommand::ClearBracketMatchHighlights))
        .unwrap();
    assert!(
        !executor
            .editor()
            .style_layers()
            .contains_key(&StyleLayerId::BRACKET_MATCHES)
    );
}

#[test]
fn auto_pairs_config_can_be_replaced_per_view() {
    let mut executor = CommandExecutor::empty(80);
    executor
        .execute(Command::View(ViewCommand::SetAutoPairsConfig {
            config: AutoPairsConfig {
                enabled: true,
                pairs: vec![],
                wrap_selection: false,
                skip_over_closing: false,
                delete_pair: false,
            },
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::TypeChar { ch: '(' }))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "(");
}
