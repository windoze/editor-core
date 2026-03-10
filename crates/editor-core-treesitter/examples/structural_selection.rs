use editor_core::{DocumentProcessor, EditorStateManager};
use editor_core_treesitter::{
    TreeSitterConfig, TreeSitterProcessor, load_processor_config_from_config,
};
use std::collections::BTreeMap;

fn main() {
    let text = include_str!("../tests/fixtures/rust_sample.rs");
    let state = EditorStateManager::new(text, 80);

    let treesitter_root = std::env::var("EDITOR_CORE_TREESITTER_ROOT")
        .map(std::path::PathBuf::from)
        .unwrap_or_else(|_| {
            std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/treesitter")
        });
    let language_dir = treesitter_root.join("rust");
    let cfg = TreeSitterConfig::from_language_dir(&language_dir)
        .expect("missing rust fixtures; set EDITOR_CORE_TREESITTER_ROOT to your treesitter/ dir");

    let mut config = load_processor_config_from_config("rust", &cfg).expect("load rust config");
    config.capture_styles = BTreeMap::from([
        ("comment".to_string(), 1),
        ("string".to_string(), 2),
        ("type".to_string(), 3),
        ("function".to_string(), 4),
    ]);
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
        println!(
            "step {i}: [{}..{}] {}",
            sel.0,
            sel.1,
            snippet.replace('\n', "\\n")
        );
    }
}
