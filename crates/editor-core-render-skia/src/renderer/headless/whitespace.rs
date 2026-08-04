use super::super::drawing::*;
use super::super::*;

pub(super) fn draw_headless_guides_and_whitespace(
    canvas: &skia_safe::Canvas,
    grid: &HeadlessGrid,
    row_idx: usize,
    text_origin_x: f32,
    y_top: f32,
    config: RenderConfig,
    theme: &RenderTheme,
    selections: &[VisualSelection],
) {
    let line = &grid.lines[row_idx];
    let row_abs = grid.start_visual_row as i64 + row_idx as i64;
    let line_total_cells: i64 =
        line.cells.iter().map(|c| c.width as i64).sum::<i64>() + line.segment_x_start_cells as i64;

    if config.show_indent_guides {
        let mut indent_cells: u32 = line.segment_x_start_cells as u32;
        for cell in &line.cells {
            if cell.ch == ' ' || cell.ch == '\t' {
                indent_cells = indent_cells.saturating_add(cell.width as u32);
            } else {
                break;
            }
        }

        draw_indent_guides(canvas, indent_cells, text_origin_x, y_top, config, theme);
    }

    let whitespace_mode = config.whitespace_render_mode;
    if !should_draw_whitespace_markers(whitespace_mode, !selections.is_empty()) {
        return;
    }

    let (dot_paint, stroke_paint) = whitespace_marker_paints(theme);
    let mut x_cells = line.segment_x_start_cells as u32;
    for cell in &line.cells {
        let w_cells = cell.width as u32;
        let cell_start = x_cells as i64;
        let cell_end = x_cells.saturating_add(w_cells) as i64;

        let is_whitespace = cell.ch == ' ' || cell.ch == '\t';
        let selected = match whitespace_mode {
            WhitespaceRenderMode::None => false,
            WhitespaceRenderMode::Selection => {
                is_whitespace
                    && cell_overlaps_selection_for_row(
                        row_abs,
                        cell_start,
                        cell_end,
                        line_total_cells,
                        selections,
                    )
            }
            WhitespaceRenderMode::All => is_whitespace,
        };

        if selected {
            let x_px = text_origin_x + x_cells as f32 * config.cell_width_px;
            let w_px = w_cells as f32 * config.cell_width_px;
            draw_whitespace_marker_cell(
                canvas,
                cell.ch,
                x_px,
                w_px,
                y_top,
                config,
                &dot_paint,
                &stroke_paint,
            );
        }

        x_cells = x_cells.saturating_add(w_cells);
    }
}
