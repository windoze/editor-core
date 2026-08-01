use super::super::*;
use super::rgba_to_skia_color;

pub(in crate::renderer) fn draw_caret(
    canvas: &skia_safe::Canvas,
    grid: &HeadlessGrid,
    caret: VisualCaret,
    text_origin_x: f32,
    config: RenderConfig,
    color: Rgba8,
) {
    let start_row = grid.start_visual_row as i64;
    let local_row = caret.row as i64 - start_row;
    if local_row < 0 {
        return;
    }
    let local_row = local_row as usize;
    if local_row >= grid.lines.len() {
        return;
    }

    let x_px = text_origin_x + caret.x_cells as f32 * config.cell_width_px;
    let y_top = config.padding_y_px + local_row as f32 * config.line_height_px - config.scroll_y_px;

    let caret_width = config.caret_width_px.max(1.0);
    let rect = Rect::from_xywh(x_px, y_top, caret_width, config.line_height_px);

    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(color));
    canvas.draw_rect(rect, &paint);
}

pub(in crate::renderer) fn draw_selection(
    canvas: &skia_safe::Canvas,
    grid: &HeadlessGrid,
    selection: VisualSelection,
    text_origin_x: f32,
    config: RenderConfig,
    color: Rgba8,
) {
    let (mut a_row, mut a_x) = (selection.start_row as i64, selection.start_x_cells as i64);
    let (mut b_row, mut b_x) = (selection.end_row as i64, selection.end_x_cells as i64);
    if (b_row, b_x) < (a_row, a_x) {
        std::mem::swap(&mut a_row, &mut b_row);
        std::mem::swap(&mut a_x, &mut b_x);
    }

    let grid_start = grid.start_visual_row as i64;
    let grid_end = grid_start + grid.lines.len() as i64;

    // Clamp selection to viewport range.
    let sel_start_row = a_row.max(grid_start);
    let sel_end_row = b_row.min(grid_end.saturating_sub(1));
    if sel_end_row < sel_start_row {
        return;
    }

    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(color));

    for row in sel_start_row..=sel_end_row {
        let local_row = (row - grid_start) as usize;
        let line = match grid.lines.get(local_row) {
            Some(l) => l,
            None => continue,
        };

        let line_total_cells: i64 = line.cells.iter().map(|c| c.width as i64).sum::<i64>()
            + line.segment_x_start_cells as i64;

        let start_x = if row == a_row { a_x } else { 0 };
        let end_x = if row == b_row { b_x } else { line_total_cells };

        if end_x <= start_x {
            continue;
        }

        let x_px = text_origin_x + start_x as f32 * config.cell_width_px;
        let w_px = (end_x - start_x) as f32 * config.cell_width_px;
        let y_top =
            config.padding_y_px + local_row as f32 * config.line_height_px - config.scroll_y_px;
        let rect = Rect::from_xywh(x_px, y_top, w_px, config.line_height_px);
        canvas.draw_rect(rect, &paint);
    }
}

pub(in crate::renderer) fn cell_overlaps_selection_for_row(
    row: i64,
    cell_start_x: i64,
    cell_end_x: i64,
    line_total_cells: i64,
    selections: &[VisualSelection],
) -> bool {
    for sel in selections {
        let (mut a_row, mut a_x) = (sel.start_row as i64, sel.start_x_cells as i64);
        let (mut b_row, mut b_x) = (sel.end_row as i64, sel.end_x_cells as i64);
        if (b_row, b_x) < (a_row, a_x) {
            std::mem::swap(&mut a_row, &mut b_row);
            std::mem::swap(&mut a_x, &mut b_x);
        }

        if row < a_row || row > b_row {
            continue;
        }

        let start_x = if row == a_row { a_x } else { 0 };
        let end_x = if row == b_row { b_x } else { line_total_cells };
        if end_x <= start_x {
            continue;
        }

        // Overlap between [cell_start_x, cell_end_x) and [start_x, end_x)
        if cell_start_x < end_x && cell_end_x > start_x {
            return true;
        }
    }

    false
}
