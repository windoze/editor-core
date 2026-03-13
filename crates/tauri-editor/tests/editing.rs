use editor_core::{Command, CursorCommand, Position, TabKeyBehavior};
use tauri_editor::{EditorBackend, EditorKey, KeyModifiers};

#[test]
fn insert_and_delete_text_work() {
    let mut backend = EditorBackend::open_text(None, "", 80).unwrap();
    let view_id = backend.view_id();
    let buffer_id = backend.workspace().buffer_id_for_view(view_id).unwrap();

    backend.insert_text("abc".to_string()).unwrap();
    assert_eq!(backend.workspace().buffer_text(buffer_id).unwrap(), "abc");

    backend.backspace().unwrap();
    assert_eq!(backend.workspace().buffer_text(buffer_id).unwrap(), "ab");

    // DeleteForward at end should be a no-op.
    backend.delete_forward().unwrap();
    assert_eq!(backend.workspace().buffer_text(buffer_id).unwrap(), "ab");

    // DeleteForward at start should delete the first character.
    backend
        .workspace_mut()
        .execute(
            view_id,
            Command::Cursor(CursorCommand::MoveTo { line: 0, column: 0 }),
        )
        .unwrap();
    backend.delete_forward().unwrap();
    assert_eq!(backend.workspace().buffer_text(buffer_id).unwrap(), "b");
}

#[test]
fn newline_and_tab_are_inserted() {
    let mut backend = EditorBackend::open_text(None, "b", 80).unwrap();
    let view_id = backend.view_id();
    let buffer_id = backend.workspace().buffer_id_for_view(view_id).unwrap();

    backend
        .workspace_mut()
        .execute(
            view_id,
            Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }),
        )
        .unwrap();
    backend.insert_newline(true).unwrap();
    backend.insert_text("x".to_string()).unwrap();
    backend.insert_newline(false).unwrap();
    backend.insert_tab().unwrap();
    backend.insert_text("y".to_string()).unwrap();

    let tab_behavior = backend
        .workspace()
        .tab_key_behavior_for_view(view_id)
        .unwrap();
    let tab_width = backend.workspace().tab_width_for_view(view_id).unwrap();
    let tab_prefix = match tab_behavior {
        TabKeyBehavior::Tab => "\t".to_string(),
        TabKeyBehavior::Spaces => " ".repeat(tab_width),
    };

    assert_eq!(
        backend.workspace().buffer_text(buffer_id).unwrap(),
        format!("b\nx\n{tab_prefix}y")
    );
}

#[test]
fn shift_arrow_creates_selection_and_selection_text_matches() {
    let mut backend = EditorBackend::open_text(None, "abc", 80).unwrap();
    let view_id = backend.view_id();

    backend
        .workspace_mut()
        .execute(
            view_id,
            Command::Cursor(CursorCommand::MoveTo { line: 0, column: 3 }),
        )
        .unwrap();

    backend
        .handle_key_down(
            EditorKey::ArrowLeft,
            KeyModifiers {
                shift: true,
                ..KeyModifiers::default()
            },
        )
        .unwrap();

    assert_eq!(backend.selection_text().unwrap(), "c");
}

#[test]
fn hit_test_moves_cursor_by_composed_row_and_cells() {
    let mut backend = EditorBackend::open_text(None, "ab\ncd", 80).unwrap();
    let view_id = backend.view_id();

    backend.move_cursor_to_composed_row(1, 1, false).unwrap();
    assert_eq!(
        backend
            .workspace()
            .cursor_position_for_view(view_id)
            .unwrap(),
        Position::new(1, 1)
    );
}

#[test]
fn cut_selection_deletes_text() {
    let mut backend = EditorBackend::open_text(None, "abc", 80).unwrap();
    let view_id = backend.view_id();
    let buffer_id = backend.workspace().buffer_id_for_view(view_id).unwrap();

    backend
        .workspace_mut()
        .execute(
            view_id,
            Command::Cursor(CursorCommand::SetSelection {
                start: Position::new(0, 1),
                end: Position::new(0, 3),
            }),
        )
        .unwrap();

    let cut = backend.cut_selection_text().unwrap();
    assert_eq!(cut, "bc");
    assert_eq!(backend.workspace().buffer_text(buffer_id).unwrap(), "a");
}

#[test]
fn select_all_selects_entire_document() {
    let mut backend = EditorBackend::open_text(None, "a\nbc", 80).unwrap();

    backend.select_all().unwrap();
    assert_eq!(backend.selection_text().unwrap(), "a\nbc");
}

#[test]
fn mouse_drag_selects_text_from_anchor() {
    let mut backend = EditorBackend::open_text(None, "abc\ndef", 80).unwrap();
    let view_id = backend.view_id();

    backend
        .set_selection_by_composed_points(0, 1, 1, 2)
        .expect("drag selection");

    assert_eq!(backend.selection_text().unwrap(), "bc\nde");
    assert_eq!(
        backend.workspace().cursor_position_for_view(view_id).unwrap(),
        Position::new(1, 2)
    );
}
