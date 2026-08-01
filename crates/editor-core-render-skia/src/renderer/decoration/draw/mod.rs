mod strike;
mod underline;

use super::super::*;
use super::run::{LineDecorationKind, LineDecorationRun};
use strike::draw_strikethrough;
use underline::{draw_double_underline, draw_single_underline, draw_squiggly_underline};

pub(in crate::renderer) fn decoration_thickness_px(config: RenderConfig) -> f32 {
    config.scale.clamp(1.0, 2.0)
}

pub(in crate::renderer) fn draw_decoration_run(
    canvas: &skia_safe::Canvas,
    run: LineDecorationRun,
    text_origin_x: f32,
    y_top: f32,
    baseline_y: f32,
    metrics: skia_safe::FontMetrics,
    config: RenderConfig,
) {
    let x_px = text_origin_x + run.start_x_cells as f32 * config.cell_width_px;
    let w_px = run.width_cells as f32 * config.cell_width_px;
    if w_px <= 0.0 {
        return;
    }

    match run.kind {
        LineDecorationKind::UnderlineSingle => {
            draw_single_underline(canvas, x_px, y_top, w_px, config, run.color);
        }
        LineDecorationKind::UnderlineDouble => {
            draw_double_underline(canvas, x_px, y_top, w_px, config, run.color);
        }
        LineDecorationKind::UnderlineSquiggly => {
            draw_squiggly_underline(canvas, x_px, y_top, w_px, config, run.color);
        }
        LineDecorationKind::Strikethrough => {
            draw_strikethrough(
                canvas, x_px, y_top, w_px, baseline_y, metrics, config, run.color,
            );
        }
    }
}
