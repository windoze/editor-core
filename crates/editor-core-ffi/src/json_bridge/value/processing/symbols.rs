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
