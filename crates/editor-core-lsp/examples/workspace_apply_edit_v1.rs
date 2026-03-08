use editor_core::Workspace;
use editor_core_lsp::workspace_sync::{
    apply_workspace_edit_to_workspace, workspace_apply_edit_response,
};
use serde_json::json;

fn main() {
    let mut ws = Workspace::new();
    let _a = ws
        .open_buffer(Some("file:///a".to_string()), "abc\n", 80)
        .unwrap();
    let _b = ws
        .open_buffer(Some("file:///b".to_string()), "xyz\n", 80)
        .unwrap();

    let workspace_edit = json!({
        "changes": {
            "file:///a": [
                { "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 1 } }, "newText": "A" }
            ],
            "file:///b": [
                { "range": { "start": { "line": 0, "character": 3 }, "end": { "line": 0, "character": 3 } }, "newText": "!" }
            ]
        }
    });

    let result = apply_workspace_edit_to_workspace(&mut ws, &workspace_edit).unwrap();
    let response = workspace_apply_edit_response(&result);

    println!("result={:?}", result);
    println!("response={}", response);
}
