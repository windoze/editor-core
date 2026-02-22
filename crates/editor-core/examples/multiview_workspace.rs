use editor_core::{Command, CursorCommand, EditCommand, OpenBufferResult, Workspace};

fn main() {
    let mut ws = Workspace::new();

    let OpenBufferResult {
        buffer_id,
        view_id: left,
    } = ws
        .open_buffer(Some("file:///demo.txt".to_string()), "0123456789\n", 10)
        .unwrap();

    // Simulate a split pane: a second view into the same buffer with a different wrap width.
    let right = ws.create_view(buffer_id, 5).unwrap();

    ws.execute(
        left,
        Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }),
    )
    .unwrap();
    ws.execute(
        right,
        Command::Cursor(CursorCommand::MoveTo { line: 0, column: 5 }),
    )
    .unwrap();

    let left_grid = ws.get_viewport_content_styled(left, 0, 100).unwrap();
    let right_grid = ws.get_viewport_content_styled(right, 0, 100).unwrap();
    println!("left view visual lines: {}", left_grid.actual_line_count());
    println!(
        "right view visual lines: {}",
        right_grid.actual_line_count()
    );

    ws.execute(
        left,
        Command::Edit(EditCommand::InsertText {
            text: "X".to_string(),
        }),
    )
    .unwrap();

    println!(
        "buffer text after edit:\n{}",
        ws.buffer_text(buffer_id).unwrap()
    );

    let delta_left = ws.take_last_text_delta_for_view(left).unwrap();
    let delta_right = ws.take_last_text_delta_for_view(right).unwrap();
    println!("left delta edits: {}", delta_left.edits.len());
    println!("right delta edits: {}", delta_right.edits.len());
}
