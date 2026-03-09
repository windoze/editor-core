use editor_core::{DocumentProcessor, EditorStateManager};
use editor_core_treesitter::{TreeSitterProcessor, TreeSitterProcessorConfig};
use tree_sitter_rust::LANGUAGE;

fn main() {
    let text = include_str!("../tests/fixtures/rust_sample.rs");
    let state = EditorStateManager::new(text, 80);

    let config = TreeSitterProcessorConfig::new(LANGUAGE.into(), tree_sitter_rust::HIGHLIGHTS_QUERY)
        .with_default_rust_folds()
        .with_simple_capture_styles([("comment", 1), ("string", 2), ("type", 3), ("function", 4)]);
    let mut processor = TreeSitterProcessor::new(config).expect("init tree-sitter");
    let _ = processor.process(&state).expect("parse");

    let caret = text.find("add").unwrap_or(0) + 1;
    let caret_chars = text[..caret].chars().count();

    let mut sel = (caret_chars, caret_chars);
    for i in 0..4 {
        let Some(next) = processor.expand_selection_syntax(sel.0, sel.1) else {
            println!("step {i}: <no further expansion>");
            break;
        };
        sel = next;
        let snippet: String = text
            .chars()
            .skip(sel.0)
            .take(sel.1.saturating_sub(sel.0))
            .collect();
        println!("step {i}: [{}..{}] {}", sel.0, sel.1, snippet.replace('\n', "\\n"));
    }
}
