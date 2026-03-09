use editor_core::{LineIndex, ProcessingEdit, StyleLayerId};
use editor_core_sublime::{SublimeProcessor, SublimeSyntaxSet};

#[test]
fn test_sublime_processor_compute_processing_edits_from_line_index() {
    let yaml = include_str!("fixtures/TOML.sublime-syntax");

    let mut syntax_set = SublimeSyntaxSet::new();
    let syntax = syntax_set.load_from_str(yaml).expect("compile TOML syntax");

    let mut proc = SublimeProcessor::new(syntax, syntax_set);
    proc.set_preserve_collapsed_folds(false);

    let line_index = LineIndex::from_text("a = 1\n");
    let edits = proc
        .compute_processing_edits(&line_index)
        .expect("compute processing edits");

    assert!(
        edits.iter().any(|e| matches!(
            e,
            ProcessingEdit::ReplaceStyleLayer {
                layer: StyleLayerId::SUBLIME_SYNTAX,
                ..
            }
        )),
        "expected sublime style layer replacement"
    );

    assert!(
        edits.iter().any(|e| matches!(
            e,
            ProcessingEdit::ReplaceFoldingRegions {
                preserve_collapsed: false,
                ..
            }
        )),
        "expected fold replacement with preserve_collapsed=false"
    );
}
