use editor_core::{Command, EditCommand, EditorStateManager, LineEnding, Workspace};

#[test]
fn test_crlf_is_normalized_on_load_and_preserved_for_saving() {
    let manager = EditorStateManager::new("a\r\nb\r\n", 80);

    // Internal storage is LF-only.
    assert_eq!(manager.editor().get_text(), "a\nb\n");

    // Preferred line ending is detected from the original input.
    assert_eq!(manager.line_ending(), LineEnding::Crlf);

    // Saving should round-trip to CRLF.
    assert_eq!(manager.get_text_for_saving(), "a\r\nb\r\n");
}

#[test]
fn test_insert_normalizes_crlf_to_lf() {
    let mut manager = EditorStateManager::new("", 80);
    manager
        .execute(Command::Edit(EditCommand::Insert {
            offset: 0,
            text: "a\r\nb".to_string(),
        }))
        .unwrap();

    assert_eq!(manager.editor().get_text(), "a\nb");
    assert_eq!(manager.line_ending(), LineEnding::Lf);
    assert_eq!(manager.get_text_for_saving(), "a\nb");
}

#[test]
fn test_cr_is_normalized_to_lf() {
    // Treat lone `\r` as a line break on load, normalizing to internal LF storage.
    let manager = EditorStateManager::new("a\rb", 80);
    assert_eq!(manager.editor().get_text(), "a\nb");
    assert_eq!(manager.editor().line_index.get_line_text(0).unwrap(), "a");
    assert_eq!(manager.editor().line_index.get_line_text(1).unwrap(), "b");
}

#[test]
fn workspace_crlf_is_normalized_on_load_and_preserved_for_saving() {
    let mut ws = Workspace::new();
    let opened = ws.open_buffer(None, "a\r\nb\r\n", 80).unwrap();

    // Internal storage is LF-only.
    assert_eq!(ws.buffer_text(opened.buffer_id).unwrap(), "a\nb\n");

    // Preferred line ending is detected from the original input.
    assert_eq!(
        ws.line_ending_for_buffer(opened.buffer_id).unwrap(),
        LineEnding::Crlf
    );

    // Saving should round-trip to CRLF.
    assert_eq!(
        ws.buffer_text_for_saving(opened.buffer_id).unwrap(),
        "a\r\nb\r\n"
    );

    // View-based helpers should match.
    assert_eq!(
        ws.line_ending_for_view(opened.view_id).unwrap(),
        LineEnding::Crlf
    );
    assert_eq!(
        ws.text_for_saving_for_view(opened.view_id).unwrap(),
        "a\r\nb\r\n"
    );
}

#[test]
fn workspace_can_override_line_ending_for_saving() {
    let mut ws = Workspace::new();
    let opened = ws.open_buffer(None, "a\nb\n", 80).unwrap();
    assert_eq!(
        ws.line_ending_for_buffer(opened.buffer_id).unwrap(),
        LineEnding::Lf
    );

    ws.set_line_ending_for_buffer(opened.buffer_id, LineEnding::Crlf)
        .unwrap();
    assert_eq!(
        ws.buffer_text_for_saving(opened.buffer_id).unwrap(),
        "a\r\nb\r\n"
    );
}
