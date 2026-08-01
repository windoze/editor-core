use super::super::drawing::*;
use super::super::*;

pub(super) fn draw_composed_gutter(
    renderer: &SkiaRenderer,
    canvas: &skia_safe::Canvas,
    line: &ComposedLine,
    fold_markers: &[FoldMarker],
    gutter_x: f32,
    y_top: f32,
    baseline_y: f32,
    config: RenderConfig,
    theme: &RenderTheme,
) {
    let ComposedLineKind::Document {
        logical_line,
        visual_in_logical,
    } = line.kind
    else {
        return;
    };
    if config.gutter_width_cells == 0 || visual_in_logical != 0 {
        return;
    }

    let marker_state = fold_marker_state_for_line(logical_line as u32, fold_markers);
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
        logical_line,
        gutter_x,
        baseline_y,
        config,
        theme,
    );
}
