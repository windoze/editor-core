use editor_core::intervals::IME_MARKED_TEXT_STYLE_ID;
use editor_core::{Command, CursorCommand, Position};
use tauri_editor::EditorBackend;

#[test]
fn ime_composition_is_undoable_as_one_step() {
    let mut backend = EditorBackend::open_text(None, "a", 80).unwrap();
    let view_id = backend.view_id();
    let buffer_id = backend.workspace().buffer_id_for_view(view_id).unwrap();

    backend
        .workspace_mut()
        .execute(
            view_id,
            Command::Cursor(CursorCommand::MoveTo { line: 0, column: 1 }),
        )
        .unwrap();

    backend.composition_start().unwrap();
    backend.composition_update("中".to_string()).unwrap();
    backend.composition_update("中文".to_string()).unwrap();
    backend.composition_end("中文".to_string()).unwrap();

    assert_eq!(backend.workspace().buffer_text(buffer_id).unwrap(), "a中文");

    backend.undo().unwrap();
    assert_eq!(backend.workspace().buffer_text(buffer_id).unwrap(), "a");

    backend.redo().unwrap();
    assert_eq!(backend.workspace().buffer_text(buffer_id).unwrap(), "a中文");
}

#[test]
fn ime_marked_text_style_layer_is_applied_and_cleared() {
    let mut backend = EditorBackend::open_text(None, "", 80).unwrap();

    backend.composition_start().unwrap();
    backend.composition_update("中".to_string()).unwrap();

    let snapshot = backend.viewport_snapshot(0, 8).unwrap();
    let used_style_sets = snapshot
        .lines
        .iter()
        .flat_map(|l| l.runs.iter().map(|r| r.style_set_id() as usize))
        .collect::<std::collections::BTreeSet<_>>();

    let mut has_ime = false;
    for set_id in used_style_sets {
        if snapshot.style_sets[set_id].contains(&(IME_MARKED_TEXT_STYLE_ID as u32)) {
            has_ime = true;
            break;
        }
    }
    assert!(
        has_ime,
        "IME marked style id should appear in viewport snapshot"
    );

    backend.composition_end("中".to_string()).unwrap();
    let snapshot = backend.viewport_snapshot(0, 8).unwrap();
    let used_style_sets = snapshot
        .lines
        .iter()
        .flat_map(|l| l.runs.iter().map(|r| r.style_set_id() as usize))
        .collect::<std::collections::BTreeSet<_>>();

    for set_id in used_style_sets {
        assert!(
            !snapshot.style_sets[set_id].contains(&(IME_MARKED_TEXT_STYLE_ID as u32)),
            "IME marked style id should be cleared after composition_end"
        );
    }
}

#[test]
fn ime_cancel_restores_original_text_and_selection() {
    let mut backend = EditorBackend::open_text(None, "abcd", 80).unwrap();
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

    backend.composition_start().unwrap();
    backend.composition_update("中".to_string()).unwrap();
    backend.composition_end("".to_string()).unwrap();

    assert_eq!(backend.workspace().buffer_text(buffer_id).unwrap(), "abcd");
    assert_eq!(backend.selection_text().unwrap(), "bc");
}
