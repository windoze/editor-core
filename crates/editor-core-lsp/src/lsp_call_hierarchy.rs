//! Typed helpers for LSP call hierarchy payloads.
//!
//! This module parses the small subset of:
//! - `textDocument/prepareCallHierarchy` → `CallHierarchyItem[]`
//! - `callHierarchy/incomingCalls` → `CallHierarchyIncomingCall[]`
//! - `callHierarchy/outgoingCalls` → `CallHierarchyOutgoingCall[]`
//!
//! It intentionally avoids a full `lsp-types` dependency.

use editor_core::{
    CallHierarchyIncomingCall, CallHierarchyOutgoingCall, HierarchyItem, SymbolKind, SymbolLocation,
    Utf16Position, Utf16Range,
};
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

/// Parse a single `CallHierarchyItem` JSON object into a [`HierarchyItem`].
pub fn call_hierarchy_item_from_value(value: &Value) -> Option<HierarchyItem> {
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

/// Parse a `CallHierarchyItem[] | null` result value.
pub fn call_hierarchy_items_from_value(value: &Value) -> Vec<HierarchyItem> {
    value
        .as_array()
        .map(|arr| {
            arr.iter()
                .filter_map(call_hierarchy_item_from_value)
                .collect::<Vec<_>>()
        })
        .unwrap_or_default()
}

/// Parse an `CallHierarchyIncomingCall[] | null` result value.
pub fn call_hierarchy_incoming_calls_from_value(value: &Value) -> Vec<CallHierarchyIncomingCall> {
    let Some(arr) = value.as_array() else {
        return Vec::new();
    };

    let mut out = Vec::new();
    for v in arr {
        let Some(from_value) = v.get("from") else {
            continue;
        };
        let Some(from) = call_hierarchy_item_from_value(from_value) else {
            continue;
        };
        let from_ranges = v
            .get("fromRanges")
            .and_then(Value::as_array)
            .map(|ranges| {
                ranges
                    .iter()
                    .filter_map(utf16_range_from_value)
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();

        out.push(CallHierarchyIncomingCall { from, from_ranges });
    }

    out
}

/// Parse a `CallHierarchyOutgoingCall[] | null` result value.
pub fn call_hierarchy_outgoing_calls_from_value(value: &Value) -> Vec<CallHierarchyOutgoingCall> {
    let Some(arr) = value.as_array() else {
        return Vec::new();
    };

    let mut out = Vec::new();
    for v in arr {
        let Some(to_value) = v.get("to") else {
            continue;
        };
        let Some(to) = call_hierarchy_item_from_value(to_value) else {
            continue;
        };
        let from_ranges = v
            .get("fromRanges")
            .and_then(Value::as_array)
            .map(|ranges| {
                ranges
                    .iter()
                    .filter_map(utf16_range_from_value)
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();

        out.push(CallHierarchyOutgoingCall { to, from_ranges });
    }

    out
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn call_hierarchy_item_prefers_selection_range() {
        let v = json!({
            "name": "foo",
            "kind": 12,
            "uri": "file:///a.rs",
            "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 9, "character": 0 } },
            "selectionRange": { "start": { "line": 1, "character": 2 }, "end": { "line": 1, "character": 5 } },
            "detail": "fn foo()",
            "data": { "k": 1 }
        });

        let item = call_hierarchy_item_from_value(&v).unwrap();
        assert_eq!(item.name, "foo");
        assert_eq!(item.kind, SymbolKind::Function);
        assert_eq!(item.location.uri, "file:///a.rs");
        assert_eq!(item.location.range.start.line, 0);
        assert_eq!(item.selection_range.start.line, 1);
        assert_eq!(item.selection_range.end.character, 5);
        assert_eq!(item.detail.as_deref(), Some("fn foo()"));
        assert_eq!(item.data_json.as_deref(), Some("{\"k\":1}"));
    }

    #[test]
    fn incoming_calls_parse_from_ranges() {
        let v = json!([
            {
                "from": {
                    "name": "caller",
                    "kind": 12,
                    "uri": "file:///a.rs",
                    "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 10 } },
                    "selectionRange": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 6 } }
                },
                "fromRanges": [
                    { "start": { "line": 0, "character": 3 }, "end": { "line": 0, "character": 6 } }
                ]
            }
        ]);

        let calls = call_hierarchy_incoming_calls_from_value(&v);
        assert_eq!(calls.len(), 1);
        assert_eq!(calls[0].from.name, "caller");
        assert_eq!(calls[0].from_ranges.len(), 1);
        assert_eq!(calls[0].from_ranges[0].start.character, 3);
    }
}

