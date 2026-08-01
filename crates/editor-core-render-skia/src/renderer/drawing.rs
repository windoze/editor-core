use super::style::*;
use super::*;

pub(super) fn rgba_to_skia_color(c: Rgba8) -> Color {
    Color::from_argb(c.a, c.r, c.g, c.b)
}

pub(super) fn draw_caret(
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

pub(super) fn draw_selection(
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

pub(super) fn fold_marker_state_for_line(
    logical_line: u32,
    fold_markers: &[FoldMarker],
) -> Option<bool> {
    fold_markers
        .iter()
        .find(|m| m.logical_line == logical_line)
        .map(|m| m.is_collapsed)
}

pub(super) fn draw_fold_marker(
    canvas: &skia_safe::Canvas,
    rect: Rect,
    is_collapsed: bool,
    style: FoldMarkerStyle,
    theme: &RenderTheme,
    style_id: u32,
) {
    if matches!(style, FoldMarkerStyle::Hidden) {
        return;
    }

    let color = resolve_style_foreground_or_background(style_id, theme, theme.foreground);

    match style {
        FoldMarkerStyle::Hidden => {}
        FoldMarkerStyle::Block => {
            let mut paint = Paint::default();
            paint.set_anti_alias(false);
            paint.set_color(rgba_to_skia_color(color));
            canvas.draw_rect(rect, &paint);
        }
        FoldMarkerStyle::Triangle => {
            let cx = rect.left + rect.width() * 0.5;
            let cy = rect.top + rect.height() * 0.5;
            let min_dim = rect.width().min(rect.height());

            // VSCode uses chevron icons (not filled triangles). We approximate them with stroked lines:
            // collapsed:  >
            // expanded:   v
            //
            // Match VSCode’s feel: relatively thin stroke + right-angle vertex (45° arms).
            let stroke = (min_dim * 0.10).clamp(1.0, 2.0);
            let mut paint = Paint::default();
            paint.set_anti_alias(true);
            paint.set_color(rgba_to_skia_color(color));
            paint.set_style(skia_safe::paint::Style::Stroke);
            paint.set_stroke_width(stroke);

            // Keep the chevron comfortably inside the cell; VSCode icons do not touch the bounds.
            let pad = (min_dim * 0.20).clamp(1.0, 4.0);
            let left = rect.left + pad;
            let right = rect.right - pad;
            let top = rect.top + pad;
            let bottom = rect.bottom - pad;

            if right <= left || bottom <= top {
                return;
            }

            let avail_w = right - left;
            let avail_h = bottom - top;

            if is_collapsed {
                // Right-pointing chevron with a 90° vertex:
                //   (x, y-Δ)  \
                //             >  (tip)
                //   (x, y+Δ)  /
                let max_arm = (avail_h * 0.5).min(avail_w);
                let arm = (max_arm * 0.92).max(2.0);

                let tip = Point::new(cx + arm * 0.5, cy);
                let start_x = tip.x - arm;
                canvas.draw_line(Point::new(start_x, tip.y - arm), tip, &paint);
                canvas.draw_line(Point::new(start_x, tip.y + arm), tip, &paint);
            } else {
                // Down-pointing chevron with a 90° vertex:
                //   (x-Δ, y)  \
                //             v  (tip)
                //   (x+Δ, y)  /
                let max_arm = (avail_w * 0.5).min(avail_h);
                let arm = (max_arm * 0.92).max(2.0);

                let tip = Point::new(cx, cy + arm * 0.5);
                let start_y = tip.y - arm;
                canvas.draw_line(Point::new(tip.x - arm, start_y), tip, &paint);
                canvas.draw_line(Point::new(tip.x + arm, start_y), tip, &paint);
            }
        }
    }
}

pub(super) fn fold_marker_column_cells(config: &RenderConfig) -> u32 {
    // VSCode has a dedicated glyph margin that is visually wider than a single text cell.
    // Reserve up to 2 cells for fold markers so the chevron matches VSCode’s perceived size.
    //
    // Keep a safe clamp so hosts that set a very small gutter width don't push line numbers
    // outside the gutter area.
    config.gutter_width_cells.clamp(1, 2)
}

pub(super) fn cell_overlaps_selection_for_row(
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
