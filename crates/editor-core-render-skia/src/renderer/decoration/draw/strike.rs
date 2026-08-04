use super::super::super::drawing::*;
use super::super::super::*;
use super::decoration_thickness_px;

#[allow(clippy::too_many_arguments)]
pub(super) fn draw_strikethrough(
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
