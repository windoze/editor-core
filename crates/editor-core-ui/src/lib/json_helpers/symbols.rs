use super::*;

pub(crate) fn symbol_kind_to_json(value: SymbolKind) -> serde_json::Value {
    match value {
        SymbolKind::File => serde_json::json!({ "kind": "file" }),
        SymbolKind::Module => serde_json::json!({ "kind": "module" }),
        SymbolKind::Namespace => serde_json::json!({ "kind": "namespace" }),
        SymbolKind::Package => serde_json::json!({ "kind": "package" }),
        SymbolKind::Class => serde_json::json!({ "kind": "class" }),
        SymbolKind::Method => serde_json::json!({ "kind": "method" }),
        SymbolKind::Property => serde_json::json!({ "kind": "property" }),
        SymbolKind::Field => serde_json::json!({ "kind": "field" }),
        SymbolKind::Constructor => serde_json::json!({ "kind": "constructor" }),
        SymbolKind::Enum => serde_json::json!({ "kind": "enum" }),
        SymbolKind::Interface => serde_json::json!({ "kind": "interface" }),
        SymbolKind::Function => serde_json::json!({ "kind": "function" }),
        SymbolKind::Variable => serde_json::json!({ "kind": "variable" }),
        SymbolKind::Constant => serde_json::json!({ "kind": "constant" }),
        SymbolKind::String => serde_json::json!({ "kind": "string" }),
        SymbolKind::Number => serde_json::json!({ "kind": "number" }),
        SymbolKind::Boolean => serde_json::json!({ "kind": "boolean" }),
        SymbolKind::Array => serde_json::json!({ "kind": "array" }),
        SymbolKind::Object => serde_json::json!({ "kind": "object" }),
        SymbolKind::Key => serde_json::json!({ "kind": "key" }),
        SymbolKind::Null => serde_json::json!({ "kind": "null" }),
        SymbolKind::EnumMember => serde_json::json!({ "kind": "enum_member" }),
        SymbolKind::Struct => serde_json::json!({ "kind": "struct" }),
        SymbolKind::Event => serde_json::json!({ "kind": "event" }),
        SymbolKind::Operator => serde_json::json!({ "kind": "operator" }),
        SymbolKind::TypeParameter => serde_json::json!({ "kind": "type_parameter" }),
        SymbolKind::Custom(v) => serde_json::json!({ "kind": "custom", "value": v }),
    }
}

pub(crate) fn value_document_symbol(symbol: &DocumentSymbol) -> serde_json::Value {
    serde_json::json!({
        "name": symbol.name,
        "detail": symbol.detail,
        "kind": symbol_kind_to_json(symbol.kind),
        "range": value_offset_range(symbol.range.start, symbol.range.end),
        "selection_range": value_offset_range(symbol.selection_range.start, symbol.selection_range.end),
        "children": symbol.children.iter().map(value_document_symbol).collect::<Vec<_>>(),
        "data_json": symbol.data_json
    })
}
