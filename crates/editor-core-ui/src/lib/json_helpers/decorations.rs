use super::*;

pub(crate) fn decoration_placement_to_str(value: DecorationPlacement) -> &'static str {
    match value {
        DecorationPlacement::Before => "before",
        DecorationPlacement::After => "after",
        DecorationPlacement::AboveLine => "above_line",
    }
}

pub(crate) fn decoration_kind_to_json(value: DecorationKind) -> serde_json::Value {
    match value {
        DecorationKind::InlayHint => serde_json::json!({ "kind": "inlay_hint" }),
        DecorationKind::CodeLens => serde_json::json!({ "kind": "code_lens" }),
        DecorationKind::DocumentLink => serde_json::json!({ "kind": "document_link" }),
        DecorationKind::Highlight => serde_json::json!({ "kind": "highlight" }),
        DecorationKind::Custom(v) => serde_json::json!({ "kind": "custom", "value": v }),
    }
}

pub(crate) fn value_decoration(decoration: &editor_core::Decoration) -> serde_json::Value {
    serde_json::json!({
        "range": value_offset_range(decoration.range.start, decoration.range.end),
        "placement": decoration_placement_to_str(decoration.placement),
        "kind": decoration_kind_to_json(decoration.kind),
        "text": decoration.text,
        "styles": decoration.styles,
        "tooltip": decoration.tooltip,
        "data_json": decoration.data_json
    })
}

pub(crate) fn value_fold_region(region: &FoldRegion) -> serde_json::Value {
    serde_json::json!({
        "start_line": region.start_line,
        "end_line": region.end_line,
        "is_collapsed": region.is_collapsed,
        "placeholder": region.placeholder
    })
}

pub(crate) fn value_interval(interval: &Interval) -> serde_json::Value {
    serde_json::json!({
        "start": interval.start,
        "end": interval.end,
        "style_id": interval.style_id
    })
}
