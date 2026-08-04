use super::*;
use crate::renderer::composed::{gutter::*, whitespace::*};

#[allow(clippy::too_many_arguments)]
pub(super) fn draw_composed_rows(
    renderer: &mut SkiaRenderer,
    canvas: &skia_safe::Canvas,
    grid: &ComposedGrid,
    fold_markers: &[FoldMarker],
    gutter_x: f32,
    text_origin_x: f32,
    baseline_offset: f32,
    config: RenderConfig,
    theme: &RenderTheme,
    row_start: usize,
    row_end: usize,
    sel_ranges: &[(usize, usize)],
) {
    for row_idx in row_start..row_end {
        let line = &grid.lines[row_idx];
        let y_top =
            config.padding_y_px + row_idx as f32 * config.line_height_px - config.scroll_y_px;
        let baseline_y = y_top + baseline_offset;

        draw_composed_gutter(
            renderer,
            canvas,
            line,
            fold_markers,
            gutter_x,
            y_top,
            baseline_y,
            config,
            theme,
        );

        if config.show_indent_guides || config.whitespace_render_mode != WhitespaceRenderMode::None
        {
            draw_composed_guides_and_whitespace(
                canvas,
                line,
                text_origin_x,
                y_top,
                config,
                theme,
                sel_ranges,
            );
        }

        draw_text_runs_for_cells(
            renderer,
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
}
