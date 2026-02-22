use editor_core::{OpenBufferResult, Workspace, WorkspaceError};

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
