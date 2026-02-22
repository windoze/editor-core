use editor_core::{LineIndex, Utf16Position, Utf16Range};
use editor_core::{ProcessingEdit, SymbolKind};
use editor_core_lsp::{
    lsp_document_symbols_to_outline, lsp_document_symbols_to_processing_edit,
    lsp_workspace_symbols_to_results,
};
use serde_json::json;

#[test]
fn test_document_symbols_convert_utf16_ranges_to_char_offsets() {
    let text = "a👋b\n";
    let line_index = LineIndex::from_text(text);

    // "a👋b": utf16 columns: a=0..1, 👋=1..3, b=3..4
    let result = json!([
        {
            "name": "emoji",
            "kind": 13,
            "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 3 } },
            "selectionRange": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 3 } },
            "children": []
        }
    ]);

    let outline = lsp_document_symbols_to_outline(&line_index, &result);
    assert_eq!(outline.top_level_count(), 1);
    let sym = &outline.symbols[0];
    assert_eq!(sym.name, "emoji");
    assert_eq!(sym.kind, SymbolKind::Variable);
    assert_eq!(sym.range.start, 1);
    assert_eq!(sym.range.end, 2);
    assert_eq!(sym.selection_range.start, 1);
    assert_eq!(sym.selection_range.end, 2);

    let edit = lsp_document_symbols_to_processing_edit(&line_index, &result);
    match edit {
        ProcessingEdit::ReplaceDocumentSymbols { symbols } => {
            assert_eq!(symbols.top_level_count(), 1);
        }
        other => panic!("unexpected edit: {:?}", other),
    }
}

#[test]
fn test_workspace_symbols_parse_location_utf16_ranges() {
    let result = json!([
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

    let symbols = lsp_workspace_symbols_to_results(&result);
    assert_eq!(symbols.len(), 1);
    let sym = &symbols[0];
    assert_eq!(sym.name, "add");
    assert_eq!(sym.kind, SymbolKind::Function);
    assert_eq!(sym.container_name.as_deref(), Some("math"));
    assert_eq!(sym.location.uri, "file:///demo.rs");
    assert_eq!(
        sym.location.range,
        Utf16Range::new(Utf16Position::new(10, 2), Utf16Position::new(10, 5))
    );
}
