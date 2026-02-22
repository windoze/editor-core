use editor_core::{Command, CursorCommand, EditCommand, OpenBufferResult, Workspace};

#[test]
fn test_two_views_share_buffer_but_keep_independent_view_state() {
    let mut ws = Workspace::new();

    let OpenBufferResult {
        buffer_id,
        view_id: view_a,
    } = ws
        .open_buffer(Some("file:///demo.txt".to_string()), "0123456789\n", 10)
        .unwrap();

    let view_b = ws.create_view(buffer_id, 5).unwrap();

    // Independent scrolling state.
    ws.set_scroll_top(view_a, 0).unwrap();
    ws.set_scroll_top(view_b, 2).unwrap();
    assert_eq!(ws.scroll_top_for_view(view_a).unwrap(), 0);
    assert_eq!(ws.scroll_top_for_view(view_b).unwrap(), 2);

    // Independent cursor/selection state.
    ws.execute(
        view_a,
        Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }),
    )
    .unwrap();
    ws.execute(
        view_b,
        Command::Cursor(CursorCommand::MoveTo { line: 0, column: 5 }),
    )
    .unwrap();
    assert_eq!(ws.cursor_position_for_view(view_a).unwrap().column, 1);
    assert_eq!(ws.cursor_position_for_view(view_b).unwrap().column, 5);

    // Different wrap widths should yield different visual line counts.
    let grid_a = ws.get_viewport_content_styled(view_a, 0, 100).unwrap();
    let grid_b = ws.get_viewport_content_styled(view_b, 0, 100).unwrap();
    assert_eq!(grid_a.actual_line_count(), 2); // "0123456789" + trailing empty line
    assert_eq!(grid_b.actual_line_count(), 3); // wrapped into 2 + trailing empty line

    // Edit in view A applies to the shared buffer and broadcasts the same delta to view B.
    ws.execute(
        view_a,
        Command::Edit(EditCommand::InsertText {
            text: "X".to_string(),
        }),
    )
    .unwrap();

    assert_eq!(ws.buffer_text(buffer_id).unwrap(), "0X123456789\n");

    let delta_a = ws.take_last_text_delta_for_view(view_a).unwrap();
    let delta_b = ws.take_last_text_delta_for_view(view_b).unwrap();
    assert_eq!(delta_a.edits, delta_b.edits);

    // View B caret should shift by the inserted length.
    assert_eq!(ws.cursor_position_for_view(view_b).unwrap().column, 6);
}
