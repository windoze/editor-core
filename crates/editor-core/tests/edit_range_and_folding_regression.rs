//! Regression tests for range-validation overflow and folding-state underflow fixes.

use editor_core::{
    Command, CommandError, CommandExecutor, EditCommand, EditorStateManager, FoldRegion,
};

/// `Delete` with a huge `length` must be rejected via checked arithmetic, not overflow-wrap past
/// the range check (which in release builds would silently bypass validation).
#[test]
fn delete_with_overflowing_length_is_rejected() {
    let mut executor = CommandExecutor::new("hello", 80);
    let before = executor.editor().get_text();

    let err = executor
        .execute(Command::Edit(EditCommand::Delete {
            start: 0,
            length: usize::MAX,
        }))
        .unwrap_err();

    assert!(
        matches!(err, CommandError::InvalidRange { start: 0, .. }),
        "expected InvalidRange, got {err:?}"
    );
    assert_eq!(executor.editor().get_text(), before, "text must be unchanged");
}

/// Same guard for `Replace`.
#[test]
fn replace_with_overflowing_length_is_rejected() {
    let mut executor = CommandExecutor::new("hello", 80);
    let before = executor.editor().get_text();

    let err = executor
        .execute(Command::Edit(EditCommand::Replace {
            start: 1,
            length: usize::MAX,
            text: "X".to_string(),
        }))
        .unwrap_err();

    assert!(
        matches!(err, CommandError::InvalidRange { start: 1, .. }),
        "expected InvalidRange, got {err:?}"
    );
    assert_eq!(executor.editor().get_text(), before, "text must be unchanged");
}

/// Nested collapsed folds must not double-count hidden lines, which previously underflowed
/// `line_count - collapsed_line_count` (debug panic / release wrap).
#[test]
fn folding_state_handles_nested_collapsed_regions() {
    let text = "l0\nl1\nl2\nl3\nl4\nl5\n"; // 7 logical lines (trailing newline)
    let mut manager = EditorStateManager::new(text, 80);

    let mut outer = FoldRegion::new(0, 5);
    outer.collapse();
    let mut inner = FoldRegion::new(2, 4);
    inner.collapse();

    manager.replace_folding_regions(vec![outer, inner], false);

    // Must not panic; union of hidden lines must not exceed the document line count.
    let state = manager.get_folding_state();
    let line_count = manager.get_document_state().line_count;
    assert!(
        state.collapsed_line_count <= line_count,
        "collapsed_line_count {} must not exceed line_count {}",
        state.collapsed_line_count,
        line_count
    );
    assert_eq!(
        state.visible_logical_lines + state.collapsed_line_count,
        line_count,
        "visible + collapsed must equal total"
    );
}
