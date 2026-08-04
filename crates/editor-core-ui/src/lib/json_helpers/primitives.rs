pub(crate) fn value_offset_range(start: usize, end: usize) -> serde_json::Value {
    serde_json::json!({ "start": start, "end": end })
}
