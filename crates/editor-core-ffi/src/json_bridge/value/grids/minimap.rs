use super::*;

pub(crate) fn value_minimap_line(line: &MinimapLine) -> Value {
    json!({
        "logical_line_index": line.logical_line_index,
        "visual_in_logical": line.visual_in_logical,
        "char_offset_start": line.char_offset_start,
        "char_offset_end": line.char_offset_end,
        "total_cells": line.total_cells,
        "non_whitespace_cells": line.non_whitespace_cells,
        "dominant_style": line.dominant_style,
        "is_fold_placeholder_appended": line.is_fold_placeholder_appended,
    })
}

pub(crate) fn value_minimap_grid(grid: &MinimapGrid) -> Value {
    json!({
        "start_visual_row": grid.start_visual_row,
        "count": grid.count,
        "actual_line_count": grid.actual_line_count(),
        "lines": grid.lines.iter().map(value_minimap_line).collect::<Vec<_>>()
    })
}
