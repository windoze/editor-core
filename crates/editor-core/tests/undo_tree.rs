use editor_core::{Command, CommandExecutor, EditCommand};

#[test]
fn undo_tree_preserves_alternate_branches_and_allows_branch_selection() {
    let mut executor = CommandExecutor::empty(80);

    // Build a simple linear history: a -> ab
    executor
        .execute(Command::Edit(EditCommand::InsertText { text: "a".into() }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::EndUndoGroup))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::InsertText { text: "b".into() }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::EndUndoGroup))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "ab");

    // Undo back to the branch point: "a"
    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(executor.editor().get_text(), "a");
    assert_eq!(executor.redo_branch_count(), 1);

    // Create a new branch from "a": "ac"
    executor
        .execute(Command::Edit(EditCommand::InsertText { text: "c".into() }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::EndUndoGroup))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "ac");
    assert!(!executor.can_redo());

    // Undo to the branch point again: now there are *two* redo branches ("b" and "c").
    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(executor.editor().get_text(), "a");
    assert_eq!(executor.redo_branch_count(), 2);
    assert!(executor.can_redo());

    // By default, redo follows the branch we just came from ("c").
    executor.execute(Command::Edit(EditCommand::Redo)).unwrap();
    assert_eq!(executor.editor().get_text(), "ac");

    // Undo again, then select the *other* branch ("b") and redo.
    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(executor.editor().get_text(), "a");
    assert_eq!(executor.redo_branch_count(), 2);

    executor.select_redo_branch(0).unwrap();
    executor.execute(Command::Edit(EditCommand::Redo)).unwrap();
    assert_eq!(executor.editor().get_text(), "ab");
}

#[test]
fn redo_depth_follows_selected_branch_in_undo_tree() {
    let mut executor = CommandExecutor::empty(80);

    // a -> ab -> abd
    executor
        .execute(Command::Edit(EditCommand::InsertText { text: "a".into() }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::EndUndoGroup))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::InsertText { text: "b".into() }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::EndUndoGroup))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::InsertText { text: "d".into() }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::EndUndoGroup))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "abd");

    // Undo back to "a" (two steps).
    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(executor.editor().get_text(), "a");

    // New branch from "a": "ac"
    executor
        .execute(Command::Edit(EditCommand::InsertText { text: "c".into() }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::EndUndoGroup))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "ac");

    // Undo to branch point again.
    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(executor.editor().get_text(), "a");

    // There are 2 redo branches:
    // - branch 0: "b" then "d" (redo_depth == 2)
    // - branch 1: "c" (redo_depth == 1)
    assert_eq!(executor.redo_branch_count(), 2);

    executor.select_redo_branch(0).unwrap();
    assert_eq!(executor.redo_depth(), 2);

    executor.select_redo_branch(1).unwrap();
    assert_eq!(executor.redo_depth(), 1);
}

