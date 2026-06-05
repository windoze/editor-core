use editor_core::{Command, CommandExecutor, EditCommand, ViewCommand};

#[test]
fn command_history_keeps_only_recent_entries() {
    let mut executor = CommandExecutor::empty(80);
    executor.set_command_history_limit(3);

    for width in 10..15 {
        executor
            .execute(Command::View(ViewCommand::SetViewportWidth { width }))
            .unwrap();
    }

    let widths: Vec<usize> = executor
        .get_command_history()
        .iter()
        .map(|command| match command {
            Command::View(ViewCommand::SetViewportWidth { width }) => *width,
            other => panic!("unexpected history entry: {other:?}"),
        })
        .collect();

    assert_eq!(widths, vec![12, 13, 14]);
}

#[test]
fn command_history_can_be_disabled() {
    let mut executor = CommandExecutor::empty(80);
    executor.set_command_history_limit(0);

    executor
        .execute(Command::View(ViewCommand::SetViewportWidth { width: 120 }))
        .unwrap();

    assert!(executor.get_command_history().is_empty());
}

#[test]
fn command_history_summarizes_large_insert_text_payloads() {
    let mut executor = CommandExecutor::empty(80);
    let large_text = "x".repeat(10_000);

    executor
        .execute(Command::Edit(EditCommand::InsertText {
            text: large_text.clone(),
        }))
        .unwrap();

    assert_eq!(executor.editor().char_count(), large_text.len());

    let history_text = match &executor.get_command_history()[0] {
        Command::Edit(EditCommand::InsertText { text }) => text,
        other => panic!("unexpected history entry: {other:?}"),
    };

    assert!(history_text.len() < large_text.len());
    assert!(history_text.contains("history truncated"));
}
