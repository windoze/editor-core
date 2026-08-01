use super::editor::value_range_state;
use crate::*;

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
