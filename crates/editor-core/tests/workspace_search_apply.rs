use editor_core::{Command, EditCommand, SearchOptions, TextEditSpec, Workspace};

#[test]
fn test_workspace_search_all_open_documents() {
    let mut ws = Workspace::new();
    let a = ws
        .open_document(Some("file:///a.txt".to_string()), "foo bar\nbaz", 80)
        .unwrap();
    let b = ws
        .open_document(Some("file:///b.txt".to_string()), "xx foo yy", 80)
        .unwrap();

    let results = ws
        .search_all_open_documents("foo", SearchOptions::default())
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
    let a = ws.open_document(None, "foo bar", 80).unwrap();
    let b = ws.open_document(None, "bar foo", 80).unwrap();

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

    assert_eq!(ws.document(a).unwrap().editor().get_text(), "foo baz");
    assert_eq!(ws.document(b).unwrap().editor().get_text(), "baz foo");

    // One undo per document should revert the batch.
    ws.document_mut(a)
        .unwrap()
        .execute(Command::Edit(EditCommand::Undo))
        .unwrap();
    ws.document_mut(b)
        .unwrap()
        .execute(Command::Edit(EditCommand::Undo))
        .unwrap();

    assert_eq!(ws.document(a).unwrap().editor().get_text(), "foo bar");
    assert_eq!(ws.document(b).unwrap().editor().get_text(), "bar foo");
}
