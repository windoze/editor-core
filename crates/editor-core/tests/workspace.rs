use editor_core::{Workspace, WorkspaceError};

#[test]
fn test_workspace_open_lookup_active_close() {
    let mut ws = Workspace::new();
    assert!(ws.is_empty());
    assert_eq!(ws.active_document_id(), None);

    let doc_a = ws
        .open_document(Some("file:///a.txt".to_string()), "a", 80)
        .unwrap();
    assert_eq!(ws.len(), 1);
    assert_eq!(ws.active_document_id(), Some(doc_a));
    assert_eq!(ws.document_id_for_uri("file:///a.txt"), Some(doc_a));
    assert_eq!(ws.document(doc_a).unwrap().editor().get_text(), "a");

    let doc_b = ws.open_document(None, "b", 80).unwrap();
    assert_eq!(ws.len(), 2);
    assert_eq!(ws.active_document_id(), Some(doc_a));

    ws.set_active_document(doc_b).unwrap();
    assert_eq!(ws.active_document_id(), Some(doc_b));
    assert_eq!(ws.active_document().unwrap().editor().get_text(), "b");

    ws.close_document(doc_b).unwrap();
    assert_eq!(ws.len(), 1);
    assert_eq!(ws.active_document_id(), Some(doc_a));
}

#[test]
fn test_workspace_uri_conflicts_and_updates() {
    let mut ws = Workspace::new();
    let doc_a = ws
        .open_document(Some("file:///a.txt".to_string()), "a", 80)
        .unwrap();

    let err = ws
        .open_document(Some("file:///a.txt".to_string()), "dup", 80)
        .unwrap_err();
    assert_eq!(
        err,
        WorkspaceError::UriAlreadyOpen("file:///a.txt".to_string())
    );

    let doc_b = ws
        .open_document(Some("file:///b.txt".to_string()), "b", 80)
        .unwrap();
    assert_eq!(ws.document_id_for_uri("file:///b.txt"), Some(doc_b));

    ws.set_document_uri(doc_b, Some("file:///c.txt".to_string()))
        .unwrap();
    assert_eq!(ws.document_id_for_uri("file:///b.txt"), None);
    assert_eq!(ws.document_id_for_uri("file:///c.txt"), Some(doc_b));

    let err = ws
        .set_document_uri(doc_b, Some("file:///a.txt".to_string()))
        .unwrap_err();
    assert_eq!(
        err,
        WorkspaceError::UriAlreadyOpen("file:///a.txt".to_string())
    );

    // Unset uri clears lookup.
    ws.set_document_uri(doc_a, None).unwrap();
    assert_eq!(ws.document_id_for_uri("file:///a.txt"), None);
}
