use editor_core_diff::DiffLineKind;
use editor_core_diff_view::{
    DiffColumnView, DiffMode, DiffModel, DiffProjection, Row, RowSlot, SideDoc,
};

#[test]
fn placeholder_types_are_constructible() {
    let _side = SideDoc::default();
    let _model = DiffModel::default();
    let _projection = DiffProjection::default();
    let _row = Row::default();
    let _slot = RowSlot::Spacer {
        change: DiffLineKind::Context,
    };
    let _mode = DiffMode::Unified;
    let _view = DiffColumnView;
}
