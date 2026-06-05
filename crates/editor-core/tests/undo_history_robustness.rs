use editor_core::{CommandExecutor, UndoHistoryRestoreError, UndoHistorySnapshot};

#[test]
fn restore_snapshot_with_invalid_clean_index_returns_error() {
    let snapshot = UndoHistorySnapshot {
        format_version: 1,
        undo_stack: Vec::new(),
        redo_stack: Vec::new(),
        max_undo: 1000,
        clean_index: Some(1),
        next_group_id: 0,
        open_group_id: None,
    };

    let mut executor = CommandExecutor::empty(80);
    let err = executor
        .restore_undo_history(snapshot)
        .expect_err("invalid clean index should be reported, not panic");

    assert_eq!(
        err,
        UndoHistoryRestoreError::InvalidCleanIndex {
            clean_index: 1,
            max_index: 0,
        }
    );
}
