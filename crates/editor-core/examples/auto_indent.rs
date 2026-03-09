use editor_core::{Command, CursorCommand, EditCommand, EditorStateManager};

fn main() {
    let mut state = EditorStateManager::new("fn main() {}", 80);

    // Insert a newline between `{}`.
    state
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 0,
            column: 11,
        }))
        .unwrap();
    state
        .execute(Command::Edit(EditCommand::InsertNewline {
            auto_indent: true,
        }))
        .unwrap();

    println!("{}", state.editor().get_text());
}
