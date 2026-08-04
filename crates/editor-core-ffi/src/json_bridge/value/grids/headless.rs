use super::*;

pub(crate) fn value_headless_cell(cell: &Cell) -> Value {
    json!({
        "ch": cell.ch.to_string(),
        "width": cell.width,
        "styles": cell.styles,
    })
}

pub(crate) fn value_headless_line(line: &HeadlessLine) -> Value {
    json!({
        "logical_line_index": line.logical_line_index,
        "is_wrapped_part": line.is_wrapped_part,
        "visual_in_logical": line.visual_in_logical,
        "char_offset_start": line.char_offset_start,
        "char_offset_end": line.char_offset_end,
        "segment_x_start_cells": line.segment_x_start_cells,
        "is_fold_placeholder_appended": line.is_fold_placeholder_appended,
        "cells": line.cells.iter().map(value_headless_cell).collect::<Vec<_>>(),
    })
}

pub(crate) fn value_headless_grid(grid: &HeadlessGrid) -> Value {
    json!({
        "start_visual_row": grid.start_visual_row,
        "count": grid.count,
        "actual_line_count": grid.actual_line_count(),
        "lines": grid.lines.iter().map(value_headless_line).collect::<Vec<_>>()
    })
}
