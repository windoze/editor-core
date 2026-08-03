use editor_core::SearchOptions;
use editor_core_lsp::path_to_file_uri;
use editor_core_ui::MultiDocumentEditorUi;
use serde_json::json;
use std::collections::BTreeSet;
use std::path::PathBuf;

fn unique_test_dir(prefix: &str) -> PathBuf {
    let unique = format!(
        "{}-{}-{}",
        prefix,
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    );
    std::env::temp_dir().join(unique)
}

#[test]
fn multi_document_ui_can_open_switch_and_close_tabs() {
    let mut ui = MultiDocumentEditorUi::new();

    let a = ui.open_tab("hello", 80);
    let b = ui.open_tab("world", 80);

    assert_eq!(ui.active_tab_id(), Some(a));
    ui.set_active_tab(b).unwrap();
    assert_eq!(ui.active_tab_id(), Some(b));

    assert!(ui.close_tab(b));
    assert_eq!(ui.active_tab_id(), Some(a));
    assert!(ui.close_tab(a));
    assert_eq!(ui.active_tab_id(), None);
}

#[test]
fn multi_document_ui_tabs_are_independent_documents() {
    let mut ui = MultiDocumentEditorUi::new();

    let a = ui.open_tab("A", 80);
    let b = ui.open_tab("B", 80);

    ui.set_active_tab(a).unwrap();
    ui.active_editor_mut().unwrap().insert_text("!").unwrap();
    assert_eq!(ui.active_editor().unwrap().text(), "!A");

    ui.set_active_tab(b).unwrap();
    assert_eq!(ui.active_editor().unwrap().text(), "B");
}

#[test]
fn multi_document_ui_tracks_tab_document_uri() {
    let mut ui = MultiDocumentEditorUi::new();
    let tab = ui.open_tab("hello", 80);

    assert_eq!(ui.tab_document_uri(tab), None);
    ui.set_tab_document_uri(tab, Some("file:///tmp/project/App.swift".to_string()))
        .unwrap();
    assert_eq!(
        ui.tab_document_uri(tab),
        Some("file:///tmp/project/App.swift")
    );

    ui.set_tab_document_uri(tab, None).unwrap();
    assert_eq!(ui.tab_document_uri(tab), None);
}

#[test]
fn multi_document_ui_can_move_tabs() {
    let mut ui = MultiDocumentEditorUi::new();
    let a = ui.open_tab("a", 80);
    let b = ui.open_tab("b", 80);
    let c = ui.open_tab("c", 80);

    ui.set_active_tab(b).unwrap();
    assert!(ui.move_tab_index(1, 0).unwrap());
    assert_eq!(ui.tab_ids(), vec![b, a, c]);
    assert_eq!(ui.active_tab_id(), Some(b));

    assert!(ui.move_tab_index(2, 1).unwrap());
    assert_eq!(ui.tab_ids(), vec![b, c, a]);

    assert!(!ui.move_tab_index(1, 1).unwrap());
    assert!(!ui.move_tab_index(3, 0).unwrap());

    let closed = ui.close_tabs_to_right(b).unwrap();
    assert_eq!(closed, 2);
    assert_eq!(ui.tab_ids(), vec![b]);
    assert_eq!(ui.active_tab_id(), Some(b));
}

#[test]
fn multi_document_ui_supports_splits_via_clone_view() {
    let mut ui = MultiDocumentEditorUi::new();
    let tab = ui.open_tab("abc\n", 80);

    // Put the original view's caret at EOF so we can observe delta propagation.
    ui.set_active_tab(tab).unwrap();
    ui.active_editor_mut()
        .unwrap()
        .set_selections_offsets(&[(4, 4)], 0)
        .unwrap();

    // Create a split; new view becomes active.
    let new_view_idx = ui.split_tab(tab, 80).unwrap();
    assert_eq!(ui.view_count(tab), Some(2));
    assert_eq!(new_view_idx, 1);

    // Edit in the split view.
    ui.active_editor_mut()
        .unwrap()
        .set_selections_offsets(&[(0, 0)], 0)
        .unwrap();
    ui.active_editor_mut().unwrap().insert_text("X").unwrap();
    assert_eq!(ui.active_editor().unwrap().text(), "Xabc\n");

    // Switch back to the original view; text is shared, but view state is independent.
    ui.set_active_view_index(tab, 0).unwrap();
    assert_eq!(ui.active_editor().unwrap().text(), "Xabc\n");
    assert_eq!(
        ui.active_editor().unwrap().primary_selection_offsets(),
        (5, 5)
    );
}

#[test]
fn multi_document_ui_can_move_split_views() {
    let mut ui = MultiDocumentEditorUi::new();
    let tab = ui.open_tab("abc\n", 80);

    ui.set_active_tab(tab).unwrap();
    ui.set_active_view_index(tab, 0).unwrap();
    ui.active_editor_mut()
        .unwrap()
        .set_selections_offsets(&[(0, 0)], 0)
        .unwrap();

    assert_eq!(ui.split_tab(tab, 80).unwrap(), 1);
    ui.active_editor_mut()
        .unwrap()
        .set_selections_offsets(&[(1, 1)], 0)
        .unwrap();

    assert_eq!(ui.split_tab(tab, 80).unwrap(), 2);
    ui.active_editor_mut()
        .unwrap()
        .set_selections_offsets(&[(2, 2)], 0)
        .unwrap();

    assert!(ui.move_view_index(tab, 2, 0).unwrap());
    assert_eq!(ui.active_view_index(tab), Some(0));
    assert_eq!(
        ui.active_editor().unwrap().primary_selection_offsets(),
        (2, 2)
    );

    ui.set_active_view_index(tab, 1).unwrap();
    assert_eq!(
        ui.active_editor().unwrap().primary_selection_offsets(),
        (0, 0)
    );
    ui.set_active_view_index(tab, 2).unwrap();
    assert_eq!(
        ui.active_editor().unwrap().primary_selection_offsets(),
        (1, 1)
    );

    assert!(!ui.move_view_index(tab, 2, 2).unwrap());
    assert!(!ui.move_view_index(tab, 2, 3).unwrap());
}

#[test]
fn multi_document_ui_can_search_across_tabs() {
    let mut ui = MultiDocumentEditorUi::new();
    let a = ui.open_tab("hello world\n", 80);
    let _b = ui.open_tab("no match here\n", 80);

    let results = ui
        .search_all_tabs("world", SearchOptions::default())
        .unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].tab_id, a);
    assert_eq!(results[0].matches.len(), 1);
}

#[test]
fn multi_document_ui_search_uses_tab_word_boundary_config() {
    let mut ui = MultiDocumentEditorUi::new();
    let tab = ui.open_tab("foo-bar bar\n", 80);
    let options = SearchOptions {
        case_sensitive: true,
        whole_word: true,
        regex: false,
    };

    let default_results = ui.search_all_tabs("bar", options).unwrap();
    assert_eq!(default_results.len(), 1);
    assert_eq!(default_results[0].tab_id, tab);
    assert_eq!(default_results[0].matches.len(), 2);

    ui.editor_for_tab_mut(tab)
        .unwrap()
        .set_word_boundary_ascii_boundary_chars(".")
        .unwrap();

    let configured_results = ui.search_all_tabs("bar", options).unwrap();
    assert_eq!(configured_results.len(), 1);
    assert_eq!(configured_results[0].tab_id, tab);
    assert_eq!(configured_results[0].matches.len(), 1);
    assert_eq!(configured_results[0].matches[0].start, 8);
}

#[test]
fn multi_document_ui_exports_workspace_outline_snapshot() {
    let mut ui = MultiDocumentEditorUi::new();
    let app = ui.open_tab("struct App {\n  func run() {}\n}\n", 80);
    let model = ui.open_tab("final class Model {}\n", 80);
    ui.set_tab_title(app, Some("App.swift".to_string()))
        .unwrap();
    ui.set_tab_title(model, Some("Model.swift".to_string()))
        .unwrap();
    ui.set_tab_document_uri(app, Some("file:///tmp/project/App.swift".to_string()))
        .unwrap();
    ui.set_tab_document_uri(model, Some("file:///tmp/project/Model.swift".to_string()))
        .unwrap();

    ui.apply_tab_document_symbols_json(
        app,
        r#"[
          {
            "name": "App",
            "kind": 23,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 2, "character": 1 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 7 },
              "end": { "line": 0, "character": 10 }
            },
            "children": [
              {
                "name": "run",
                "kind": 12,
                "range": {
                  "start": { "line": 1, "character": 2 },
                  "end": { "line": 1, "character": 15 }
                },
                "selectionRange": {
                  "start": { "line": 1, "character": 7 },
                  "end": { "line": 1, "character": 10 }
                }
              }
            ]
          }
        ]"#,
    )
    .unwrap();
    ui.apply_tab_document_symbols_json(
        model,
        r#"[
          {
            "name": "Model",
            "kind": 5,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 20 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 12 },
              "end": { "line": 0, "character": 17 }
            }
          }
        ]"#,
    )
    .unwrap();

    let snapshot = ui.workspace_outline_snapshot().unwrap();
    assert_eq!(snapshot.documents.len(), 2);
    assert_eq!(snapshot.documents[0].tab_id, app.get());
    assert_eq!(snapshot.documents[0].title.as_deref(), Some("App.swift"));
    assert_eq!(
        snapshot.documents[0].document_uri.as_deref(),
        Some("file:///tmp/project/App.swift")
    );
    assert_eq!(snapshot.documents[0].symbol_count, 2);
    assert_eq!(snapshot.documents[0].symbols[0]["name"], "App");
    assert_eq!(
        snapshot.documents[0].symbols[0]["children"][0]["name"],
        "run"
    );
    assert_eq!(snapshot.documents[1].tab_id, model.get());
    assert_eq!(snapshot.documents[1].title.as_deref(), Some("Model.swift"));
    assert_eq!(snapshot.documents[1].symbols[0]["name"], "Model");

    let json: serde_json::Value =
        serde_json::from_str(&ui.workspace_outline_snapshot_json().unwrap()).unwrap();
    assert_eq!(json["documents"][0]["tab_id"], app.get());
    assert_eq!(
        json["documents"][0]["document_uri"],
        "file:///tmp/project/App.swift"
    );
    assert_eq!(json["documents"][0]["symbol_count"], 2);
}

#[test]
fn multi_document_ui_previews_and_applies_workspace_edit_transactions() {
    let mut ui = MultiDocumentEditorUi::new();
    let app = ui.open_tab("alpha\n", 80);
    let model = ui.open_tab("model\n", 80);
    ui.set_tab_document_uri(app, Some("file:///tmp/project/App.swift".to_string()))
        .unwrap();
    ui.set_tab_document_uri(model, Some("file:///tmp/project/Model.swift".to_string()))
        .unwrap();

    let edit = r#"{
      "changes": {
        "file:///tmp/project/App.swift": [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 5 }
            },
            "newText": "App"
          }
        ],
        "file:///tmp/project/Other.swift": [
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 0 }
            },
            "newText": "Other"
          }
        ]
      },
      "documentChanges": [
        {
          "kind": "rename",
          "oldUri": "file:///tmp/project/Old.swift",
          "newUri": "file:///tmp/project/New.swift"
        }
      ]
    }"#;

    let preview = ui.preview_workspace_edit_transaction(edit).unwrap();
    assert_eq!(preview.mode, "preview");
    assert!(!preview.applied);
    assert_eq!(ui.tab_text(app).unwrap(), "alpha\n");
    assert_eq!(
        preview.skipped_uris,
        vec![
            "file:///tmp/project/New.swift",
            "file:///tmp/project/Old.swift",
            "file:///tmp/project/Other.swift",
        ]
    );

    let applied = ui.apply_workspace_edit_transaction(edit).unwrap();
    assert_eq!(applied.mode, "apply");
    assert!(applied.applied);
    assert_eq!(applied.applied_uris, vec!["file:///tmp/project/App.swift"]);
    assert_eq!(applied.applied_edit_count, 1);
    assert_eq!(applied.applied_resource_operation_count, 0);
    assert_eq!(ui.tab_text(app).unwrap(), "App\n");
    assert_eq!(ui.tab_text(model).unwrap(), "model\n");
    assert_eq!(
        applied.unsupported_operation_uris,
        vec![
            "file:///tmp/project/New.swift",
            "file:///tmp/project/Old.swift"
        ]
    );

    let events = ui.workspace_edit_transaction_events_after(0);
    assert_eq!(events.latest_sequence, 1);
    assert_eq!(events.events.len(), 1);
    assert_eq!(events.events[0].sequence, 1);
    assert_eq!(events.events[0].operation, "apply");
    assert_eq!(events.events[0].result.applied_uris, applied.applied_uris);

    let json: serde_json::Value =
        serde_json::from_str(&ui.preview_workspace_edit_transaction_json(edit).unwrap()).unwrap();
    assert_eq!(json["mode"], "preview");
    assert_eq!(json["documents"][0]["uri"], "file:///tmp/project/App.swift");

    let events_json: serde_json::Value =
        serde_json::from_str(&ui.workspace_edit_transaction_events_json(0).unwrap()).unwrap();
    assert_eq!(events_json["latest_sequence"], 1);
    assert_eq!(events_json["events"][0]["result"]["mode"], "apply");
}

#[test]
fn multi_document_ui_atomic_workspace_edit_preflight_skips_without_mutating() {
    let mut ui = MultiDocumentEditorUi::new();
    let app = ui.open_tab("alpha\n", 80);
    let dirty = ui.open_tab("dirty\n", 80);
    ui.set_tab_document_uri(app, Some("file:///tmp/project/App.swift".to_string()))
        .unwrap();
    ui.set_tab_document_uri(dirty, Some("file:///tmp/project/Dirty.swift".to_string()))
        .unwrap();
    ui.replace_tab_text(dirty, "dirty changed\n", false)
        .unwrap();

    let edit = json!({
        "applyMode": "atomic",
        "workspaceEdit": {
            "documentChanges": [
                {
                    "textDocument": {
                        "uri": "file:///tmp/project/App.swift",
                        "version": null
                    },
                    "edits": [
                        {
                            "range": {
                                "start": { "line": 0, "character": 0 },
                                "end": { "line": 0, "character": 5 }
                            },
                            "newText": "App"
                        }
                    ]
                },
                {
                    "kind": "delete",
                    "uri": "file:///tmp/project/Dirty.swift"
                }
            ]
        }
    })
    .to_string();

    let preview = ui
        .preview_workspace_edit_transaction(edit.as_str())
        .unwrap();
    assert_eq!(preview.mode, "preview");
    assert_eq!(preview.apply_mode, "atomic");
    assert!(!preview.applied);
    assert!(
        preview
            .skipped_uris
            .contains(&"file:///tmp/project/Dirty.swift".to_string())
    );

    let applied = ui.apply_workspace_edit_transaction(edit.as_str()).unwrap();
    assert_eq!(applied.mode, "apply");
    assert_eq!(applied.apply_mode, "atomic");
    assert!(!applied.applied);
    assert_eq!(applied.applied_edit_count, 0);
    assert_eq!(applied.applied_resource_operation_count, 0);
    assert!(applied.applied_uris.is_empty());
    assert!(applied.skipped_details.iter().any(|detail| {
        detail.uri == "file:///tmp/project/Dirty.swift"
            && detail.operation.as_deref() == Some("delete")
            && detail.reason == "resource_operation_dirty_target"
    }));
    assert_eq!(ui.tab_text(app).unwrap(), "alpha\n");
    assert_eq!(ui.tab_text(dirty).unwrap(), "dirty changed\n");
    assert!(ui.is_tab_modified(dirty).unwrap());

    let events = ui.workspace_edit_transaction_events_after(0);
    assert_eq!(events.latest_sequence, 1);
    assert_eq!(events.events[0].result.apply_mode, "atomic");
    assert!(!events.events[0].result.applied);
}

#[test]
fn multi_document_ui_atomic_workspace_edit_rolls_back_runtime_text_failure() {
    let root = unique_test_dir("atomic-runtime-text-failure");
    std::fs::create_dir_all(&root).unwrap();
    let first_path = root.join("First.swift");
    let bad_path = root.join("Bad.swift");
    std::fs::write(&bad_path, [0xff]).unwrap();
    let first_uri = path_to_file_uri(first_path.as_path());
    let bad_uri = path_to_file_uri(bad_path.as_path());
    let root_uri = path_to_file_uri(root.as_path());

    let mut ui = MultiDocumentEditorUi::new();
    let first = ui.open_tab("alpha\n", 80);
    ui.set_workspace_roots([root_uri]);
    ui.set_tab_document_uri(first, Some(first_uri.clone()))
        .unwrap();

    let edit = json!({
        "applyMode": "atomic",
        "workspaceEdit": {
            "documentChanges": [
                {
                    "textDocument": {
                        "uri": first_uri.as_str(),
                        "version": null
                    },
                    "edits": [
                        {
                            "range": {
                                "start": { "line": 0, "character": 0 },
                                "end": { "line": 0, "character": 5 }
                            },
                            "newText": "ALPHA"
                        }
                    ]
                },
                {
                    "textDocument": {
                        "uri": bad_uri.as_str(),
                        "version": null
                    },
                    "edits": [
                        {
                            "range": {
                                "start": { "line": 0, "character": 0 },
                                "end": { "line": 0, "character": 0 }
                            },
                            "newText": "invalid"
                        }
                    ]
                }
            ]
        }
    })
    .to_string();

    let preview = ui
        .preview_workspace_edit_transaction(edit.as_str())
        .unwrap();
    assert_eq!(preview.apply_mode, "atomic");
    assert!(preview.skipped_details.is_empty());

    let applied = ui.apply_workspace_edit_transaction(edit.as_str()).unwrap();
    assert_eq!(applied.mode, "apply");
    assert_eq!(applied.apply_mode, "atomic");
    assert!(!applied.applied);
    assert!(applied.applied_uris.is_empty());
    assert_eq!(applied.applied_edit_count, 0);
    assert_eq!(applied.applied_resource_operation_count, 0);
    assert!(applied.skipped_details.iter().any(|detail| {
        detail.uri == bad_uri
            && detail.operation.as_deref() == Some("text_edit")
            && detail.reason == "file_text_edit_read_failed"
    }));
    assert_eq!(ui.tab_text(first).unwrap(), "alpha\n");
    assert_eq!(std::fs::read(&bad_path).unwrap(), vec![0xff]);

    let events = ui.workspace_edit_transaction_events_after(0);
    assert_eq!(events.latest_sequence, 1);
    assert_eq!(events.events[0].result.apply_mode, "atomic");
    assert!(!events.events[0].result.applied);
    assert!(events.events[0].result.applied_uris.is_empty());

    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn multi_document_ui_tracks_workspace_roots() {
    let mut ui = MultiDocumentEditorUi::new();

    let initial_change = ui.set_workspace_roots_with_change([
        "file:///tmp/project".to_string(),
        "file:///tmp/project".to_string(),
        String::new(),
        "file:///tmp/other".to_string(),
    ]);
    assert_eq!(initial_change.added.len(), 2);
    assert_eq!(initial_change.added[0].uri, "file:///tmp/project");
    assert_eq!(initial_change.added[0].name, "project");
    assert_eq!(initial_change.added[1].uri, "file:///tmp/other");
    assert_eq!(initial_change.added[1].name, "other");
    assert!(initial_change.removed.is_empty());

    let expected = vec![
        "file:///tmp/project".to_string(),
        "file:///tmp/other".to_string(),
    ];
    assert_eq!(ui.workspace_roots(), expected.as_slice());

    let next_change = ui.set_workspace_roots_with_change([
        "file:///tmp/other".to_string(),
        "file:///tmp/new".to_string(),
        "file:///tmp/new".to_string(),
    ]);
    assert_eq!(next_change.added.len(), 1);
    assert_eq!(next_change.added[0].uri, "file:///tmp/new");
    assert_eq!(next_change.added[0].name, "new");
    assert_eq!(next_change.removed.len(), 1);
    assert_eq!(next_change.removed[0].uri, "file:///tmp/project");
    assert_eq!(next_change.removed[0].name, "project");
    assert_eq!(
        ui.workspace_roots(),
        &[
            "file:///tmp/other".to_string(),
            "file:///tmp/new".to_string()
        ]
    );
}

#[test]
fn multi_document_ui_applies_unopened_workspace_file_text_edits() {
    let root = unique_test_dir("editor-core-ui-workspace-edit-root");
    let outside_root = unique_test_dir("editor-core-ui-workspace-edit-outside");
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::create_dir_all(&outside_root).unwrap();

    let target = root.join("src").join("App.swift");
    let versioned = root.join("src").join("Versioned.swift");
    let outside = outside_root.join("Outside.swift");
    std::fs::write(&target, "alpha\nbeta\n").unwrap();
    std::fs::write(&versioned, "versioned\n").unwrap();
    std::fs::write(&outside, "outside\n").unwrap();

    let root_uri = path_to_file_uri(root.as_path());
    let target_uri = path_to_file_uri(target.as_path());
    let versioned_uri = path_to_file_uri(versioned.as_path());
    let outside_uri = path_to_file_uri(outside.as_path());

    let mut ui = MultiDocumentEditorUi::new();
    ui.set_workspace_roots([root_uri]);

    let edit = json!({
        "changes": {
            (target_uri.as_str()): [
                {
                    "range": {
                        "start": { "line": 1, "character": 0 },
                        "end": { "line": 1, "character": 4 }
                    },
                    "newText": "BETA"
                }
            ],
            (outside_uri.as_str()): [
                {
                    "range": {
                        "start": { "line": 0, "character": 0 },
                        "end": { "line": 0, "character": 0 }
                    },
                    "newText": "changed "
                }
            ]
        },
        "documentChanges": [
            {
                "textDocument": {
                    "uri": versioned_uri.as_str(),
                    "version": 7
                },
                "edits": [
                    {
                        "range": {
                            "start": { "line": 0, "character": 0 },
                            "end": { "line": 0, "character": 0 }
                        },
                        "newText": "stale "
                    }
                ]
            }
        ]
    })
    .to_string();

    let preview = ui
        .preview_workspace_edit_transaction(edit.as_str())
        .unwrap();
    assert_eq!(preview.mode, "preview");
    assert!(!preview.applied);
    assert_eq!(std::fs::read_to_string(&target).unwrap(), "alpha\nbeta\n");
    let target_document = preview
        .documents
        .iter()
        .find(|doc| doc.uri == target_uri)
        .unwrap();
    assert_eq!(target_document.edit_count, 1);
    assert!(!target_document.is_open);
    assert_eq!(target_document.tab_id, None);
    assert!(preview.skipped_uris.contains(&outside_uri));
    assert!(preview.skipped_uris.contains(&versioned_uri));
    assert!(preview.skipped_details.iter().any(|detail| {
        detail.uri == outside_uri
            && detail.operation.as_deref() == Some("text_edit")
            && detail.reason == "document_outside_workspace"
    }));
    assert!(preview.skipped_details.iter().any(|detail| {
        detail.uri == versioned_uri
            && detail.operation.as_deref() == Some("text_edit")
            && detail.reason == "version_unavailable"
    }));

    let applied = ui.apply_workspace_edit_transaction(edit.as_str()).unwrap();
    assert!(applied.applied);
    assert_eq!(applied.applied_uris, vec![target_uri.clone()]);
    assert_eq!(applied.applied_edit_count, 1);
    assert_eq!(applied.applied_resource_operation_count, 0);
    assert!(applied.skipped_uris.contains(&outside_uri));
    assert!(applied.skipped_uris.contains(&versioned_uri));
    assert_eq!(std::fs::read_to_string(&target).unwrap(), "alpha\nBETA\n");
    assert_eq!(std::fs::read_to_string(&versioned).unwrap(), "versioned\n");
    assert_eq!(std::fs::read_to_string(&outside).unwrap(), "outside\n");

    let events = ui.workspace_edit_transaction_events_after(0);
    assert_eq!(events.latest_sequence, 1);
    assert_eq!(events.events[0].result.applied_uris, vec![target_uri]);

    let _ = std::fs::remove_dir_all(root);
    let _ = std::fs::remove_dir_all(outside_root);
}

#[test]
fn multi_document_ui_applies_unopened_workspace_file_resource_operations() {
    let root = unique_test_dir("editor-core-ui-workspace-resource-root");
    let outside_root = unique_test_dir("editor-core-ui-workspace-resource-outside");
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::create_dir_all(&outside_root).unwrap();

    let old = root.join("src").join("Old.swift");
    let renamed = root.join("src").join("Renamed.swift");
    let created = root.join("generated").join("Created.swift");
    let deleted = root.join("src").join("Deleted.swift");
    let non_recursive_dir = root.join("src").join("Folder");
    let outside = outside_root.join("Outside.swift");
    std::fs::write(&old, "old\n").unwrap();
    std::fs::write(&deleted, "delete me\n").unwrap();
    std::fs::create_dir_all(&non_recursive_dir).unwrap();

    let root_uri = path_to_file_uri(root.as_path());
    let old_uri = path_to_file_uri(old.as_path());
    let renamed_uri = path_to_file_uri(renamed.as_path());
    let created_uri = path_to_file_uri(created.as_path());
    let deleted_uri = path_to_file_uri(deleted.as_path());
    let non_recursive_dir_uri = path_to_file_uri(non_recursive_dir.as_path());
    let outside_uri = path_to_file_uri(outside.as_path());

    let mut ui = MultiDocumentEditorUi::new();
    ui.set_workspace_roots([root_uri]);

    let edit = json!({
        "documentChanges": [
            {
                "kind": "create",
                "uri": created_uri.as_str()
            },
            {
                "textDocument": {
                    "uri": created_uri.as_str(),
                    "version": null
                },
                "edits": [
                    {
                        "range": {
                            "start": { "line": 0, "character": 0 },
                            "end": { "line": 0, "character": 0 }
                        },
                        "newText": "created\n"
                    }
                ]
            },
            {
                "kind": "rename",
                "oldUri": old_uri.as_str(),
                "newUri": renamed_uri.as_str()
            },
            {
                "textDocument": {
                    "uri": renamed_uri.as_str(),
                    "version": null
                },
                "edits": [
                    {
                        "range": {
                            "start": { "line": 0, "character": 0 },
                            "end": { "line": 0, "character": 0 }
                        },
                        "newText": "renamed "
                    }
                ]
            },
            {
                "kind": "delete",
                "uri": deleted_uri.as_str()
            },
            {
                "kind": "delete",
                "uri": non_recursive_dir_uri.as_str()
            },
            {
                "kind": "create",
                "uri": outside_uri.as_str()
            }
        ]
    })
    .to_string();

    let preview = ui
        .preview_workspace_edit_transaction(edit.as_str())
        .unwrap();
    assert_eq!(preview.mode, "preview");
    assert!(!preview.applied);
    assert!(!created.exists());
    assert!(old.exists());
    assert!(!renamed.exists());
    assert!(deleted.exists());
    assert!(preview.skipped_uris.contains(&outside_uri));
    assert!(preview.skipped_uris.contains(&non_recursive_dir_uri));
    assert!(preview.skipped_details.iter().any(|detail| {
        detail.uri == outside_uri
            && detail.operation.as_deref() == Some("create")
            && detail.reason == "document_outside_workspace"
    }));
    assert!(preview.skipped_details.iter().any(|detail| {
        detail.uri == non_recursive_dir_uri
            && detail.operation.as_deref() == Some("delete")
            && detail.reason == "resource_operation_delete_directory_requires_recursive"
    }));

    let applied = ui.apply_workspace_edit_transaction(edit.as_str()).unwrap();
    assert!(applied.applied);
    assert_eq!(applied.applied_edit_count, 2);
    assert_eq!(applied.applied_resource_operation_count, 3);
    assert!(applied.applied_uris.contains(&created_uri));
    assert!(applied.applied_uris.contains(&old_uri));
    assert!(applied.applied_uris.contains(&renamed_uri));
    assert!(applied.applied_uris.contains(&deleted_uri));
    assert!(applied.skipped_uris.contains(&outside_uri));
    assert!(applied.skipped_uris.contains(&non_recursive_dir_uri));
    assert_eq!(std::fs::read_to_string(&created).unwrap(), "created\n");
    assert!(!old.exists());
    assert_eq!(std::fs::read_to_string(&renamed).unwrap(), "renamed old\n");
    assert!(!deleted.exists());
    assert!(non_recursive_dir.exists());
    assert!(!outside.exists());

    let events = ui.workspace_edit_transaction_events_after(0);
    assert_eq!(events.latest_sequence, 1);
    assert_eq!(events.events[0].result.applied_resource_operation_count, 3);

    let _ = std::fs::remove_dir_all(root);
    let _ = std::fs::remove_dir_all(outside_root);
}

#[test]
fn multi_document_ui_rolls_back_unopened_resource_operations_after_runtime_failure() {
    let root = unique_test_dir("editor-core-ui-workspace-resource-rollback-root");
    std::fs::create_dir_all(root.join("src")).unwrap();

    let old = root.join("src").join("Old.swift");
    let target = root.join("src").join("Target.swift");
    let created = root.join("generated").join("Created.swift");
    let blocker = root.join("blocker");
    let blocked_child = blocker.join("Child.swift");
    std::fs::write(&old, "old\n").unwrap();
    std::fs::write(&target, "target\n").unwrap();
    std::fs::write(&blocker, "blocker\n").unwrap();

    let root_uri = path_to_file_uri(root.as_path());
    let old_uri = path_to_file_uri(old.as_path());
    let target_uri = path_to_file_uri(target.as_path());
    let created_uri = path_to_file_uri(created.as_path());
    let blocked_child_uri = path_to_file_uri(blocked_child.as_path());

    let mut ui = MultiDocumentEditorUi::new();
    ui.set_workspace_roots([root_uri]);

    let edit = json!({
        "documentChanges": [
            {
                "kind": "create",
                "uri": created_uri.as_str()
            },
            {
                "kind": "rename",
                "oldUri": old_uri.as_str(),
                "newUri": target_uri.as_str(),
                "options": { "overwrite": true }
            },
            {
                "kind": "create",
                "uri": blocked_child_uri.as_str()
            }
        ]
    })
    .to_string();

    let preview = ui
        .preview_workspace_edit_transaction(edit.as_str())
        .unwrap();
    assert!(preview.skipped_uris.is_empty());
    assert!(!created.exists());
    assert!(old.exists());
    assert_eq!(std::fs::read_to_string(&target).unwrap(), "target\n");

    let err = ui
        .apply_workspace_edit_transaction(edit.as_str())
        .unwrap_err();
    assert!(
        err.to_string()
            .contains("filesystem side effects were rolled back")
    );
    assert!(!created.exists());
    assert!(!root.join("generated").exists());
    assert!(old.exists());
    assert_eq!(std::fs::read_to_string(&old).unwrap(), "old\n");
    assert!(target.exists());
    assert_eq!(std::fs::read_to_string(&target).unwrap(), "target\n");
    assert_eq!(std::fs::read_to_string(&blocker).unwrap(), "blocker\n");
    assert!(!blocked_child.exists());
    assert_eq!(
        ui.workspace_edit_transaction_events_after(0)
            .latest_sequence,
        0
    );

    let backup_left = std::fs::read_dir(root.join("src"))
        .unwrap()
        .filter_map(Result::ok)
        .any(|entry| {
            entry
                .file_name()
                .to_string_lossy()
                .starts_with(".atto-workspace-edit-rollback-")
        });
    assert!(!backup_left);

    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn multi_document_ui_rolls_back_unopened_text_edits_after_runtime_failure() {
    let root = unique_test_dir("editor-core-ui-workspace-text-rollback-root");
    std::fs::create_dir_all(root.join("src")).unwrap();

    let target = root.join("src").join("Target.swift");
    let blocker = root.join("blocker");
    let blocked_child = blocker.join("Child.swift");
    std::fs::write(&target, "alpha\nbeta\n").unwrap();
    std::fs::write(&blocker, "blocker\n").unwrap();

    let root_uri = path_to_file_uri(root.as_path());
    let target_uri = path_to_file_uri(target.as_path());
    let blocked_child_uri = path_to_file_uri(blocked_child.as_path());

    let mut ui = MultiDocumentEditorUi::new();
    ui.set_workspace_roots([root_uri]);

    let edit = json!({
        "documentChanges": [
            {
                "textDocument": {
                    "uri": target_uri.as_str(),
                    "version": null
                },
                "edits": [
                    {
                        "range": {
                            "start": { "line": 1, "character": 0 },
                            "end": { "line": 1, "character": 4 }
                        },
                        "newText": "BETA"
                    }
                ]
            },
            {
                "kind": "create",
                "uri": blocked_child_uri.as_str()
            }
        ]
    })
    .to_string();

    let preview = ui
        .preview_workspace_edit_transaction(edit.as_str())
        .unwrap();
    assert!(preview.skipped_uris.is_empty());
    assert_eq!(std::fs::read_to_string(&target).unwrap(), "alpha\nbeta\n");

    let err = ui
        .apply_workspace_edit_transaction(edit.as_str())
        .unwrap_err();
    assert!(
        err.to_string()
            .contains("filesystem side effects were rolled back")
    );
    assert_eq!(std::fs::read_to_string(&target).unwrap(), "alpha\nbeta\n");
    assert_eq!(std::fs::read_to_string(&blocker).unwrap(), "blocker\n");
    assert!(!blocked_child.exists());
    assert_eq!(
        ui.workspace_edit_transaction_events_after(0)
            .latest_sequence,
        0
    );

    let backup_left = std::fs::read_dir(root.join("src"))
        .unwrap()
        .filter_map(Result::ok)
        .any(|entry| {
            entry
                .file_name()
                .to_string_lossy()
                .starts_with(".atto-workspace-edit-rollback-")
        });
    assert!(!backup_left);

    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn multi_document_ui_rolls_back_open_tabs_after_runtime_failure() {
    let root = unique_test_dir("editor-core-ui-open-tab-rollback-root");
    std::fs::create_dir_all(root.join("src")).unwrap();

    let old_path = root.join("src").join("Old.swift");
    let delete_path = root.join("src").join("Delete.swift");
    let overwrite_path = root.join("src").join("Overwrite.swift");
    let blocker = root.join("blocker");
    let blocked_child = blocker.join("Child.swift");
    std::fs::write(&old_path, "old\n").unwrap();
    std::fs::write(&delete_path, "delete\n").unwrap();
    std::fs::write(&overwrite_path, "existing\n").unwrap();
    std::fs::write(&blocker, "blocker\n").unwrap();

    let root_uri = path_to_file_uri(root.as_path());
    let old_uri = path_to_file_uri(old_path.as_path());
    let renamed_uri = path_to_file_uri(root.join("src").join("Renamed.swift").as_path());
    let delete_uri = path_to_file_uri(delete_path.as_path());
    let overwrite_uri = path_to_file_uri(overwrite_path.as_path());
    let blocked_child_uri = path_to_file_uri(blocked_child.as_path());

    let mut ui = MultiDocumentEditorUi::new();
    ui.set_workspace_roots([root_uri]);
    let old_tab = ui.open_tab("old\n", 80);
    let delete_tab = ui.open_tab("delete\n", 80);
    let overwrite_tab = ui.open_tab("existing\n", 80);
    ui.set_tab_document_uri(old_tab, Some(old_uri.clone()))
        .unwrap();
    ui.set_tab_document_uri(delete_tab, Some(delete_uri.clone()))
        .unwrap();
    ui.set_tab_document_uri(overwrite_tab, Some(overwrite_uri.clone()))
        .unwrap();
    ui.set_active_tab(delete_tab).unwrap();

    let edit = json!({
        "documentChanges": [
            {
                "textDocument": {
                    "uri": old_uri.as_str(),
                    "version": null
                },
                "edits": [
                    {
                        "range": {
                            "start": { "line": 0, "character": 0 },
                            "end": { "line": 0, "character": 0 }
                        },
                        "newText": "edited "
                    }
                ]
            },
            {
                "kind": "rename",
                "oldUri": old_uri.as_str(),
                "newUri": renamed_uri.as_str()
            },
            {
                "kind": "delete",
                "uri": delete_uri.as_str()
            },
            {
                "kind": "create",
                "uri": overwrite_uri.as_str(),
                "options": { "overwrite": true }
            },
            {
                "kind": "create",
                "uri": blocked_child_uri.as_str()
            }
        ]
    })
    .to_string();

    let preview = ui
        .preview_workspace_edit_transaction(edit.as_str())
        .unwrap();
    assert!(preview.skipped_uris.is_empty());
    assert_eq!(ui.tab_text(old_tab).unwrap(), "old\n");
    assert_eq!(ui.tab_document_uri(old_tab), Some(old_uri.as_str()));
    assert!(ui.tab_ids().contains(&delete_tab));

    let err = ui
        .apply_workspace_edit_transaction(edit.as_str())
        .unwrap_err();
    assert!(err.to_string().contains("open tab state was rolled back"));
    assert_eq!(ui.tab_text(old_tab).unwrap(), "old\n");
    assert!(!ui.is_tab_modified(old_tab).unwrap());
    assert_eq!(ui.tab_document_uri(old_tab), Some(old_uri.as_str()));
    assert!(ui.tab_ids().contains(&delete_tab));
    assert_eq!(ui.tab_text(delete_tab).unwrap(), "delete\n");
    assert_eq!(ui.tab_document_uri(delete_tab), Some(delete_uri.as_str()));
    assert!(ui.tab_ids().contains(&overwrite_tab));
    assert_eq!(ui.tab_text(overwrite_tab).unwrap(), "existing\n");
    assert!(!ui.is_tab_modified(overwrite_tab).unwrap());
    assert_eq!(
        ui.tab_document_uri(overwrite_tab),
        Some(overwrite_uri.as_str())
    );
    assert_eq!(ui.active_tab_id(), Some(delete_tab));
    assert!(old_path.exists());
    assert!(!root.join("src").join("Renamed.swift").exists());
    assert!(delete_path.exists());
    assert_eq!(
        std::fs::read_to_string(&overwrite_path).unwrap(),
        "existing\n"
    );
    assert_eq!(std::fs::read_to_string(&blocker).unwrap(), "blocker\n");
    assert!(!blocked_child.exists());
    assert_eq!(
        ui.workspace_edit_transaction_events_after(0)
            .latest_sequence,
        0
    );

    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn multi_document_ui_undoes_last_workspace_edit_transaction() {
    let root = unique_test_dir("editor-core-ui-workspace-edit-undo");
    std::fs::create_dir_all(root.join("src")).unwrap();
    let unopened = root.join("src").join("Unopened.swift");
    std::fs::write(&unopened, "unopened\n").unwrap();

    let root_uri = path_to_file_uri(root.as_path());
    let open_uri = path_to_file_uri(root.join("src").join("Open.swift").as_path());
    let unopened_uri = path_to_file_uri(unopened.as_path());

    let mut ui = MultiDocumentEditorUi::new();
    ui.set_workspace_roots([root_uri]);
    let tab = ui.open_tab("open\n", 80);
    ui.set_tab_document_uri(tab, Some(open_uri.clone()))
        .unwrap();

    let edit = json!({
        "documentChanges": [
            {
                "textDocument": {
                    "uri": open_uri.as_str(),
                    "version": 0
                },
                "edits": [
                    {
                        "range": {
                            "start": { "line": 0, "character": 0 },
                            "end": { "line": 0, "character": 4 }
                        },
                        "newText": "OPEN"
                    }
                ]
            },
            {
                "textDocument": {
                    "uri": unopened_uri.as_str(),
                    "version": null
                },
                "edits": [
                    {
                        "range": {
                            "start": { "line": 0, "character": 0 },
                            "end": { "line": 0, "character": 8 }
                        },
                        "newText": "UNOPENED"
                    }
                ]
            }
        ]
    })
    .to_string();

    let applied = ui.apply_workspace_edit_transaction(&edit).unwrap();
    assert!(applied.applied);
    assert_eq!(applied.applied_edit_count, 2);
    assert_eq!(ui.tab_text(tab).unwrap(), "OPEN\n");
    assert_eq!(std::fs::read_to_string(&unopened).unwrap(), "UNOPENED\n");

    let undone = ui.undo_last_workspace_edit_transaction().unwrap();
    assert!(undone.undone);
    assert_eq!(undone.restored_open_tab_count, 1);
    assert!(undone.restored_filesystem_entry_count >= 1);
    assert_eq!(
        undone
            .restored_uris
            .into_iter()
            .collect::<std::collections::BTreeSet<_>>(),
        [open_uri, unopened_uri].into_iter().collect()
    );
    assert_eq!(ui.tab_text(tab).unwrap(), "open\n");
    assert!(!ui.is_tab_modified(tab).unwrap());
    assert_eq!(std::fs::read_to_string(&unopened).unwrap(), "unopened\n");

    let unavailable = ui.undo_last_workspace_edit_transaction().unwrap();
    assert!(!unavailable.undone);
    assert!(unavailable.restored_uris.is_empty());

    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn multi_document_ui_redoes_last_workspace_edit_transaction() {
    let root = unique_test_dir("editor-core-ui-workspace-edit-redo");
    std::fs::create_dir_all(root.join("src")).unwrap();
    let unopened = root.join("src").join("Unopened.swift");
    std::fs::write(&unopened, "unopened\n").unwrap();

    let root_uri = path_to_file_uri(root.as_path());
    let open_uri = path_to_file_uri(root.join("src").join("Open.swift").as_path());
    let unopened_uri = path_to_file_uri(unopened.as_path());

    let mut ui = MultiDocumentEditorUi::new();
    ui.set_workspace_roots([root_uri]);
    let tab = ui.open_tab("open\n", 80);
    ui.set_tab_document_uri(tab, Some(open_uri.clone()))
        .unwrap();

    let edit = json!({
        "documentChanges": [
            {
                "textDocument": {
                    "uri": open_uri.as_str(),
                    "version": 0
                },
                "edits": [
                    {
                        "range": {
                            "start": { "line": 0, "character": 0 },
                            "end": { "line": 0, "character": 4 }
                        },
                        "newText": "OPEN"
                    }
                ]
            },
            {
                "textDocument": {
                    "uri": unopened_uri.as_str(),
                    "version": null
                },
                "edits": [
                    {
                        "range": {
                            "start": { "line": 0, "character": 0 },
                            "end": { "line": 0, "character": 8 }
                        },
                        "newText": "UNOPENED"
                    }
                ]
            }
        ]
    })
    .to_string();

    let applied = ui.apply_workspace_edit_transaction(&edit).unwrap();
    assert!(applied.applied);
    assert_eq!(ui.tab_text(tab).unwrap(), "OPEN\n");
    assert_eq!(std::fs::read_to_string(&unopened).unwrap(), "UNOPENED\n");

    let undone = ui.undo_last_workspace_edit_transaction().unwrap();
    assert!(undone.undone);
    assert_eq!(ui.tab_text(tab).unwrap(), "open\n");
    assert_eq!(std::fs::read_to_string(&unopened).unwrap(), "unopened\n");

    let redone = ui.redo_last_workspace_edit_transaction().unwrap();
    assert!(redone.applied);
    assert_eq!(redone.mode, "redo");
    assert_eq!(redone.applied_edit_count, 2);
    assert_eq!(
        redone.applied_uris.into_iter().collect::<BTreeSet<_>>(),
        [open_uri, unopened_uri].into_iter().collect()
    );
    assert_eq!(ui.tab_text(tab).unwrap(), "OPEN\n");
    assert_eq!(std::fs::read_to_string(&unopened).unwrap(), "UNOPENED\n");

    let events = ui.workspace_edit_transaction_events_after(0);
    assert_eq!(events.latest_sequence, 2);
    assert_eq!(events.events[0].operation, "apply");
    assert_eq!(events.events[1].operation, "redo");

    let unavailable = ui.redo_last_workspace_edit_transaction().unwrap();
    assert!(!unavailable.applied);
    assert_eq!(unavailable.mode, "redo");

    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn multi_document_ui_applies_unopened_document_changes_in_order() {
    let root = unique_test_dir("editor-core-ui-workspace-resource-order-root");
    std::fs::create_dir_all(root.join("src")).unwrap();

    let draft = root.join("src").join("Draft.swift");
    let final_file = root.join("src").join("Final.swift");

    let root_uri = path_to_file_uri(root.as_path());
    let draft_uri = path_to_file_uri(draft.as_path());
    let final_uri = path_to_file_uri(final_file.as_path());

    let mut ui = MultiDocumentEditorUi::new();
    ui.set_workspace_roots([root_uri]);

    let edit = json!({
        "documentChanges": [
            {
                "kind": "create",
                "uri": draft_uri.as_str()
            },
            {
                "textDocument": {
                    "uri": draft_uri.as_str(),
                    "version": null
                },
                "edits": [
                    {
                        "range": {
                            "start": { "line": 0, "character": 0 },
                            "end": { "line": 0, "character": 0 }
                        },
                        "newText": "draft\n"
                    }
                ]
            },
            {
                "kind": "rename",
                "oldUri": draft_uri.as_str(),
                "newUri": final_uri.as_str()
            },
            {
                "textDocument": {
                    "uri": final_uri.as_str(),
                    "version": null
                },
                "edits": [
                    {
                        "range": {
                            "start": { "line": 0, "character": 0 },
                            "end": { "line": 0, "character": 0 }
                        },
                        "newText": "final "
                    }
                ]
            }
        ]
    })
    .to_string();

    let preview = ui
        .preview_workspace_edit_transaction(edit.as_str())
        .unwrap();
    assert!(preview.skipped_uris.is_empty());
    assert!(!draft.exists());
    assert!(!final_file.exists());

    let applied = ui.apply_workspace_edit_transaction(edit.as_str()).unwrap();
    assert!(applied.applied);
    assert_eq!(applied.applied_resource_operation_count, 2);
    assert_eq!(applied.applied_edit_count, 2);
    assert!(applied.applied_uris.contains(&draft_uri));
    assert!(applied.applied_uris.contains(&final_uri));
    assert!(applied.skipped_uris.is_empty());
    assert!(!draft.exists());
    assert_eq!(
        std::fs::read_to_string(&final_file).unwrap(),
        "final draft\n"
    );

    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn multi_document_ui_applies_open_tab_document_changes_in_order() {
    let mut ui = MultiDocumentEditorUi::new();
    let tab = ui.open_tab("old\n", 80);
    ui.set_tab_document_uri(tab, Some("file:///tmp/project/Old.swift".to_string()))
        .unwrap();

    let edit = r#"{
      "documentChanges": [
        {
          "textDocument": {
            "uri": "file:///tmp/project/Old.swift",
            "version": null
          },
          "edits": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 0 }
              },
              "newText": "first "
            }
          ]
        },
        {
          "kind": "rename",
          "oldUri": "file:///tmp/project/Old.swift",
          "newUri": "file:///tmp/project/New.swift"
        },
        {
          "textDocument": {
            "uri": "file:///tmp/project/New.swift",
            "version": null
          },
          "edits": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 0 }
              },
              "newText": "second "
            }
          ]
        }
      ]
    }"#;

    let applied = ui.apply_workspace_edit_transaction(edit).unwrap();
    assert!(applied.applied);
    assert_eq!(applied.applied_resource_operation_count, 1);
    assert_eq!(applied.applied_edit_count, 2);
    assert!(applied.skipped_uris.is_empty());
    assert_eq!(
        ui.tab_document_uri(tab),
        Some("file:///tmp/project/New.swift")
    );
    assert_eq!(ui.tab_text(tab).unwrap(), "second first old\n");
}

#[test]
fn multi_document_ui_keeps_prior_text_edit_when_later_resource_operation_is_skipped() {
    let mut ui = MultiDocumentEditorUi::new();
    let tab = ui.open_tab("old\n", 80);
    ui.set_tab_document_uri(tab, Some("file:///tmp/project/Old.swift".to_string()))
        .unwrap();

    let edit = r#"{
      "documentChanges": [
        {
          "textDocument": {
            "uri": "file:///tmp/project/Old.swift",
            "version": null
          },
          "edits": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 0 }
              },
              "newText": "first "
            }
          ]
        },
        {
          "kind": "create",
          "uri": "file:///tmp/project/Old.swift"
        }
      ]
    }"#;

    let preview = ui.preview_workspace_edit_transaction(edit).unwrap();
    assert!(preview.skipped_details.iter().any(|detail| {
        detail.uri == "file:///tmp/project/Old.swift"
            && detail.operation.as_deref() == Some("create")
            && detail.reason == "resource_operation_create_exists"
    }));
    assert!(!preview.skipped_details.iter().any(|detail| {
        detail.uri == "file:///tmp/project/Old.swift"
            && detail.operation.as_deref() == Some("text_edit")
            && detail.reason == "resource_operation_dependency_unsupported"
    }));

    let applied = ui.apply_workspace_edit_transaction(edit).unwrap();
    assert!(applied.applied);
    assert_eq!(applied.applied_edit_count, 1);
    assert_eq!(applied.applied_resource_operation_count, 0);
    assert!(
        applied
            .skipped_uris
            .contains(&"file:///tmp/project/Old.swift".to_string())
    );
    assert!(applied.skipped_details.iter().any(|detail| {
        detail.uri == "file:///tmp/project/Old.swift"
            && detail.operation.as_deref() == Some("create")
            && detail.reason == "resource_operation_create_exists"
    }));
    assert_eq!(ui.tab_text(tab).unwrap(), "first old\n");
}

#[test]
fn multi_document_ui_previews_later_text_edit_blocked_by_unsupported_resource_operation() {
    let mut ui = MultiDocumentEditorUi::new();
    let tab = ui.open_tab("old\n", 80);
    ui.set_tab_document_uri(tab, Some("file:///tmp/project/Old.swift".to_string()))
        .unwrap();

    let edit = r#"{
      "documentChanges": [
        {
          "kind": "create",
          "uri": "file:///tmp/project/Old.swift"
        },
        {
          "textDocument": {
            "uri": "file:///tmp/project/Old.swift",
            "version": null
          },
          "edits": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 0 }
              },
              "newText": "later "
            }
          ]
        }
      ]
    }"#;

    let preview = ui.preview_workspace_edit_transaction(edit).unwrap();
    assert!(preview.skipped_details.iter().any(|detail| {
        detail.uri == "file:///tmp/project/Old.swift"
            && detail.operation.as_deref() == Some("create")
            && detail.reason == "resource_operation_create_exists"
    }));
    assert!(preview.skipped_details.iter().any(|detail| {
        detail.uri == "file:///tmp/project/Old.swift"
            && detail.operation.as_deref() == Some("text_edit")
            && detail.reason == "resource_operation_dependency_unsupported"
    }));

    let applied = ui.apply_workspace_edit_transaction(edit).unwrap();
    assert!(!applied.applied);
    assert_eq!(applied.applied_edit_count, 0);
    assert_eq!(applied.applied_resource_operation_count, 0);
    assert!(applied.skipped_details.iter().any(|detail| {
        detail.uri == "file:///tmp/project/Old.swift"
            && detail.operation.as_deref() == Some("text_edit")
            && detail.reason == "resource_operation_dependency_skipped"
    }));
    assert_eq!(ui.tab_text(tab).unwrap(), "old\n");
}

#[test]
fn multi_document_ui_atomic_workspace_edit_preflights_removed_text_edit_dependency() {
    let mut ui = MultiDocumentEditorUi::new();
    let tab = ui.open_tab("delete me\n", 80);
    ui.set_tab_document_uri(tab, Some("file:///tmp/project/Delete.swift".to_string()))
        .unwrap();

    let edit = json!({
        "applyMode": "atomic",
        "workspaceEdit": {
            "documentChanges": [
                {
                    "kind": "delete",
                    "uri": "file:///tmp/project/Delete.swift"
                },
                {
                    "textDocument": {
                        "uri": "file:///tmp/project/Delete.swift",
                        "version": null
                    },
                    "edits": [
                        {
                            "range": {
                                "start": { "line": 0, "character": 0 },
                                "end": { "line": 0, "character": 0 }
                            },
                            "newText": "late "
                        }
                    ]
                }
            ]
        }
    })
    .to_string();

    let preview = ui
        .preview_workspace_edit_transaction(edit.as_str())
        .unwrap();
    assert_eq!(preview.apply_mode, "atomic");
    assert!(preview.skipped_details.iter().any(|detail| {
        detail.uri == "file:///tmp/project/Delete.swift"
            && detail.operation.as_deref() == Some("text_edit")
            && detail.reason == "resource_operation_dependency_removed"
    }));

    let applied = ui.apply_workspace_edit_transaction(edit.as_str()).unwrap();
    assert_eq!(applied.apply_mode, "atomic");
    assert!(!applied.applied);
    assert_eq!(applied.applied_resource_operation_count, 0);
    assert_eq!(applied.applied_edit_count, 0);
    assert!(applied.skipped_details.iter().any(|detail| {
        detail.uri == "file:///tmp/project/Delete.swift"
            && detail.operation.as_deref() == Some("text_edit")
            && detail.reason == "resource_operation_dependency_removed"
    }));
    assert_eq!(
        ui.tab_document_uri(tab),
        Some("file:///tmp/project/Delete.swift")
    );
    assert_eq!(ui.tab_text(tab).unwrap(), "delete me\n");
}

#[test]
fn multi_document_ui_skips_unopened_rename_to_open_tab_target() {
    let root = unique_test_dir("editor-core-ui-workspace-resource-open-target");
    std::fs::create_dir_all(root.join("src")).unwrap();

    let old = root.join("src").join("Old.swift");
    let target = root.join("src").join("Target.swift");
    std::fs::write(&old, "old\n").unwrap();
    std::fs::write(&target, "target on disk\n").unwrap();

    let root_uri = path_to_file_uri(root.as_path());
    let old_uri = path_to_file_uri(old.as_path());
    let target_uri = path_to_file_uri(target.as_path());

    let mut ui = MultiDocumentEditorUi::new();
    ui.set_workspace_roots([root_uri]);
    let target_tab = ui.open_tab("target in editor\n", 80);
    ui.set_tab_document_uri(target_tab, Some(target_uri.clone()))
        .unwrap();

    let edit = json!({
        "documentChanges": [
            {
                "kind": "rename",
                "oldUri": old_uri.as_str(),
                "newUri": target_uri.as_str(),
                "options": { "overwrite": true }
            },
            {
                "textDocument": {
                    "uri": target_uri.as_str(),
                    "version": null
                },
                "edits": [
                    {
                        "range": {
                            "start": { "line": 0, "character": 0 },
                            "end": { "line": 0, "character": 0 }
                        },
                        "newText": "edited "
                    }
                ]
            }
        ]
    })
    .to_string();

    let preview = ui
        .preview_workspace_edit_transaction(edit.as_str())
        .unwrap();
    assert!(preview.skipped_uris.contains(&old_uri));
    assert!(preview.skipped_uris.contains(&target_uri));
    assert!(preview.skipped_details.iter().any(|detail| {
        detail.uri == target_uri
            && detail.operation.as_deref() == Some("rename")
            && detail.reason == "resource_operation_target_open"
    }));

    let applied = ui.apply_workspace_edit_transaction(edit.as_str()).unwrap();
    assert_eq!(applied.applied_resource_operation_count, 0);
    assert_eq!(applied.applied_edit_count, 0);
    assert!(old.exists());
    assert_eq!(
        std::fs::read_to_string(&target).unwrap(),
        "target on disk\n"
    );
    assert_eq!(ui.tab_text(target_tab).unwrap(), "target in editor\n");

    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn multi_document_ui_applies_open_tab_resource_operations() {
    let mut ui = MultiDocumentEditorUi::new();
    let old = ui.open_tab("old\n", 80);
    let delete = ui.open_tab("delete\n", 80);
    let overwrite = ui.open_tab("existing\n", 80);
    ui.set_tab_document_uri(old, Some("file:///tmp/project/Old.swift".to_string()))
        .unwrap();
    ui.set_tab_document_uri(delete, Some("file:///tmp/project/Delete.swift".to_string()))
        .unwrap();
    ui.set_tab_document_uri(
        overwrite,
        Some("file:///tmp/project/Overwrite.swift".to_string()),
    )
    .unwrap();

    let edit = r#"{
      "documentChanges": [
        {
          "kind": "rename",
          "oldUri": "file:///tmp/project/Old.swift",
          "newUri": "file:///tmp/project/Renamed.swift"
        },
        {
          "textDocument": {
            "uri": "file:///tmp/project/Renamed.swift",
            "version": null
          },
          "edits": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 0 }
              },
              "newText": "renamed "
            }
          ]
        },
        {
          "kind": "delete",
          "uri": "file:///tmp/project/Delete.swift"
        },
        {
          "kind": "create",
          "uri": "file:///tmp/project/Overwrite.swift",
          "options": { "overwrite": true }
        }
      ]
    }"#;

    let preview = ui.preview_workspace_edit_transaction(edit).unwrap();
    assert!(preview.skipped_uris.is_empty());
    assert!(preview.unsupported_operation_uris.is_empty());
    assert_eq!(preview.resource_operations.len(), 3);
    assert!(
        preview
            .resource_operations
            .iter()
            .all(|operation| operation.supported && !operation.applied)
    );
    let rename_operation = preview
        .resource_operations
        .iter()
        .find(|operation| operation.kind == "rename")
        .unwrap();
    assert_eq!(
        rename_operation.old_uri.as_deref(),
        Some("file:///tmp/project/Old.swift")
    );
    assert_eq!(
        rename_operation.new_uri.as_deref(),
        Some("file:///tmp/project/Renamed.swift")
    );
    assert_eq!(
        rename_operation.affected_uris,
        vec![
            "file:///tmp/project/Old.swift".to_string(),
            "file:///tmp/project/Renamed.swift".to_string(),
        ]
    );
    let renamed_preview = preview
        .documents
        .iter()
        .find(|doc| doc.uri == "file:///tmp/project/Renamed.swift")
        .unwrap();
    assert_eq!(renamed_preview.tab_id, Some(old.get()));
    assert!(renamed_preview.is_open);

    let applied = ui.apply_workspace_edit_transaction(edit).unwrap();
    assert!(applied.applied);
    assert_eq!(applied.applied_edit_count, 1);
    assert_eq!(applied.applied_resource_operation_count, 3);
    assert!(applied.skipped_uris.is_empty());
    assert!(applied.unsupported_operation_uris.is_empty());
    assert_eq!(applied.resource_operations.len(), 3);
    assert!(
        applied
            .resource_operations
            .iter()
            .all(|operation| operation.supported && operation.applied)
    );
    assert_eq!(
        ui.tab_document_uri(old),
        Some("file:///tmp/project/Renamed.swift")
    );
    assert_eq!(ui.tab_text(old).unwrap(), "renamed old\n");
    assert!(!ui.tab_ids().contains(&delete));
    assert_eq!(ui.tab_text(overwrite).unwrap(), "");
    assert!(!ui.is_tab_modified(overwrite).unwrap());
}

#[test]
fn multi_document_ui_applies_open_tab_resource_operation_filesystem_side_effects() {
    let root = unique_test_dir("editor-core-ui-open-tab-resource-fs-root");
    std::fs::create_dir_all(root.join("src")).unwrap();

    let old_path = root.join("src").join("Old.swift");
    let renamed_path = root.join("src").join("Renamed.swift");
    let delete_path = root.join("src").join("Delete.swift");
    let overwrite_path = root.join("src").join("Overwrite.swift");
    std::fs::write(&old_path, "old\n").unwrap();
    std::fs::write(&delete_path, "delete\n").unwrap();
    std::fs::write(&overwrite_path, "existing\n").unwrap();

    let root_uri = path_to_file_uri(root.as_path());
    let old_uri = path_to_file_uri(old_path.as_path());
    let renamed_uri = path_to_file_uri(renamed_path.as_path());
    let delete_uri = path_to_file_uri(delete_path.as_path());
    let overwrite_uri = path_to_file_uri(overwrite_path.as_path());

    let mut ui = MultiDocumentEditorUi::new();
    ui.set_workspace_roots([root_uri]);
    let old = ui.open_tab("old\n", 80);
    let delete = ui.open_tab("delete\n", 80);
    let overwrite = ui.open_tab("existing\n", 80);
    ui.set_tab_document_uri(old, Some(old_uri.clone())).unwrap();
    ui.set_tab_document_uri(delete, Some(delete_uri.clone()))
        .unwrap();
    ui.set_tab_document_uri(overwrite, Some(overwrite_uri.clone()))
        .unwrap();

    let edit = json!({
        "documentChanges": [
            {
                "kind": "rename",
                "oldUri": old_uri.as_str(),
                "newUri": renamed_uri.as_str()
            },
            {
                "textDocument": {
                    "uri": renamed_uri.as_str(),
                    "version": null
                },
                "edits": [
                    {
                        "range": {
                            "start": { "line": 0, "character": 0 },
                            "end": { "line": 0, "character": 0 }
                        },
                        "newText": "renamed "
                    }
                ]
            },
            {
                "kind": "delete",
                "uri": delete_uri.as_str()
            },
            {
                "kind": "create",
                "uri": overwrite_uri.as_str(),
                "options": { "overwrite": true }
            }
        ]
    })
    .to_string();

    let preview = ui
        .preview_workspace_edit_transaction(edit.as_str())
        .unwrap();
    assert!(preview.skipped_uris.is_empty());
    assert!(old_path.exists());
    assert!(!renamed_path.exists());
    assert!(delete_path.exists());
    assert_eq!(
        std::fs::read_to_string(&overwrite_path).unwrap(),
        "existing\n"
    );

    let applied = ui.apply_workspace_edit_transaction(edit.as_str()).unwrap();
    assert!(applied.applied);
    assert_eq!(applied.applied_edit_count, 1);
    assert_eq!(applied.applied_resource_operation_count, 3);
    assert!(applied.skipped_uris.is_empty());
    assert!(!old_path.exists());
    assert_eq!(std::fs::read_to_string(&renamed_path).unwrap(), "old\n");
    assert!(!delete_path.exists());
    assert_eq!(std::fs::read_to_string(&overwrite_path).unwrap(), "");
    assert_eq!(ui.tab_document_uri(old), Some(renamed_uri.as_str()));
    assert_eq!(ui.tab_text(old).unwrap(), "renamed old\n");
    assert!(!ui.tab_ids().contains(&delete));
    assert_eq!(ui.tab_text(overwrite).unwrap(), "");
    assert!(!ui.is_tab_modified(overwrite).unwrap());

    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn multi_document_ui_reports_workspace_edit_transaction_skipped_details() {
    let mut ui = MultiDocumentEditorUi::new();
    let dirty = ui.open_tab("dirty\n", 80);
    let overlap = ui.open_tab("overlap\n", 80);
    let versioned = ui.open_tab("versioned\n", 80);
    ui.set_tab_document_uri(dirty, Some("file:///tmp/project/Dirty.swift".to_string()))
        .unwrap();
    ui.set_tab_document_uri(
        overlap,
        Some("file:///tmp/project/Overlap.swift".to_string()),
    )
    .unwrap();
    ui.set_tab_document_uri(
        versioned,
        Some("file:///tmp/project/Versioned.swift".to_string()),
    )
    .unwrap();
    ui.replace_tab_text(dirty, "dirty changed\n", false)
        .unwrap();

    let edit = r#"{
      "documentChanges": [
        {
          "textDocument": {
            "uri": "file:///tmp/project/Missing.swift",
            "version": null
          },
          "edits": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 0 }
              },
              "newText": "missing"
            }
          ]
        },
        {
          "textDocument": {
            "uri": "file:///tmp/project/Overlap.swift",
            "version": null
          },
          "edits": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 2 }
              },
              "newText": "a"
            },
            {
              "range": {
                "start": { "line": 0, "character": 1 },
                "end": { "line": 0, "character": 3 }
              },
              "newText": "b"
            }
          ]
        },
        {
          "textDocument": {
            "uri": "file:///tmp/project/Versioned.swift",
            "version": 1
          },
          "edits": [
            {
              "range": {
                "start": { "line": 0, "character": 0 },
                "end": { "line": 0, "character": 0 }
              },
              "newText": "stale "
            }
          ]
        },
        {
          "kind": "delete",
          "uri": "file:///tmp/project/Dirty.swift"
        }
      ]
    }"#;

    let preview = ui.preview_workspace_edit_transaction(edit).unwrap();
    assert_eq!(
        preview.skipped_uris,
        vec![
            "file:///tmp/project/Dirty.swift",
            "file:///tmp/project/Missing.swift",
            "file:///tmp/project/Overlap.swift",
            "file:///tmp/project/Versioned.swift",
        ]
    );
    let versioned_document = preview
        .documents
        .iter()
        .find(|doc| doc.uri == "file:///tmp/project/Versioned.swift")
        .unwrap();
    assert_eq!(versioned_document.expected_version, Some(1));
    assert_eq!(versioned_document.actual_version, Some(0));
    assert!(versioned_document.version_mismatch);
    let dirty_document = preview
        .documents
        .iter()
        .find(|doc| doc.uri == "file:///tmp/project/Dirty.swift")
        .unwrap();
    assert!(dirty_document.is_dirty);
    assert_eq!(
        preview.dirty_document_uris,
        vec!["file:///tmp/project/Dirty.swift"]
    );
    let detail_reasons = preview
        .skipped_details
        .iter()
        .map(|detail| {
            (
                detail.uri.as_str(),
                detail.operation.as_deref(),
                detail.reason.as_str(),
            )
        })
        .collect::<Vec<_>>();
    assert!(detail_reasons.contains(&(
        "file:///tmp/project/Dirty.swift",
        Some("delete"),
        "resource_operation_dirty_target"
    )));
    assert!(detail_reasons.contains(&(
        "file:///tmp/project/Missing.swift",
        Some("text_edit"),
        "document_not_open"
    )));
    assert!(detail_reasons.contains(&(
        "file:///tmp/project/Overlap.swift",
        Some("text_edit"),
        "overlapping_text_edits"
    )));
    assert!(detail_reasons.contains(&(
        "file:///tmp/project/Versioned.swift",
        Some("text_edit"),
        "version_mismatch"
    )));
    let conflict_kinds = preview
        .conflicts
        .iter()
        .map(|conflict| {
            (
                conflict.uri.as_str(),
                conflict.operation.as_deref(),
                conflict.reason.as_str(),
                conflict.kind.as_str(),
                conflict.severity.as_str(),
                conflict.apply_impact.as_str(),
                conflict.resolution.as_str(),
            )
        })
        .collect::<Vec<_>>();
    assert!(conflict_kinds.contains(&(
        "file:///tmp/project/Dirty.swift",
        Some("delete"),
        "resource_operation_dirty_target",
        "dirty_document",
        "warning",
        "skips_change",
        "save_or_discard",
    )));
    assert!(conflict_kinds.contains(&(
        "file:///tmp/project/Missing.swift",
        Some("text_edit"),
        "document_not_open",
        "missing_resource",
        "warning",
        "skips_change",
        "restore_resource",
    )));
    assert!(conflict_kinds.contains(&(
        "file:///tmp/project/Overlap.swift",
        Some("text_edit"),
        "overlapping_text_edits",
        "overlap",
        "warning",
        "skips_change",
        "recompute_edit",
    )));
    assert!(conflict_kinds.contains(&(
        "file:///tmp/project/Versioned.swift",
        Some("text_edit"),
        "version_mismatch",
        "version",
        "warning",
        "skips_change",
        "refresh_request",
    )));

    let applied = ui.apply_workspace_edit_transaction(edit).unwrap();
    assert_eq!(applied.applied_edit_count, 0);
    assert_eq!(
        applied.dirty_document_uris,
        vec!["file:///tmp/project/Dirty.swift"]
    );
    assert!(applied.conflicts.iter().any(|conflict| {
        conflict.uri == "file:///tmp/project/Dirty.swift"
            && conflict.kind == "dirty_document"
            && conflict.severity == "warning"
            && conflict.apply_impact == "skips_change"
            && conflict.resolution == "save_or_discard"
    }));
    assert_eq!(ui.tab_text(versioned).unwrap(), "versioned\n");
}

#[test]
fn multi_document_ui_can_replace_tab_text_and_track_dirty_state() {
    let mut ui = MultiDocumentEditorUi::new();
    let tab = ui.open_tab("hello world\n", 80);

    ui.replace_tab_text(tab, "hello mirror\n", false).unwrap();

    assert_eq!(ui.tab_text(tab).unwrap(), "hello mirror\n");
    assert!(ui.is_tab_modified(tab).unwrap());

    let results = ui
        .search_all_tabs("mirror", SearchOptions::default())
        .unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0].tab_id, tab);
    assert_eq!(results[0].matches.len(), 1);

    ui.mark_tab_saved(tab).unwrap();
    assert!(!ui.is_tab_modified(tab).unwrap());

    ui.replace_tab_text(tab, "saved mirror\n", true).unwrap();
    assert_eq!(ui.tab_text(tab).unwrap(), "saved mirror\n");
    assert!(!ui.is_tab_modified(tab).unwrap());
}

#[test]
fn multi_document_ui_preview_tabs_are_reused_until_pinned_or_modified() {
    let mut ui = MultiDocumentEditorUi::new();

    let pinned = ui.open_tab("pinned", 80);
    ui.set_active_tab(pinned).unwrap();

    let p1 = ui.open_preview_tab("preview-1", 80);
    assert_eq!(ui.is_preview_tab(p1), Some(true));

    // Opening another preview should reuse the same tab id (replace content).
    let p1_again = ui.open_preview_tab("preview-2", 80);
    assert_eq!(p1_again, p1);

    ui.set_active_tab(p1).unwrap();
    assert_eq!(ui.active_editor().unwrap().text(), "preview-2");

    // Pinning turns it into a normal tab and forces a new preview tab next time.
    ui.pin_tab(p1).unwrap();
    assert_eq!(ui.is_preview_tab(p1), Some(false));
    let p2 = ui.open_preview_tab("preview-3", 80);
    assert_ne!(p2, p1);
}

#[test]
fn multi_document_ui_can_close_other_tabs_and_tabs_to_right() {
    let mut ui = MultiDocumentEditorUi::new();
    let a = ui.open_tab("a", 80);
    let b = ui.open_tab("b", 80);
    let _c = ui.open_tab("c", 80);

    // Close to the right of b should remove c.
    let closed = ui.close_tabs_to_right(b).unwrap();
    assert_eq!(closed, 1);
    assert_eq!(ui.tab_ids(), vec![a, b]);

    // Close others for b should leave only b.
    let closed = ui.close_other_tabs(b).unwrap();
    assert_eq!(closed, 1);
    assert_eq!(ui.tab_ids(), vec![b]);
    assert_eq!(ui.active_tab_id(), Some(b));
}

#[test]
fn multi_document_ui_owns_incremental_workspace_diagnostics() {
    let mut ui = MultiDocumentEditorUi::new();

    let snapshot = ui
        .apply_workspace_diagnostics_json(
            r#"{
              "items": [
                {
                  "uri": "file:///project/a.swift",
                  "kind": "full",
                  "resultId": "a-1",
                  "items": [
                    {
                      "range": {
                        "start": { "line": 0, "character": 1 },
                        "end": { "line": 0, "character": 3 }
                      },
                      "severity": 1,
                      "code": 7001,
                      "source": "unit-test",
                      "message": "first problem"
                    }
                  ],
                  "relatedDocuments": {
                    "file:///project/related.swift": {
                      "kind": "full",
                      "resultId": "r-1",
                      "items": [
                        {
                          "range": {
                            "start": { "line": 2, "character": 4 },
                            "end": { "line": 2, "character": 8 }
                          },
                          "severity": 2,
                          "message": "related warning"
                        }
                      ]
                    }
                  }
                }
              ]
            }"#,
        )
        .unwrap();

    assert_eq!(
        snapshot
            .diagnostics
            .iter()
            .map(|diagnostic| diagnostic.message.as_str())
            .collect::<Vec<_>>(),
        vec!["first problem", "related warning"]
    );
    assert_eq!(snapshot.diagnostics[0].severity_label, Some("error"));
    assert_eq!(snapshot.diagnostics[0].code.as_deref(), Some("7001"));
    assert_eq!(
        snapshot.diagnostics[1].target.uri,
        "file:///project/related.swift"
    );
    assert_eq!(
        ui.workspace_diagnostic_markers_snapshot(),
        editor_core_ui::WorkspaceDiagnosticMarkersSnapshot {
            markers: vec![
                editor_core_ui::WorkspaceDiagnosticMarker {
                    uri: "file:///project/a.swift".to_string(),
                    line: 0,
                    utf16_character: 1,
                    severity: Some(1),
                    severity_label: Some("error"),
                },
                editor_core_ui::WorkspaceDiagnosticMarker {
                    uri: "file:///project/related.swift".to_string(),
                    line: 2,
                    utf16_character: 4,
                    severity: Some(2),
                    severity_label: Some("warning"),
                },
            ],
        }
    );

    let previous: serde_json::Value =
        serde_json::from_str(&ui.workspace_diagnostics_previous_result_ids_json().unwrap())
            .unwrap();
    assert_eq!(
        previous,
        json!([
            {"uri": "file:///project/a.swift", "value": "a-1"},
            {"uri": "file:///project/related.swift", "value": "r-1"},
        ])
    );
    assert_eq!(ui.workspace_diagnostics_latest_event_sequence(), 1);
    let events = ui.workspace_diagnostics_events_after(0);
    assert_eq!(events.latest_sequence, 1);
    assert_eq!(events.events.len(), 1);
    assert_eq!(events.events[0].sequence, 1);
    assert_eq!(events.events[0].family, "workspace_diagnostics");
    assert_eq!(events.events[0].operation, "apply");
    assert_eq!(events.events[0].document_count, 2);
    assert_eq!(events.events[0].diagnostic_count, 2);
    assert_eq!(events.events[0].marker_count, 2);

    let snapshot = ui
        .apply_workspace_diagnostics_json(
            r#"{
              "items": [
                {
                  "uri": "file:///project/a.swift",
                  "kind": "unchanged",
                  "resultId": "a-2"
                }
              ]
            }"#,
        )
        .unwrap();
    assert_eq!(
        snapshot
            .diagnostics
            .iter()
            .map(|diagnostic| diagnostic.message.as_str())
            .collect::<Vec<_>>(),
        vec!["first problem", "related warning"]
    );
    assert_eq!(snapshot.documents[0].result_id.as_deref(), Some("a-2"));
    let events = ui.workspace_diagnostics_events_after(1);
    assert_eq!(events.latest_sequence, 2);
    assert_eq!(events.events.len(), 1);
    assert_eq!(events.events[0].sequence, 2);
    assert_eq!(events.events[0].operation, "apply");
    assert_eq!(events.events[0].diagnostic_count, 2);

    let snapshot = ui
        .apply_workspace_diagnostics_json(
            r#"{
              "items": [
                {
                  "uri": "file:///project/a.swift",
                  "kind": "full",
                  "resultId": "a-3",
                  "items": []
                }
              ]
            }"#,
        )
        .unwrap();
    assert_eq!(
        snapshot
            .diagnostics
            .iter()
            .map(|diagnostic| diagnostic.message.as_str())
            .collect::<Vec<_>>(),
        vec!["related warning"]
    );

    ui.clear_workspace_diagnostics();
    assert!(ui.workspace_diagnostics_snapshot().diagnostics.is_empty());
    assert_eq!(
        ui.workspace_diagnostics_previous_result_ids_json().unwrap(),
        "[]"
    );
    let events: serde_json::Value =
        serde_json::from_str(&ui.workspace_diagnostics_events_json(2).unwrap()).unwrap();
    assert_eq!(events["latest_sequence"], 4);
    assert_eq!(events["events"].as_array().unwrap().len(), 2);
    assert_eq!(events["events"][0]["operation"], "apply");
    assert_eq!(events["events"][0]["diagnostic_count"], 1);
    assert_eq!(events["events"][1]["operation"], "clear");
    assert_eq!(events["events"][1]["diagnostic_count"], 0);
}
