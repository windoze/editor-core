use editor_core::LineIndex;
use editor_core_sublime::{SublimeScopeMapper, SublimeSyntaxSet, highlight_document};

#[test]
fn test_sublime_embed_with_unresolved_scope_falls_back_and_still_escapes() {
    // Minimal embed syntax:
    // - Enter an embedded region on a BEGIN line
    // - Apply `embed_scope` to embedded content
    // - Exit on an END line (escape), then keep matching in the parent context
    let yaml = r#"
%YAML 1.2
---
name: Embed Test
scope: source.embedtest
version: 2

contexts:
  main:
    - match: '^BEGIN$'
      embed: scope:source.fake
      embed_scope: meta.embed
      escape: '^END$'
      escape_captures:
        0: meta.end
    - match: '^after$'
      scope: meta.after
"#;

    let text = "BEGIN\nhello\nEND\nafter\n";
    let line_index = LineIndex::from_text(text);

    let mut syntax_set = SublimeSyntaxSet::new();
    let syntax = syntax_set
        .load_from_str(yaml)
        .expect("compile embed syntax");

    let mut mapper = SublimeScopeMapper::new();
    let result = highlight_document(syntax, &line_index, Some(&mut syntax_set), &mut mapper)
        .expect("highlight");

    let embed_style = mapper.style_id_for_scope("meta.embed");
    let end_style = mapper.style_id_for_scope("meta.end");
    let after_style = mapper.style_id_for_scope("meta.after");

    assert!(
        result.intervals.iter().any(|i| i.style_id == embed_style),
        "expected meta.embed intervals inside embedded content"
    );
    assert!(
        result.intervals.iter().any(|i| i.style_id == end_style),
        "expected meta.end intervals for escape match"
    );
    assert!(
        result.intervals.iter().any(|i| i.style_id == after_style),
        "expected meta.after intervals after escaping the embed"
    );
}
