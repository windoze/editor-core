use editor_core::{Command, CursorCommand, EditCommand, EditorStateManager, Workspace};

fn read_fixture(rel: &str) -> String {
    std::fs::read_to_string(format!("tests/fixtures/{rel}")).expect("read fixture")
}

#[test]
fn workspace_bookmarks_shift_under_edits() {
    let text = read_fixture("navigation_sample.txt");
    let mut ws = Workspace::new();
    let opened = ws.open_buffer(None, &text, 80).unwrap();
    let view = opened.view_id;

    ws.execute(
        view,
        Command::Cursor(CursorCommand::MoveTo { line: 1, column: 0 }),
    )
    .unwrap();
    assert!(ws.toggle_bookmark_at_cursor_line(view).unwrap());
    assert_eq!(ws.bookmark_lines(opened.buffer_id).unwrap(), vec![1]);

    // Insert a new line at the top; existing bookmarks should shift down.
    ws.execute(
        view,
        Command::Edit(EditCommand::Insert {
            offset: 0,
            text: "x\n".to_string(),
        }),
    )
    .unwrap();
    assert_eq!(ws.bookmark_lines(opened.buffer_id).unwrap(), vec![2]);
}

#[test]
fn workspace_marks_shift_under_edits() {
    let text = read_fixture("navigation_sample.txt");
    let mut ws = Workspace::new();
    let opened = ws.open_buffer(None, &text, 80).unwrap();
    let view = opened.view_id;

    ws.execute(
        view,
        Command::Cursor(CursorCommand::MoveTo { line: 2, column: 0 }),
    )
    .unwrap();
    ws.set_mark_at_cursor(view, "m".to_string()).unwrap();

    ws.execute(
        view,
        Command::Edit(EditCommand::Insert {
            offset: 0,
            text: "x\n".to_string(),
        }),
    )
    .unwrap();

    let pos = ws.goto_mark(view, "m").unwrap().expect("mark exists");
    assert_eq!(pos.line, 3);
    assert_eq!(pos.column, 0);
}

#[test]
fn workspace_jump_list_back_forward_and_shifts() {
    let text = read_fixture("navigation_sample.txt");
    let mut ws = Workspace::new();
    let opened = ws.open_buffer(None, &text, 80).unwrap();
    let view = opened.view_id;

    // Record a jump location on beta (line 1).
    ws.execute(
        view,
        Command::Cursor(CursorCommand::MoveTo { line: 1, column: 0 }),
    )
    .unwrap();
    ws.push_jump_location(view).unwrap();

    // Insert a line at the very top (cursor-based), so the saved jump location shifts.
    ws.execute(
        view,
        Command::Cursor(CursorCommand::MoveTo { line: 0, column: 0 }),
    )
    .unwrap();
    ws.execute(view, Command::Edit(EditCommand::InsertText { text: "x\n".to_string() }))
        .unwrap();

    // Move to delta (which is now line 4) and jump back to the shifted beta.
    ws.execute(
        view,
        Command::Cursor(CursorCommand::MoveTo { line: 4, column: 0 }),
    )
    .unwrap();

    let back = ws.jump_back(view).unwrap().expect("has back");
    assert_eq!(back.buffer_id, opened.buffer_id);
    assert_eq!(back.position.line, 2); // beta moved from line 1 -> 2

    // Now insert another line at top; the forward entry should shift too.
    ws.execute(
        view,
        Command::Cursor(CursorCommand::MoveTo { line: 0, column: 0 }),
    )
    .unwrap();
    ws.execute(view, Command::Edit(EditCommand::InsertText { text: "y\n".to_string() }))
        .unwrap();

    let forward = ws.jump_forward(view).unwrap().expect("has forward");
    assert_eq!(forward.buffer_id, opened.buffer_id);
    assert_eq!(forward.position.line, 5); // delta moved from line 4 -> 5
}

#[test]
fn state_manager_bookmarks_and_jump_list_smoke() {
    let text = read_fixture("navigation_sample.txt");
    let mut manager = EditorStateManager::new(&text, 80);

    manager
        .execute(Command::Cursor(CursorCommand::MoveTo { line: 1, column: 0 }))
        .unwrap();
    assert!(manager.toggle_bookmark_at_cursor_line());
    assert_eq!(manager.bookmark_lines(), vec![1]);

    manager.push_jump_location();
    manager
        .execute(Command::Cursor(CursorCommand::MoveTo { line: 3, column: 0 }))
        .unwrap();
    let back = manager.jump_back().unwrap().expect("has back");
    assert_eq!(back.line, 1);
}
