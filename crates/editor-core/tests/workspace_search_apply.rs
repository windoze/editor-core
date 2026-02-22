use editor_core::{Command, EditCommand, OpenBufferResult, SearchOptions, TextEditSpec, Workspace};

#[test]
fn test_workspace_search_all_open_documents() {
    let mut ws = Workspace::new();
    let OpenBufferResult { buffer_id: a, .. } = ws
        .open_buffer(Some("file:///a.txt".to_string()), "foo bar\nbaz", 80)
        .unwrap();
    let OpenBufferResult { buffer_id: b, .. } = ws
        .open_buffer(Some("file:///b.txt".to_string()), "xx foo yy", 80)
        .unwrap();

    let results = ws
        .search_all_open_buffers("foo", SearchOptions::default())
        .unwrap();

    assert_eq!(results.len(), 2);
    assert_eq!(results[0].id, a);
    assert_eq!(results[0].matches.len(), 1);
    assert_eq!(results[1].id, b);
    assert_eq!(results[1].matches.len(), 1);
}

#[test]
fn test_workspace_apply_text_edits_groups_undo_per_document() {
    let mut ws = Workspace::new();
    let OpenBufferResult {
        buffer_id: a,
        view_id: a_view,
    } = ws.open_buffer(None, "foo bar", 80).unwrap();
    let OpenBufferResult {
        buffer_id: b,
        view_id: b_view,
    } = ws.open_buffer(None, "bar foo", 80).unwrap();

    ws.apply_text_edits(vec![
        (
            a,
            vec![TextEditSpec {
                start: 4,
                end: 7,
                text: "baz".to_string(),
            }],
        ),
        (
            b,
            vec![TextEditSpec {
                start: 0,
                end: 3,
                text: "baz".to_string(),
            }],
        ),
    ])
    .unwrap();

    assert_eq!(ws.buffer_text(a).unwrap(), "foo baz");
    assert_eq!(ws.buffer_text(b).unwrap(), "baz foo");

    // One undo per buffer should revert the batch.
    ws.execute(a_view, Command::Edit(EditCommand::Undo))
        .unwrap();
    ws.execute(b_view, Command::Edit(EditCommand::Undo))
        .unwrap();

    assert_eq!(ws.buffer_text(a).unwrap(), "foo bar");
    assert_eq!(ws.buffer_text(b).unwrap(), "bar foo");
}
