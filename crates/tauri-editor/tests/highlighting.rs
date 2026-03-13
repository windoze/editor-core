use tauri_editor::EditorBackend;

const SIMPLE_STYLE_STRING: u32 = 0x0200_0001;
const SIMPLE_STYLE_NUMBER: u32 = 0x0200_0002;
const SIMPLE_STYLE_BOOLEAN: u32 = 0x0200_0003;

const MD_STYLE_HEADING: u32 = 0x0200_0101;
const MD_STYLE_INLINE_CODE: u32 = 0x0200_0102;
const MD_STYLE_LINK: u32 = 0x0200_0103;

fn snapshot_contains_style_id(
    snapshot: &tauri_editor::snapshot::ViewportSnapshot,
    style_id: u32,
) -> bool {
    snapshot
        .style_sets
        .iter()
        .any(|set| set.contains(&style_id))
}

#[test]
fn markdown_highlighter_applies_heading_inline_code_and_link_styles() {
    let mut backend = EditorBackend::open_text(
        Some("README.md".to_string()),
        "# Title\nSome `code` and a [link](https://example.com)\n",
        80,
    )
    .unwrap();

    let snapshot = backend.viewport_snapshot(0, 32).unwrap();
    assert!(snapshot_contains_style_id(&snapshot, MD_STYLE_HEADING));
    assert!(snapshot_contains_style_id(&snapshot, MD_STYLE_INLINE_CODE));
    assert!(snapshot_contains_style_id(&snapshot, MD_STYLE_LINK));
}

#[test]
fn json_highlighter_applies_string_number_and_boolean_styles() {
    let mut backend =
        EditorBackend::open_text(Some("a.json".to_string()), r#"{ "a": 1, "b": true }"#, 80)
            .unwrap();

    let snapshot = backend.viewport_snapshot(0, 32).unwrap();
    assert!(snapshot_contains_style_id(&snapshot, SIMPLE_STYLE_STRING));
    assert!(snapshot_contains_style_id(&snapshot, SIMPLE_STYLE_NUMBER));
    assert!(snapshot_contains_style_id(&snapshot, SIMPLE_STYLE_BOOLEAN));
}

#[test]
fn highlighting_refreshes_after_edit() {
    let mut backend = EditorBackend::open_text(Some("a.json".to_string()), "{}", 80).unwrap();

    let snapshot = backend.viewport_snapshot(0, 8).unwrap();
    assert!(!snapshot_contains_style_id(&snapshot, SIMPLE_STYLE_STRING));

    backend.insert_text(r#""a": 1"#.to_string()).unwrap();

    let snapshot = backend.viewport_snapshot(0, 8).unwrap();
    assert!(snapshot_contains_style_id(&snapshot, SIMPLE_STYLE_STRING));
    assert!(snapshot_contains_style_id(&snapshot, SIMPLE_STYLE_NUMBER));
}
