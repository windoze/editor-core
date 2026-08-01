use super::super::style::*;
use super::super::*;
use super::rgba_to_skia_color;

pub(in crate::renderer) fn fold_marker_state_for_line(
    logical_line: u32,
    fold_markers: &[FoldMarker],
) -> Option<bool> {
    fold_markers
        .iter()
        .find(|m| m.logical_line == logical_line)
        .map(|m| m.is_collapsed)
}

pub(in crate::renderer) fn draw_fold_marker(
    canvas: &skia_safe::Canvas,
    rect: Rect,
    is_collapsed: bool,
    style: FoldMarkerStyle,
    theme: &RenderTheme,
    style_id: u32,
) {
    if matches!(style, FoldMarkerStyle::Hidden) {
        return;
    }

    let color = resolve_style_foreground_or_background(style_id, theme, theme.foreground);

    match style {
        FoldMarkerStyle::Hidden => {}
        FoldMarkerStyle::Block => {
            let mut paint = Paint::default();
            paint.set_anti_alias(false);
            paint.set_color(rgba_to_skia_color(color));
            canvas.draw_rect(rect, &paint);
        }
        FoldMarkerStyle::Triangle => {
            let cx = rect.left + rect.width() * 0.5;
            let cy = rect.top + rect.height() * 0.5;
            let min_dim = rect.width().min(rect.height());

            // VSCode-like chevron: collapsed is `>`, expanded is `v`.
            let stroke = (min_dim * 0.10).clamp(1.0, 2.0);
            let mut paint = Paint::default();
            paint.set_anti_alias(true);
            paint.set_color(rgba_to_skia_color(color));
            paint.set_style(skia_safe::paint::Style::Stroke);
            paint.set_stroke_width(stroke);

            let pad = (min_dim * 0.20).clamp(1.0, 4.0);
            let left = rect.left + pad;
            let right = rect.right - pad;
            let top = rect.top + pad;
            let bottom = rect.bottom - pad;

            if right <= left || bottom <= top {
                return;
            }

            let avail_w = right - left;
            let avail_h = bottom - top;

            if is_collapsed {
                let max_arm = (avail_h * 0.5).min(avail_w);
                let arm = (max_arm * 0.92).max(2.0);

                let tip = Point::new(cx + arm * 0.5, cy);
                let start_x = tip.x - arm;
                canvas.draw_line(Point::new(start_x, tip.y - arm), tip, &paint);
                canvas.draw_line(Point::new(start_x, tip.y + arm), tip, &paint);
            } else {
                let max_arm = (avail_w * 0.5).min(avail_h);
                let arm = (max_arm * 0.92).max(2.0);

                let tip = Point::new(cx, cy + arm * 0.5);
                let start_y = tip.y - arm;
                canvas.draw_line(Point::new(tip.x - arm, start_y), tip, &paint);
                canvas.draw_line(Point::new(tip.x + arm, start_y), tip, &paint);
            }
        }
    }
}

pub(in crate::renderer) fn fold_marker_column_cells(config: &RenderConfig) -> u32 {
    // VSCode has a dedicated glyph margin that is visually wider than a single text cell.
    // Reserve up to 2 cells for fold markers so the chevron matches VSCode’s perceived size.
    config.gutter_width_cells.clamp(1, 2)
}
