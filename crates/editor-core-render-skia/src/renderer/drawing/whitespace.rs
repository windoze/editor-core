use super::super::style::*;
use super::super::*;
use super::rgba_to_skia_color;

pub(in crate::renderer) fn draw_indent_guides(
    canvas: &skia_safe::Canvas,
    indent_cells: u32,
    text_origin_x: f32,
    y_top: f32,
    config: RenderConfig,
    theme: &RenderTheme,
) {
    let tab_w = config.tab_width_cells.max(1);
    let levels = indent_cells / tab_w;
    if levels == 0 {
        return;
    }

    let guide_color = resolve_style_foreground_or_background(
        INDENT_GUIDE_STYLE_ID,
        theme,
        default_indent_guide_color(theme),
    );
    let mut paint = Paint::default();
    paint.set_anti_alias(false);
    paint.set_color(rgba_to_skia_color(guide_color));

    for level in 1..=levels {
        // Place the guide on the boundary between indentation levels, right after a tabstop.
        let boundary_cells = level.saturating_mul(tab_w);
        let x_px = (text_origin_x + boundary_cells as f32 * config.cell_width_px).round();
        let rect = Rect::from_xywh(x_px, y_top, 1.0, config.line_height_px);
        canvas.draw_rect(rect, &paint);
    }
}

pub(in crate::renderer) fn should_draw_whitespace_markers(
    whitespace_mode: WhitespaceRenderMode,
    has_selection: bool,
) -> bool {
    match whitespace_mode {
        WhitespaceRenderMode::None => false,
        WhitespaceRenderMode::Selection => has_selection,
        WhitespaceRenderMode::All => true,
    }
}

pub(in crate::renderer) fn whitespace_marker_paints(theme: &RenderTheme) -> (Paint, Paint) {
    let marker_color = resolve_style_foreground_or_background(
        WHITESPACE_STYLE_ID,
        theme,
        default_whitespace_marker_color(theme),
    );

    let mut dot_paint = Paint::default();
    dot_paint.set_anti_alias(true);
    dot_paint.set_color(rgba_to_skia_color(marker_color));

    let mut stroke_paint = Paint::default();
    stroke_paint.set_anti_alias(true);
    stroke_paint.set_color(rgba_to_skia_color(marker_color));
    stroke_paint.set_style(skia_safe::paint::Style::Stroke);
    stroke_paint.set_stroke_width(1.0);

    (dot_paint, stroke_paint)
}

pub(in crate::renderer) fn draw_whitespace_marker_cell(
    canvas: &skia_safe::Canvas,
    ch: char,
    x_px: f32,
    w_px: f32,
    y_top: f32,
    config: RenderConfig,
    dot_paint: &Paint,
    stroke_paint: &Paint,
) {
    let cy = y_top + config.line_height_px * 0.5;

    if ch == ' ' {
        let cx = x_px + w_px * 0.5;
        let r = (config.cell_width_px.min(config.line_height_px) * 0.10).max(1.0);
        canvas.draw_circle(Point::new(cx, cy), r, dot_paint);
    } else if ch == '\t' {
        let pad = (config.cell_width_px * 0.15).min(w_px * 0.25);
        let x0 = x_px + pad;
        let x1 = (x_px + w_px - pad).max(x0 + 1.0);
        let head = (config.cell_width_px.min(config.line_height_px) * 0.20).max(2.0);
        let shaft_end = (x1 - head).max(x0);

        canvas.draw_line(Point::new(x0, cy), Point::new(shaft_end, cy), stroke_paint);
        canvas.draw_line(Point::new(shaft_end, cy), Point::new(x1, cy), stroke_paint);
        canvas.draw_line(
            Point::new(x1, cy),
            Point::new(x1 - head, cy - head * 0.6),
            stroke_paint,
        );
        canvas.draw_line(
            Point::new(x1, cy),
            Point::new(x1 - head, cy + head * 0.6),
            stroke_paint,
        );
    }
}
