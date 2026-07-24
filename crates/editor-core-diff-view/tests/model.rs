use editor_core_diff::{DiffLineKind, LineDiffConfig};
use editor_core_diff_view::model::align_before_after;
use editor_core_diff_view::{AlignUnit, DiffModel, SideDoc};

fn config(context_lines: usize) -> LineDiffConfig {
    LineDiffConfig {
        context_lines,
        ..LineDiffConfig::default()
    }
}

fn side_kinds(model: &DiffModel, side: usize) -> Vec<DiffLineKind> {
    let line_count = model.side(side).expect("side exists").line_count();
    (0..line_count)
        .map(|logical_line| model.side_line_kind(side, logical_line))
        .collect()
}

#[test]
fn from_before_after_reuses_alignment_for_core_change_shapes() {
    let cases = [
        ("a\nb\nc\n", "a\nb\nc\n"),
        ("a\nc\n", "a\nb\nc\n"),
        ("a\nb\nc\n", "a\nc\n"),
        ("a\nold one\nold two\nz\n", "a\nnew\nz\n"),
    ];

    for (before, after) in cases {
        let model = DiffModel::from_before_after(before, after, config(0));
        assert_eq!(
            model.alignment(),
            align_before_after(before, after, config(0))
        );
    }
}

#[test]
fn side_line_kind_marks_pure_add_lines_on_after_side() {
    let model = DiffModel::from_before_after("a\nc\n", "a\nb\nc\n", config(0));

    assert_eq!(
        model.alignment(),
        [
            AlignUnit::Context {
                sides: vec![0..1, 0..1]
            },
            AlignUnit::Add {
                side: 1,
                lines: 1..2,
            },
            AlignUnit::Context {
                sides: vec![1..2, 2..3]
            },
        ]
    );
    assert_eq!(
        side_kinds(&model, 0),
        [DiffLineKind::Context, DiffLineKind::Context]
    );
    assert_eq!(
        side_kinds(&model, 1),
        [
            DiffLineKind::Context,
            DiffLineKind::Add,
            DiffLineKind::Context,
        ]
    );
}

#[test]
fn side_line_kind_marks_pure_remove_lines_on_before_side() {
    let model = DiffModel::from_before_after("a\nb\nc\n", "a\nc\n", config(0));

    assert_eq!(
        side_kinds(&model, 0),
        [
            DiffLineKind::Context,
            DiffLineKind::Remove,
            DiffLineKind::Context,
        ]
    );
    assert_eq!(
        side_kinds(&model, 1),
        [DiffLineKind::Context, DiffLineKind::Context]
    );
}

#[test]
fn side_line_kind_marks_replace_as_remove_before_and_add_after() {
    let model = DiffModel::from_before_after("a\nold one\nold two\nz\n", "a\nnew\nz\n", config(0));

    assert_eq!(
        model.alignment(),
        [
            AlignUnit::Context {
                sides: vec![0..1, 0..1]
            },
            AlignUnit::Replace {
                sides: vec![1..3, 1..2]
            },
            AlignUnit::Context {
                sides: vec![3..4, 2..3]
            },
        ]
    );
    assert_eq!(
        side_kinds(&model, 0),
        [
            DiffLineKind::Context,
            DiffLineKind::Remove,
            DiffLineKind::Remove,
            DiffLineKind::Context,
        ]
    );
    assert_eq!(
        side_kinds(&model, 1),
        [
            DiffLineKind::Context,
            DiffLineKind::Add,
            DiffLineKind::Context,
        ]
    );
}

#[test]
fn side_docs_cache_original_text_and_logical_lines() {
    let model = DiffModel::from_before_after("a\nb", "a\nb\n", config(0));

    assert_eq!(model.sides().len(), 2);
    assert_eq!(model.side(0).expect("before side").text(), "a\nb");
    assert_eq!(model.side(1).expect("after side").text(), "a\nb\n");
    assert_eq!(
        model.side(0).expect("before side").logical_lines(),
        ["a", "b"]
    );
    assert_eq!(
        model.side(1).expect("after side").logical_lines(),
        ["a", "b"]
    );
    assert_eq!(
        model.side(0).expect("before side").logical_line(1),
        Some("b")
    );
    assert_eq!(model.side(1).expect("after side").line_count(), 2);
    assert_eq!(
        model.alignment(),
        [
            AlignUnit::Context {
                sides: vec![0..1, 0..1]
            },
            AlignUnit::Replace {
                sides: vec![1..2, 1..2]
            },
        ]
    );
    assert_eq!(
        side_kinds(&model, 0),
        [DiffLineKind::Context, DiffLineKind::Remove]
    );
    assert_eq!(
        side_kinds(&model, 1),
        [DiffLineKind::Context, DiffLineKind::Add]
    );
}

#[test]
fn side_doc_normalizes_crlf_line_endings() {
    // Regression (P1-6): CRLF used to leave a stray `\r` in logical lines while the projection's
    // SnapshotGenerator produced clean cells, so model content and rendered content disagreed.
    let side = SideDoc::from_text("a\r\nb\r\n");
    assert_eq!(side.line_count(), 2);
    assert_eq!(side.logical_line(0), Some("a"));
    assert_eq!(side.logical_line(1), Some("b"));
    assert_eq!(side.text(), "a\nb\n");
}

#[test]
fn side_doc_normalizes_lone_cr_line_endings() {
    // Regression (P1-6): a lone CR made the model see 1 line while SnapshotGenerator (which
    // normalizes CR to LF) saw 2, so the extra line's content was silently dropped in projection.
    let side = SideDoc::from_text("a\rb\n");
    assert_eq!(side.line_count(), 2);
    assert_eq!(side.logical_line(0), Some("a"));
    assert_eq!(side.logical_line(1), Some("b"));
    assert_eq!(side.text(), "a\nb\n");
}

#[test]
fn empty_side_doc_has_no_logical_lines() {
    let side = SideDoc::from_text("");
    let model = DiffModel::from_before_after("", "", config(0));

    assert_eq!(side.text(), "");
    assert!(side.logical_lines().is_empty());
    assert_eq!(side.logical_line(0), None);
    assert_eq!(model.side(0).expect("before side").line_count(), 0);
    assert_eq!(model.side(1).expect("after side").line_count(), 0);
    assert!(model.alignment().is_empty());
}
