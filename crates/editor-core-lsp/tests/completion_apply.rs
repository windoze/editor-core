use editor_core::{Command, CursorCommand, EditCommand, EditorStateManager, Position};
use editor_core_lsp::{CompletionTextEditMode, apply_completion_item};
use serde_json::json;

#[test]
fn test_apply_completion_item_groups_edits_into_single_undo_step() {
    let original = "fn main() {\n    fo\n}\n";
    let mut state = EditorStateManager::new(original, 80);

    // Put the caret on the completion site (not strictly required when the item has `textEdit`).
    state
        .execute(Command::Cursor(CursorCommand::MoveTo {
            line: 1,
            column: 6,
        }))
        .unwrap();

    let item = json!({
        "label": "println!",
        "insertTextFormat": 2,
        "textEdit": {
            "range": { "start": { "line": 1, "character": 4 }, "end": { "line": 1, "character": 6 } },
            "newText": "println!(${1:msg})$0"
        },
        "additionalTextEdits": [
            {
                "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } },
                "newText": "use std::io;\n"
            }
        ]
    });

    apply_completion_item(&mut state, &item, CompletionTextEditMode::Insert).unwrap();
    assert_eq!(
        state.editor().get_text(),
        "use std::io;\nfn main() {\n    println!(msg)\n}\n"
    );
    assert!(state.has_active_snippet_session());

    let text = state.editor().get_text();
    let expected_start = text.find("msg").expect("msg placeholder inserted");
    let expected_end = expected_start + "msg".len();

    let sel = state.editor().selection().expect("placeholder should be selected");
    let a = state
        .editor()
        .line_index
        .position_to_char_offset(sel.start.line, sel.start.column);
    let b = state
        .editor()
        .line_index
        .position_to_char_offset(sel.end.line, sel.end.column);
    assert_eq!((a.min(b), a.max(b)), (expected_start, expected_end));
    assert!(state.editor().secondary_selections().is_empty());

    // One undo should revert both the main edit and additionalTextEdits.
    state.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(state.editor().get_text(), original);
}

#[test]
fn test_apply_completion_item_falls_back_to_insert_text_over_selection() {
    let mut state = EditorStateManager::new("hello world\n", 80);

    state
        .execute(Command::Cursor(CursorCommand::SetSelection {
            start: Position::new(0, 6),
            end: Position::new(0, 11),
        }))
        .unwrap();

    let item = json!({
        "label": "earth",
        "insertText": "earth"
    });

    apply_completion_item(&mut state, &item, CompletionTextEditMode::Insert).unwrap();
    assert_eq!(state.editor().get_text(), "hello earth\n");
}
