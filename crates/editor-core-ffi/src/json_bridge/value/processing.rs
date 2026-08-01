use super::*;

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
