use editor_core::{SearchOptions, TextEditSpec, Workspace};

fn main() {
    let mut ws = Workspace::new();
    let a = ws
        .open_document(Some("file:///a.txt".to_string()), "foo bar", 80)
        .unwrap();
    let _b = ws
        .open_document(Some("file:///b.txt".to_string()), "bar foo", 80)
        .unwrap();

    let results = ws
        .search_all_open_documents("foo", SearchOptions::default())
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

    assert_eq!(ws.document(a).unwrap().editor().get_text(), "foo baz");
}
