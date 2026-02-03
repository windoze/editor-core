use editor_core::{
    Command, CommandExecutor, CommandResult, CursorCommand, EditCommand, SearchOptions,
};

fn opts(case_sensitive: bool, whole_word: bool, regex: bool) -> SearchOptions {
    SearchOptions {
        case_sensitive,
        whole_word,
        regex,
    }
}

#[test]
fn test_find_next_and_prev_basic() {
    let mut executor = CommandExecutor::new("Hello hello HELLO", 80);

    // Find next (case-sensitive): should match the lowercase "hello".
    let result = executor
        .execute(Command::Cursor(CursorCommand::FindNext {
            query: "hello".to_string(),
            options: opts(true, false, false),
        }))
        .unwrap();
    let CommandResult::SearchMatch { start, end } = result else {
        panic!("expected CommandResult::SearchMatch");
    };
    assert_eq!((start, end), (6, 11));

    // Find prev from current selection start: should match the leading "Hello" with case-insensitive.
    let result = executor
        .execute(Command::Cursor(CursorCommand::FindPrev {
            query: "hello".to_string(),
            options: opts(false, false, false),
        }))
        .unwrap();
    let CommandResult::SearchMatch { start, end } = result else {
        panic!("expected CommandResult::SearchMatch");
    };
    assert_eq!((start, end), (0, 5));
}

#[test]
fn test_find_whole_word() {
    let mut executor = CommandExecutor::new("foobar foo barfoo foo", 80);

    let result = executor
        .execute(Command::Cursor(CursorCommand::FindNext {
            query: "foo".to_string(),
            options: opts(true, true, false),
        }))
        .unwrap();
    let CommandResult::SearchMatch { start, end } = result else {
        panic!("expected CommandResult::SearchMatch");
    };
    assert_eq!((start, end), (7, 10));

    let result = executor
        .execute(Command::Cursor(CursorCommand::FindNext {
            query: "foo".to_string(),
            options: opts(true, true, false),
        }))
        .unwrap();
    let CommandResult::SearchMatch { start, end } = result else {
        panic!("expected CommandResult::SearchMatch");
    };
    assert_eq!((start, end), (18, 21));
}

#[test]
fn test_replace_current_is_single_undo_step() {
    let mut executor = CommandExecutor::new("foo foo", 80);

    // Select the first "foo".
    executor
        .execute(Command::Cursor(CursorCommand::FindNext {
            query: "foo".to_string(),
            options: opts(true, true, false),
        }))
        .unwrap();

    assert_eq!(executor.undo_depth(), 0);

    executor
        .execute(Command::Edit(EditCommand::ReplaceCurrent {
            query: "foo".to_string(),
            replacement: "bar".to_string(),
            options: opts(true, true, false),
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "bar foo");
    assert_eq!(executor.undo_depth(), 1);

    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(executor.editor().get_text(), "foo foo");

    executor.execute(Command::Edit(EditCommand::Redo)).unwrap();
    assert_eq!(executor.editor().get_text(), "bar foo");
}

#[test]
fn test_replace_all_is_single_undo_step_and_supports_regex_replacement() {
    let mut executor = CommandExecutor::new("foo1 foo2 foo3", 80);

    executor
        .execute(Command::Edit(EditCommand::ReplaceAll {
            query: "foo(\\d)".to_string(),
            replacement: "bar$1".to_string(),
            options: opts(true, false, true),
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "bar1 bar2 bar3");
    assert_eq!(executor.undo_depth(), 1);

    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(executor.editor().get_text(), "foo1 foo2 foo3");

    executor.execute(Command::Edit(EditCommand::Redo)).unwrap();
    assert_eq!(executor.editor().get_text(), "bar1 bar2 bar3");
}
