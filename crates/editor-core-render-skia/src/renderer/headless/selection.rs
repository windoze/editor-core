use super::super::drawing::*;
use super::super::*;

pub(super) fn draw_headless_selection_overlays(
    canvas: &skia_safe::Canvas,
    grid: &HeadlessGrid,
    selections: &[VisualSelection],
    text_origin_x: f32,
    config: RenderConfig,
    theme: &RenderTheme,
    row_range: Option<(usize, usize)>,
) {
    for sel in selections
        .iter()
        .filter(|sel| selection_intersects_row_range(sel, row_range))
    {
        draw_selection(
            canvas,
            grid,
            *sel,
            text_origin_x,
            config,
            theme.selection_background,
        );
    }
}

pub(super) fn selection_intersects_row_range(
    selection: &VisualSelection,
    row_range: Option<(usize, usize)>,
) -> bool {
    let Some((row_start, row_end)) = row_range else {
        return true;
    };
    let min_row = selection.start_row.min(selection.end_row) as usize;
    let max_row = selection.start_row.max(selection.end_row) as usize;
    min_row < row_end && max_row >= row_start
}
