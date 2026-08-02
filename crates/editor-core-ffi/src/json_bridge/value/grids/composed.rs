use super::*;

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
