use editor_core::IndentStyle;
use editor_core_treesitter::{TreeSitterIndenter, TreeSitterIndenterConfig, TreeSitterLanguage};
use std::path::PathBuf;

fn rust_fixture_dir() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures/treesitter/rust")
}

#[test]
fn indenter_computes_indent_inside_block_and_outdents_on_closing_brace() {
    let dir = rust_fixture_dir();
    let wasm_bytes = std::fs::read(dir.join("language.wasm")).expect("read language.wasm");
    let query = std::fs::read_to_string(dir.join("indents.scm")).expect("read indents.scm");

    let mut indenter = TreeSitterIndenter::new(TreeSitterIndenterConfig::new(
        TreeSitterLanguage::wasm("rust".to_string(), wasm_bytes),
        query,
    ))
    .expect("create indenter");

    let text = "fn main() {\nlet x = 1;\n}\n";
    indenter.sync_to_text(1, text).expect("sync");

    assert_eq!(
        indenter
            .indent_string_for_line(1, IndentStyle::Spaces(4))
            .expect("indent for line 1"),
        "    "
    );

    // Closing brace should be outdented back to column 0.
    assert_eq!(
        indenter
            .indent_string_for_line(2, IndentStyle::Spaces(4))
            .expect("indent for line 2"),
        ""
    );
}

#[test]
fn indenter_handles_empty_line_inside_block() {
    let dir = rust_fixture_dir();
    let wasm_bytes = std::fs::read(dir.join("language.wasm")).expect("read language.wasm");
    let query = std::fs::read_to_string(dir.join("indents.scm")).expect("read indents.scm");

    let mut indenter = TreeSitterIndenter::new(TreeSitterIndenterConfig::new(
        TreeSitterLanguage::wasm("rust".to_string(), wasm_bytes),
        query,
    ))
    .expect("create indenter");

    let text = "fn main() {\n\n}\n";
    indenter.sync_to_text(1, text).expect("sync");

    // The empty line between `{` and `}` should still be indented.
    assert_eq!(
        indenter
            .indent_string_for_line(1, IndentStyle::Spaces(4))
            .expect("indent for empty line"),
        "    "
    );
}

#[test]
fn indenter_produces_reindent_text_edit_for_line() {
    let dir = rust_fixture_dir();
    let wasm_bytes = std::fs::read(dir.join("language.wasm")).expect("read language.wasm");
    let query = std::fs::read_to_string(dir.join("indents.scm")).expect("read indents.scm");

    let mut indenter = TreeSitterIndenter::new(TreeSitterIndenterConfig::new(
        TreeSitterLanguage::wasm("rust".to_string(), wasm_bytes),
        query,
    ))
    .expect("create indenter");

    let text = "fn main() {\nlet x = 1;\n}\n";
    indenter.sync_to_text(1, text).expect("sync");

    let edit = indenter
        .reindent_text_edit_for_line(1, IndentStyle::Spaces(4))
        .expect("needs reindent");
    assert_eq!(edit.text, "    ");
    assert_eq!(edit.start, edit.end);
}
