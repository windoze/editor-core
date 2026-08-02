use super::region::toggle_fold_region;
use super::*;

pub(super) fn toggle_composed_fold_from_gutter_click(
    ui: &mut EditorUi,
    x_px: f32,
    y_px: f32,
) -> Result<bool, UiError> {
    let (_start_composed, _row_count, grid) = ui.composed_viewport_grid();
    let (local_row, _x_cells) = ui.pixel_to_local_row_col(x_px, y_px);
    let Some(line) = grid.lines.get(local_row) else {
        return Ok(false);
    };
    let editor_core::ComposedLineKind::Document { logical_line, .. } = line.kind else {
        return Ok(false);
    };

    let fold_regions = {
        let doc = ui.lock_doc();
        doc.ws
            .folding_regions_for_buffer(ui.buffer_id)
            .unwrap_or_default()
    };
    let Some(region) = fold_regions
        .iter()
        .filter(|r| r.start_line == logical_line)
        .min_by_key(|r| r.end_line)
        .cloned()
    else {
        return Ok(false);
    };

    toggle_fold_region(ui, region.start_line, region.end_line, region.is_collapsed)?;
    Ok(true)
}
