use editor_core::EditorStateManager;
use editor_core_lsp::{lsp_document_symbols_to_processing_edit, lsp_workspace_symbols_to_results};
use serde_json::json;

fn main() {
    let mut state = EditorStateManager::new("a👋b\n", 80);

    // `textDocument/documentSymbol` (DocumentSymbol[])
    let document_symbols = json!([
        {
            "name": "emoji",
            "kind": 13,
            "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 3 } },
            "selectionRange": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 3 } },
            "children": []
        }
    ]);

    state.apply_processing_edits(vec![lsp_document_symbols_to_processing_edit(
        &state.editor().line_index,
        &document_symbols,
    )]);

    let outline = &state.editor().document_symbols;
    println!("document symbols: top_level={}", outline.top_level_count());
    for sym in outline.flatten_preorder() {
        println!(
            "- name={} kind={:?} range={}..{}",
            sym.name, sym.kind, sym.range.start, sym.range.end
        );
    }

    // `workspace/symbol` (SymbolInformation[])
    let workspace_symbols = json!([
        {
            "name": "add",
            "kind": 12,
            "containerName": "math",
            "location": {
                "uri": "file:///demo.rs",
                "range": { "start": { "line": 10, "character": 2 }, "end": { "line": 10, "character": 5 } }
            }
        }
    ]);

    let results = lsp_workspace_symbols_to_results(&workspace_symbols);
    println!("workspace symbols: count={}", results.len());
}
