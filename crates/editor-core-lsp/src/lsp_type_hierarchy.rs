//! Typed helpers for LSP type hierarchy payloads.
//!
//! This module parses the small subset of:
//! - `textDocument/prepareTypeHierarchy` → `TypeHierarchyItem[]`
//! - `typeHierarchy/supertypes` → `TypeHierarchyItem[]`
//! - `typeHierarchy/subtypes` → `TypeHierarchyItem[]`
//!
//! It intentionally avoids a full `lsp-types` dependency.

use editor_core::{HierarchyItem, SymbolKind, SymbolLocation, Utf16Position, Utf16Range};
use serde_json::Value;

fn utf16_position_from_value(value: &Value) -> Option<Utf16Position> {
    Some(Utf16Position {
        line: value.get("line")?.as_u64()? as u32,
        character: value.get("character")?.as_u64()? as u32,
    })
}

fn utf16_range_from_value(value: &Value) -> Option<Utf16Range> {
    Some(Utf16Range {
        start: utf16_position_from_value(value.get("start")?)?,
        end: utf16_position_from_value(value.get("end")?)?,
    })
}

/// Parse a single `TypeHierarchyItem` JSON object into a [`HierarchyItem`].
pub fn type_hierarchy_item_from_value(value: &Value) -> Option<HierarchyItem> {
    let name = value.get("name")?.as_str()?.to_string();
    let kind = value.get("kind")?.as_u64()? as u32;
    let uri = value.get("uri")?.as_str()?.to_string();

    let range = utf16_range_from_value(value.get("range")?)?;
    let selection_range = value
        .get("selectionRange")
        .and_then(utf16_range_from_value)
        .unwrap_or(range);

    let detail = value.get("detail").and_then(Value::as_str).map(|s| s.to_string());
    let data_json = value.get("data").map(|v| v.to_string());

    Some(HierarchyItem {
        name,
        detail,
        kind: SymbolKind::from_lsp_kind(kind),
        location: SymbolLocation { uri, range },
        selection_range,
        data_json,
    })
}

/// Parse a `TypeHierarchyItem[] | null` result value.
pub fn type_hierarchy_items_from_value(value: &Value) -> Vec<HierarchyItem> {
    value
        .as_array()
        .map(|arr| {
            arr.iter()
                .filter_map(type_hierarchy_item_from_value)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn type_hierarchy_item_parses_basic_shape() {
        let v = json!({
            "name": "Foo",
            "kind": 23,
            "uri": "file:///a.rs",
            "range": { "start": { "line": 10, "character": 0 }, "end": { "line": 20, "character": 0 } },
            "selectionRange": { "start": { "line": 10, "character": 7 }, "end": { "line": 10, "character": 10 } },
            "detail": "struct Foo",
            "data": { "id": "abc" }
        });

        let item = type_hierarchy_item_from_value(&v).unwrap();
        assert_eq!(item.name, "Foo");
        assert_eq!(item.kind, SymbolKind::Struct);
        assert_eq!(item.location.uri, "file:///a.rs");
        assert_eq!(item.location.range.start.line, 10);
        assert_eq!(item.selection_range.start.character, 7);
        assert_eq!(item.detail.as_deref(), Some("struct Foo"));
        assert_eq!(item.data_json.as_deref(), Some("{\"id\":\"abc\"}"));
    }
}

