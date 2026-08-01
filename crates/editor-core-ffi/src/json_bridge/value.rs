use super::*;

pub(crate) fn value_position(value: Position) -> Value {
    json!({ "line": value.line, "column": value.column })
}

pub(crate) fn value_selection(value: &Selection) -> Value {
    json!({
        "start": value_position(value.start),
        "end": value_position(value.end),
        "direction": selection_direction_to_str(value.direction)
    })
}

pub(crate) fn value_offset_range(start: usize, end: usize) -> Value {
    json!({ "start": start, "end": end })
}

pub(crate) fn value_utf16_position(value: Utf16Position) -> Value {
    json!({ "line": value.line, "character": value.character })
}

pub(crate) fn value_utf16_range(value: Utf16Range) -> Value {
    json!({
        "start": value_utf16_position(value.start),
        "end": value_utf16_position(value.end)
    })
}

pub(crate) fn value_symbol_location(value: &SymbolLocation) -> Value {
    json!({
        "uri": value.uri,
        "range": value_utf16_range(value.range)
    })
}

pub(crate) fn value_document_symbol(symbol: &DocumentSymbol) -> Value {
    json!({
        "name": symbol.name,
        "detail": symbol.detail,
        "kind": symbol_kind_to_json(symbol.kind),
        "range": value_offset_range(symbol.range.start, symbol.range.end),
        "selection_range": value_offset_range(symbol.selection_range.start, symbol.selection_range.end),
        "children": symbol.children.iter().map(value_document_symbol).collect::<Vec<_>>(),
        "data_json": symbol.data_json
    })
}

pub(crate) fn value_workspace_symbol(symbol: &WorkspaceSymbol) -> Value {
    json!({
        "name": symbol.name,
        "detail": symbol.detail,
        "kind": symbol_kind_to_json(symbol.kind),
        "location": value_symbol_location(&symbol.location),
        "container_name": symbol.container_name,
        "data_json": symbol.data_json
    })
}

pub(crate) fn value_interval(interval: &Interval) -> Value {
    json!({
        "start": interval.start,
        "end": interval.end,
        "style_id": interval.style_id
    })
}

pub(crate) fn value_fold_region(region: &FoldRegion) -> Value {
    json!({
        "start_line": region.start_line,
        "end_line": region.end_line,
        "is_collapsed": region.is_collapsed,
        "placeholder": region.placeholder
    })
}

pub(crate) fn value_diagnostic(diagnostic: &Diagnostic) -> Value {
    json!({
        "range": value_offset_range(diagnostic.range.start, diagnostic.range.end),
        "severity": diagnostic.severity.map(diagnostic_severity_to_str),
        "code": diagnostic.code,
        "source": diagnostic.source,
        "message": diagnostic.message,
        "related_information_json": diagnostic.related_information_json,
        "data_json": diagnostic.data_json
    })
}

pub(crate) fn value_decoration(decoration: &Decoration) -> Value {
    json!({
        "range": value_offset_range(decoration.range.start, decoration.range.end),
        "placement": decoration_placement_to_str(decoration.placement),
        "kind": decoration_kind_to_json(decoration.kind),
        "text": decoration.text,
        "styles": decoration.styles,
        "tooltip": decoration.tooltip,
        "data_json": decoration.data_json
    })
}

pub(crate) fn value_processing_edit(edit: &ProcessingEdit) -> Value {
    match edit {
        ProcessingEdit::ReplaceStyleLayer { layer, intervals } => json!({
            "op": "replace_style_layer",
            "layer": layer.0,
            "intervals": intervals.iter().map(value_interval).collect::<Vec<_>>()
        }),
        ProcessingEdit::ClearStyleLayer { layer } => json!({
            "op": "clear_style_layer",
            "layer": layer.0
        }),
        ProcessingEdit::ReplaceFoldingRegions {
            regions,
            preserve_collapsed,
        } => json!({
            "op": "replace_folding_regions",
            "regions": regions.iter().map(value_fold_region).collect::<Vec<_>>(),
            "preserve_collapsed": preserve_collapsed,
        }),
        ProcessingEdit::ClearFoldingRegions => json!({ "op": "clear_folding_regions" }),
        ProcessingEdit::ReplaceDiagnostics { diagnostics } => json!({
            "op": "replace_diagnostics",
            "diagnostics": diagnostics.iter().map(value_diagnostic).collect::<Vec<_>>()
        }),
        ProcessingEdit::ClearDiagnostics => json!({ "op": "clear_diagnostics" }),
        ProcessingEdit::ReplaceDecorations { layer, decorations } => json!({
            "op": "replace_decorations",
            "layer": layer.0,
            "decorations": decorations.iter().map(value_decoration).collect::<Vec<_>>()
        }),
        ProcessingEdit::ClearDecorations { layer } => json!({
            "op": "clear_decorations",
            "layer": layer.0,
        }),
        ProcessingEdit::ReplaceDocumentSymbols { symbols } => json!({
            "op": "replace_document_symbols",
            "symbols": symbols.symbols.iter().map(value_document_symbol).collect::<Vec<_>>()
        }),
        ProcessingEdit::ClearDocumentSymbols => json!({ "op": "clear_document_symbols" }),
    }
}

pub(crate) fn value_text_delta(delta: &editor_core::TextDelta) -> Value {
    json!({
        "before_char_count": delta.before_char_count,
        "after_char_count": delta.after_char_count,
        "undo_group_id": delta.undo_group_id,
        "edits": delta.edits.iter().map(|edit| json!({
            "start": edit.start,
            "deleted_text": edit.deleted_text,
            "inserted_text": edit.inserted_text,
        })).collect::<Vec<_>>()
    })
}

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

pub(crate) fn value_command_result(result: CommandResult) -> Value {
    match result {
        CommandResult::Success => json!({ "kind": "success" }),
        CommandResult::Text(text) => json!({ "kind": "text", "text": text }),
        CommandResult::Position(pos) => {
            json!({ "kind": "position", "position": value_position(pos) })
        }
        CommandResult::Offset(offset) => json!({ "kind": "offset", "offset": offset }),
        CommandResult::Viewport(grid) => {
            json!({ "kind": "viewport", "viewport": value_headless_grid(&grid) })
        }
        CommandResult::SearchMatch { start, end } => {
            json!({ "kind": "search_match", "start": start, "end": end })
        }
        CommandResult::SearchNotFound => json!({ "kind": "search_not_found" }),
        CommandResult::ReplaceResult { replaced } => {
            json!({ "kind": "replace_result", "replaced": replaced })
        }
    }
}

pub(crate) fn value_document_state(state: &DocumentState) -> Value {
    json!({
        "line_count": state.line_count,
        "char_count": state.char_count,
        "byte_count": state.byte_count,
        "is_modified": state.is_modified,
        "version": state.version,
    })
}

pub(crate) fn value_cursor_state(state: &CursorState) -> Value {
    json!({
        "position": value_position(state.position),
        "offset": state.offset,
        "multi_cursors": state.multi_cursors.iter().map(|p| value_position(*p)).collect::<Vec<_>>(),
        "selection": state.selection.as_ref().map(value_selection),
        "selections": state.selections.iter().map(value_selection).collect::<Vec<_>>(),
        "primary_selection_index": state.primary_selection_index,
    })
}

pub(crate) fn value_range_state(start: usize, end: usize) -> Value {
    json!({ "start": start, "end": end })
}

pub(crate) fn value_viewport_state(state: &ViewportState) -> Value {
    json!({
        "width": state.width,
        "height": state.height,
        "scroll_top": state.scroll_top,
        "sub_row_offset": state.sub_row_offset,
        "overscan_rows": state.overscan_rows,
        "visible_lines": value_range_state(state.visible_lines.start, state.visible_lines.end),
        "prefetch_lines": value_range_state(state.prefetch_lines.start, state.prefetch_lines.end),
        "total_visual_lines": state.total_visual_lines,
    })
}

pub(crate) fn value_undo_redo_state(state: &UndoRedoState) -> Value {
    json!({
        "can_undo": state.can_undo,
        "can_redo": state.can_redo,
        "undo_depth": state.undo_depth,
        "redo_depth": state.redo_depth,
        "current_change_group": state.current_change_group,
    })
}

pub(crate) fn value_folding_state(state: &FoldingState) -> Value {
    json!({
        "regions": state.regions.iter().map(value_fold_region).collect::<Vec<_>>(),
        "collapsed_line_count": state.collapsed_line_count,
        "visible_logical_lines": state.visible_logical_lines,
        "total_visual_lines": state.total_visual_lines,
    })
}

pub(crate) fn value_diagnostics_state(state: &DiagnosticsState) -> Value {
    json!({ "diagnostics_count": state.diagnostics_count })
}

pub(crate) fn value_decorations_state(state: &DecorationsState) -> Value {
    json!({
        "layer_count": state.layer_count,
        "decoration_count": state.decoration_count,
    })
}

pub(crate) fn value_style_state(state: &StyleState) -> Value {
    json!({ "style_count": state.style_count })
}

pub(crate) fn value_editor_state(state: &EditorState) -> Value {
    json!({
        "document": value_document_state(&state.document),
        "cursor": value_cursor_state(&state.cursor),
        "viewport": value_viewport_state(&state.viewport),
        "undo_redo": value_undo_redo_state(&state.undo_redo),
        "folding": value_folding_state(&state.folding),
        "diagnostics": value_diagnostics_state(&state.diagnostics),
        "decorations": value_decorations_state(&state.decorations),
        "style": value_style_state(&state.style),
    })
}

pub(crate) fn value_workspace_search_result(item: &WorkspaceSearchResult) -> Value {
    json!({
        "buffer_id": item.id.get(),
        "uri": item.uri,
        "matches": item.matches.iter().map(|m| value_search_match(*m)).collect::<Vec<_>>(),
    })
}

pub(crate) fn value_search_match(m: SearchMatch) -> Value {
    json!({ "start": m.start, "end": m.end })
}

pub(crate) fn value_smooth_scroll_state(state: ViewSmoothScrollState) -> Value {
    json!({
        "top_visual_row": state.top_visual_row,
        "sub_row_offset": state.sub_row_offset,
        "overscan_rows": state.overscan_rows,
    })
}

pub(crate) fn value_workspace_viewport_state(state: &WorkspaceViewportState) -> Value {
    json!({
        "width": state.width,
        "height": state.height,
        "scroll_top": state.scroll_top,
        "visible_lines": value_range_state(state.visible_lines.start, state.visible_lines.end),
        "total_visual_lines": state.total_visual_lines,
        "smooth_scroll": value_smooth_scroll_state(state.smooth_scroll),
        "prefetch_lines": value_range_state(state.prefetch_lines.start, state.prefetch_lines.end),
    })
}

pub(crate) fn value_open_buffer_result(result: OpenBufferResult) -> Value {
    json!({
        "buffer_id": result.buffer_id.get(),
        "view_id": result.view_id.get(),
    })
}
