use editor_core::SearchOptions;
use editor_core_ui::MultiDocumentEditorUi;
use serde_json::json;

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

    let applied = ui.apply_workspace_edit_transaction(edit).unwrap();
    assert_eq!(applied.applied_edit_count, 0);
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
