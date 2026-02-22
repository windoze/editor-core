use editor_core::{Command, CommandExecutor, CommentConfig, CursorCommand, EditCommand};

fn main() {
    let mut executor = CommandExecutor::new("fn main() {\n    println!(\"hi\");\n}\n", 80);

    // Toggle line comments on the current line.
    executor
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 1,
            column: 4,
        }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::ToggleComment {
            config: CommentConfig::line_and_block("//", "/*", "*/"),
        }))
        .unwrap();

    assert_eq!(
        executor.editor().get_text(),
        "fn main() {\n    // println!(\"hi\");\n}\n"
    );
}
