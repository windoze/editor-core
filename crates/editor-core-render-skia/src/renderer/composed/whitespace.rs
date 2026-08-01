use super::super::drawing::*;
use super::super::*;

pub(super) fn draw_composed_guides_and_whitespace(
    canvas: &skia_safe::Canvas,
    line: &ComposedLine,
    text_origin_x: f32,
    y_top: f32,
    config: RenderConfig,
    theme: &RenderTheme,
    sel_ranges: &[(usize, usize)],
) {
    if config.show_indent_guides {
        let mut indent_cells: u32 = 0;
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
    if !should_draw_whitespace_markers(whitespace_mode, !sel_ranges.is_empty()) {
        return;
    }

    let (dot_paint, stroke_paint) = whitespace_marker_paints(theme);
    let mut marker_x_cells: u32 = 0;
    for cell in &line.cells {
        let w_cells = cell.width as u32;
        let selected = match cell.source {
            ComposedCellSource::Document { offset } => {
                let is_whitespace = cell.ch == ' ' || cell.ch == '\t';
                match whitespace_mode {
                    WhitespaceRenderMode::None => false,
                    WhitespaceRenderMode::Selection => {
                        is_whitespace && sel_ranges.iter().any(|(s, e)| offset >= *s && offset < *e)
                    }
                    WhitespaceRenderMode::All => is_whitespace,
                }
            }
            _ => false,
        };

        if selected {
            let x_px = text_origin_x + marker_x_cells as f32 * config.cell_width_px;
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

        marker_x_cells = marker_x_cells.saturating_add(w_cells);
    }
}
