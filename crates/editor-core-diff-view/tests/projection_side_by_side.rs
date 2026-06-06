use editor_core_diff::{DiffLineKind, LineDiffConfig};
use editor_core_diff_view::{DiffMode, DiffModel, DiffProjection, RowSlot};

#[derive(Debug, PartialEq, Eq)]
enum SlotSummary {
    Line(usize, usize, usize, DiffLineKind),
    Spacer(DiffLineKind),
}

fn config(context_lines: usize) -> LineDiffConfig {
    LineDiffConfig {
        context_lines,
        ..LineDiffConfig::default()
    }
}

fn model(before: &str, after: &str) -> DiffModel {
    DiffModel::from_before_after(before, after, config(0))
}

fn line(
    side: usize,
    logical_line: usize,
    visual_in_logical: usize,
    change: DiffLineKind,
) -> SlotSummary {
    SlotSummary::Line(side, logical_line, visual_in_logical, change)
}

fn spacer(change: DiffLineKind) -> SlotSummary {
    SlotSummary::Spacer(change)
}

fn projected_slots(projection: &DiffProjection) -> Vec<Vec<SlotSummary>> {
    assert_eq!(projection.columns(), 2);
    projection
        .rows()
        .iter()
        .map(|row| {
            assert_eq!(row.slots().len(), 2);
            row.slots()
                .iter()
                .map(|slot| match slot {
                    RowSlot::Line {
                        side,
                        logical_line,
                        visual_in_logical,
                        change,
                    } => line(*side, *logical_line, *visual_in_logical, *change),
                    RowSlot::Spacer { change } => spacer(*change),
                })
                .collect()
        })
        .collect()
}

#[test]
fn add_units_fill_missing_side_with_add_spacers() {
    let model = model("a\nc\n", "a\nb\nc\n");

    let projection = DiffProjection::build(&model, DiffMode::SideBySide, &[80, 80]);

    assert_eq!(
        projected_slots(&projection),
        vec![
            vec![
                line(0, 0, 0, DiffLineKind::Context),
                line(1, 0, 0, DiffLineKind::Context),
            ],
            vec![spacer(DiffLineKind::Add), line(1, 1, 0, DiffLineKind::Add),],
            vec![
                line(0, 1, 0, DiffLineKind::Context),
                line(1, 2, 0, DiffLineKind::Context),
            ],
        ]
    );
}

#[test]
fn remove_units_fill_missing_side_with_remove_spacers() {
    let model = model("a\nb\nc\n", "a\nc\n");

    let projection = DiffProjection::build(&model, DiffMode::SideBySide, &[80, 80]);

    assert_eq!(
        projected_slots(&projection),
        vec![
            vec![
                line(0, 0, 0, DiffLineKind::Context),
                line(1, 0, 0, DiffLineKind::Context),
            ],
            vec![
                line(0, 1, 0, DiffLineKind::Remove),
                spacer(DiffLineKind::Remove),
            ],
            vec![
                line(0, 2, 0, DiffLineKind::Context),
                line(1, 1, 0, DiffLineKind::Context),
            ],
        ]
    );
}

#[test]
fn shorter_side_is_padded_at_unit_end_when_widths_differ() {
    let model = model("abcdef\nxy\n", "abcdef\nxy\n");

    let projection = DiffProjection::build(&model, DiffMode::SideBySide, &[3, 80]);

    assert_eq!(
        projected_slots(&projection),
        vec![
            vec![
                line(0, 0, 0, DiffLineKind::Context),
                line(1, 0, 0, DiffLineKind::Context),
            ],
            vec![
                line(0, 0, 1, DiffLineKind::Context),
                line(1, 1, 0, DiffLineKind::Context),
            ],
            vec![
                line(0, 1, 0, DiffLineKind::Context),
                spacer(DiffLineKind::Context),
            ],
        ]
    );
}

#[test]
fn replace_units_pad_shorter_changed_side_with_column_change_kind() {
    let model = model("a\nabcdef\nz\n", "a\nxy\nz\n");

    let projection = DiffProjection::build(&model, DiffMode::SideBySide, &[3, 80]);

    assert_eq!(
        projected_slots(&projection),
        vec![
            vec![
                line(0, 0, 0, DiffLineKind::Context),
                line(1, 0, 0, DiffLineKind::Context),
            ],
            vec![
                line(0, 1, 0, DiffLineKind::Remove),
                line(1, 1, 0, DiffLineKind::Add),
            ],
            vec![
                line(0, 1, 1, DiffLineKind::Remove),
                spacer(DiffLineKind::Add),
            ],
            vec![
                line(0, 2, 0, DiffLineKind::Context),
                line(1, 2, 0, DiffLineKind::Context),
            ],
        ]
    );
}
