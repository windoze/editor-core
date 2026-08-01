use super::super::drawing::*;
use super::super::text_runs::*;
use super::super::*;
use super::{background::*, caret::*, gutter::*, selection::*, whitespace::*};

impl SkiaRenderer {
    #[allow(clippy::too_many_arguments)]
    pub(super) fn draw_headless_grid_to_canvas(
        &mut self,
        canvas: &skia_safe::Canvas,
        grid: &HeadlessGrid,
        carets: &[VisualCaret],
        selections: &[VisualSelection],
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

        // 1) Draw per-cell backgrounds (including styled backgrounds).
        //
        // Selection is an overlay and must win over style backgrounds, so we draw it in a
        // separate pass *after* this.
        draw_headless_cell_backgrounds(
            canvas,
            grid,
            text_origin_x,
            config,
            theme,
            row_start,
            row_end,
        );

        // 2) Selection overlay (under text, over backgrounds).
        draw_headless_selection_overlays(
            canvas,
            grid,
            selections,
            text_origin_x,
            config,
            theme,
            row_range,
        );

        // Text.
        debug_assert!(
            !self.fonts_normal.fonts.is_empty(),
            "SkiaRenderer must always have at least one font"
        );
        let baseline_offset = self.baseline_offset_px(config);

        // Text + underlines.
        for row_idx in row_start..row_end {
            let line = &grid.lines[row_idx];
            let y_top =
                config.padding_y_px + row_idx as f32 * config.line_height_px - config.scroll_y_px;
            let baseline_y = y_top + baseline_offset;

            draw_headless_gutter(
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
                draw_headless_guides_and_whitespace(
                    canvas,
                    grid,
                    row_idx,
                    text_origin_x,
                    y_top,
                    config,
                    theme,
                    selections,
                );
            }

            draw_text_runs_for_cells(
                self,
                canvas,
                line.cells.as_slice(),
                line.segment_x_start_cells as u32,
                text_origin_x,
                y_top,
                baseline_y,
                config,
                theme,
            );
        }

        // Carets on top.
        if config.show_caret {
            for caret in carets
                .iter()
                .filter(|caret| caret_in_row_range(caret, row_range))
            {
                draw_caret(canvas, grid, *caret, text_origin_x, config, theme.caret);
            }
        }

        Ok(())
    }
}
