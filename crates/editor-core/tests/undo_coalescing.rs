use std::time::Duration;

use editor_core::{
    Command, CommandExecutor, CursorCommand, EditCommand, Position, Selection, SelectionDirection,
};

fn insert_text(executor: &mut CommandExecutor, text: &str) {
    executor
        .execute(Command::Edit(EditCommand::InsertText {
            text: text.to_string(),
        }))
        .unwrap();
}

#[test]
fn adjacent_quick_insert_text_coalesces() {
    let mut executor = CommandExecutor::empty(80);

    insert_text(&mut executor, "a");
    insert_text(&mut executor, "b");
    insert_text(&mut executor, "c");

    assert_eq!(executor.editor().get_text(), "abc");
    assert_eq!(executor.undo_depth(), 3);

    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();

    assert_eq!(executor.editor().get_text(), "");
    assert_eq!(executor.undo_depth(), 0);
}

#[test]
fn zero_coalescing_timeout_breaks_insert_group_without_sleeping() {
    let mut executor = CommandExecutor::empty(80);
    executor.set_undo_coalescing_timeout(Duration::ZERO);

    insert_text(&mut executor, "a");
    insert_text(&mut executor, "b");

    assert_eq!(executor.editor().get_text(), "ab");

    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();

    assert_eq!(executor.editor().get_text(), "a");
    assert_eq!(executor.undo_depth(), 1);
}

#[test]
fn explicit_end_undo_group_breaks_insert_group() {
    let mut executor = CommandExecutor::empty(80);

    insert_text(&mut executor, "a");
    executor
        .execute(Command::Edit(EditCommand::EndUndoGroup))
        .unwrap();
    insert_text(&mut executor, "b");

    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();

    assert_eq!(executor.editor().get_text(), "a");
}

#[test]
fn non_adjacent_inserts_do_not_coalesce() {
    let mut executor = CommandExecutor::empty(80);

    executor
        .execute(Command::Edit(EditCommand::Insert {
            offset: 0,
            text: "a".to_string(),
        }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::Insert {
            offset: 0,
            text: "b".to_string(),
        }))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "ba");

    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();

    assert_eq!(executor.editor().get_text(), "a");
}

#[test]
fn cursor_movement_breaks_insert_group() {
    let mut executor = CommandExecutor::empty(80);

    insert_text(&mut executor, "a");
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 0,
        }))
        .unwrap();
    insert_text(&mut executor, "b");

    assert_eq!(executor.editor().get_text(), "ba");

    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();

    assert_eq!(executor.editor().get_text(), "a");
}

#[test]
fn newline_insertion_breaks_insert_group() {
    let mut executor = CommandExecutor::empty(80);

    insert_text(&mut executor, "a");
    executor
        .execute(Command::Edit(EditCommand::InsertNewline {
            auto_indent: false,
        }))
        .unwrap();
    insert_text(&mut executor, "b");

    assert_eq!(executor.editor().get_text(), "a\nb");

    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();

    assert_eq!(executor.editor().get_text(), "a\n");
}

#[test]
fn explicit_replacement_coalescing_keeps_ime_like_updates_together() {
    let mut executor = CommandExecutor::empty(80);

    insert_text(&mut executor, "a");
    executor
        .execute(Command::Edit(EditCommand::EndUndoGroup))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::ReplaceCoalescingUndo {
            start: 1,
            length: 0,
            text: "n".to_string(),
        }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::ReplaceCoalescingUndo {
            start: 1,
            length: 1,
            text: "ni".to_string(),
        }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::ReplaceCoalescingUndo {
            start: 1,
            length: 2,
            text: "你".to_string(),
        }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::EndUndoGroup))
        .unwrap();

    assert_eq!(executor.editor().get_text(), "a你");

    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();

    assert_eq!(executor.editor().get_text(), "a");
}

#[test]
fn continuous_multi_cursor_inserts_coalesce_as_one_user_sequence() {
    let mut executor = CommandExecutor::new("one\ntwo", 80);
    let selections = vec![
        Selection {
            start: Position::new(0, 0),
            end: Position::new(0, 0),
            direction: SelectionDirection::Forward,
        },
        Selection {
            start: Position::new(1, 0),
            end: Position::new(1, 0),
            direction: SelectionDirection::Forward,
        },
    ];
    executor
        .execute(Command::Cursor(CursorCommand::SetSelections {
            selections,
            primary_index: 0,
        }))
        .unwrap();

    insert_text(&mut executor, "X");
    insert_text(&mut executor, "Y");

    assert_eq!(executor.editor().get_text(), "XYone\nXYtwo");

    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();

    assert_eq!(executor.editor().get_text(), "one\ntwo");
}
