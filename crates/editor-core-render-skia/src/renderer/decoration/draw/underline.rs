use super::super::super::drawing::*;
use super::super::super::*;
use super::decoration_thickness_px;

pub(super) fn draw_single_underline(
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

pub(super) fn draw_double_underline(
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

pub(super) fn draw_squiggly_underline(
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
