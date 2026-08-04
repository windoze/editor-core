mod rows;

use super::super::drawing::*;
use super::super::text_runs::*;
use super::super::*;
use super::{background::*, caret::*, selection::*};
use rows::draw_composed_rows;

impl SkiaRenderer {
    #[allow(clippy::too_many_arguments)]
    pub(super) fn draw_composed_grid_to_canvas(
        &mut self,
        canvas: &skia_safe::Canvas,
        grid: &ComposedGrid,
        caret_offsets: &[usize],
        selection_ranges: &[(usize, usize)],
        fold_markers: &[FoldMarker],
        config: RenderConfig,
        theme: &RenderTheme,
        row_range: Option<(usize, usize)>,
    ) -> Result<(), RenderError> {
        draw_canvas_background(canvas, theme);
        let (gutter_x, _gutter_w_px, text_origin_x) = gutter_metrics(config);
        draw_gutter_background(canvas, config, theme);

        let total_rows = grid.lines.len();
        let (row_start, row_end) = row_range.unwrap_or((0, total_rows));
        let row_start = row_start.min(total_rows);
        let row_end = row_end.min(total_rows);

        let pending_carets = pending_carets_for_composed_grid(grid, caret_offsets);

        debug_assert!(
            !self.fonts_normal.fonts.is_empty(),
            "SkiaRenderer must always have at least one font"
        );
        let baseline_offset = self.baseline_offset_px(config);

        draw_composed_cell_backgrounds(
            canvas,
            grid,
            text_origin_x,
            config,
            theme,
            row_start,
            row_end,
        );

        let sel_ranges = normalized_selection_ranges(selection_ranges);
        if !sel_ranges.is_empty() {
            draw_composed_selection_overlay(
                canvas,
                grid,
                text_origin_x,
                config,
                theme,
                row_start,
                row_end,
                sel_ranges.as_slice(),
            );
        }

        draw_composed_rows(
            self,
            canvas,
            grid,
            fold_markers,
            gutter_x,
            text_origin_x,
            baseline_offset,
            config,
            theme,
            row_start,
            row_end,
            sel_ranges.as_slice(),
        );

        if config.show_caret {
            draw_visible_composed_carets(
                canvas,
                pending_carets.as_slice(),
                text_origin_x,
                row_start,
                row_end,
                config,
                theme,
            );
        }

        Ok(())
    }
}

fn draw_visible_composed_carets(
    canvas: &skia_safe::Canvas,
    pending_carets: &[PendingCaret],
    text_origin_x: f32,
    row_start: usize,
    row_end: usize,
    config: RenderConfig,
    theme: &RenderTheme,
) {
    let caret_width = config.caret_width_px.max(1.0);
    for caret in pending_carets
        .iter()
        .filter(|c| c.local_row >= row_start && c.local_row < row_end)
    {
        let x_px = text_origin_x + caret.x_cells as f32 * config.cell_width_px;
        let y_top = config.padding_y_px + caret.local_row as f32 * config.line_height_px
            - config.scroll_y_px;

        let rect = Rect::from_xywh(x_px, y_top, caret_width, config.line_height_px);

        let mut paint = Paint::default();
        paint.set_anti_alias(false);
        paint.set_color(rgba_to_skia_color(theme.caret));
        canvas.draw_rect(rect, &paint);
    }
}
