use super::*;

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
