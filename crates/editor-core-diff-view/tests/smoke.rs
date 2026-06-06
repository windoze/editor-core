use editor_core_diff::{DiffLineKind, LineDiffConfig};
use editor_core_diff_view::{
    DiffColumnView, DiffMode, DiffModel, DiffProjection, Gutter, Row, RowSlot, SideDoc,
};

#[test]
fn placeholder_types_are_constructible() {
    let _side = SideDoc::default();
    let _model = DiffModel::default();
    let _projection = DiffProjection::default();
    let _row = Row::default();
    let _slot = RowSlot::Spacer {
        change: DiffLineKind::Context,
        gutter: Gutter::empty(),
        cells: Vec::new(),
    };
    let _mode = DiffMode::Unified;
    let model = DiffModel::from_before_after("a\n", "a\n", LineDiffConfig::default());
    let projection = DiffProjection::build(&model, DiffMode::SideBySide, &[80, 80]);
    let _view = DiffColumnView::new(&model, &projection, 0, 0, 80);
}
