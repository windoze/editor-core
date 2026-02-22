use editor_core::{Command, CommandExecutor, CursorCommand, EditCommand};

fn main() {
    let mut executor = CommandExecutor::new("a\nb\nc", 80);

    // Duplicate the current line.
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 1,
            column: 0,
        }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::DuplicateLines))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "a\nb\nb\nc");

    // Move the duplicated line back up.
    executor
        .execute(Command::Edit(EditCommand::MoveLinesUp))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "b\na\nb\nc");

    // Join the first two lines ("b" + "a") into one line.
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 0,
        }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::JoinLines))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "b a\nb\nc");
}
