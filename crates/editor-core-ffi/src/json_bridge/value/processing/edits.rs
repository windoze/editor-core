use super::*;

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
