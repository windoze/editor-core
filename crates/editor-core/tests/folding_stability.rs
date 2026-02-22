use editor_core::{
    Command, CommandExecutor, EditCommand, EditorStateManager, FoldRegion, StyleCommand,
};

#[test]
fn test_user_folds_shift_on_newline_insertion_above() {
    let mut ex = CommandExecutor::new("a\nb\nc\nd\ne", 80);

    ex.execute(Command::Style(StyleCommand::Fold {
        start_line: 1,
        end_line: 3,
    }))
    .unwrap();

    let user = ex.editor().folding_manager.user_regions();
    assert_eq!(user.len(), 1);
    assert_eq!(user[0].start_line, 1);
    assert_eq!(user[0].end_line, 3);

    ex.execute(Command::Edit(EditCommand::Insert {
        offset: 0,
        text: "\n".to_string(),
    }))
    .unwrap();

    let user = ex.editor().folding_manager.user_regions();
    assert_eq!(user.len(), 1);
    assert_eq!(user[0].start_line, 2);
    assert_eq!(user[0].end_line, 4);
}

#[test]
fn test_user_folds_shift_on_newline_insertion_inside_region() {
    let mut ex = CommandExecutor::new("a\nb\nc\nd\ne", 80);

    ex.execute(Command::Style(StyleCommand::Fold {
        start_line: 1,
        end_line: 3,
    }))
    .unwrap();

    // Insert a newline at the start of logical line 2 (inside the folded region).
    let offset = ex.editor().line_index.position_to_char_offset(2, 0);
    ex.execute(Command::Edit(EditCommand::Insert {
        offset,
        text: "\n".to_string(),
    }))
    .unwrap();

    let user = ex.editor().folding_manager.user_regions();
    assert_eq!(user.len(), 1);
    assert_eq!(user[0].start_line, 1);
    assert_eq!(user[0].end_line, 4);
}

#[test]
fn test_user_folds_shift_on_newline_deletion_above() {
    let mut ex = CommandExecutor::new("a\nb\nc\nd\ne", 80);

    ex.execute(Command::Style(StyleCommand::Fold {
        start_line: 1,
        end_line: 3,
    }))
    .unwrap();

    // Delete the newline after line 0, merging line 0 and line 1.
    let newline_offset = ex.editor().line_index.position_to_char_offset(0, 1);
    ex.execute(Command::Edit(EditCommand::Delete {
        start: newline_offset,
        length: 1,
    }))
    .unwrap();

    let user = ex.editor().folding_manager.user_regions();
    assert_eq!(user.len(), 1);
    assert_eq!(user[0].start_line, 0);
    assert_eq!(user[0].end_line, 2);
}

#[test]
fn test_replace_derived_folds_keeps_user_folds() {
    let mut state = EditorStateManager::new("a\nb\nc\nd", 80);

    state
        .execute(Command::Style(StyleCommand::Fold {
            start_line: 2,
            end_line: 3,
        }))
        .unwrap();

    assert_eq!(state.editor().folding_manager.user_regions().len(), 1);
    assert_eq!(state.editor().folding_manager.derived_regions().len(), 0);

    state.replace_folding_regions(vec![FoldRegion::new(0, 1)], false);

    assert_eq!(state.editor().folding_manager.user_regions().len(), 1);
    assert_eq!(state.editor().folding_manager.derived_regions().len(), 1);
    assert_eq!(state.editor().folding_manager.regions().len(), 2);
}
