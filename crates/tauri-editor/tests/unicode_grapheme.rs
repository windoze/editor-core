use tauri_editor::{EditorBackend, EditorKey, KeyModifiers};

#[test]
fn zwj_emoji_grapheme_can_be_navigated_as_one_unit() {
    // 👩‍❤️‍💋‍👩 is a ZWJ-based emoji sequence (multi-codepoint grapheme cluster).
    // Regression: inserting it should not cause subsequent editing/navigation to get "stuck".
    let emoji = "👩‍❤️‍💋‍👩";

    let mut backend = EditorBackend::open_text(None, "", 80).unwrap();
    let view_id = backend.view_id();
    let buffer_id = backend.workspace().buffer_id_for_view(view_id).unwrap();

    backend.insert_text(emoji.to_string()).unwrap();
    assert_eq!(backend.workspace().buffer_text(buffer_id).unwrap(), emoji);

    backend
        .handle_key_down(EditorKey::ArrowLeft, KeyModifiers::default())
        .unwrap();
    assert_eq!(
        backend.workspace().cursor_position_for_view(view_id).unwrap().column,
        0
    );

    backend
        .handle_key_down(EditorKey::ArrowRight, KeyModifiers::default())
        .unwrap();
    assert!(
        backend.workspace().cursor_position_for_view(view_id).unwrap().column > 0,
        "cursor should move to after the emoji cluster"
    );
}

#[test]
fn zwj_emoji_grapheme_is_deleted_as_a_unit() {
    let emoji = "👩‍❤️‍💋‍👩";

    let mut backend = EditorBackend::open_text(None, &format!("a{emoji}b"), 80).unwrap();
    let view_id = backend.view_id();
    let buffer_id = backend.workspace().buffer_id_for_view(view_id).unwrap();

    // Backspace should delete the whole grapheme cluster.
    let after_emoji_col = 1 + emoji.chars().count();
    backend
        .workspace_mut()
        .execute(
            view_id,
            editor_core::Command::Cursor(editor_core::CursorCommand::MoveTo {
                line: 0,
                column: after_emoji_col,
            }),
        )
        .unwrap();

    backend.backspace().unwrap();
    assert_eq!(backend.workspace().buffer_text(buffer_id).unwrap(), "ab");
    backend.undo().unwrap();
    assert_eq!(backend.workspace().buffer_text(buffer_id).unwrap(), format!("a{emoji}b"));

    // DeleteForward should also delete the whole grapheme cluster.
    backend
        .workspace_mut()
        .execute(
            view_id,
            editor_core::Command::Cursor(editor_core::CursorCommand::MoveTo { line: 0, column: 1 }),
        )
        .unwrap();
    backend.delete_forward().unwrap();
    assert_eq!(backend.workspace().buffer_text(buffer_id).unwrap(), "ab");
}
