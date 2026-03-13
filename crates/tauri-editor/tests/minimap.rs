use tauri_editor::EditorBackend;

#[test]
fn minimap_snapshot_returns_fixed_height_samples() {
    let text = "a\n\n   \nhello world\nrust\n";
    let mut backend = EditorBackend::open_text(None, text, 40).unwrap();

    let snap = backend.minimap_snapshot(12).unwrap();
    assert!(snap.total_rows > 0);
    assert_eq!(snap.samples.len(), 12);
    assert!(snap.bucket_size >= 1);
}
