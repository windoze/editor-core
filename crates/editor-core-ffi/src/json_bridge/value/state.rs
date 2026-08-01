use super::*;

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
