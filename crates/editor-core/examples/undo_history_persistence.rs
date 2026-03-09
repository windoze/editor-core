use editor_core::{Command, CommandExecutor, EditCommand};

fn main() {
    let mut executor = CommandExecutor::new("hello", 80);
    executor
        .execute(Command::Edit(EditCommand::InsertText {
            text: "!".to_string(),
        }))
        .unwrap();
    executor.mark_clean();

    executor
        .execute(Command::Edit(EditCommand::InsertText {
            text: " world".to_string(),
        }))
        .unwrap();

    let text = executor.editor().get_text().to_string();
    let snapshot = executor.undo_history_snapshot();

    // Optional: serialize the snapshot with `serde` (host decides the storage format).
    #[cfg(feature = "serde")]
    {
        let json = serde_json::to_string_pretty(&snapshot).unwrap();
        let _roundtrip: editor_core::UndoHistorySnapshot = serde_json::from_str(&json).unwrap();
        println!("undo snapshot json bytes={}", json.len());
    }

    let mut restored = CommandExecutor::new(&text, 80);
    restored.restore_undo_history(snapshot).unwrap();

    restored.execute(Command::Edit(EditCommand::Undo)).unwrap();
    println!("after undo: {:?}", restored.editor().get_text());
}
