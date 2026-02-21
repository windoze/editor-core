use editor_core::{Command, EditCommand, EditorStateManager, LineEnding};

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
