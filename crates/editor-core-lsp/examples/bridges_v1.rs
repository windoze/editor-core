use editor_core::{EditorStateManager, StyleLayerId};
use editor_core_lsp::{
    CompletionTextEditMode, apply_completion_item, lsp_code_lens_to_processing_edit,
    lsp_document_highlights_to_processing_edit, lsp_document_links_to_processing_edit,
};
use serde_json::json;

fn main() {
    let mut state = EditorStateManager::new("fn main() {\n    fo\n}\n", 80);

    // 1) Document highlights → style layer
    let highlights = json!([
        { "range": { "start": { "line": 1, "character": 4 }, "end": { "line": 1, "character": 6 } }, "kind": 1 }
    ]);
    let edit = lsp_document_highlights_to_processing_edit(&state.editor().line_index, &highlights);
    state.apply_processing_edits(vec![edit]);

    let highlight_count = state
        .editor()
        .style_layers
        .get(&StyleLayerId::DOCUMENT_HIGHLIGHTS)
        .map(|tree| tree.query_range(0, state.editor().char_count()).len())
        .unwrap_or(0);
    println!("document highlight intervals: {}", highlight_count);

    // 2) Document links → decorations
    let links = json!([
        {
            "range": { "start": { "line": 0, "character": 3 }, "end": { "line": 0, "character": 7 } },
            "target": "https://example.com",
            "tooltip": "example"
        }
    ]);
    let edit = lsp_document_links_to_processing_edit(&state.editor().line_index, &links);
    state.apply_processing_edits(vec![edit]);

    // 3) Code lens → decorations
    let lenses = json!([
        {
            "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } },
            "command": { "title": "Run (demo)", "command": "demo.run" }
        }
    ]);
    let edit = lsp_code_lens_to_processing_edit(&state.editor().line_index, &lenses);
    state.apply_processing_edits(vec![edit]);

    // 4) Completion apply helpers (additionalTextEdits + snippet-shaped inserts)
    let completion_item = json!({
        "label": "println!",
        "insertTextFormat": 2,
        "textEdit": {
            "range": { "start": { "line": 1, "character": 4 }, "end": { "line": 1, "character": 6 } },
            "newText": "println!(${1:msg})$0"
        },
        "additionalTextEdits": [
            {
                "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } },
                "newText": "use std::io;\n"
            }
        ]
    });

    apply_completion_item(&mut state, &completion_item, CompletionTextEditMode::Insert).unwrap();
    println!("after completion:\n{}", state.editor().get_text());
}
