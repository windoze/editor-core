use editor_core::EditorStateManager;
use editor_core_treesitter::{
    TreeSitterConfig, TreeSitterProcessor, load_processor_config_from_config,
};
use std::collections::BTreeMap;

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
