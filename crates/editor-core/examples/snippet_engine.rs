use editor_core::{Command, CommandExecutor, CursorCommand, EditCommand};

fn main() {
    let mut exec = CommandExecutor::empty(80);

    exec.execute(Command::Edit(EditCommand::ApplySnippet {
        start: 0,
        end: 0,
        snippet: "fn ${1:name}(${2:args}) {\n    $0\n}\n".to_string(),
        additional_edits: Vec::new(),
    }))
    .unwrap();

    println!("=== After snippet insert ===");
    println!("{}", exec.editor().get_text());

    // Fill tabstop 1 ("name").
    exec.execute(Command::Edit(EditCommand::InsertText {
        text: "main".to_string(),
    }))
    .unwrap();

    // Jump to tabstop 2 ("args").
    exec.execute(Command::Cursor(CursorCommand::SnippetNextPlaceholder))
        .unwrap();
    exec.execute(Command::Edit(EditCommand::InsertText {
        text: "&str".to_string(),
    }))
    .unwrap();

    // Jump to `$0` (final caret) and finish the snippet session.
    exec.execute(Command::Cursor(CursorCommand::SnippetNextPlaceholder))
        .unwrap();

    println!("=== After filling placeholders ===");
    println!("{}", exec.editor().get_text());
}
