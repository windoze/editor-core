use editor_core::LineIndex;
use editor_core_sublime::{SublimeScopeMapper, SublimeSyntaxSet, highlight_document};

#[test]
fn test_sublime_branch_and_fail_backtracks_to_next_branch() {
    let yaml = r#"
%YAML 1.2
---
name: Branch/Fail Test
scope: source.branchfail
version: 2

contexts:
  main:
    - match: '^'
      branch_point: choose-ab
      branch:
        - branch-a
        - branch-b

  branch-a:
    - meta_scope: meta.a
    # If we see a 'b', this branch is wrong; backtrack and try branch-b.
    - match: 'b'
      fail: choose-ab
    - match: '.'
      pop: 1

  branch-b:
    - meta_scope: meta.b
    - match: '.'
      pop: 1
"#;

    // Case 1: no fail, stick with the first branch.
    {
        let mut syntax_set = SublimeSyntaxSet::new();
        let syntax = syntax_set
            .load_from_str(yaml)
            .expect("compile branch syntax");
        let line_index = LineIndex::from_text("a\n");
        let mut mapper = SublimeScopeMapper::new();
        let result = highlight_document(syntax, &line_index, Some(&mut syntax_set), &mut mapper)
            .expect("highlight");

        let a_style = mapper.style_id_for_scope("meta.a");
        let b_style = mapper.style_id_for_scope("meta.b");

        assert!(
            result.intervals.iter().any(|i| i.style_id == a_style),
            "expected meta.a intervals for input 'a'"
        );
        assert!(
            result.intervals.iter().all(|i| i.style_id != b_style),
            "did not expect meta.b intervals for input 'a'"
        );
    }

    // Case 2: fail on branch-a, rewind, then highlight using branch-b.
    {
        let mut syntax_set = SublimeSyntaxSet::new();
        let syntax = syntax_set
            .load_from_str(yaml)
            .expect("compile branch syntax");
        let line_index = LineIndex::from_text("b\n");
        let mut mapper = SublimeScopeMapper::new();
        let result = highlight_document(syntax, &line_index, Some(&mut syntax_set), &mut mapper)
            .expect("highlight");

        let a_style = mapper.style_id_for_scope("meta.a");
        let b_style = mapper.style_id_for_scope("meta.b");

        assert!(
            result.intervals.iter().any(|i| i.style_id == b_style),
            "expected meta.b intervals for input 'b'"
        );
        assert!(
            result.intervals.iter().all(|i| i.style_id != a_style),
            "did not expect meta.a intervals after backtracking for input 'b'"
        );
    }
}
