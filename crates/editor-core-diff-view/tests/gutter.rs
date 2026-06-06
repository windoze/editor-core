use editor_core_diff::{DiffLineKind, LineDiffConfig};
use editor_core_diff_view::{DiffMode, DiffModel, DiffProjection, Gutter, RowSlot};

fn config(context_lines: usize) -> LineDiffConfig {
    LineDiffConfig {
        context_lines,
        ..LineDiffConfig::default()
    }
}

fn model(before: &str, after: &str) -> DiffModel {
    DiffModel::from_before_after(before, after, config(0))
}

fn gutter(before_line: Option<usize>, after_line: Option<usize>, marker: Option<char>) -> Gutter {
    Gutter {
        before_line,
        after_line,
        marker,
    }
}

fn slot_gutter(projection: &DiffProjection, row: usize, column: usize) -> Gutter {
    projection.rows()[row].slots()[column].gutter()
}

fn assert_line_slot(
    slot: &RowSlot,
    side: usize,
    logical_line: usize,
    visual_in_logical: usize,
    change: DiffLineKind,
) {
    match slot {
        RowSlot::Line {
            side: actual_side,
            logical_line: actual_line,
            visual_in_logical: actual_visual,
            change: actual_change,
            ..
        } => {
            assert_eq!(*actual_side, side);
            assert_eq!(*actual_line, logical_line);
            assert_eq!(*actual_visual, visual_in_logical);
            assert_eq!(*actual_change, change);
        }
        RowSlot::Spacer { .. } => panic!("expected a line slot"),
    }
}

#[test]
fn add_and_remove_gutters_use_side_line_numbers_and_markers() {
    let add_projection = DiffProjection::build(
        &model("context\nkept\n", "context\nadded\nkept\n"),
        DiffMode::SideBySide,
        &[80, 80],
    );

    assert_eq!(
        slot_gutter(&add_projection, 0, 0),
        gutter(Some(0), None, None)
    );
    assert_eq!(
        slot_gutter(&add_projection, 0, 1),
        gutter(None, Some(0), None)
    );
    assert_eq!(slot_gutter(&add_projection, 1, 0), Gutter::empty());
    assert_eq!(
        slot_gutter(&add_projection, 1, 1),
        gutter(None, Some(1), Some('+'))
    );
    assert_eq!(
        slot_gutter(&add_projection, 2, 0),
        gutter(Some(1), None, None)
    );
    assert_eq!(
        slot_gutter(&add_projection, 2, 1),
        gutter(None, Some(2), None)
    );

    let remove_projection = DiffProjection::build(
        &model("context\nremoved\nkept\n", "context\nkept\n"),
        DiffMode::SideBySide,
        &[80, 80],
    );

    assert_eq!(
        slot_gutter(&remove_projection, 1, 0),
        gutter(Some(1), None, Some('-'))
    );
    assert_eq!(slot_gutter(&remove_projection, 1, 1), Gutter::empty());
}

#[test]
fn unified_context_rows_carry_both_side_line_numbers() {
    let projection = DiffProjection::build(&model("a\nc\n", "a\nb\nc\n"), DiffMode::Unified, &[80]);

    assert_eq!(projection.columns(), 1);
    assert_eq!(
        slot_gutter(&projection, 0, 0),
        gutter(Some(0), Some(0), None)
    );
    assert_eq!(
        slot_gutter(&projection, 1, 0),
        gutter(None, Some(1), Some('+'))
    );
    assert_eq!(
        slot_gutter(&projection, 2, 0),
        gutter(Some(1), Some(2), None)
    );
}

#[test]
fn spacer_slots_never_have_gutter_data() {
    let add_projection =
        DiffProjection::build(&model("a\n", "a\nb\n"), DiffMode::SideBySide, &[80, 80]);
    let remove_projection =
        DiffProjection::build(&model("a\nb\n", "a\n"), DiffMode::SideBySide, &[80, 80]);

    assert!(matches!(
        add_projection.rows()[1].slots()[0],
        RowSlot::Spacer { .. }
    ));
    assert_eq!(slot_gutter(&add_projection, 1, 0), Gutter::empty());
    assert!(matches!(
        remove_projection.rows()[1].slots()[1],
        RowSlot::Spacer { .. }
    ));
    assert_eq!(slot_gutter(&remove_projection, 1, 1), Gutter::empty());
}

#[test]
fn wrapped_continuation_segments_do_not_repeat_gutter_data() {
    let projection = DiffProjection::build(&model("", "abcdef"), DiffMode::SideBySide, &[80, 3]);

    assert_eq!(projection.rows().len(), 2);
    assert_eq!(slot_gutter(&projection, 0, 0), Gutter::empty());
    assert_eq!(slot_gutter(&projection, 1, 0), Gutter::empty());

    assert_line_slot(&projection.rows()[0].slots()[1], 1, 0, 0, DiffLineKind::Add);
    assert_eq!(
        slot_gutter(&projection, 0, 1),
        gutter(None, Some(0), Some('+'))
    );

    assert_line_slot(&projection.rows()[1].slots()[1], 1, 0, 1, DiffLineKind::Add);
    assert_eq!(slot_gutter(&projection, 1, 1), Gutter::empty());
}
