//! Helpers for normalizing LSP "go to" targets.
//!
//! Different servers return either `Location` or `LocationLink` (or arrays of either) for:
//! - `textDocument/definition`
//! - `textDocument/declaration`
//! - `textDocument/typeDefinition`
//! - `textDocument/implementation`
//!
//! This module provides a small, dependency-free normalizer that converts those shapes into a
//! unified list of `(uri, range)` pairs.

use crate::lsp_sync::{LspPosition, LspRange};
use serde_json::Value;

#[derive(Debug, Clone, PartialEq, Eq)]
/// A normalized LSP location (URI + range).
pub struct LspLocation {
    /// Target document URI (e.g. `file:///...`).
    pub uri: String,
    /// Target range within the document.
    pub range: LspRange,
}

fn position_from_value(value: &Value) -> Option<LspPosition> {
    Some(LspPosition {
        line: value.get("line")?.as_u64()? as u32,
        character: value.get("character")?.as_u64()? as u32,
    })
}

fn range_from_value(value: &Value) -> Option<LspRange> {
    Some(LspRange {
        start: position_from_value(value.get("start")?)?,
        end: position_from_value(value.get("end")?)?,
    })
}

fn location_from_value(value: &Value) -> Option<LspLocation> {
    // Location: { uri, range }
    if let (Some(uri), Some(range)) = (
        value.get("uri").and_then(Value::as_str),
        value.get("range").and_then(range_from_value),
    ) {
        return Some(LspLocation {
            uri: uri.to_string(),
            range,
        });
    }

    // LocationLink: { targetUri, targetRange, targetSelectionRange?, originSelectionRange? }
    let target_uri = value.get("targetUri").and_then(Value::as_str)?;

    let range = if let Some(sel) = value.get("targetSelectionRange").and_then(range_from_value) {
        sel
    } else {
        value.get("targetRange").and_then(range_from_value)?
    };

    Some(LspLocation {
        uri: target_uri.to_string(),
        range,
    })
}

/// Normalize a "go to" LSP result (Location | Location[] | LocationLink | LocationLink[]).
pub fn locations_from_value(value: &Value) -> Vec<LspLocation> {
    if value.is_null() {
        return Vec::new();
    }

    if let Some(arr) = value.as_array() {
        return arr.iter().filter_map(location_from_value).collect();
    }

    location_from_value(value).into_iter().collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    #[test]
    fn test_locations_from_location() {
        let v = json!({
            "uri": "file:///a.rs",
            "range": { "start": { "line": 1, "character": 2 }, "end": { "line": 1, "character": 3 } }
        });
        let locs = locations_from_value(&v);
        assert_eq!(locs.len(), 1);
        assert_eq!(locs[0].uri, "file:///a.rs");
        assert_eq!(locs[0].range.start.line, 1);
    }

    #[test]
    fn test_locations_from_location_link_prefers_selection_range() {
        let v = json!({
            "targetUri": "file:///a.rs",
            "targetRange": { "start": { "line": 1, "character": 0 }, "end": { "line": 9, "character": 0 } },
            "targetSelectionRange": { "start": { "line": 2, "character": 4 }, "end": { "line": 2, "character": 8 } }
        });
        let locs = locations_from_value(&v);
        assert_eq!(locs.len(), 1);
        assert_eq!(locs[0].range.start.line, 2);
        assert_eq!(locs[0].range.end.character, 8);
    }
}
