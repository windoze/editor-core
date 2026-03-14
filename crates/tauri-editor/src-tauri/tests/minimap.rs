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

#[test]
fn minimap_density_reflects_line_length() {
    // 注意：不要以 `\n` 结尾，避免额外的末尾空行参与采样导致密度被拉低。
    let text = "x\nxx\nxxx\nxxxx\nxxxxx\nxxxxxx\nxxxxxxx\nxxxxxxxx\nxxxxxxxxx\nxxxxxxxxxx";
    // viewport 宽度=10 cells：密度应随行长度递增（避免“整块纯色”）。
    let mut backend = EditorBackend::open_text(None, text, 10).unwrap();

    let snap = backend.minimap_snapshot(10).unwrap();
    assert_eq!(snap.samples.len(), 10);

    for i in 1..snap.samples.len() {
        assert!(
            snap.samples[i - 1] < snap.samples[i],
            "expected samples to be strictly increasing: idx {}: {} !< {}",
            i,
            snap.samples[i - 1],
            snap.samples[i]
        );
    }
    assert_eq!(snap.samples[9], 255);
}
