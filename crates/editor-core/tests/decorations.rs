use editor_core::{
    Decoration, DecorationKind, DecorationLayerId, DecorationPlacement, DecorationRange,
    EditorStateManager, ProcessingEdit, StateChangeType,
};
use std::sync::{Arc, Mutex};

#[test]
fn test_replace_and_clear_decorations() {
    let mut manager = EditorStateManager::new("a👋b\n", 80);

    let seen = Arc::new(Mutex::new(Vec::<StateChangeType>::new()));
    let seen_clone = Arc::clone(&seen);
    manager.subscribe(move |change| {
        seen_clone.lock().unwrap().push(change.change_type);
    });

    let decorations = vec![
        Decoration {
            range: DecorationRange::new(3, 3),
            placement: DecorationPlacement::After,
            kind: DecorationKind::InlayHint,
            text: Some(": u32".to_string()),
            styles: vec![1, 2],
            tooltip: Some("hint".to_string()),
            data_json: None,
        },
        Decoration {
            range: DecorationRange::new(1, 1),
            placement: DecorationPlacement::After,
            kind: DecorationKind::InlayHint,
            text: Some(": emoji".to_string()),
            styles: vec![],
            tooltip: None,
            data_json: Some(r#"{"k":1}"#.to_string()),
        },
    ];

    let initial_version = manager.version();
    assert!(!manager.get_document_state().is_modified);

    manager.apply_processing_edits(vec![ProcessingEdit::ReplaceDecorations {
        layer: DecorationLayerId::INLAY_HINTS,
        decorations: decorations.clone(),
    }]);

    // State is normalized (sorted by range).
    let stored = manager
        .editor()
        .decorations_for_layer(DecorationLayerId::INLAY_HINTS);
    assert_eq!(stored.len(), 2);
    assert_eq!(stored[0].range.start, 1);
    assert_eq!(stored[1].range.start, 3);

    let decorations_state = manager.get_decorations_state();
    assert_eq!(decorations_state.layer_count, 1);
    assert_eq!(decorations_state.decoration_count, 2);
    assert!(!manager.get_document_state().is_modified);
    assert_eq!(manager.version(), initial_version + 1);

    manager.apply_processing_edits(vec![ProcessingEdit::ClearDecorations {
        layer: DecorationLayerId::INLAY_HINTS,
    }]);

    assert!(
        manager
            .editor()
            .decorations_for_layer(DecorationLayerId::INLAY_HINTS)
            .is_empty()
    );
    let decorations_state = manager.get_decorations_state();
    assert_eq!(decorations_state.layer_count, 0);
    assert_eq!(decorations_state.decoration_count, 0);
    assert!(!manager.get_document_state().is_modified);
    assert_eq!(manager.version(), initial_version + 2);

    let seen = seen.lock().unwrap().clone();
    assert_eq!(
        seen,
        vec![
            StateChangeType::DecorationsChanged,
            StateChangeType::DecorationsChanged
        ]
    );
}
