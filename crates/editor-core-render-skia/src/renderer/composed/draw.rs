use super::super::drawing::*;
use super::super::text_runs::*;
use super::super::*;
use super::{background::*, caret::*, gutter::*, selection::*, whitespace::*};

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

        // 1) Draw per-cell backgrounds (including styled backgrounds).
        draw_composed_cell_backgrounds(
            canvas,
            grid,
            text_origin_x,
            config,
            theme,
            row_start,
            row_end,
        );

        // 2) Selection overlay (under text, over backgrounds).
        //
        // Note: selection highlight is applied only to document cells. Virtual text is not
        // considered part of the selection.
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

        // 3) Text + underlines.
        for row_idx in row_start..row_end {
            let line = &grid.lines[row_idx];
            let y_top =
                config.padding_y_px + row_idx as f32 * config.line_height_px - config.scroll_y_px;
            let baseline_y = y_top + baseline_offset;

            draw_composed_gutter(
                self,
                canvas,
                line,
                fold_markers,
                gutter_x,
                y_top,
                baseline_y,
                config,
                theme,
            );

            // Indent guides + whitespace markers are drawn after selection but before text.
            if config.show_indent_guides
                || config.whitespace_render_mode != WhitespaceRenderMode::None
            {
                draw_composed_guides_and_whitespace(
                    canvas,
                    line,
                    text_origin_x,
                    y_top,
                    config,
                    theme,
                    sel_ranges.as_slice(),
                );
            }

            draw_text_runs_for_cells(
                self,
                canvas,
                line.cells.as_slice(),
                0,
                text_origin_x,
                y_top,
                baseline_y,
                config,
                theme,
            );
        }

        // Carets on top.
        if config.show_caret {
            let caret_width = config.caret_width_px.max(1.0);
            for caret in pending_carets
                .into_iter()
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

        Ok(())
    }
}
