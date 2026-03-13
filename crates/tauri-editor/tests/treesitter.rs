use tauri_editor::EditorBackend;

#[test]
fn treesitter_rust_highlighting_and_folds_are_applied() {
    // 触发 treesitter 选择逻辑：uri 扩展名为 .rs
    let text = "fn main() {\n  let x = 1;\n}\n";
    let mut backend =
        EditorBackend::open_text(Some("test.rs".to_string()), text, 80).expect("open rust file");

    let snapshot = backend.viewport_snapshot(0, 50).expect("viewport snapshot");

    // 0x0600_0005 = TS_STYLE_KEYWORD（见 tauri-editor/src/backend.rs）
    let ts_keyword: u32 = 0x0600_0005;
    let mut saw_keyword = false;

    for line in &snapshot.lines {
        for run in &line.runs {
            let style_set_id = run.style_set_id() as usize;
            let styles = snapshot.style_sets.get(style_set_id).cloned().unwrap_or_default();
            if styles.contains(&ts_keyword) && run.text().contains("fn") {
                saw_keyword = true;
            }
        }
    }
    assert!(saw_keyword, "expected to see tree-sitter keyword style on `fn`");

    // folds.scm 包含 (function_item) @fold，因此第 0 行应该有 fold 标记（默认未折叠）。
    let fold_line0 = snapshot
        .lines
        .iter()
        .find(|l| l.logical_line == Some(0) && l.visual_in_logical == Some(0))
        .and_then(|l| l.fold.as_ref())
        .expect("expected fold marker on first logical line");
    assert!(!fold_line0.collapsed);
    assert!(fold_line0.end_line >= 1);
}

