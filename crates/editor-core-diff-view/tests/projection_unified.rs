use editor_core_diff::{DiffLineKind, LineDiffConfig};
use editor_core_diff_view::{DiffMode, DiffModel, DiffProjection, RowSlot};

fn config(context_lines: usize) -> LineDiffConfig {
    LineDiffConfig {
        context_lines,
        ..LineDiffConfig::default()
    }
}

fn model(before: &str, after: &str) -> DiffModel {
    DiffModel::from_before_after(before, after, config(0))
}

fn line_slots(projection: &DiffProjection) -> Vec<(usize, usize, usize, DiffLineKind)> {
    projection
        .rows()
        .iter()
        .map(|row| {
            assert_eq!(row.slots().len(), 1);
            match &row.slots()[0] {
                RowSlot::Line {
                    side,
                    logical_line,
                    visual_in_logical,
                    change,
                } => (*side, *logical_line, *visual_in_logical, *change),
                RowSlot::Spacer { .. } => panic!("unified projection must not produce spacers"),
            }
        })
        .collect()
}

fn assert_no_spacers(projection: &DiffProjection) {
    assert_eq!(projection.columns(), 1);
    for row in projection.rows() {
        assert_eq!(row.slots().len(), 1);
        assert!(matches!(row.slots()[0], RowSlot::Line { .. }));
    }
}

#[test]
fn unified_projection_has_one_column_and_no_spacers() {
    let model = model("a\nc\n", "a\nb\nc\n");

    let projection = DiffProjection::build(&model, DiffMode::Unified, &[80]);

    assert_no_spacers(&projection);
    assert_eq!(projection.rows().len(), 3);
}

#[test]
fn replace_blocks_expand_removed_rows_before_added_rows() {
    let model = model("a\nold one\nold two\nz\n", "a\nnew\nz\n");

    let projection = DiffProjection::build(&model, DiffMode::Unified, &[80]);

    let changed_rows: Vec<_> = line_slots(&projection)
        .into_iter()
        .filter(|(_, _, _, change)| *change != DiffLineKind::Context)
        .collect();

    assert_eq!(
        changed_rows,
        [
            (0, 1, 0, DiffLineKind::Remove),
            (0, 2, 0, DiffLineKind::Remove),
            (1, 1, 0, DiffLineKind::Add),
        ]
    );
}

#[test]
fn repeated_builds_are_deterministic_and_width_changes_rewrap() {
    let model = model("abcdef", "abcdef");

    let narrow = DiffProjection::build(&model, DiffMode::Unified, &[3]);
    let repeated_narrow = DiffProjection::build(&model, DiffMode::Unified, &[3]);
    let wide = DiffProjection::build(&model, DiffMode::Unified, &[80]);

    assert_eq!(narrow, repeated_narrow);
    assert_eq!(line_slots(&narrow).len(), 2);
    assert_eq!(line_slots(&wide).len(), 1);
}

#[test]
fn cjk_and_emoji_lines_use_snapshot_generator_wrap_segments() {
    let model = model("你👋好", "你👋好");

    let projection = DiffProjection::build(&model, DiffMode::Unified, &[2]);

    assert_eq!(
        line_slots(&projection),
        [
            (1, 0, 0, DiffLineKind::Context),
            (1, 0, 1, DiffLineKind::Context),
            (1, 0, 2, DiffLineKind::Context),
        ]
    );
}
