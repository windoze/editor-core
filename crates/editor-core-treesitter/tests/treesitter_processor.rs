use editor_core::intervals::StyleLayerId;
use editor_core::{Command, DocumentProcessor, EditCommand, EditorStateManager, ProcessingEdit};
use editor_core_treesitter::{
    TreeSitterProcessor, TreeSitterProcessorConfig, TreeSitterUpdateMode,
};
use tree_sitter_rust::LANGUAGE;

fn rust_test_highlights_query() -> &'static str {
    r#"
    (line_comment) @comment
    (block_comment) @comment
    (string_literal) @string
    (primitive_type) @type
    (type_identifier) @type
    (identifier) @ident
    (function_item name: (identifier) @function)
    "#
}

fn rust_test_folds_query() -> &'static str {
    r#"
    (function_item) @fold
    (block) @fold
    "#
}

#[test]
fn test_processor_produces_highlights_and_folds_from_fixture() {
    let text = include_str!("fixtures/rust_sample.rs");
    let state = EditorStateManager::new(text, 80);

    let config = TreeSitterProcessorConfig::new(LANGUAGE.into(), rust_test_highlights_query())
        .with_folds_query(rust_test_folds_query())
        .with_simple_capture_styles([
            ("comment", 10),
            ("string", 11),
            ("type", 12),
            ("ident", 13),
            ("function", 14),
        ]);

    let mut processor = TreeSitterProcessor::new(config).unwrap();
    let edits = processor.process(&state).unwrap();
    assert_eq!(processor.last_update_mode(), TreeSitterUpdateMode::Initial);

    let mut saw_style = false;
    let mut saw_folds = false;
    for edit in edits {
        match edit {
            ProcessingEdit::ReplaceStyleLayer { layer, intervals } => {
                assert_eq!(layer, StyleLayerId::TREE_SITTER);
                assert!(!intervals.is_empty());
                saw_style = true;
            }
            ProcessingEdit::ReplaceFoldingRegions { regions, .. } => {
                assert!(!regions.is_empty());
                saw_folds = true;
            }
            _ => {}
        }
    }
    assert!(saw_style);
    assert!(saw_folds);
}

#[test]
fn test_processor_uses_text_delta_incrementally() {
    let text = include_str!("fixtures/rust_sample.rs");
    let mut state = EditorStateManager::new(text, 80);

    let config = TreeSitterProcessorConfig::new(LANGUAGE.into(), rust_test_highlights_query())
        .with_folds_query(rust_test_folds_query())
        .with_simple_capture_styles([("comment", 1), ("string", 2), ("type", 3), ("function", 4)]);

    let mut processor = TreeSitterProcessor::new(config).unwrap();
    state.apply_processor(&mut processor).unwrap();

    // Insert a small change; `EditorStateManager` records a `TextDelta`.
    state
        .execute(Command::Edit(EditCommand::Insert {
            offset: 0,
            text: "// header\n".to_string(),
        }))
        .unwrap();

    let edits = processor.process(&state).unwrap();
    assert_eq!(
        processor.last_update_mode(),
        TreeSitterUpdateMode::Incremental
    );
    assert!(!edits.is_empty());
}
