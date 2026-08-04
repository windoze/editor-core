mod rows;

use super::super::drawing::*;
use super::super::text_runs::*;
use super::super::*;
use super::{background::*, caret::*, selection::*};
use rows::draw_headless_rows;

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

        draw_headless_cell_backgrounds(
            canvas,
            grid,
            text_origin_x,
            config,
            theme,
            row_start,
            row_end,
        );

        draw_headless_selection_overlays(
            canvas,
            grid,
            selections,
            text_origin_x,
            config,
            theme,
            row_range,
        );

        debug_assert!(
            !self.fonts_normal.fonts.is_empty(),
            "SkiaRenderer must always have at least one font"
        );
        let baseline_offset = self.baseline_offset_px(config);

        draw_headless_rows(
            self,
            canvas,
            grid,
            selections,
            fold_markers,
            gutter_x,
            text_origin_x,
            baseline_offset,
            config,
            theme,
            row_start,
            row_end,
        );

        if config.show_caret {
            draw_visible_headless_carets(
                canvas,
                grid,
                carets,
                text_origin_x,
                config,
                theme,
                row_range,
            );
        }

        Ok(())
    }
}

#[allow(clippy::too_many_arguments)]
fn draw_visible_headless_carets(
    canvas: &skia_safe::Canvas,
    grid: &HeadlessGrid,
    carets: &[VisualCaret],
    text_origin_x: f32,
    config: RenderConfig,
    theme: &RenderTheme,
    row_range: Option<(usize, usize)>,
) {
    for caret in carets
        .iter()
        .filter(|caret| caret_in_row_range(caret, row_range))
    {
        draw_caret(canvas, grid, *caret, text_origin_x, config, theme.caret);
    }
}
