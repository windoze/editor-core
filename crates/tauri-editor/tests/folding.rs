use editor_core::{Command, StyleCommand};
use tauri_editor::EditorBackend;

#[test]
fn viewport_snapshot_includes_logical_line_count() {
    let mut backend = EditorBackend::open_text(None, "a\nb\nc", 80).expect("open text");
    let snapshot = backend.viewport_snapshot(0, 10).expect("viewport snapshot");
    assert_eq!(snapshot.logical_line_count, 3);
}

#[test]
fn toggle_fold_updates_snapshot_fold_state() {
    let text = "a\nb\nc\nd";
    let mut backend = EditorBackend::open_text(None, text, 80).expect("open text");

    // 先确保区域存在：折叠 0..=2
    backend
        .toggle_fold(0, 2, false)
        .expect("fold region must be toggled");

    let snapshot = backend.viewport_snapshot(0, 20).expect("viewport snapshot");
    let line0 = snapshot
        .lines
        .iter()
        .find(|l| l.logical_line == Some(0) && l.visual_in_logical == Some(0))
        .expect("line 0 must be visible");
    let fold = line0.fold.as_ref().expect("fold marker must exist");
    assert_eq!(fold.end_line, 2);
    assert!(fold.collapsed);

    // 展开后 fold marker 应该仍存在，但 collapsed=false
    backend
        .toggle_fold(0, 2, true)
        .expect("unfold region must succeed");

    let snapshot2 = backend.viewport_snapshot(0, 20).expect("viewport snapshot");
    let line0_2 = snapshot2
        .lines
        .iter()
        .find(|l| l.logical_line == Some(0) && l.visual_in_logical == Some(0))
        .expect("line 0 must be visible");
    let fold2 = line0_2.fold.as_ref().expect("fold marker must exist");
    assert_eq!(fold2.end_line, 2);
    assert!(!fold2.collapsed);

    // 对外暴露的 StyleCommand 仍应可用（避免 toggle_fold 变成唯一入口）
    let view_id = backend.view_id();
    backend
        .workspace_mut()
        .execute(
            view_id,
            Command::Style(StyleCommand::Fold {
                start_line: 1,
                end_line: 3,
            }),
        )
        .expect("style fold command works");
}

#[test]
fn fallback_brace_folding_produces_markers_for_js_files() {
    let text = "function foo() {\n  if (true) {\n    console.log(1);\n  }\n}\n";
    let mut backend =
        EditorBackend::open_text(Some("test.js".to_string()), text, 80).expect("open js file");

    let snapshot = backend.viewport_snapshot(0, 200).expect("viewport snapshot");

    let line0 = snapshot
        .lines
        .iter()
        .find(|l| l.logical_line == Some(0) && l.visual_in_logical == Some(0))
        .expect("line 0 must be visible");
    let fold0 = line0
        .fold
        .as_ref()
        .expect("expected fallback fold marker on js line 0");
    assert!(fold0.end_line >= 1);

    let line1 = snapshot
        .lines
        .iter()
        .find(|l| l.logical_line == Some(1) && l.visual_in_logical == Some(0))
        .expect("line 1 must be visible");
    let fold1 = line1
        .fold
        .as_ref()
        .expect("expected fallback fold marker on js line 1");
    assert!(fold1.end_line >= 2);
}
