use editor_core::{Command, CursorCommand, EditCommand, EditorStateManager};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    let mut manager = EditorStateManager::new("alpha\nbeta\ngamma\ndelta\n", 80);

    // Toggle a bookmark on the "beta" line.
    manager.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 1,
        column: 0,
    }))?;
    manager.toggle_bookmark_at_cursor_line();
    println!("bookmarks: {:?}", manager.bookmark_lines());

    // Marks: remember a cursor location and jump back to it later.
    manager.set_mark_at_cursor("b".to_string())?;
    manager.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 3,
        column: 0,
    }))?;
    manager.goto_mark("b")?;

    // Jump list: record a location before performing a jump.
    manager.push_jump_location();
    manager.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 2,
        column: 0,
    }))?;
    manager.jump_back()?;

    // Bookmarks/marks/jump-list anchors shift through edits.
    manager.execute(Command::Edit(EditCommand::Insert {
        offset: 0,
        text: "x\n".to_string(),
    }))?;
    println!("bookmarks after insert: {:?}", manager.bookmark_lines());

    Ok(())
}
