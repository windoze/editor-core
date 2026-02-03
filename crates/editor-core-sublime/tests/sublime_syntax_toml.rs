use editor_core::LineIndex;
use editor_core_sublime::{SublimeScopeMapper, SublimeSyntaxSet, highlight_document};

#[test]
fn test_sublime_syntax_toml_highlight_and_folding() {
    let yaml = include_str!("fixtures/TOML.sublime-syntax");

    let mut syntax_set = SublimeSyntaxSet::new();
    let syntax = syntax_set.load_from_str(yaml).expect("compile TOML syntax");

    let text = r#"title = "TOML Example" # comment
numbers = [
  1,
  2,
  3,
]
multiline = """
hello
world
"""
"#;

    let line_index = LineIndex::from_text(text);
    let mut mapper = SublimeScopeMapper::new();
    let result = highlight_document(syntax, &line_index, Some(&mut syntax_set), &mut mapper)
        .expect("highlight");

    // Smoke-check a handful of scopes known to be present in the official syntax.
    let comment_style = mapper.style_id_for_scope("comment.line.number-sign.toml");
    assert!(
        result.intervals.iter().any(|i| i.style_id == comment_style),
        "expected comment scope intervals"
    );

    let string_style = mapper.style_id_for_scope("string.quoted.double.toml");
    assert!(
        result.intervals.iter().any(|i| i.style_id == string_style),
        "expected basic string scope intervals"
    );

    let number_style = mapper.style_id_for_scope("meta.number.integer.decimal.toml");
    assert!(
        result.intervals.iter().any(|i| i.style_id == number_style),
        "expected integer number scope intervals"
    );

    // Folding is derived from multi-line contexts with `meta_scope` (arrays, multiline strings, etc.).
    assert!(
        result
            .fold_regions
            .iter()
            .any(|r| r.start_line == 1 && r.end_line == 5),
        "expected fold region for multi-line array (lines 1..=5)"
    );

    assert!(
        result
            .fold_regions
            .iter()
            .any(|r| r.start_line == 6 && r.end_line == 9),
        "expected fold region for multi-line basic string (lines 6..=9)"
    );
}
