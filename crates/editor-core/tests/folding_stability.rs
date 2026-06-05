use editor_core::{
    Command, CommandExecutor, EditCommand, EditorStateManager, FoldRegion, ProcessingEdit,
    StyleCommand, Workspace,
};

fn collapsed_region(start_line: usize, end_line: usize) -> FoldRegion {
    let mut region = FoldRegion::new(start_line, end_line);
    region.collapse();
    region
}

fn collapsed_region_with_placeholder(
    start_line: usize,
    end_line: usize,
    placeholder: &str,
) -> FoldRegion {
    let mut region = FoldRegion::with_placeholder(start_line, end_line, placeholder.to_string());
    region.collapse();
    region
}

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

#[test]
fn test_replace_derived_folds_preserves_collapsed_after_line_drift() {
    let mut state = EditorStateManager::new("a\nb\nc\nd\ne\nf", 80);

    state.replace_folding_regions(
        vec![
            collapsed_region_with_placeholder(1, 3, "[...]"),
            collapsed_region_with_placeholder(4, 5, "use ..."),
        ],
        false,
    );

    state.replace_folding_regions(
        vec![
            FoldRegion::with_placeholder(2, 4, "[...]".to_string()),
            FoldRegion::with_placeholder(4, 5, "use ...".to_string()),
        ],
        true,
    );

    let derived = state.editor().folding_manager.derived_regions();
    assert_eq!(derived.len(), 2);
    assert!(
        derived
            .iter()
            .any(|region| region.start_line == 2 && region.end_line == 4 && region.is_collapsed)
    );
    assert!(
        derived
            .iter()
            .any(|region| region.start_line == 4 && region.end_line == 5 && region.is_collapsed)
    );
}

#[test]
fn test_replace_derived_folds_does_not_preserve_boundary_only_default_placeholder_match() {
    let mut state = EditorStateManager::new("a\nb\nc\nd\ne\nf\ng\nh\ni", 80);

    state.replace_folding_regions(vec![collapsed_region(1, 2), collapsed_region(5, 6)], false);

    state.replace_folding_regions(vec![FoldRegion::new(2, 3), FoldRegion::new(7, 8)], true);

    let derived = state.editor().folding_manager.derived_regions();
    assert_eq!(derived.len(), 2);
    assert!(derived.iter().all(|region| !region.is_collapsed));
}

#[test]
fn test_replace_derived_folds_does_not_copy_user_collapsed_state() {
    let mut state = EditorStateManager::new("a\nb\nc\nd", 80);

    state
        .execute(Command::Style(StyleCommand::Fold {
            start_line: 1,
            end_line: 3,
        }))
        .unwrap();

    state.replace_folding_regions(vec![FoldRegion::new(1, 3)], true);

    let user = state.editor().folding_manager.user_regions();
    assert_eq!(user.len(), 1);
    assert!(user[0].is_collapsed);

    let derived = state.editor().folding_manager.derived_regions();
    assert_eq!(derived.len(), 1);
    assert!(!derived[0].is_collapsed);

    let merged = state.editor().folding_manager.regions();
    assert_eq!(merged.len(), 1);
    assert!(merged[0].is_collapsed);
}

#[test]
fn test_multiple_derived_folds_shift_on_insert_and_delete() {
    let mut state = EditorStateManager::new("a\nb\nc\nd\ne\nf", 80);

    state.replace_folding_regions(vec![collapsed_region(1, 2), collapsed_region(4, 5)], false);

    state
        .execute(Command::Edit(EditCommand::Insert {
            offset: 0,
            text: "\n".to_string(),
        }))
        .unwrap();

    let derived = state.editor().folding_manager.derived_regions();
    assert_eq!(derived[0].start_line, 2);
    assert_eq!(derived[0].end_line, 3);
    assert!(derived[0].is_collapsed);
    assert_eq!(derived[1].start_line, 5);
    assert_eq!(derived[1].end_line, 6);
    assert!(derived[1].is_collapsed);

    state
        .execute(Command::Edit(EditCommand::Delete {
            start: 0,
            length: 1,
        }))
        .unwrap();

    let derived = state.editor().folding_manager.derived_regions();
    assert_eq!(derived[0].start_line, 1);
    assert_eq!(derived[0].end_line, 2);
    assert!(derived[0].is_collapsed);
    assert_eq!(derived[1].start_line, 4);
    assert_eq!(derived[1].end_line, 5);
    assert!(derived[1].is_collapsed);
}

#[test]
fn test_state_folding_replace_and_clear_rebuild_visual_row_cache() {
    let mut state = EditorStateManager::new("a\nb\nc\nd\ne", 80);

    assert_eq!(state.total_visual_lines(), 5);

    state.replace_folding_regions(vec![collapsed_region(1, 3)], false);
    assert_eq!(state.total_visual_lines(), 3);
    assert_eq!(state.visual_to_logical_line(2), (4, 0));

    state.clear_folding_regions();
    assert_eq!(state.total_visual_lines(), 5);
    assert_eq!(state.visual_to_logical_line(2), (2, 0));
}

#[test]
fn test_workspace_folding_replace_and_clear_rebuild_visual_row_cache() {
    let mut workspace = Workspace::new();
    let opened = workspace.open_buffer(None, "a\nb\nc\nd\ne", 80).unwrap();

    assert_eq!(
        workspace
            .total_visual_lines_for_view(opened.view_id)
            .unwrap(),
        5
    );

    workspace
        .apply_processing_edits(
            opened.buffer_id,
            [ProcessingEdit::ReplaceFoldingRegions {
                regions: vec![collapsed_region(1, 3)],
                preserve_collapsed: false,
            }],
        )
        .unwrap();
    assert_eq!(
        workspace
            .total_visual_lines_for_view(opened.view_id)
            .unwrap(),
        3
    );
    assert_eq!(
        workspace
            .visual_to_logical_for_view(opened.view_id, 2)
            .unwrap(),
        (4, 0)
    );

    workspace
        .apply_processing_edits(opened.buffer_id, [ProcessingEdit::ClearFoldingRegions])
        .unwrap();
    assert_eq!(
        workspace
            .total_visual_lines_for_view(opened.view_id)
            .unwrap(),
        5
    );
    assert_eq!(
        workspace
            .visual_to_logical_for_view(opened.view_id, 2)
            .unwrap(),
        (2, 0)
    );
}
