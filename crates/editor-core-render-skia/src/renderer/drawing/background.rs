use super::super::style::*;
use super::super::*;
use super::fold::fold_marker_column_cells;
use super::rgba_to_skia_color;

pub(in crate::renderer) fn draw_canvas_background(canvas: &skia_safe::Canvas, theme: &RenderTheme) {
    let mut bg_paint = Paint::default();
    bg_paint.set_anti_alias(false);
    bg_paint.set_color(rgba_to_skia_color(theme.background));
    canvas.draw_paint(&bg_paint);
}

pub(in crate::renderer) fn gutter_metrics(config: RenderConfig) -> (f32, f32, f32) {
    let gutter_x = config.padding_x_px;
    let gutter_w_px = config.gutter_width_cells as f32 * config.cell_width_px;
    let text_origin_x = gutter_x + gutter_w_px;
    (gutter_x, gutter_w_px, text_origin_x)
}

pub(in crate::renderer) fn draw_gutter_background(
    canvas: &skia_safe::Canvas,
    config: RenderConfig,
    theme: &RenderTheme,
) {
    let (gutter_x, gutter_w_px, text_origin_x) = gutter_metrics(config);
    if config.gutter_width_cells == 0 || gutter_w_px <= 0.0 {
        return;
    }

    let gutter_bg = resolve_style_background(GUTTER_BACKGROUND_STYLE_ID, theme, theme.background);
    let rect = Rect::from_xywh(gutter_x, 0.0, gutter_w_px, config.height_px as f32);
    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(gutter_bg));
    canvas.draw_rect(rect, &paint);

    let sep = resolve_style_foreground(GUTTER_SEPARATOR_STYLE_ID, theme, theme.foreground);
    let sep_rect = Rect::from_xywh(text_origin_x, 0.0, 1.0, config.height_px as f32);
    let mut sep_paint = Paint::default();
    sep_paint.set_anti_alias(false);
    sep_paint.set_color(rgba_to_skia_color(sep));
    canvas.draw_rect(sep_rect, &sep_paint);
}

pub(in crate::renderer) fn draw_gutter_line_number(
    renderer: &SkiaRenderer,
    canvas: &skia_safe::Canvas,
    logical_line: usize,
    gutter_x: f32,
    baseline_y: f32,
    config: RenderConfig,
    theme: &RenderTheme,
) {
    // Line number text is best-effort; tests should not depend on glyph rasterization.
    let gutter_fg = resolve_style_foreground(GUTTER_FOREGROUND_STYLE_ID, theme, theme.foreground);
    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(gutter_fg));

    let line_no = (logical_line + 1).to_string();
    let marker_cells = fold_marker_column_cells(&config);
    let x_px = gutter_x + config.cell_width_px * marker_cells as f32;
    canvas.draw_str(
        line_no,
        Point::new(x_px, baseline_y),
        renderer.normal_primary_font(),
        &paint,
    );
}
