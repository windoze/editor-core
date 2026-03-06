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

#[test]
fn test_process_text_api_supports_incremental_and_full_resync() {
    let initial = "fn main() {\n  let x = 1;\n}\n";

    let config = TreeSitterProcessorConfig::new(LANGUAGE.into(), rust_test_highlights_query())
        .with_folds_query(rust_test_folds_query())
        .with_simple_capture_styles([("comment", 1), ("string", 2), ("type", 3), ("function", 4)]);

    let mut processor = TreeSitterProcessor::new(config).unwrap();

    let edits1 = processor.process_text(1, None, Some(initial)).unwrap();
    assert_eq!(processor.last_update_mode(), TreeSitterUpdateMode::Initial);
    assert!(!edits1.is_empty());

    let insert = "// header\n";
    let delta = editor_core::delta::TextDelta {
        before_char_count: initial.chars().count(),
        after_char_count: initial.chars().count() + insert.chars().count(),
        edits: vec![editor_core::delta::TextDeltaEdit {
            start: 0,
            deleted_text: String::new(),
            inserted_text: insert.to_string(),
        }],
        undo_group_id: None,
    };

    let edits2 = processor.process_text(2, Some(&delta), None).unwrap();
    assert_eq!(processor.last_update_mode(), TreeSitterUpdateMode::Incremental);
    assert!(!edits2.is_empty());

    // Corrupt delta should surface as a mismatch unless the caller provides a full resync text.
    let bad_delta = editor_core::delta::TextDelta {
        before_char_count: delta.after_char_count,
        after_char_count: delta.after_char_count,
        edits: vec![editor_core::delta::TextDeltaEdit {
            start: 0,
            deleted_text: "not-a-match".to_string(),
            inserted_text: String::new(),
        }],
        undo_group_id: None,
    };
    assert!(matches!(
        processor.process_text(3, Some(&bad_delta), None),
        Err(editor_core_treesitter::TreeSitterError::DeltaMismatch)
    ));

    let full = format!("{insert}{initial}");
    let edits3 = processor.process_text(3, Some(&bad_delta), Some(&full)).unwrap();
    assert_eq!(processor.last_update_mode(), TreeSitterUpdateMode::FullReparse);
    assert!(!edits3.is_empty());
}

#[test]
fn test_sync_to_and_compute_edits_supports_debounced_query_and_char_range() {
    let text = "// a\nfn main() {\n  let x = 1;\n}\n// b\n";

    let config = TreeSitterProcessorConfig::new(LANGUAGE.into(), rust_test_highlights_query())
        .with_folds_query(rust_test_folds_query())
        .with_simple_capture_styles([("comment", 10), ("string", 11), ("type", 12), ("function", 13)]);

    let mut processor = TreeSitterProcessor::new(config).unwrap();

    let mode0 = processor.sync_to(1, None, Some(text)).unwrap();
    assert_eq!(mode0, TreeSitterUpdateMode::Initial);
    assert_eq!(processor.last_update_mode(), TreeSitterUpdateMode::Initial);

    // Debounced model: sync first, query later. Use a range-limited query (first line only).
    let end_first_line = text.find('\n').unwrap_or(0) + 1;
    let edits = processor
        .compute_processing_edits(Some((0, end_first_line)))
        .unwrap();
    let style_edits = edits
        .iter()
        .filter_map(|e| match e {
            ProcessingEdit::ReplaceStyleLayer { intervals, .. } => Some(intervals.as_slice()),
            _ => None,
        })
        .collect::<Vec<_>>();
    assert_eq!(style_edits.len(), 1);
    for interval in style_edits[0] {
        assert!(interval.end <= end_first_line);
    }

    // Already processed version 1, so compute again should yield empty edits.
    assert!(processor.compute_processing_edits(None).unwrap().is_empty());

    // Make a tiny edit to bump to version 2 and re-run query within a range.
    let delta = editor_core::delta::TextDelta {
        before_char_count: text.chars().count(),
        after_char_count: text.chars().count() + 1,
        edits: vec![editor_core::delta::TextDeltaEdit {
            start: 0,
            deleted_text: String::new(),
            inserted_text: " ".to_string(),
        }],
        undo_group_id: None,
    };
    let mode1 = processor.sync_to(2, Some(&delta), None).unwrap();
    assert_eq!(mode1, TreeSitterUpdateMode::Incremental);

    let edits2 = processor
        .compute_processing_edits(Some((0, end_first_line + 1)))
        .unwrap();
    let style_edits2 = edits2
        .iter()
        .filter_map(|e| match e {
            ProcessingEdit::ReplaceStyleLayer { intervals, .. } => Some(intervals.as_slice()),
            _ => None,
        })
        .collect::<Vec<_>>();
    assert_eq!(style_edits2.len(), 1);
    for interval in style_edits2[0] {
        assert!(interval.end <= end_first_line + 1);
    }
}
