use super::super::drawing::*;
use super::super::style::*;
use super::super::*;

pub(super) fn draw_headless_cell_backgrounds(
    canvas: &skia_safe::Canvas,
    grid: &HeadlessGrid,
    text_origin_x: f32,
    config: RenderConfig,
    theme: &RenderTheme,
    row_start: usize,
    row_end: usize,
) {
    for row_idx in row_start..row_end {
        let line = &grid.lines[row_idx];
        let y_top =
            config.padding_y_px + row_idx as f32 * config.line_height_px - config.scroll_y_px;
        let mut x_cells = line.segment_x_start_cells as u32;
        for cell in &line.cells {
            let (_fg, bg) = resolve_cell_colors(cell.styles.as_slice(), theme);
            if bg != theme.background {
                let x_px = text_origin_x + x_cells as f32 * config.cell_width_px;
                let w_px = cell.width as f32 * config.cell_width_px;
                let rect = Rect::from_xywh(x_px, y_top, w_px, config.line_height_px);
                let mut bg_paint = Paint::default();
                bg_paint.set_anti_alias(false);
                bg_paint.set_color(rgba_to_skia_color(bg));
                canvas.draw_rect(rect, &bg_paint);
            }
            x_cells = x_cells.saturating_add(cell.width as u32);
        }
    }
}
