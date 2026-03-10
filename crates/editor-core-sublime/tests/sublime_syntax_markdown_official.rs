use editor_core::LineIndex;
use editor_core_sublime::{SublimeScopeMapper, SublimeSyntaxSet, highlight_document};

#[test]
fn test_official_markdown_sublime_syntax_loads_and_highlights() {
    // Official Sublime Text Markdown syntax (CommonMark + GFM) is used as a real-world
    // compatibility fixture. Load from *path* to match the FFI host behavior.
    let fixture_path = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures/Markdown.sublime-syntax");
    let mut syntax_set = SublimeSyntaxSet::new();
    let syntax = syntax_set
        .load_from_path(&fixture_path)
        .expect("compile official Markdown.sublime-syntax");

    // Exercise real-world features used by the official Markdown syntax:
    // - `embed/escape`: YAML frontmatter + fenced code blocks
    // - `branch/fail`: setext heading vs paragraph backtracking
    // - context backrefs (`\1`, `\2`, ...): fenced code block termination
    let text = r#"---
title: Demo
---

Heading
=======

Just a paragraph.

```rust
fn main() {}
````

~~~js
console.log("x");
~~~~
"#;

    let line_index = LineIndex::from_text(text);
    let mut mapper = SublimeScopeMapper::new();
    let result = highlight_document(syntax, &line_index, Some(&mut syntax_set), &mut mapper)
        .expect("highlight markdown document");

    // Frontmatter embed scope should be applied (even if the embedded YAML syntax isn't available).
    let frontmatter_style = mapper.style_id_for_scope("source.yaml.embedded.markdown");
    assert!(
        result.intervals.iter().any(|i| i.style_id == frontmatter_style),
        "expected YAML frontmatter embed scope intervals"
    );

    // Setext heading content should be detected via branch/fail backtracking.
    let heading_style = mapper.style_id_for_scope("entity.name.section.markdown");
    assert!(
        result.intervals.iter().any(|i| i.style_id == heading_style),
        "expected setext heading content scope intervals"
    );

    // Fenced code blocks should be terminated via a regex that uses Sublime-style context
    // backrefs inside the fence end pattern. Our engine doesn't emit per-capture scopes, so
    // assert on scopes that we *do* produce:
    // - the injected escape match uses `escape_captures[0]` as its pattern scope
    // - embedded fenced code bodies apply `embed_scope` (e.g. `source.rust`, `source.js`)
    let fence_end_definition_style =
        mapper.style_id_for_scope("meta.code-fence.definition.end.markdown-gfm");
    assert!(
        result
            .intervals
            .iter()
            .any(|i| i.style_id == fence_end_definition_style),
        "expected fenced code fence end definition intervals"
    );

    let rust_style = mapper.style_id_for_scope("source.rust");
    assert!(
        result.intervals.iter().any(|i| i.style_id == rust_style),
        "expected fenced code block embed scope for rust"
    );

}
