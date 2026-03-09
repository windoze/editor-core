use editor_core::{Command, CommandExecutor, EditCommand};

fn main() {
    let mut exec = CommandExecutor::empty(80);

    exec.execute(Command::Edit(EditCommand::InsertText { text: "a".into() }))
        .unwrap();
    exec.execute(Command::Edit(EditCommand::EndUndoGroup))
        .unwrap();
    exec.execute(Command::Edit(EditCommand::InsertText { text: "b".into() }))
        .unwrap();
    exec.execute(Command::Edit(EditCommand::EndUndoGroup))
        .unwrap();

    println!("text = {:?}", exec.editor().get_text());
    println!(
        "undo_depth={}, redo_depth={}",
        exec.undo_depth(),
        exec.redo_depth()
    );

    // Undo back to the branch point ("a").
    exec.execute(Command::Edit(EditCommand::Undo)).unwrap();
    println!("after undo: {:?}", exec.editor().get_text());

    // Create a new branch from the undone state.
    exec.execute(Command::Edit(EditCommand::InsertText { text: "c".into() }))
        .unwrap();
    exec.execute(Command::Edit(EditCommand::EndUndoGroup))
        .unwrap();
    println!("after branching edit: {:?}", exec.editor().get_text());

    // Undo again to the branch point. Now there are 2 redo branches ("b" and "c").
    exec.execute(Command::Edit(EditCommand::Undo)).unwrap();
    println!(
        "branch point: {:?} (redo branches={})",
        exec.editor().get_text(),
        exec.redo_branch_count()
    );

    // Choose branch 0 and redo.
    exec.select_redo_branch(0).unwrap();
    exec.execute(Command::Edit(EditCommand::Redo)).unwrap();
    println!("redo branch 0: {:?}", exec.editor().get_text());
}
