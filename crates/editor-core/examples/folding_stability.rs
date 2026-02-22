use editor_core::{Command, EditorStateManager, FoldRegion, StyleCommand};

fn main() {
    let mut state = EditorStateManager::new("a\nb\nc\nd\n", 80);

    // User fold (explicit command).
    state
        .execute(Command::Style(StyleCommand::Fold {
            start_line: 1,
            end_line: 3,
        }))
        .unwrap();

    // Derived folds (e.g. from an external processor like LSP/Sublime).
    state.replace_folding_regions(vec![FoldRegion::new(0, 2)], false);

    // Both sources coexist in the merged view.
    assert_eq!(state.editor().folding_manager.user_regions().len(), 1);
    assert_eq!(state.editor().folding_manager.derived_regions().len(), 1);
    assert_eq!(state.editor().folding_manager.regions().len(), 2);
}
