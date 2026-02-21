use editor_core::{
    Diagnostic, DiagnosticRange, DiagnosticSeverity, EditorStateManager, ProcessingEdit,
    StateChangeType,
};
use std::sync::{Arc, Mutex};

#[test]
fn test_replace_and_clear_diagnostics() {
    let mut manager = EditorStateManager::new("a👋b\nc\n", 80);

    let seen = Arc::new(Mutex::new(Vec::<StateChangeType>::new()));
    let seen_clone = Arc::clone(&seen);
    manager.subscribe(move |change| {
        seen_clone.lock().unwrap().push(change.change_type);
    });

    let diagnostics = vec![
        Diagnostic {
            range: DiagnosticRange::new(0, 1),
            severity: Some(DiagnosticSeverity::Hint),
            code: Some("H1".to_string()),
            source: Some("unit-test".to_string()),
            message: "hello".to_string(),
            related_information_json: None,
            data_json: None,
        },
        Diagnostic {
            range: DiagnosticRange::new(1, 2),
            severity: Some(DiagnosticSeverity::Error),
            code: None,
            source: None,
            message: "emoji".to_string(),
            related_information_json: Some(r#"[{"note":"x"}]"#.to_string()),
            data_json: Some(r#"{"k":1}"#.to_string()),
        },
    ];

    let initial_version = manager.version();
    assert!(!manager.get_document_state().is_modified);

    manager.apply_processing_edits(vec![ProcessingEdit::ReplaceDiagnostics {
        diagnostics: diagnostics.clone(),
    }]);

    assert_eq!(manager.editor().diagnostics(), diagnostics.as_slice());
    assert_eq!(manager.get_diagnostics_state().diagnostics_count, 2);
    assert!(!manager.get_document_state().is_modified);
    assert_eq!(manager.version(), initial_version + 1);

    manager.apply_processing_edits(vec![ProcessingEdit::ClearDiagnostics]);
    assert!(manager.editor().diagnostics().is_empty());
    assert_eq!(manager.get_diagnostics_state().diagnostics_count, 0);
    assert!(!manager.get_document_state().is_modified);
    assert_eq!(manager.version(), initial_version + 2);

    let seen = seen.lock().unwrap().clone();
    assert_eq!(
        seen,
        vec![
            StateChangeType::DiagnosticsChanged,
            StateChangeType::DiagnosticsChanged
        ]
    );
}
