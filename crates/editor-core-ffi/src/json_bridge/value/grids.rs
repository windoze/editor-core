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

pub(crate) fn value_composed_cell_source(source: ComposedCellSource) -> Value {
    match source {
        ComposedCellSource::Document { offset } => json!({ "kind": "document", "offset": offset }),
        ComposedCellSource::Virtual { anchor_offset } => {
            json!({ "kind": "virtual", "anchor_offset": anchor_offset })
        }
    }
}

pub(crate) fn value_composed_cell(cell: &ComposedCell) -> Value {
    json!({
        "ch": cell.ch.to_string(),
        "width": cell.width,
        "styles": cell.styles,
        "source": value_composed_cell_source(cell.source),
    })
}

pub(crate) fn value_composed_line_kind(kind: ComposedLineKind) -> Value {
    match kind {
        ComposedLineKind::Document {
            logical_line,
            visual_in_logical,
        } => json!({
            "kind": "document",
            "logical_line": logical_line,
            "visual_in_logical": visual_in_logical,
        }),
        ComposedLineKind::VirtualAboveLine { logical_line } => {
            json!({ "kind": "virtual_above_line", "logical_line": logical_line })
        }
    }
}

pub(crate) fn value_composed_line(line: &ComposedLine) -> Value {
    json!({
        "kind": value_composed_line_kind(line.kind),
        "cells": line.cells.iter().map(value_composed_cell).collect::<Vec<_>>(),
    })
}

pub(crate) fn value_composed_grid(grid: &ComposedGrid) -> Value {
    json!({
        "start_visual_row": grid.start_visual_row,
        "count": grid.count,
        "actual_line_count": grid.actual_line_count(),
        "lines": grid.lines.iter().map(value_composed_line).collect::<Vec<_>>(),
    })
}
