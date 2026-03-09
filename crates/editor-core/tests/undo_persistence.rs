use editor_core::{
    Command, CommandExecutor, CursorCommand, EditCommand, Position, Selection, SelectionDirection,
};

#[test]
fn test_undo_history_snapshot_restore_roundtrip_preserves_clean_point_and_redo() {
    let mut executor = CommandExecutor::new("one\ntwo\nthree\n", 80);

    // Create an undoable edit with multi-caret state (so selection snapshots are exercised).
    let selections = vec![
        Selection {
            start: Position::new(0, 0),
            end: Position::new(0, 0),
            direction: SelectionDirection::Forward,
        },
        Selection {
            start: Position::new(1, 0),
            end: Position::new(1, 0),
            direction: SelectionDirection::Forward,
        },
        Selection {
            start: Position::new(2, 0),
            end: Position::new(2, 0),
            direction: SelectionDirection::Forward,
        },
    ];
    executor
        .execute(Command::Cursor(CursorCommand::SetSelections {
            selections,
            primary_index: 1,
        }))
        .unwrap();

    executor
        .execute(Command::Edit(EditCommand::InsertText {
            text: "X".to_string(),
        }))
        .unwrap();
    assert_eq!(executor.editor().get_text(), "Xone\nXtwo\nXthree\n");

    // Mark clean after the initial edit.
    executor.mark_clean();
    assert!(executor.is_clean());

    // Add another coalesced insert group, then undo it back to clean.
    executor
        .execute(Command::Edit(EditCommand::InsertText {
            text: "Y".to_string(),
        }))
        .unwrap();
    executor
        .execute(Command::Edit(EditCommand::InsertText {
            text: "Z".to_string(),
        }))
        .unwrap();
    assert!(!executor.is_clean());

    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert!(executor.is_clean());

    // Undo past the clean point so the clean marker is now in the redo area.
    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(executor.editor().get_text(), "one\ntwo\nthree\n");
    assert!(!executor.is_clean());
    assert!(!executor.can_undo());
    assert!(executor.can_redo());

    let snapshot = executor.undo_history_snapshot();
    let current_text = executor.editor().get_text().to_string();

    let mut restored = CommandExecutor::new(&current_text, 80);
    restored.restore_undo_history(snapshot).unwrap();

    assert_eq!(restored.editor().get_text(), executor.editor().get_text());
    assert_eq!(restored.can_undo(), executor.can_undo());
    assert_eq!(restored.can_redo(), executor.can_redo());
    assert_eq!(restored.undo_depth(), executor.undo_depth());
    assert_eq!(restored.redo_depth(), executor.redo_depth());
    assert_eq!(restored.is_clean(), executor.is_clean());

    // Redo should first return to the clean point (X inserted on all lines).
    restored.execute(Command::Edit(EditCommand::Redo)).unwrap();
    assert_eq!(restored.editor().get_text(), "Xone\nXtwo\nXthree\n");
    assert!(restored.is_clean());

    // Redo again re-applies the second insert group (YZ).
    restored.execute(Command::Edit(EditCommand::Redo)).unwrap();
    assert_eq!(restored.editor().get_text(), "XYZone\nXYZtwo\nXYZthree\n");
    assert!(!restored.is_clean());

    // Undo reverts that group and returns to clean again.
    restored.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(restored.editor().get_text(), "Xone\nXtwo\nXthree\n");
    assert!(restored.is_clean());
}

#[cfg(feature = "serde")]
#[test]
fn test_undo_history_snapshot_can_load_json_fixture() {
    use editor_core::UndoHistorySnapshot;

    let json = include_str!("fixtures/undo_history_snapshot_v1.json");
    let snapshot: UndoHistorySnapshot = serde_json::from_str(json).expect("fixture parse");

    let mut executor = CommandExecutor::empty(80);
    executor.restore_undo_history(snapshot).unwrap();

    // The fixture represents an undone insertion of "X" at offset 0.
    assert!(executor.can_redo());
    executor.execute(Command::Edit(EditCommand::Redo)).unwrap();
    assert_eq!(executor.editor().get_text(), "X");
    executor.execute(Command::Edit(EditCommand::Undo)).unwrap();
    assert_eq!(executor.editor().get_text(), "");
}
