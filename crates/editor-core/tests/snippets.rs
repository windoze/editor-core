use editor_core::{Command, CommandExecutor, CursorCommand, EditCommand, TextEditSpec};

fn primary_selection_offsets(executor: &CommandExecutor) -> Option<(usize, usize)> {
    let editor = executor.editor();
    let sel = editor.selection()?;
    let a = editor
        .line_index()
        .position_to_char_offset(sel.start.line, sel.start.column);
    let b = editor
        .line_index()
        .position_to_char_offset(sel.end.line, sel.end.column);
    Some((a.min(b), a.max(b)))
}

#[test]
fn apply_snippet_inserts_text_and_selects_first_placeholder() {
    let mut executor = CommandExecutor::empty(80);

    executor
        .execute(Command::Edit(EditCommand::ApplySnippet {
            start: 0,
            end: 0,
            snippet: "println!(${1:msg})$0".to_string(),
            additional_edits: Vec::new(),
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "println!(msg)");
    assert!(executor.has_active_snippet_session());

    let text = executor.editor().get_text();
    let expected_start = text.find("msg").unwrap();
    let expected_end = expected_start + "msg".len();
    assert_eq!(
        primary_selection_offsets(&executor),
        Some((expected_start, expected_end))
    );
    assert!(executor.editor().secondary_selections().is_empty());

    executor
        .execute(Command::Cursor(CursorCommand::SnippetNextPlaceholder))
        .unwrap();
    assert!(!executor.has_active_snippet_session());
    assert!(executor.editor().selection().is_none());
    assert!(executor.editor().secondary_selections().is_empty());

    let caret = executor.editor().cursor_position();
    let caret_off = executor
        .editor()
        .line_index()
        .position_to_char_offset(caret.line, caret.column);
    assert_eq!(caret_off, executor.editor().get_text().chars().count());
}

#[test]
fn snippet_next_prev_placeholder_navigates_and_ranges_shift_under_edits() {
    let mut executor = CommandExecutor::empty(80);

    executor
        .execute(Command::Edit(EditCommand::ApplySnippet {
            start: 0,
            end: 0,
            snippet: "${1:foo} ${2:bar}$0".to_string(),
            additional_edits: Vec::new(),
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "foo bar");
    assert!(executor.has_active_snippet_session());

    // Replace "foo" with "hello".
    executor
        .execute(Command::Edit(EditCommand::InsertText {
            text: "hello".to_string(),
        }))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "hello bar");

    // Jump to tabstop 2 ("bar") and back to tabstop 1 ("hello").
    executor
        .execute(Command::Cursor(CursorCommand::SnippetNextPlaceholder))
        .unwrap();
    let text = executor.editor().get_text();
    let expected_start = text.find("bar").unwrap();
    let expected_end = expected_start + "bar".len();
    assert_eq!(
        primary_selection_offsets(&executor),
        Some((expected_start, expected_end))
    );

    executor
        .execute(Command::Cursor(CursorCommand::SnippetPrevPlaceholder))
        .unwrap();
    let text = executor.editor().get_text();
    let expected_start = text.find("hello").unwrap();
    let expected_end = expected_start + "hello".len();
    assert_eq!(
        primary_selection_offsets(&executor),
        Some((expected_start, expected_end))
    );
}

#[test]
fn mirrored_tabstop_creates_multi_cursor_and_edits_in_lockstep() {
    let mut executor = CommandExecutor::empty(80);

    executor
        .execute(Command::Edit(EditCommand::ApplySnippet {
            start: 0,
            end: 0,
            snippet: "${1:foo} = $1; $0".to_string(),
            additional_edits: Vec::new(),
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "foo = foo; ");
    assert!(executor.has_active_snippet_session());
    assert_eq!(executor.editor().secondary_selections().len(), 1);

    executor
        .execute(Command::Edit(EditCommand::InsertText { text: "x".into() }))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "x = x; ");
}

#[test]
fn apply_snippet_with_additional_text_edits_selects_placeholder_in_final_document() {
    let original = include_str!("fixtures/snippet_completion_site.txt");
    let mut executor = CommandExecutor::new(original, 80);

    let start = original.find("fo").unwrap();
    let end = start + "fo".len();

    executor
        .execute(Command::Edit(EditCommand::ApplySnippet {
            start,
            end,
            snippet: "println!(${1:msg})$0".to_string(),
            additional_edits: vec![TextEditSpec {
                start: 0,
                end: 0,
                text: "use std::io;\n".to_string(),
            }],
        }))
        .unwrap();

    assert_eq!(
        executor.editor().get_text(),
        "use std::io;\nfn main() {\n    println!(msg)\n}\n"
    );

    let text = executor.editor().get_text();
    let expected_start = text.find("msg").unwrap();
    let expected_end = expected_start + "msg".len();
    assert_eq!(
        primary_selection_offsets(&executor),
        Some((expected_start, expected_end))
    );
}

#[test]
fn snippet_choice_placeholder_inserts_first_option_and_selects_it() {
    let mut executor = CommandExecutor::empty(80);
    executor
        .execute(Command::Edit(EditCommand::ApplySnippet {
            start: 0,
            end: 0,
            snippet: "${1|a,b,c|} $0".to_string(),
            additional_edits: Vec::new(),
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "a ");
    assert!(executor.has_active_snippet_session());
    assert_eq!(primary_selection_offsets(&executor), Some((0, 1)));
}

#[test]
fn snippet_variable_default_inserts_default_and_does_not_start_session() {
    let mut executor = CommandExecutor::empty(80);
    executor
        .execute(Command::Edit(EditCommand::ApplySnippet {
            start: 0,
            end: 0,
            snippet: "${TM_FILENAME:main.rs} $0".to_string(),
            additional_edits: Vec::new(),
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "main.rs ");
    assert!(!executor.has_active_snippet_session());
    assert!(executor.editor().selection().is_none());
}
