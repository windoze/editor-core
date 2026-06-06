use editor_core::{
    CODE_LENS_STYLE_ID, DOCUMENT_HIGHLIGHT_READ_STYLE_ID, DOCUMENT_HIGHLIGHT_TEXT_STYLE_ID,
    DOCUMENT_HIGHLIGHT_WRITE_STYLE_ID, DOCUMENT_LINK_STYLE_ID, FOLD_PLACEHOLDER_STYLE_ID,
    IME_MARKED_TEXT_STYLE_ID, INLAY_HINT_STYLE_ID, MATCH_HIGHLIGHT_STYLE_ID,
};
use editor_core_diff::{DiffLineKind, LineDiffConfig};
use editor_core_diff_view::style::{
    DIFF_ADD_LINE_STYLE_ID, DIFF_REMOVE_LINE_STYLE_ID, DIFF_SPACER_STYLE_ID, apply_diff_line_style,
};
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

fn assert_cells_contain(slot: &RowSlot, style_id: u32) {
    assert!(
        !slot.cells().is_empty(),
        "expected slot to expose styled cells"
    );
    assert!(
        slot.cells()
            .iter()
            .all(|cell| cell.styles.contains(&style_id)),
        "expected all cells to contain style {style_id:#x}"
    );
}

fn assert_cells_omit_diff_styles(slot: &RowSlot) {
    for cell in slot.cells() {
        assert!(!cell.styles.contains(&DIFF_ADD_LINE_STYLE_ID));
        assert!(!cell.styles.contains(&DIFF_REMOVE_LINE_STYLE_ID));
        assert!(!cell.styles.contains(&DIFF_SPACER_STYLE_ID));
    }
}

#[test]
fn changed_lines_and_spacers_carry_diff_semantic_styles() {
    let add_projection = DiffProjection::build(
        &model("context\nkept\n", "context\nadded\nkept\n"),
        DiffMode::SideBySide,
        &[80, 80],
    );
    let context_slot = &add_projection.rows()[0].slots()[0];
    let add_spacer = &add_projection.rows()[1].slots()[0];
    let add_line = &add_projection.rows()[1].slots()[1];

    assert!(matches!(
        add_line,
        RowSlot::Line {
            change: DiffLineKind::Add,
            ..
        }
    ));
    assert!(matches!(
        add_spacer,
        RowSlot::Spacer {
            change: DiffLineKind::Add,
            ..
        }
    ));
    assert_cells_omit_diff_styles(context_slot);
    assert_cells_contain(add_line, DIFF_ADD_LINE_STYLE_ID);
    assert_cells_contain(add_spacer, DIFF_SPACER_STYLE_ID);

    let remove_projection = DiffProjection::build(
        &model("context\nremoved\nkept\n", "context\nkept\n"),
        DiffMode::SideBySide,
        &[80, 80],
    );
    let remove_line = &remove_projection.rows()[1].slots()[0];
    let remove_spacer = &remove_projection.rows()[1].slots()[1];

    assert!(matches!(
        remove_line,
        RowSlot::Line {
            change: DiffLineKind::Remove,
            ..
        }
    ));
    assert!(matches!(
        remove_spacer,
        RowSlot::Spacer {
            change: DiffLineKind::Remove,
            ..
        }
    ));
    assert_cells_contain(remove_line, DIFF_REMOVE_LINE_STYLE_ID);
    assert_cells_contain(remove_spacer, DIFF_SPACER_STYLE_ID);
}

#[test]
fn diff_line_styles_are_stacked_without_replacing_existing_styles() {
    let mut cells = vec![editor_core::Cell::with_styles(
        'x',
        1,
        vec![CODE_LENS_STYLE_ID],
    )];

    apply_diff_line_style(&mut cells, DiffLineKind::Add);
    apply_diff_line_style(&mut cells, DiffLineKind::Add);
    apply_diff_line_style(&mut cells, DiffLineKind::Context);

    assert_eq!(
        cells[0].styles,
        vec![CODE_LENS_STYLE_ID, DIFF_ADD_LINE_STYLE_ID]
    );
}

#[test]
fn diff_style_ids_use_a_distinct_core_style_segment() {
    let existing_style_ids = [
        FOLD_PLACEHOLDER_STYLE_ID,
        DOCUMENT_HIGHLIGHT_TEXT_STYLE_ID,
        DOCUMENT_HIGHLIGHT_READ_STYLE_ID,
        DOCUMENT_HIGHLIGHT_WRITE_STYLE_ID,
        IME_MARKED_TEXT_STYLE_ID,
        INLAY_HINT_STYLE_ID,
        CODE_LENS_STYLE_ID,
        DOCUMENT_LINK_STYLE_ID,
        MATCH_HIGHLIGHT_STYLE_ID,
    ];
    let diff_style_ids = [
        DIFF_ADD_LINE_STYLE_ID,
        DIFF_REMOVE_LINE_STYLE_ID,
        DIFF_SPACER_STYLE_ID,
    ];

    for style_id in diff_style_ids {
        assert_eq!(style_id & 0xff00_0000, 0x0900_0000);
        assert!(!existing_style_ids.contains(&style_id));
    }

    for style_id in existing_style_ids {
        assert_ne!(style_id & 0xff00_0000, 0x0900_0000);
    }
}
