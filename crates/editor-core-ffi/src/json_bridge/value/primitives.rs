use super::*;

pub(crate) fn value_position(value: Position) -> Value {
    json!({ "line": value.line, "column": value.column })
}

pub(crate) fn value_selection(value: &Selection) -> Value {
    json!({
        "start": value_position(value.start),
        "end": value_position(value.end),
        "direction": selection_direction_to_str(value.direction)
    })
}

pub(crate) fn value_offset_range(start: usize, end: usize) -> Value {
    json!({ "start": start, "end": end })
}

pub(crate) fn value_utf16_position(value: Utf16Position) -> Value {
    json!({ "line": value.line, "character": value.character })
}

pub(crate) fn value_utf16_range(value: Utf16Range) -> Value {
    json!({
        "start": value_utf16_position(value.start),
        "end": value_utf16_position(value.end)
    })
}

pub(crate) fn value_symbol_location(value: &SymbolLocation) -> Value {
    json!({
        "uri": value.uri,
        "range": value_utf16_range(value.range)
    })
}
