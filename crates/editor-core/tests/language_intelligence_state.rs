use editor_core::{
    Command, EditCommand, OpenBufferResult, SymbolLocation, Utf16Position, Utf16Range, Workspace,
};

#[test]
fn workspace_marks_intelligence_results_stale_on_buffer_edit() {
    let mut ws = Workspace::new();

    let OpenBufferResult { view_id, .. } = ws
        .open_buffer(Some("file:///a.rs".to_string()), "hello", 80)
        .unwrap();

    let refs_id = ws.intelligence_mut().create_references(
        "References: hello",
        vec![SymbolLocation {
            uri: "file:///a.rs".to_string(),
            range: Utf16Range::new(Utf16Position::new(0, 0), Utf16Position::new(0, 1)),
        }],
    );

    let other_id = ws.intelligence_mut().create_references(
        "References: other",
        vec![SymbolLocation {
            uri: "file:///b.rs".to_string(),
            range: Utf16Range::new(Utf16Position::new(0, 0), Utf16Position::new(0, 1)),
        }],
    );

    assert!(!ws.intelligence().get(refs_id).unwrap().is_stale());
    assert!(!ws.intelligence().get(other_id).unwrap().is_stale());

    ws.execute(
        view_id,
        Command::Edit(EditCommand::InsertText {
            text: "X".to_string(),
        }),
    )
    .unwrap();

    assert!(ws.intelligence().get(refs_id).unwrap().is_stale());
    assert!(!ws.intelligence().get(other_id).unwrap().is_stale());
}
