use super::super::drawing::*;
use super::super::*;

pub(super) fn normalized_selection_ranges(
    selection_ranges: &[(usize, usize)],
) -> Vec<(usize, usize)> {
    let mut ranges = Vec::new();
    for (a, b) in selection_ranges {
        if *a == *b {
            continue;
        }
        if *a <= *b {
            ranges.push((*a, *b));
        } else {
            ranges.push((*b, *a));
        }
    }
    ranges
}

pub(super) fn draw_composed_selection_overlay(
    canvas: &skia_safe::Canvas,
    grid: &ComposedGrid,
    text_origin_x: f32,
    config: RenderConfig,
    theme: &RenderTheme,
    row_start: usize,
    row_end: usize,
    sel_ranges: &[(usize, usize)],
) {
    for row_idx in row_start..row_end {
        let line = &grid.lines[row_idx];
        if !matches!(line.kind, ComposedLineKind::Document { .. }) {
            continue;
        }
        let y_top =
            config.padding_y_px + row_idx as f32 * config.line_height_px - config.scroll_y_px;
        let mut x_cells: u32 = 0;
        for cell in &line.cells {
            let selected = match cell.source {
                ComposedCellSource::Document { offset } => {
                    sel_ranges.iter().any(|(s, e)| offset >= *s && offset < *e)
                }
                _ => false,
            };
            if selected {
                let x_px = text_origin_x + x_cells as f32 * config.cell_width_px;
                let w_px = cell.width as f32 * config.cell_width_px;
                let rect = Rect::from_xywh(x_px, y_top, w_px, config.line_height_px);
                let mut sel_paint = Paint::default();
                sel_paint.set_anti_alias(false);
                sel_paint.set_color(rgba_to_skia_color(theme.selection_background));
                canvas.draw_rect(rect, &sel_paint);
            }
            x_cells = x_cells.saturating_add(cell.width as u32);
        }
    }
}
