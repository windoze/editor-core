use editor_core::{
    Command, CommandError, CommandResult, CursorCommand, EditCommand, Position, SearchOptions,
    StyleCommand, ViewCommand,
};
use editor_core_diff::{DiffLineKind, LineDiffConfig};
use editor_core_diff_view::{
    DiffColumnRowSource, DiffColumnView, DiffMode, DiffModel, DiffProjection, Gutter,
};

fn config(context_lines: usize) -> LineDiffConfig {
    LineDiffConfig {
        context_lines,
        ..LineDiffConfig::default()
    }
}

fn model(before: &str, after: &str) -> DiffModel {
    DiffModel::from_before_after(before, after, config(0))
}

fn side_by_side_projection(model: &DiffModel, widths: [usize; 2]) -> DiffProjection {
    DiffProjection::build(model, DiffMode::SideBySide, &widths)
}

fn assert_readonly_error(error: CommandError) {
    assert!(matches!(error, CommandError::Other(message) if message.contains("readonly")));
}

#[test]
fn readonly_view_rejects_mutating_commands_and_allows_navigation() {
    let model = model("alpha\nbeta\n", "alpha\nbeta\n");
    let projection = side_by_side_projection(&model, [80, 80]);
    let mut view = DiffColumnView::new(&model, &projection, 0, 0);

    let rejected_commands = [
        Command::Edit(EditCommand::Insert {
            offset: 0,
            text: "x".to_string(),
        }),
        Command::Edit(EditCommand::Delete {
            start: 0,
            length: 1,
        }),
        Command::Edit(EditCommand::Replace {
            start: 0,
            length: 1,
            text: "x".to_string(),
        }),
        Command::Edit(EditCommand::Undo),
        Command::Edit(EditCommand::Redo),
        Command::Style(StyleCommand::Fold {
            start_line: 0,
            end_line: 1,
        }),
    ];

    for command in rejected_commands {
        assert_readonly_error(view.execute(command).unwrap_err());
        assert_eq!(view.editor().get_text(), "alpha\nbeta\n");
    }

    view.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 1,
        column: 2,
    }))
    .unwrap();
    assert_eq!(view.editor().cursor_position(), Position::new(1, 2));

    view.execute(Command::Cursor(CursorCommand::SetSelection {
        start: Position::new(0, 0),
        end: Position::new(0, 5),
    }))
    .unwrap();
    assert!(view.editor().selection().is_some());

    view.execute(Command::View(ViewCommand::ScrollTo { line: 1 }))
        .unwrap();
    let result = view
        .execute(Command::Cursor(CursorCommand::FindNext {
            query: "beta".to_string(),
            options: SearchOptions::default(),
        }))
        .unwrap();
    assert!(matches!(result, CommandResult::SearchMatch { .. }));
}

#[test]
fn side_visual_and_unified_row_mapping_round_trips_with_spacers_and_wraps() {
    let model = model("你👋好\nk\n", "你👋好\nb\nk\n");
    let projection = side_by_side_projection(&model, [2, 2]);

    let before_pairs = [(0, 0), (1, 1), (2, 2), (3, 4)];
    let after_pairs = [(0, 0), (1, 1), (2, 2), (3, 3), (4, 4)];

    for (side_visual_row, unified_row) in before_pairs {
        assert_eq!(
            projection.unified_row_for_side_visual_row(0, side_visual_row),
            Some(unified_row)
        );
        assert_eq!(
            projection.side_visual_row_for_unified_row(0, unified_row),
            Some(side_visual_row)
        );
    }
    for (side_visual_row, unified_row) in after_pairs {
        assert_eq!(
            projection.unified_row_for_side_visual_row(1, side_visual_row),
            Some(unified_row)
        );
        assert_eq!(
            projection.side_visual_row_for_unified_row(1, unified_row),
            Some(side_visual_row)
        );
    }

    assert_eq!(projection.side_visual_row_for_unified_row(0, 3), None);
    assert_eq!(projection.unified_row_for_side_visual_row(0, 4), None);
    assert_eq!(projection.unified_row_for_side_visual_row(1, 5), None);
}

#[test]
fn vertical_navigation_uses_side_coordinates_and_skips_spacer_rows() {
    let model = model("a\nc\n", "a\nb\nc\n");
    let projection = side_by_side_projection(&model, [80, 80]);
    let mut before_view = DiffColumnView::new(&model, &projection, 0, 0);

    assert_eq!(before_view.cursor_side_visual_row(), Some(0));
    assert_eq!(before_view.cursor_unified_row(), Some(0));

    before_view
        .execute(Command::Cursor(CursorCommand::MoveVisualBy {
            delta_rows: 1,
        }))
        .unwrap();

    assert_eq!(before_view.editor().cursor_position(), Position::new(1, 0));
    assert_eq!(before_view.cursor_side_visual_row(), Some(1));
    assert_eq!(before_view.cursor_unified_row(), Some(2));
    assert_eq!(before_view.side_visual_row_for_unified_row(1), None);
}

#[test]
fn view_width_is_derived_from_projection_so_cursor_mapping_stays_consistent() {
    // Regression (P1-5): DiffColumnView used to take an independent viewport_width, which could
    // differ from the width the projection wrapped at, silently desynchronizing
    // cursor_side_visual_row (view's wrapping) from the projection's row axis. Now the view derives
    // its width from the projection, so a long line wraps identically on both sides.

    // Column width 3 wraps the 8-char first line ("abcdefgh") into multiple visual segments; the
    // second line "Z" then lives on a later visual row within its own logical line.
    let before = "abcdefgh\nZ\n";
    let model = model(before, before);
    let projection = side_by_side_projection(&model, [3, 3]);
    let view = DiffColumnView::new(&model, &projection, 0, 0);

    // The view must have adopted the projection's column width (3), not some default.
    assert_eq!(view.editor().viewport_width(), 3);

    // "abcdefgh" (8 cells at width 3) wraps into 3 visual segments (rows 0,1,2); "Z" is visual
    // row 3 on this side. That side-visual-row must round-trip through the projection's axis.
    let side_row = view
        .editor()
        .logical_position_to_visual(1, 0)
        .expect("line 1 is visible")
        .0;
    assert_eq!(
        side_row, 3,
        "second logical line starts at side visual row 3"
    );

    let unified = view
        .unified_row_for_side_visual_row(side_row)
        .expect("side visual row maps onto the unified axis");
    // The same side row must map back to itself (identical wrapping on both sides).
    assert_eq!(
        projection.side_visual_row_for_unified_row(0, unified),
        Some(side_row)
    );
}

#[test]
fn side_by_side_column_views_project_rows_on_the_unified_axis() {
    let model = model("a\nc\n", "a\nb\nc\n");
    let projection = side_by_side_projection(&model, [80, 80]);
    let before_view = DiffColumnView::new(&model, &projection, 0, 0);
    let after_view = DiffColumnView::new(&model, &projection, 1, 1);

    assert_eq!(before_view.row_count(), projection.rows().len());
    assert_eq!(after_view.row_count(), projection.rows().len());

    let before_spacer = before_view.row(1).unwrap();
    assert_eq!(before_spacer.cells, Vec::new());
    assert_eq!(before_spacer.gutter, Gutter::empty());
    assert_eq!(
        before_spacer.source,
        DiffColumnRowSource::Spacer {
            change: DiffLineKind::Add,
        }
    );

    let after_added = after_view.row(1).unwrap();
    assert!(!after_added.cells.is_empty());
    assert_eq!(after_added.gutter.after_line, Some(1));
    assert_eq!(after_added.gutter.marker, Some('+'));
    assert_eq!(
        after_added.source,
        DiffColumnRowSource::Line {
            side: 1,
            logical_line: 1,
            visual_in_logical: 0,
            change: DiffLineKind::Add,
        }
    );
}
