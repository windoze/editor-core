use super::region::toggle_fold_region;
use super::*;

pub(super) fn toggle_headless_fold_from_gutter_click(
    ui: &mut EditorUi,
    x_px: f32,
    y_px: f32,
) -> Result<bool, UiError> {
    let (row, _x_cells) = ui.pixel_to_visual(x_px, y_px);
    let pos = {
        let mut doc = ui.lock_doc();
        doc.ws
            .visual_position_to_logical_for_view(ui.view_id, row, 0)
            .ok()
            .flatten()
    };
    let Some(pos) = pos else {
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
        .filter(|r| r.start_line == pos.line)
        .min_by_key(|r| r.end_line)
        .cloned()
    else {
        return Ok(false);
    };

    toggle_fold_region(ui, region.start_line, region.end_line, region.is_collapsed)?;
    Ok(true)
}
