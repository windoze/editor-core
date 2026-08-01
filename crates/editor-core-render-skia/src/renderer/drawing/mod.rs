mod background;
mod fold;
mod selection;
mod whitespace;

use super::*;

pub(super) use background::{
    draw_canvas_background, draw_gutter_background, draw_gutter_line_number, gutter_metrics,
};
pub(super) use fold::{draw_fold_marker, fold_marker_column_cells, fold_marker_state_for_line};
pub(super) use selection::{cell_overlaps_selection_for_row, draw_caret, draw_selection};
pub(super) use whitespace::{
    draw_indent_guides, draw_whitespace_marker_cell, should_draw_whitespace_markers,
    whitespace_marker_paints,
};

pub(super) fn rgba_to_skia_color(c: Rgba8) -> Color {
    Color::from_argb(c.a, c.r, c.g, c.b)
}
