use editor_core::{OpenBufferResult, SearchOptions, TextEditSpec, Workspace};

fn main() {
    let mut ws = Workspace::new();
    let OpenBufferResult { buffer_id: a, .. } = ws
        .open_buffer(Some("file:///a.txt".to_string()), "foo bar", 80)
        .unwrap();
    let _b = ws
        .open_buffer(Some("file:///b.txt".to_string()), "bar foo", 80)
        .unwrap();

    let results = ws
        .search_all_open_buffers("foo", SearchOptions::default())
        .unwrap();
    assert_eq!(results.len(), 2);

    // Apply a simple edit in one document (as a single undoable step).
    ws.apply_text_edits(vec![(
        a,
        vec![TextEditSpec {
            start: 4,
            end: 7,
            text: "baz".to_string(),
        }],
    )])
    .unwrap();

    assert_eq!(ws.buffer_text(a).unwrap(), "foo baz");
}
