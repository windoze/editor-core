use super::super::drawing::*;
use super::super::*;
use super::run::{LineDecorationKind, LineDecorationRun};

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

pub(in crate::renderer) fn draw_single_underline(
    canvas: &skia_safe::Canvas,
    x_px: f32,
    y_top: f32,
    w_px: f32,
    config: RenderConfig,
    color: Rgba8,
) {
    let h = decoration_thickness_px(config);
    let y = (y_top + config.line_height_px - h).max(y_top);
    let rect = Rect::from_xywh(x_px, y, w_px, h);
    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(color));
    canvas.draw_rect(rect, &paint);
}

pub(in crate::renderer) fn draw_double_underline(
    canvas: &skia_safe::Canvas,
    x_px: f32,
    y_top: f32,
    w_px: f32,
    config: RenderConfig,
    color: Rgba8,
) {
    let h = decoration_thickness_px(config);
    let y1 = (y_top + config.line_height_px - h).max(y_top);
    let y2 = (y1 - h * 2.0).max(y_top);

    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(color));

    let rect1 = Rect::from_xywh(x_px, y1, w_px, h);
    canvas.draw_rect(rect1, &paint);

    let rect2 = Rect::from_xywh(x_px, y2, w_px, h);
    canvas.draw_rect(rect2, &paint);
}

pub(in crate::renderer) fn draw_squiggly_underline(
    canvas: &skia_safe::Canvas,
    x_px: f32,
    y_top: f32,
    w_px: f32,
    config: RenderConfig,
    color: Rgba8,
) {
    // Deterministic, non-antialiased "zig-zag" made of small rectangles.
    //
    // This avoids diagonal AA differences across backends while still looking squiggly at typical
    // editor sizes.
    let h = decoration_thickness_px(config);
    let y_bottom = (y_top + config.line_height_px - h).max(y_top);
    let y_upper = (y_bottom - h).max(y_top);
    let seg_w = (h * 2.0).max(2.0);

    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(color));

    let mut x = x_px;
    let x_end = x_px + w_px;
    let mut upper = false;
    while x < x_end {
        let w = (x_end - x).min(seg_w);
        let y = if upper { y_upper } else { y_bottom };
        let rect = Rect::from_xywh(x, y, w, h);
        canvas.draw_rect(rect, &paint);
        upper = !upper;
        x += seg_w;
    }
}

#[allow(clippy::too_many_arguments)]
pub(in crate::renderer) fn draw_strikethrough(
    canvas: &skia_safe::Canvas,
    x_px: f32,
    y_top: f32,
    w_px: f32,
    baseline_y: f32,
    metrics: skia_safe::FontMetrics,
    config: RenderConfig,
    color: Rgba8,
) {
    // Keep strikethrough thickness consistent with underline thickness for crisp, deterministic
    // rendering across fonts/backends.
    let h = decoration_thickness_px(config);

    let strike_pos = metrics.strikeout_position().unwrap_or_else(|| {
        // `x_height` is a positive distance from baseline up; convert to y-down.
        if metrics.x_height.is_finite() && metrics.x_height > 0.0 {
            -metrics.x_height * 0.5
        } else if metrics.ascent.is_finite() {
            metrics.ascent * 0.3
        } else {
            -config.line_height_px * 0.3
        }
    });

    let center_y = baseline_y + strike_pos;
    let mut y = center_y - h * 0.5;
    let max_y = (y_top + config.line_height_px - h).max(y_top);
    if !y.is_finite() {
        y = y_top + config.line_height_px * 0.5;
    }
    y = y.clamp(y_top, max_y).round().clamp(y_top, max_y);

    let rect = Rect::from_xywh(x_px, y, w_px, h);
    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(color));
    canvas.draw_rect(rect, &paint);
}
