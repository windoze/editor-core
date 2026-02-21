use editor_core::{Command, CursorCommand, EditCommand, EditorStateManager, Position, Selection};
use std::sync::{Arc, Mutex};

#[test]
fn test_insert_produces_text_delta() {
    let mut manager = EditorStateManager::new("abc", 80);

    let changes: Arc<Mutex<Vec<editor_core::StateChange>>> = Arc::new(Mutex::new(Vec::new()));
    let changes_cb = changes.clone();
    manager.subscribe(move |change| {
        changes_cb.lock().expect("lock").push(change.clone());
    });

    manager
        .execute(Command::Edit(EditCommand::Insert {
            offset: 1,
            text: "X".to_string(),
        }))
        .unwrap();

    let changes = changes.lock().expect("lock");
    assert_eq!(changes.len(), 1);
    let change = &changes[0];
    assert_eq!(
        change.change_type,
        editor_core::StateChangeType::DocumentModified
    );

    let delta = change.text_delta.as_ref().expect("missing delta");
    assert_eq!(delta.before_char_count, 3);
    assert_eq!(delta.after_char_count, 4);
    assert_eq!(delta.undo_group_id, Some(0));
    assert_eq!(delta.edits.len(), 1);
    assert_eq!(delta.edits[0].start, 1);
    assert_eq!(delta.edits[0].deleted_text, "");
    assert_eq!(delta.edits[0].inserted_text, "X");
}

#[test]
fn test_multi_caret_insert_text_delta_ordering() {
    // Offsets in "a\nb\nc":
    // 0 'a'
    // 1 '\n'
    // 2 'b'
    // 3 '\n'
    // 4 'c'
    let mut manager = EditorStateManager::new("a\nb\nc", 80);

    // Carets at start of each logical line.
    let selections = vec![
        Selection {
            start: Position::new(0, 0),
            end: Position::new(0, 0),
            direction: editor_core::SelectionDirection::Forward,
        },
        Selection {
            start: Position::new(1, 0),
            end: Position::new(1, 0),
            direction: editor_core::SelectionDirection::Forward,
        },
        Selection {
            start: Position::new(2, 0),
            end: Position::new(2, 0),
            direction: editor_core::SelectionDirection::Forward,
        },
    ];

    manager
        .execute(Command::Cursor(CursorCommand::SetSelections {
            selections,
            primary_index: 0,
        }))
        .unwrap();

    let changes: Arc<Mutex<Vec<editor_core::StateChange>>> = Arc::new(Mutex::new(Vec::new()));
    let changes_cb = changes.clone();
    manager.subscribe(move |change| {
        changes_cb.lock().expect("lock").push(change.clone());
    });

    manager
        .execute(Command::Edit(EditCommand::InsertText {
            text: "X".to_string(),
        }))
        .unwrap();

    let changes = changes.lock().expect("lock");
    assert_eq!(changes.len(), 1);
    let delta = changes[0].text_delta.as_ref().expect("missing delta");

    assert_eq!(delta.edits.len(), 3);
    // The executor applies multi-caret edits in descending offset order to keep offsets stable,
    // so the delta should be ordered the same way.
    let starts: Vec<usize> = delta.edits.iter().map(|e| e.start).collect();
    assert_eq!(starts, vec![4, 2, 0]);

    for edit in &delta.edits {
        assert_eq!(edit.deleted_text, "");
        assert_eq!(edit.inserted_text, "X");
    }
}

#[test]
fn test_undo_redo_produce_group_delta() {
    let mut manager = EditorStateManager::new("", 80);

    let changes: Arc<Mutex<Vec<editor_core::StateChange>>> = Arc::new(Mutex::new(Vec::new()));
    let changes_cb = changes.clone();
    manager.subscribe(move |change| {
        changes_cb.lock().expect("lock").push(change.clone());
    });

    // Two inserts that should coalesce into the same undo group.
    manager
        .execute(Command::Edit(EditCommand::Insert {
            offset: 0,
            text: "A".to_string(),
        }))
        .unwrap();
    manager
        .execute(Command::Edit(EditCommand::Insert {
            offset: 1,
            text: "B".to_string(),
        }))
        .unwrap();

    // Undo should undo the whole group (both inserts).
    manager.execute(Command::Edit(EditCommand::Undo)).unwrap();

    // Redo should redo the whole group.
    manager.execute(Command::Edit(EditCommand::Redo)).unwrap();

    let changes = changes.lock().expect("lock");
    assert_eq!(changes.len(), 4);

    let insert1 = changes[0].text_delta.as_ref().expect("delta 0");
    let insert2 = changes[1].text_delta.as_ref().expect("delta 1");
    let undo = changes[2].text_delta.as_ref().expect("delta 2");
    let redo = changes[3].text_delta.as_ref().expect("delta 3");

    assert_eq!(insert1.undo_group_id, Some(0));
    assert_eq!(insert2.undo_group_id, Some(0));
    assert_eq!(undo.undo_group_id, Some(0));
    assert_eq!(redo.undo_group_id, Some(0));

    assert_eq!(undo.edits.len(), 2);
    assert_eq!(undo.edits[0].start, 1);
    assert_eq!(undo.edits[0].deleted_text, "B");
    assert_eq!(undo.edits[0].inserted_text, "");
    assert_eq!(undo.edits[1].start, 0);
    assert_eq!(undo.edits[1].deleted_text, "A");
    assert_eq!(undo.edits[1].inserted_text, "");

    assert_eq!(redo.edits.len(), 2);
    assert_eq!(redo.edits[0].start, 0);
    assert_eq!(redo.edits[0].deleted_text, "");
    assert_eq!(redo.edits[0].inserted_text, "A");
    assert_eq!(redo.edits[1].start, 1);
    assert_eq!(redo.edits[1].deleted_text, "");
    assert_eq!(redo.edits[1].inserted_text, "B");
}
