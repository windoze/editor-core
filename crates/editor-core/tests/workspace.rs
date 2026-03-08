use editor_core::{
    Command, CursorCommand, EditCommand, OpenBufferResult, Position, Workspace, WorkspaceError,
};

#[test]
fn test_workspace_open_lookup_active_close() {
    let mut ws = Workspace::new();
    assert!(ws.is_empty());
    assert_eq!(ws.active_view_id(), None);

    let OpenBufferResult {
        buffer_id: buf_a,
        view_id: view_a,
    } = ws
        .open_buffer(Some("file:///a.txt".to_string()), "a", 80)
        .unwrap();
    assert_eq!(ws.len(), 1);
    assert_eq!(ws.view_count(), 1);
    assert_eq!(ws.active_view_id(), Some(view_a));
    assert_eq!(ws.active_buffer_id(), Some(buf_a));
    assert_eq!(ws.buffer_id_for_uri("file:///a.txt"), Some(buf_a));
    assert_eq!(ws.buffer_text(buf_a).unwrap(), "a");

    let OpenBufferResult {
        buffer_id: buf_b,
        view_id: view_b,
    } = ws.open_buffer(None, "b", 80).unwrap();
    assert_eq!(ws.len(), 2);
    assert_eq!(ws.active_view_id(), Some(view_a));

    ws.set_active_view(view_b).unwrap();
    assert_eq!(ws.active_view_id(), Some(view_b));
    assert_eq!(ws.active_buffer_id(), Some(buf_b));
    assert_eq!(ws.buffer_text(buf_b).unwrap(), "b");

    // Closing the last view of a buffer closes the buffer too.
    ws.close_view(view_b).unwrap();
    assert_eq!(ws.len(), 1);
    assert_eq!(ws.active_view_id(), Some(view_a));
    assert_eq!(ws.active_buffer_id(), Some(buf_a));
}

#[test]
fn test_workspace_uri_conflicts_and_updates() {
    let mut ws = Workspace::new();
    let OpenBufferResult {
        buffer_id: buf_a, ..
    } = ws
        .open_buffer(Some("file:///a.txt".to_string()), "a", 80)
        .unwrap();

    let err = ws
        .open_buffer(Some("file:///a.txt".to_string()), "dup", 80)
        .unwrap_err();
    assert_eq!(
        err,
        WorkspaceError::UriAlreadyOpen("file:///a.txt".to_string())
    );

    let OpenBufferResult {
        buffer_id: buf_b, ..
    } = ws
        .open_buffer(Some("file:///b.txt".to_string()), "b", 80)
        .unwrap();
    assert_eq!(ws.buffer_id_for_uri("file:///b.txt"), Some(buf_b));

    ws.set_buffer_uri(buf_b, Some("file:///c.txt".to_string()))
        .unwrap();
    assert_eq!(ws.buffer_id_for_uri("file:///b.txt"), None);
    assert_eq!(ws.buffer_id_for_uri("file:///c.txt"), Some(buf_b));

    let err = ws
        .set_buffer_uri(buf_b, Some("file:///a.txt".to_string()))
        .unwrap_err();
    assert_eq!(
        err,
        WorkspaceError::UriAlreadyOpen("file:///a.txt".to_string())
    );

    // Unset uri clears lookup.
    ws.set_buffer_uri(buf_a, None).unwrap();
    assert_eq!(ws.buffer_id_for_uri("file:///a.txt"), None);
}

#[test]
fn test_workspace_dirty_tracking_and_mark_saved() {
    let mut ws = Workspace::new();
    let OpenBufferResult { view_id, .. } = ws.open_buffer(None, "x", 80).unwrap();

    assert_eq!(ws.is_modified_for_view(view_id).unwrap(), false);

    ws.execute(
        view_id,
        Command::Edit(EditCommand::InsertText {
            text: "A".to_string(),
        }),
    )
    .unwrap();
    assert_eq!(ws.is_modified_for_view(view_id).unwrap(), true);

    // Undoing back to the initial clean point should clear the modified flag.
    ws.execute(view_id, Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(ws.is_modified_for_view(view_id).unwrap(), false);

    // Mark-saved establishes a new clean point.
    ws.execute(
        view_id,
        Command::Edit(EditCommand::InsertText {
            text: "B".to_string(),
        }),
    )
    .unwrap();
    assert_eq!(ws.is_modified_for_view(view_id).unwrap(), true);
    ws.mark_saved_for_view(view_id).unwrap();
    assert_eq!(ws.is_modified_for_view(view_id).unwrap(), false);
}

#[test]
fn test_workspace_cursor_state_for_view_matches_editor_state_manager_semantics() {
    let mut ws = Workspace::new();
    let OpenBufferResult { view_id, .. } = ws.open_buffer(None, "abc\ndef", 80).unwrap();

    // Move to "de|f" (line=1, col=2) => offset = 3 + 1 + 2 = 6.
    ws.execute(
        view_id,
        Command::Cursor(CursorCommand::MoveTo { line: 1, column: 2 }),
    )
    .unwrap();
    let s1 = ws.cursor_state_for_view(view_id).unwrap();
    assert_eq!(s1.position, Position::new(1, 2));
    assert_eq!(s1.offset, 6);
    assert!(s1.selection.is_none());

    // Set a selection without changing the executor's cursor_position; cursor state should use
    // the active selection end as the primary caret.
    ws.execute(
        view_id,
        Command::Cursor(CursorCommand::SetSelection {
            start: Position::new(0, 0),
            end: Position::new(0, 2),
        }),
    )
    .unwrap();
    let s2 = ws.cursor_state_for_view(view_id).unwrap();
    assert_eq!(s2.position, Position::new(0, 2));
    assert_eq!(s2.offset, 2);
    assert!(s2.selection.is_some());
}
