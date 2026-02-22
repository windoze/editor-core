use editor_core::{
    DocumentOutline, DocumentSymbol, EditorStateManager, ProcessingEdit, StateChangeType,
    SymbolKind, SymbolRange,
};
use std::sync::{Arc, Mutex};

#[test]
fn test_replace_and_clear_document_symbols() {
    let mut manager = EditorStateManager::new("x\n", 80);

    let seen = Arc::new(Mutex::new(Vec::<StateChangeType>::new()));
    let seen_clone = Arc::clone(&seen);
    manager.subscribe(move |change| {
        seen_clone.lock().unwrap().push(change.change_type);
    });

    let outline = DocumentOutline::new(vec![DocumentSymbol {
        name: "x".to_string(),
        detail: None,
        kind: SymbolKind::Variable,
        range: SymbolRange::new(0, 1),
        selection_range: SymbolRange::new(0, 1),
        children: Vec::new(),
        data_json: Some(r#"{"k":1}"#.to_string()),
    }]);

    manager.apply_processing_edits(vec![ProcessingEdit::ReplaceDocumentSymbols {
        symbols: outline.clone(),
    }]);

    assert_eq!(manager.editor().document_symbols, outline);

    manager.apply_processing_edits(vec![ProcessingEdit::ClearDocumentSymbols]);
    assert!(manager.editor().document_symbols.is_empty());

    let seen = seen.lock().unwrap().clone();
    assert_eq!(
        seen,
        vec![
            StateChangeType::SymbolsChanged,
            StateChangeType::SymbolsChanged
        ]
    );
}
