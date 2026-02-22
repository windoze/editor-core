use editor_core::EditorStateManager;
use editor_core_treesitter::{TreeSitterProcessor, TreeSitterProcessorConfig};
use tree_sitter_rust::LANGUAGE;

fn main() {
    let mut state = EditorStateManager::new(
        r#"
// comment
fn add(a: i32, b: i32) -> i32 {
    let s = "hi";
    a + b
}
"#,
        80,
    );

    let config =
        TreeSitterProcessorConfig::new(LANGUAGE.into(), tree_sitter_rust::HIGHLIGHTS_QUERY)
            .with_default_rust_folds()
            .with_simple_capture_styles([
                ("comment", 1),
                ("string", 2),
                ("type", 3),
                ("function", 4),
            ]);

    let mut processor = TreeSitterProcessor::new(config).expect("init tree-sitter");
    state
        .apply_processor(&mut processor)
        .expect("apply highlights/folds");

    let style_state = state.get_style_state();
    let folding_state = state.get_folding_state();
    println!(
        "style_intervals={} fold_regions={}",
        style_state.style_count,
        folding_state.regions.len()
    );
}
