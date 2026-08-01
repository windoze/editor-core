use super::super::drawing::*;
use super::super::*;
use editor_core::snapshot::HeadlessLine;

pub(super) fn draw_headless_gutter(
    renderer: &SkiaRenderer,
    canvas: &skia_safe::Canvas,
    line: &HeadlessLine,
    fold_markers: &[FoldMarker],
    gutter_x: f32,
    y_top: f32,
    baseline_y: f32,
    config: RenderConfig,
    theme: &RenderTheme,
) {
    if config.gutter_width_cells == 0 || line.visual_in_logical != 0 {
        return;
    }

    let marker_state = fold_marker_state_for_line(line.logical_line_index as u32, fold_markers);
    if let Some(is_collapsed) = marker_state {
        let style_id = if is_collapsed {
            FOLD_MARKER_COLLAPSED_STYLE_ID
        } else {
            FOLD_MARKER_EXPANDED_STYLE_ID
        };
        let marker_cells = fold_marker_column_cells(&config);
        let rect = Rect::from_xywh(
            gutter_x,
            y_top,
            config.cell_width_px * marker_cells as f32,
            config.line_height_px,
        );
        draw_fold_marker(
            canvas,
            rect,
            is_collapsed,
            config.fold_marker_style,
            theme,
            style_id,
        );
    }

    draw_gutter_line_number(
        renderer,
        canvas,
        line.logical_line_index as usize,
        gutter_x,
        baseline_y,
        config,
        theme,
    );
}
