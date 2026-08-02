use super::*;
use std::ffi::CString;
use std::ptr;

fn wait_for_processing(ui: *mut EditorUi) {
    let start = std::time::Instant::now();
    loop {
        let mut applied: u8 = 0;
        let mut pending: u8 = 0;
        assert_eq!(
            unsafe { editor_core_ui_ffi_editor_ui_poll_processing(ui, &mut applied, &mut pending) },
            ECU_OK
        );
        if pending == 0 {
            break;
        }
        if start.elapsed() > std::time::Duration::from_secs(2) {
            panic!("timeout waiting for async processing");
        }
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
}

fn set_test_treesitter_registry(ui: *mut EditorUi) {
    // Keep the tree-sitter worker at normal priority in tests so a single grammar load/parse
    // finishes within the bounded wait window (see editor-core-ui's QoS helper). Set here,
    // before any worker is spawned by treesitter_set_language below.
    // SAFETY: test-only; called on the main test thread before spawning the worker.
    unsafe { std::env::set_var("EDITOR_CORE_DISABLE_TS_WORKER_QOS", "1") };

    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../editor-core-treesitter/tests/fixtures/treesitter");
    let json = serde_json::json!({
        "schema_version": 1,
        "root_dir": root.to_string_lossy(),
        "extension_map": { "rs": "rust" },
        "languages": {
            "rust": {
                "wasm": "rust/language.wasm",
                "highlights": "rust/highlights.scm",
                "folds": "rust/folds.scm"
            }
        }
    })
    .to_string();
    let json = CString::new(json).unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_treesitter_set_registry_json(ui, json.as_ptr()),
        ECU_OK
    );
}

#[test]
fn ffi_multi_document_exposes_tab_preview_split_and_search() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let alpha = CString::new("alpha world").unwrap();
    let beta = CString::new("beta world").unwrap();
    let mut alpha_id: u64 = 0;
    let mut beta_id: u64 = 0;
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(multi, alpha.as_ptr(), 80, &mut alpha_id),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(multi, beta.as_ptr(), 80, &mut beta_id),
        ECU_OK
    );
    assert_ne!(alpha_id, beta_id);

    let title = CString::new("Beta").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_title(multi, beta_id, title.as_ptr()),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_active_tab(multi, beta_id),
        ECU_OK
    );

    let mut has_active: u8 = 0;
    let mut active_id: u64 = 0;
    assert_eq!(
        editor_core_ui_ffi_multi_document_active_tab_id(multi, &mut has_active, &mut active_id),
        ECU_OK
    );
    assert_eq!(has_active, 1);
    assert_eq!(active_id, beta_id);

    let mut moved_tab: u8 = 0;
    assert_eq!(
        editor_core_ui_ffi_multi_document_move_tab_index(multi, 1, 0, &mut moved_tab),
        ECU_OK
    );
    assert_eq!(moved_tab, 1);

    let mut view_index: u32 = 0;
    assert_eq!(
        editor_core_ui_ffi_multi_document_split_tab(multi, beta_id, 80, &mut view_index),
        ECU_OK
    );
    assert_eq!(view_index, 1);
    let mut view_count: u32 = 0;
    assert_eq!(
        editor_core_ui_ffi_multi_document_view_count(multi, beta_id, &mut view_count),
        ECU_OK
    );
    assert_eq!(view_count, 2);
    let mut closed_view: u8 = 0;
    assert_eq!(
        editor_core_ui_ffi_multi_document_close_view_index(
            multi,
            beta_id,
            view_index,
            &mut closed_view,
        ),
        ECU_OK
    );
    assert_eq!(closed_view, 1);
    assert_eq!(
        editor_core_ui_ffi_multi_document_view_count(multi, beta_id, &mut view_count),
        ECU_OK
    );
    assert_eq!(view_count, 1);
    assert_eq!(
        editor_core_ui_ffi_multi_document_split_tab(multi, beta_id, 80, &mut view_index),
        ECU_OK
    );
    assert_eq!(view_index, 1);
    assert_eq!(
        editor_core_ui_ffi_multi_document_split_tab(multi, beta_id, 80, &mut view_index),
        ECU_OK
    );
    assert_eq!(view_index, 2);
    let mut moved_view: u8 = 0;
    assert_eq!(
        editor_core_ui_ffi_multi_document_move_view_index(multi, beta_id, 2, 0, &mut moved_view),
        ECU_OK
    );
    assert_eq!(moved_view, 1);

    let replacement = CString::new("beta mirror").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_replace_tab_text(multi, beta_id, replacement.as_ptr(), 0,),
        ECU_OK
    );
    let beta_text_ptr = editor_core_ui_ffi_multi_document_tab_text(multi, beta_id);
    assert!(!beta_text_ptr.is_null());
    let beta_text = unsafe { std::ffi::CStr::from_ptr(beta_text_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(beta_text_ptr) };
    assert_eq!(beta_text, "beta mirror");
    let mut modified: u8 = 0;
    assert_eq!(
        editor_core_ui_ffi_multi_document_is_tab_modified(multi, beta_id, &mut modified),
        ECU_OK
    );
    assert_eq!(modified, 1);
    assert_eq!(
        editor_core_ui_ffi_multi_document_mark_tab_saved(multi, beta_id),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_is_tab_modified(multi, beta_id, &mut modified),
        ECU_OK
    );
    assert_eq!(modified, 0);
    let saved = CString::new("beta saved mirror").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_replace_tab_text(multi, beta_id, saved.as_ptr(), 1),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_is_tab_modified(multi, beta_id, &mut modified),
        ECU_OK
    );
    assert_eq!(modified, 0);

    let preview1 = CString::new("preview one").unwrap();
    let preview2 = CString::new("preview two").unwrap();
    let mut preview_id: u64 = 0;
    let mut preview_again_id: u64 = 0;
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_preview_tab(
            multi,
            preview1.as_ptr(),
            80,
            &mut preview_id,
        ),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_preview_tab(
            multi,
            preview2.as_ptr(),
            80,
            &mut preview_again_id,
        ),
        ECU_OK
    );
    assert_eq!(preview_again_id, preview_id);
    let mut is_preview: u8 = 0;
    assert_eq!(
        editor_core_ui_ffi_multi_document_is_preview_tab(multi, preview_id, &mut is_preview),
        ECU_OK
    );
    assert_eq!(is_preview, 1);
    assert_eq!(
        editor_core_ui_ffi_multi_document_pin_tab(multi, preview_id),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_is_preview_tab(multi, preview_id, &mut is_preview),
        ECU_OK
    );
    assert_eq!(is_preview, 0);

    let query = CString::new("mirror").unwrap();
    let search_ptr =
        editor_core_ui_ffi_multi_document_search_all_tabs_json(multi, query.as_ptr(), 1, 0, 0);
    assert!(!search_ptr.is_null());
    let search_json = unsafe { std::ffi::CStr::from_ptr(search_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(search_ptr) };
    let search_value: serde_json::Value = serde_json::from_str(&search_json).unwrap();
    let search_results = search_value["results"].as_array().unwrap();
    assert_eq!(search_results.len(), 1);
    assert_eq!(search_results[0]["tab_id"], beta_id);

    let workspace_diagnostics = CString::new(
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
                  "message": "first problem"
                }
              ]
            }
          ]
        }"#,
    )
    .unwrap();
    let diagnostics_ptr = editor_core_ui_ffi_multi_document_apply_workspace_diagnostics_json(
        multi,
        workspace_diagnostics.as_ptr(),
    );
    assert!(!diagnostics_ptr.is_null());
    let diagnostics_json = unsafe { std::ffi::CStr::from_ptr(diagnostics_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(diagnostics_ptr) };
    let diagnostics_value: serde_json::Value = serde_json::from_str(&diagnostics_json).unwrap();
    assert_eq!(
        diagnostics_value["diagnostics"][0]["message"],
        "first problem"
    );
    assert_eq!(
        diagnostics_value["diagnostics"][0]["severity_label"],
        "error"
    );

    let markers_ptr = editor_core_ui_ffi_multi_document_workspace_diagnostic_markers_json(multi);
    assert!(!markers_ptr.is_null());
    let markers_json = unsafe { std::ffi::CStr::from_ptr(markers_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(markers_ptr) };
    let markers_value: serde_json::Value = serde_json::from_str(&markers_json).unwrap();
    assert_eq!(
        markers_value["markers"][0]["uri"],
        "file:///project/a.swift"
    );
    assert_eq!(markers_value["markers"][0]["line"], 0);
    assert_eq!(markers_value["markers"][0]["utf16_character"], 1);
    assert_eq!(markers_value["markers"][0]["severity_label"], "error");

    let previous_ptr =
        editor_core_ui_ffi_multi_document_workspace_diagnostics_previous_result_ids_json(multi);
    assert!(!previous_ptr.is_null());
    let previous_json = unsafe { std::ffi::CStr::from_ptr(previous_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(previous_ptr) };
    let previous_value: serde_json::Value = serde_json::from_str(&previous_json).unwrap();
    assert_eq!(
        previous_value,
        serde_json::json!([{"uri": "file:///project/a.swift", "value": "a-1"}])
    );
    let mut latest_sequence: u64 = 0;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_multi_document_workspace_diagnostics_latest_event_sequence(
                multi,
                &mut latest_sequence,
            )
        },
        ECU_OK
    );
    assert_eq!(latest_sequence, 1);
    let events_ptr = editor_core_ui_ffi_multi_document_workspace_diagnostics_events_json(multi, 0);
    assert!(!events_ptr.is_null());
    let events_json = unsafe { std::ffi::CStr::from_ptr(events_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(events_ptr) };
    let events_value: serde_json::Value = serde_json::from_str(&events_json).unwrap();
    assert_eq!(events_value["latest_sequence"], 1);
    assert_eq!(events_value["events"][0]["family"], "workspace_diagnostics");
    assert_eq!(events_value["events"][0]["operation"], "apply");
    assert_eq!(events_value["events"][0]["diagnostic_count"], 1);

    assert_eq!(
        editor_core_ui_ffi_multi_document_clear_workspace_diagnostics(multi),
        ECU_OK
    );
    let cleared_ptr = editor_core_ui_ffi_multi_document_workspace_diagnostics_snapshot_json(multi);
    assert!(!cleared_ptr.is_null());
    let cleared_json = unsafe { std::ffi::CStr::from_ptr(cleared_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(cleared_ptr) };
    let cleared_value: serde_json::Value = serde_json::from_str(&cleared_json).unwrap();
    assert_eq!(cleared_value["diagnostics"].as_array().unwrap().len(), 0);
    let events_ptr = editor_core_ui_ffi_multi_document_workspace_diagnostics_events_json(multi, 1);
    assert!(!events_ptr.is_null());
    let events_json = unsafe { std::ffi::CStr::from_ptr(events_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(events_ptr) };
    let events_value: serde_json::Value = serde_json::from_str(&events_json).unwrap();
    assert_eq!(events_value["latest_sequence"], 2);
    assert_eq!(events_value["events"][0]["operation"], "clear");
    assert_eq!(events_value["events"][0]["diagnostic_count"], 0);

    let snapshot_ptr = editor_core_ui_ffi_multi_document_snapshot_json(multi);
    assert!(!snapshot_ptr.is_null());
    let snapshot_json = unsafe { std::ffi::CStr::from_ptr(snapshot_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(snapshot_ptr) };
    let snapshot: serde_json::Value = serde_json::from_str(&snapshot_json).unwrap();
    assert_eq!(snapshot["active_tab_id"], beta_id);
    let tabs = snapshot["tabs"].as_array().unwrap();
    assert_eq!(tabs[0]["id"], beta_id);
    assert_eq!(tabs[1]["id"], alpha_id);
    assert!(tabs.iter().any(|tab| tab["id"] == beta_id
        && tab["title"] == "Beta"
        && tab["view_count"] == 3
        && tab["active_view_index"] == 0
        && tab["is_modified"] == false));
    assert!(
        tabs.iter()
            .any(|tab| tab["id"] == preview_id && tab["is_preview"] == false)
    );

    let mut closed: u32 = 0;
    assert_eq!(
        editor_core_ui_ffi_multi_document_close_tabs_to_right(multi, beta_id, &mut closed),
        ECU_OK
    );
    assert!(closed >= 1);

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
}

#[test]
fn ffi_editor_ui_lsp_result_events_snapshot_empty() {
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_LSP_RESULT_EVENTS,
        0
    );

    let initial = CString::new("abc").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let mut latest_sequence: u64 = u64::MAX;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_lsp_result_events_latest_sequence(ui, &mut latest_sequence)
        },
        ECU_OK
    );
    assert_eq!(latest_sequence, 0);

    let events_ptr = editor_core_ui_ffi_editor_ui_lsp_result_events_json(ui, 0);
    assert!(!events_ptr.is_null());
    let events_json = unsafe { std::ffi::CStr::from_ptr(events_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(events_ptr) };
    let events: serde_json::Value = serde_json::from_str(&events_json).unwrap();
    assert_eq!(events["latest_sequence"], 0);
    assert_eq!(events["events"].as_array().unwrap().len(), 0);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_editor_ui_lsp_request_events_snapshot_empty() {
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_LSP_REQUEST_EVENTS,
        0
    );

    let initial = CString::new("abc").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let mut latest_sequence: u64 = u64::MAX;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_lsp_request_events_latest_sequence(
                ui,
                &mut latest_sequence,
            )
        },
        ECU_OK
    );
    assert_eq!(latest_sequence, 0);

    let events_ptr = editor_core_ui_ffi_editor_ui_lsp_request_events_json(ui, 0);
    assert!(!events_ptr.is_null());
    let events_json = unsafe { std::ffi::CStr::from_ptr(events_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(events_ptr) };
    let events: serde_json::Value = serde_json::from_str(&events_json).unwrap();
    assert_eq!(events["latest_sequence"], 0);
    assert_eq!(events["events"].as_array().unwrap().len(), 0);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_multi_document_lsp_result_events_snapshot_empty() {
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_MULTI_DOCUMENT_LSP_RESULT_EVENTS,
        0
    );

    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let initial = CString::new("abc").unwrap();
    let mut tab_id: u64 = 0;
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(multi, initial.as_ptr(), 80, &mut tab_id),
        ECU_OK
    );

    let mut latest_sequence: u64 = u64::MAX;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_multi_document_lsp_result_events_latest_sequence(
                multi,
                &mut latest_sequence,
            )
        },
        ECU_OK
    );
    assert_eq!(latest_sequence, 0);

    let events_ptr = editor_core_ui_ffi_multi_document_lsp_result_events_json(multi, 0);
    assert!(!events_ptr.is_null());
    let events_json = unsafe { std::ffi::CStr::from_ptr(events_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(events_ptr) };
    let events: serde_json::Value = serde_json::from_str(&events_json).unwrap();
    assert_eq!(events["latest_sequence"], 0);
    assert_eq!(events["events"].as_array().unwrap().len(), 0);

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
}

#[test]
fn ffi_multi_document_lsp_request_events_snapshot_empty() {
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_MULTI_DOCUMENT_LSP_REQUEST_EVENTS,
        0
    );

    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let initial = CString::new("abc").unwrap();
    let mut tab_id: u64 = 0;
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(multi, initial.as_ptr(), 80, &mut tab_id),
        ECU_OK
    );

    let mut latest_sequence: u64 = u64::MAX;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_multi_document_lsp_request_events_latest_sequence(
                multi,
                &mut latest_sequence,
            )
        },
        ECU_OK
    );
    assert_eq!(latest_sequence, 0);

    let events_ptr = editor_core_ui_ffi_multi_document_lsp_request_events_json(multi, 0);
    assert!(!events_ptr.is_null());
    let events_json = unsafe { std::ffi::CStr::from_ptr(events_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(events_ptr) };
    let events: serde_json::Value = serde_json::from_str(&events_json).unwrap();
    assert_eq!(events["latest_sequence"], 0);
    assert_eq!(events["events"].as_array().unwrap().len(), 0);

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
}

#[test]
fn ffi_smoke_create_insert_render_get_text() {
    let initial = CString::new("abc").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    // Configure rendering for deterministic pixel tests.
    let theme = EcuTheme {
        background: EcuRgba8 {
            r: 10,
            g: 20,
            b: 30,
            a: 255,
        },
        foreground: EcuRgba8 {
            r: 250,
            g: 250,
            b: 250,
            a: 255,
        },
        selection_background: EcuRgba8 {
            r: 200,
            g: 0,
            b: 0,
            a: 255,
        },
        caret: EcuRgba8 {
            r: 0,
            g: 0,
            b: 200,
            a: 255,
        },
    };
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 80, 40, 1.0),
        ECU_OK
    );

    let insert = CString::new("!").unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_insert_text(ui, insert.as_ptr()),
        ECU_OK
    );

    let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
    assert!(!text_ptr.is_null());
    let text = unsafe { CStr::from_ptr(text_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(text_ptr) };
    assert_eq!(text, "!abc");

    // undo/redo smoke
    assert_eq!(editor_core_ui_ffi_editor_ui_undo(ui), ECU_OK);
    let t2_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
    let t2 = unsafe { CStr::from_ptr(t2_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(t2_ptr) };
    assert_eq!(t2, "abc");
    assert_eq!(editor_core_ui_ffi_editor_ui_redo(ui), ECU_OK);

    let mut out_len: u32 = 0;
    let mut buf = vec![0u8; 80 * 40 * 4];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(out_len as usize, buf.len());
    assert_eq!(pixel(&buf, 80, 70, 30), [10, 20, 30, 255]);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_insert_tab_default_spaces_mode_inserts_to_next_stop() {
    let initial = CString::new("abc").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    // Caret at end of "abc" (col=3, tab_width=4) => inserts 1 space.
    let ranges = [EcuSelectionRange { start: 3, end: 3 }];
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), 1, 0) },
        ECU_OK
    );
    assert_eq!(editor_core_ui_ffi_editor_ui_insert_tab(ui), ECU_OK);

    let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
    assert!(!text_ptr.is_null());
    let text = unsafe { CStr::from_ptr(text_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(text_ptr) };
    assert_eq!(text, "abc ");

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_insert_tab_respects_tab_width_setting_in_spaces_mode() {
    let initial = CString::new("a").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    assert_eq!(editor_core_ui_ffi_editor_ui_set_tab_width(ui, 2), ECU_OK);

    // Caret at end of "a" (col=1, tab_width=2) => inserts 1 space.
    let ranges = [EcuSelectionRange { start: 1, end: 1 }];
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), 1, 0) },
        ECU_OK
    );
    assert_eq!(editor_core_ui_ffi_editor_ui_insert_tab(ui), ECU_OK);

    let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
    assert!(!text_ptr.is_null());
    let text = unsafe { CStr::from_ptr(text_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(text_ptr) };
    assert_eq!(text, "a ");

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_insert_tab_respects_tab_key_behavior_tab_mode() {
    let initial = CString::new("").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_tab_key_behavior(ui, 0),
        ECU_OK
    );
    assert_eq!(editor_core_ui_ffi_editor_ui_insert_tab(ui), ECU_OK);

    let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
    assert!(!text_ptr.is_null());
    let text = unsafe { CStr::from_ptr(text_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(text_ptr) };
    assert_eq!(text, "\t");

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_minimap_json_smoke() {
    let initial = CString::new("a\nb\nc").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let ptr = editor_core_ui_ffi_editor_ui_minimap_json(ui, 0, 20);
    assert!(!ptr.is_null());
    let json = unsafe { CStr::from_ptr(ptr) }.to_str().unwrap().to_string();
    unsafe { editor_core_ui_ffi_string_free(ptr) };

    assert!(json.contains("\"lines\""));
    assert!(json.contains("\"actual_line_count\""));

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_selected_text_and_delete_selections_only_roundtrip() {
    let initial = CString::new("one two three").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    // Selections: "one", caret, "three".
    let ranges = [
        EcuSelectionRange { start: 0, end: 3 },
        EcuSelectionRange { start: 4, end: 4 },
        EcuSelectionRange { start: 8, end: 13 },
    ];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), ranges.len() as u32, 0)
        },
        ECU_OK
    );

    let sel_ptr = editor_core_ui_ffi_editor_ui_get_selected_text(ui);
    assert!(!sel_ptr.is_null());
    let sel = unsafe { CStr::from_ptr(sel_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(sel_ptr) };
    assert_eq!(sel, "one\nthree");

    assert_eq!(
        editor_core_ui_ffi_editor_ui_delete_selections_only(ui),
        ECU_OK
    );

    let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
    assert!(!text_ptr.is_null());
    let text = unsafe { CStr::from_ptr(text_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(text_ptr) };
    assert_eq!(text, " two ");

    // Cut should clear selections (leave carets only), so selected text becomes empty.
    let sel2_ptr = editor_core_ui_ffi_editor_ui_get_selected_text(ui);
    assert!(!sel2_ptr.is_null());
    let sel2 = unsafe { CStr::from_ptr(sel2_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(sel2_ptr) };
    assert_eq!(sel2, "");

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_set_style_colors_affects_rendering() {
    // Use a space in the styled cell so glyph rasterization does not affect the pixel sample.
    let initial = CString::new("a c").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let theme = EcuTheme {
        background: EcuRgba8 {
            r: 10,
            g: 20,
            b: 30,
            a: 255,
        },
        foreground: EcuRgba8 {
            r: 250,
            g: 250,
            b: 250,
            a: 255,
        },
        selection_background: EcuRgba8 {
            r: 200,
            g: 0,
            b: 0,
            a: 255,
        },
        caret: EcuRgba8 {
            r: 0,
            g: 0,
            b: 200,
            a: 255,
        },
    };
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 80, 40, 1.0),
        ECU_OK
    );

    // Apply style id 42 to the middle cell (a space).
    assert_eq!(editor_core_ui_ffi_editor_ui_add_style(ui, 1, 2, 42), ECU_OK);

    let styles = [EcuStyleColors {
        style_id: 42,
        flags: ECU_STYLE_FLAG_BACKGROUND,
        foreground: EcuRgba8 {
            r: 0,
            g: 0,
            b: 0,
            a: 0,
        },
        background: EcuRgba8 {
            r: 1,
            g: 200,
            b: 2,
            a: 255,
        },
    }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32)
        },
        ECU_OK
    );

    let mut out_len: u32 = 0;
    let mut buf = vec![0u8; 80 * 40 * 4];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(out_len as usize, buf.len());

    // Styled cell is at x in [10..20], pick a center pixel at y=10.
    assert_eq!(pixel(&buf, 80, 15, 10), [1, 200, 2, 255]);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_set_style_text_decorations_affects_rendering() {
    // Use a space in the styled cell so glyph rasterization does not affect the pixel sample.
    let initial = CString::new("a c").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let bg = EcuRgba8 {
        r: 10,
        g: 20,
        b: 30,
        a: 255,
    };
    let theme = EcuTheme {
        background: bg,
        foreground: bg,
        selection_background: bg,
        caret: bg,
    };
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 10.0, 10.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 80, 20, 1.0),
        ECU_OK
    );

    // Apply style id 42 to the middle cell (a space).
    assert_eq!(editor_core_ui_ffi_editor_ui_add_style(ui, 1, 2, 42), ECU_OK);

    let decorations = [EcuStyleTextDecorations {
        style_id: 42,
        flags: ECU_TEXT_DECORATION_FLAG_UNDERLINE | ECU_TEXT_DECORATION_FLAG_UNDERLINE_COLOR,
        underline_style: 3, // squiggly
        underline_color: EcuRgba8 {
            r: 1,
            g: 200,
            b: 2,
            a: 255,
        },
        strikethrough: 0,
        strikethrough_color: EcuRgba8 {
            r: 0,
            g: 0,
            b: 0,
            a: 0,
        },
    }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_style_text_decorations(
                ui,
                decorations.as_ptr(),
                decorations.len() as u32,
            )
        },
        ECU_OK
    );

    let mut out_len: u32 = 0;
    let mut buf = vec![0u8; 80 * 20 * 4];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(out_len as usize, buf.len());

    // Styled cell is at x in [10..20]. The squiggle starts at y=9 (line height 10).
    assert_eq!(pixel(&buf, 80, 11, 9), [1, 200, 2, 255]);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_sublime_highlight_scope_mapping_and_rendering() {
    // Put a space after '#' so we can sample a highlighted cell without glyph pixels.
    let initial = CString::new("a # \n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let theme = EcuTheme {
        background: EcuRgba8 {
            r: 10,
            g: 20,
            b: 30,
            a: 255,
        },
        foreground: EcuRgba8 {
            r: 250,
            g: 250,
            b: 250,
            a: 255,
        },
        selection_background: EcuRgba8 {
            r: 200,
            g: 0,
            b: 0,
            a: 255,
        },
        caret: EcuRgba8 {
            r: 0,
            g: 0,
            b: 200,
            a: 255,
        },
    };
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
        ECU_OK
    );

    let yaml = CString::new(
        r##"%YAML 1.2
---
name: Demo
scope: source.demo
contexts:
  main:
    - match: "#.*$"
      scope: comment.line.demo
"##,
    )
    .unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_sublime_set_syntax_yaml(ui, yaml.as_ptr()),
        ECU_OK
    );

    let scope = CString::new("comment.line.demo").unwrap();
    let mut style_id: u32 = 0;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_sublime_style_id_for_scope(
                ui,
                scope.as_ptr(),
                &mut style_id,
            )
        },
        ECU_OK
    );

    let scope_ptr = editor_core_ui_ffi_editor_ui_sublime_scope_for_style_id(ui, style_id);
    assert!(!scope_ptr.is_null());
    let roundtrip = unsafe { CStr::from_ptr(scope_ptr) }.to_str().unwrap();
    assert_eq!(roundtrip, "comment.line.demo");
    unsafe { editor_core_ui_ffi_string_free(scope_ptr) };

    let styles = [EcuStyleColors {
        style_id,
        flags: ECU_STYLE_FLAG_BACKGROUND,
        foreground: EcuRgba8 {
            r: 0,
            g: 0,
            b: 0,
            a: 0,
        },
        background: EcuRgba8 {
            r: 1,
            g: 200,
            b: 2,
            a: 255,
        },
    }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32)
        },
        ECU_OK
    );

    let mut out_len: u32 = 0;
    let mut buf = vec![0u8; 200 * 40 * 4];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(out_len as usize, buf.len());

    // "a # " => space at col=3 is highlighted => x in [30..40]
    assert_eq!(pixel(&buf, 200, 35, 10), [1, 200, 2, 255]);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_treesitter_highlight_capture_mapping_and_rendering() {
    let initial = CString::new("// c\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let theme = EcuTheme {
        background: EcuRgba8 {
            r: 10,
            g: 20,
            b: 30,
            a: 255,
        },
        foreground: EcuRgba8 {
            r: 250,
            g: 250,
            b: 250,
            a: 255,
        },
        selection_background: EcuRgba8 {
            r: 200,
            g: 0,
            b: 0,
            a: 255,
        },
        caret: EcuRgba8 {
            r: 0,
            g: 0,
            b: 200,
            a: 255,
        },
    };
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
        ECU_OK
    );

    set_test_treesitter_registry(ui);
    let language_id = CString::new("rust").unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_treesitter_enable_language(ui, language_id.as_ptr()),
        ECU_OK
    );
    wait_for_processing(ui);

    let capture = CString::new("comment").unwrap();
    let mut style_id: u32 = 0;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_treesitter_style_id_for_capture(
                ui,
                capture.as_ptr(),
                &mut style_id,
            )
        },
        ECU_OK
    );

    let name_ptr = editor_core_ui_ffi_editor_ui_treesitter_capture_for_style_id(ui, style_id);
    assert!(!name_ptr.is_null());
    let roundtrip = unsafe { CStr::from_ptr(name_ptr) }.to_str().unwrap();
    assert_eq!(roundtrip, "comment");
    unsafe { editor_core_ui_ffi_string_free(name_ptr) };

    let styles = [EcuStyleColors {
        style_id,
        flags: ECU_STYLE_FLAG_BACKGROUND,
        foreground: EcuRgba8 {
            r: 0,
            g: 0,
            b: 0,
            a: 0,
        },
        background: EcuRgba8 {
            r: 1,
            g: 200,
            b: 2,
            a: 255,
        },
    }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32)
        },
        ECU_OK
    );

    let mut out_len: u32 = 0;
    let mut buf = vec![0u8; 200 * 40 * 4];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(out_len as usize, buf.len());

    // Comment contains a space at col=2 => x in [20..30]
    assert_eq!(pixel(&buf, 200, 25, 10), [1, 200, 2, 255]);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_get_set_selections_roundtrip_and_insert_applies_to_all() {
    let initial = CString::new("abc\ndef\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let ranges = [
        EcuSelectionRange { start: 0, end: 0 },
        EcuSelectionRange { start: 4, end: 4 },
    ];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), ranges.len() as u32, 0)
        },
        ECU_OK
    );

    let mut required: u32 = 0;
    let mut primary: u32 = 0;
    let code = unsafe {
        editor_core_ui_ffi_editor_ui_get_selections(
            ui,
            ptr::null_mut(),
            0,
            &mut required,
            &mut primary,
        )
    };
    assert_eq!(code, ECU_ERR_BUFFER_TOO_SMALL);
    assert_eq!(required, 2);
    assert_eq!(primary, 0);

    let mut out = vec![EcuSelectionRange { start: 0, end: 0 }; required as usize];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_get_selections(
                ui,
                out.as_mut_ptr(),
                out.len() as u32,
                &mut required,
                &mut primary,
            )
        },
        ECU_OK
    );
    assert_eq!(required as usize, out.len());
    assert_eq!(out[0].start, 0);
    assert_eq!(out[0].end, 0);
    assert_eq!(out[1].start, 4);
    assert_eq!(out[1].end, 4);

    let insert = CString::new("X").unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_insert_text(ui, insert.as_ptr()),
        ECU_OK
    );

    let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
    let text = unsafe { CStr::from_ptr(text_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(text_ptr) };
    assert_eq!(text, "Xabc\nXdef\n");

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_rect_selection_replaces_each_line_range() {
    let initial = CString::new("abc\ndef\nghi\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    // anchor: offset 1 ('b'), active: offset 10 ('i')
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_rect_selection(ui, 1, 10),
        ECU_OK
    );

    let insert = CString::new("X").unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_insert_text(ui, insert.as_ptr()),
        ECU_OK
    );

    let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
    let text = unsafe { CStr::from_ptr(text_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(text_ptr) };
    assert_eq!(text, "aXc\ndXf\ngXi\n");

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_multi_cursor_commands_work() {
    let initial = CString::new("aa\naa\naa\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    // One caret at line 1 col 1 => offset 4.
    let ranges = [EcuSelectionRange { start: 4, end: 4 }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), ranges.len() as u32, 0)
        },
        ECU_OK
    );

    assert_eq!(editor_core_ui_ffi_editor_ui_add_cursor_above(ui), ECU_OK);

    let insert = CString::new("X").unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_insert_text(ui, insert.as_ptr()),
        ECU_OK
    );

    let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
    let text = unsafe { CStr::from_ptr(text_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(text_ptr) };
    assert_eq!(text, "aXa\naXa\naa\n");

    assert_eq!(
        editor_core_ui_ffi_editor_ui_clear_secondary_selections(ui),
        ECU_OK
    );

    let mut required: u32 = 0;
    let mut primary: u32 = 0;
    let code = unsafe {
        editor_core_ui_ffi_editor_ui_get_selections(
            ui,
            ptr::null_mut(),
            0,
            &mut required,
            &mut primary,
        )
    };
    assert_eq!(code, ECU_ERR_BUFFER_TOO_SMALL);
    assert_eq!(required, 1);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_select_word_and_add_all_occurrences() {
    let initial = CString::new("foo foo foo\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    // Place caret at start.
    let ranges = [EcuSelectionRange { start: 0, end: 0 }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), ranges.len() as u32, 0)
        },
        ECU_OK
    );

    assert_eq!(editor_core_ui_ffi_editor_ui_select_word(ui), ECU_OK);
    assert_eq!(editor_core_ui_ffi_editor_ui_add_all_occurrences(ui), ECU_OK);

    let insert = CString::new("X").unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_insert_text(ui, insert.as_ptr()),
        ECU_OK
    );

    let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
    let text = unsafe { CStr::from_ptr(text_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(text_ptr) };
    assert_eq!(text, "X X X\n");

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_expand_selection_by_word_is_expand_only() {
    let initial = CString::new("one two three").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    // caret at start of "two" (offset 4)
    let ranges = [EcuSelectionRange { start: 4, end: 4 }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), ranges.len() as u32, 0)
        },
        ECU_OK
    );

    // 1 = word, 1 = forward
    assert_eq!(
        editor_core_ui_ffi_editor_ui_expand_selection_by(ui, 1, 2, 1),
        ECU_OK
    );

    let mut start: u32 = 0;
    let mut end: u32 = 0;
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
        ECU_OK
    );
    assert_eq!((start, end), (4, 13));

    // Change direction: 0 = backward. Expand-only means we keep the end and extend start.
    assert_eq!(
        editor_core_ui_ffi_editor_ui_expand_selection_by(ui, 1, 1, 0),
        ECU_OK
    );
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
        ECU_OK
    );
    assert_eq!((start, end), (0, 13));

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_word_boundary_config_affects_select_word() {
    let initial = CString::new("foo-bar").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    // caret inside "foo"
    let ranges = [EcuSelectionRange { start: 1, end: 1 }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), ranges.len() as u32, 0)
        },
        ECU_OK
    );
    assert_eq!(editor_core_ui_ffi_editor_ui_select_word(ui), ECU_OK);

    let mut start: u32 = 0;
    let mut end: u32 = 0;
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
        ECU_OK
    );
    assert_eq!((start, end), (0, 3)); // "foo"

    // Make '-' a word char (do not include it in boundary chars).
    let boundary = CString::new(".").unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_word_boundary_ascii_boundary_chars(ui, boundary.as_ptr()),
        ECU_OK
    );

    // Clear selection and select word again to observe config change.
    let ranges = [EcuSelectionRange { start: 1, end: 1 }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), ranges.len() as u32, 0)
        },
        ECU_OK
    );
    assert_eq!(editor_core_ui_ffi_editor_ui_select_word(ui), ECU_OK);
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
        ECU_OK
    );
    assert_eq!((start, end), (0, 7)); // "foo-bar"

    // Reset defaults: '-' becomes boundary again.
    assert_eq!(
        editor_core_ui_ffi_editor_ui_reset_word_boundary_defaults(ui),
        ECU_OK
    );
    let ranges = [EcuSelectionRange { start: 1, end: 1 }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), ranges.len() as u32, 0)
        },
        ECU_OK
    );
    assert_eq!(editor_core_ui_ffi_editor_ui_select_word(ui), ECU_OK);
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
        ECU_OK
    );
    assert_eq!((start, end), (0, 3)); // "foo"

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_word_movement_and_word_deletion_roundtrip() {
    let initial = CString::new("one two").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    // Move word right: 0 -> 3.
    assert_eq!(editor_core_ui_ffi_editor_ui_move_word_right(ui), ECU_OK);
    let mut start: u32 = 0;
    let mut end: u32 = 0;
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
        ECU_OK
    );
    assert_eq!((start, end), (3, 3));

    // Shift+Option right: extend selection to next boundary (3..4).
    assert_eq!(
        editor_core_ui_ffi_editor_ui_move_word_right_and_modify_selection(ui),
        ECU_OK
    );
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
        ECU_OK
    );
    assert_eq!((start, end), (3, 4));

    // Delete word back from end.
    let ranges = [EcuSelectionRange { start: 7, end: 7 }];
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), 1, 0) },
        ECU_OK
    );
    assert_eq!(editor_core_ui_ffi_editor_ui_delete_word_back(ui), ECU_OK);
    let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
    assert!(!text_ptr.is_null());
    let text = unsafe { CStr::from_ptr(text_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(text_ptr) };
    assert_eq!(text, "one ");

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_line_document_and_page_navigation_roundtrip() {
    // Line/document navigation.
    let initial = CString::new("abc\ndef").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    // Caret at offset 2 ("ab|c").
    let ranges = [EcuSelectionRange { start: 2, end: 2 }];
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), 1, 0) },
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_move_to_visual_line_start(ui),
        ECU_OK
    );
    let mut start: u32 = 0;
    let mut end: u32 = 0;
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
        ECU_OK
    );
    assert_eq!((start, end), (0, 0));

    assert_eq!(
        editor_core_ui_ffi_editor_ui_move_to_document_end(ui),
        ECU_OK
    );
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
        ECU_OK
    );
    assert_eq!((start, end), (7, 7));

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };

    // Page navigation depends on viewport height rows.
    let initial = CString::new("0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 10.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 100, 30, 1.0),
        ECU_OK
    ); // 3 rows

    let ranges = [EcuSelectionRange { start: 0, end: 0 }];
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), 1, 0) },
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_move_visual_by_pages(ui, 1),
        ECU_OK
    );
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
        ECU_OK
    );
    assert_eq!((start, end), (6, 6));

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_gutter_renders_fold_marker_and_click_toggles_fold() {
    let initial = CString::new("fn main() {\n  let x = 1;\n}\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let theme = EcuTheme {
        background: EcuRgba8 {
            r: 10,
            g: 20,
            b: 30,
            a: 255,
        },
        foreground: EcuRgba8 {
            r: 250,
            g: 250,
            b: 250,
            a: 255,
        },
        selection_background: EcuRgba8 {
            r: 200,
            g: 0,
            b: 0,
            a: 255,
        },
        caret: EcuRgba8 {
            r: 0,
            g: 0,
            b: 200,
            a: 255,
        },
    };
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 60, 1.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_fold_marker_style(ui, 1),
        ECU_OK
    );
    set_test_treesitter_registry(ui);
    assert_eq!(
        editor_core_ui_ffi_editor_ui_treesitter_rust_enable_default(ui),
        ECU_OK
    );
    wait_for_processing(ui);

    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_gutter_width_cells(ui, 4),
        ECU_OK
    );

    let styles = [
        // Make the gutter background visible and keep digits "invisible" to keep pixel tests deterministic.
        EcuStyleColors {
            style_id: editor_core_render_skia::GUTTER_BACKGROUND_STYLE_ID,
            flags: ECU_STYLE_FLAG_BACKGROUND,
            foreground: EcuRgba8 {
                r: 0,
                g: 0,
                b: 0,
                a: 0,
            },
            background: EcuRgba8 {
                r: 1,
                g: 2,
                b: 3,
                a: 255,
            },
        },
        EcuStyleColors {
            style_id: editor_core_render_skia::GUTTER_FOREGROUND_STYLE_ID,
            flags: ECU_STYLE_FLAG_FOREGROUND,
            foreground: EcuRgba8 {
                r: 1,
                g: 2,
                b: 3,
                a: 255,
            },
            background: EcuRgba8 {
                r: 0,
                g: 0,
                b: 0,
                a: 0,
            },
        },
        EcuStyleColors {
            style_id: editor_core_render_skia::FOLD_MARKER_EXPANDED_STYLE_ID,
            flags: ECU_STYLE_FLAG_BACKGROUND,
            foreground: EcuRgba8 {
                r: 0,
                g: 0,
                b: 0,
                a: 0,
            },
            background: EcuRgba8 {
                r: 9,
                g: 9,
                b: 9,
                a: 255,
            },
        },
        EcuStyleColors {
            style_id: editor_core_render_skia::FOLD_MARKER_COLLAPSED_STYLE_ID,
            flags: ECU_STYLE_FLAG_BACKGROUND,
            foreground: EcuRgba8 {
                r: 0,
                g: 0,
                b: 0,
                a: 0,
            },
            background: EcuRgba8 {
                r: 8,
                g: 8,
                b: 8,
                a: 255,
            },
        },
    ];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32)
        },
        ECU_OK
    );

    let mut out_len: u32 = 0;
    let mut buf = vec![0u8; 200 * 60 * 4];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(out_len as usize, buf.len());

    // Expanded fold marker at first gutter cell.
    assert_eq!(pixel(&buf, 200, 5, 10), [9, 9, 9, 255]);
    // Gutter background after the 2-cell block marker column.
    assert_eq!(pixel(&buf, 200, 25, 10), [1, 2, 3, 255]);

    // Click in gutter should toggle fold collapse.
    assert_eq!(
        editor_core_ui_ffi_editor_ui_mouse_down(ui, 5.0, 10.0),
        ECU_OK
    );
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(pixel(&buf, 200, 5, 10), [8, 8, 8, 255]);

    // And expand again on second click.
    assert_eq!(
        editor_core_ui_ffi_editor_ui_mouse_down(ui, 5.0, 10.0),
        ECU_OK
    );
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(pixel(&buf, 200, 5, 10), [9, 9, 9, 255]);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_move_and_modify_selection_extends_from_anchor() {
    let initial = CString::new("abc\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let ranges = [EcuSelectionRange { start: 2, end: 2 }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_selections(ui, ranges.as_ptr(), ranges.len() as u32, 0)
        },
        ECU_OK
    );

    assert_eq!(
        editor_core_ui_ffi_editor_ui_move_grapheme_left_and_modify_selection(ui),
        ECU_OK
    );
    let mut s: u32 = 0;
    let mut e: u32 = 0;
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut s, &mut e) },
        ECU_OK
    );
    assert_eq!((s, e), (1, 2));

    assert_eq!(
        editor_core_ui_ffi_editor_ui_move_grapheme_left_and_modify_selection(ui),
        ECU_OK
    );
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut s, &mut e) },
        ECU_OK
    );
    assert_eq!((s, e), (0, 2));

    assert_eq!(
        editor_core_ui_ffi_editor_ui_move_grapheme_right_and_modify_selection(ui),
        ECU_OK
    );
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut s, &mut e) },
        ECU_OK
    );
    assert_eq!((s, e), (1, 2));

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_lsp_diagnostics_affect_rendering() {
    // Use a space in the highlighted range so glyph rasterization does not affect the pixel sample.
    let initial = CString::new("a c\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let theme = EcuTheme {
        background: EcuRgba8 {
            r: 10,
            g: 20,
            b: 30,
            a: 255,
        },
        foreground: EcuRgba8 {
            r: 250,
            g: 250,
            b: 250,
            a: 255,
        },
        selection_background: EcuRgba8 {
            r: 200,
            g: 0,
            b: 0,
            a: 255,
        },
        caret: EcuRgba8 {
            r: 0,
            g: 0,
            b: 200,
            a: 255,
        },
    };
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
        ECU_OK
    );

    // LSP diagnostics style id encoding: 0x0400_0100 | severity.
    let styles = [EcuStyleColors {
        style_id: 0x0400_0100 | 1,
        flags: ECU_STYLE_FLAG_BACKGROUND,
        foreground: EcuRgba8 {
            r: 0,
            g: 0,
            b: 0,
            a: 0,
        },
        background: EcuRgba8 {
            r: 1,
            g: 200,
            b: 2,
            a: 255,
        },
    }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32)
        },
        ECU_OK
    );

    let params = CString::new(
        r#"{
              "uri": "file:///test",
              "diagnostics": [
                {
                  "range": {
                    "start": { "line": 0, "character": 1 },
                    "end": { "line": 0, "character": 2 }
                  },
                  "severity": 1,
                  "message": "unit"
                }
              ],
              "version": 1
            }"#,
    )
    .unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_lsp_apply_diagnostics_json(ui, params.as_ptr()),
        ECU_OK
    );

    let mut out_len: u32 = 0;
    let mut buf = vec![0u8; 200 * 40 * 4];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(out_len as usize, buf.len());

    assert_eq!(pixel(&buf, 200, 15, 10), [1, 200, 2, 255]);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_lsp_inlay_hints_affect_rendering() {
    // Use a space in the inlay hint label so glyph rasterization does not affect the pixel sample.
    let initial = CString::new("ab\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let theme = EcuTheme {
        background: EcuRgba8 {
            r: 10,
            g: 20,
            b: 30,
            a: 255,
        },
        foreground: EcuRgba8 {
            r: 250,
            g: 250,
            b: 250,
            a: 255,
        },
        selection_background: EcuRgba8 {
            r: 200,
            g: 0,
            b: 0,
            a: 255,
        },
        caret: EcuRgba8 {
            r: 0,
            g: 0,
            b: 200,
            a: 255,
        },
    };
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
        ECU_OK
    );

    // Built-in style id for LSP inlay hint virtual text: 0x0800_0001
    let styles = [EcuStyleColors {
        style_id: 0x0800_0001,
        flags: ECU_STYLE_FLAG_BACKGROUND,
        foreground: EcuRgba8 {
            r: 0,
            g: 0,
            b: 0,
            a: 0,
        },
        background: EcuRgba8 {
            r: 1,
            g: 200,
            b: 2,
            a: 255,
        },
    }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32)
        },
        ECU_OK
    );

    let result = CString::new(
        r#"[
              {
                "position": { "line": 0, "character": 1 },
                "label": " "
              }
            ]"#,
    )
    .unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_lsp_apply_inlay_hints_json(ui, result.as_ptr()),
        ECU_OK
    );

    let mut out_len: u32 = 0;
    let mut buf = vec![0u8; 200 * 40 * 4];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(out_len as usize, buf.len());

    // Inlay hint at offset=1 => inserted between 'a' and 'b' => col=1 => x in [10..20]
    assert_eq!(pixel(&buf, 200, 15, 10), [1, 200, 2, 255]);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_lsp_code_lens_affect_rendering() {
    // Use a space in the code lens title so glyph rasterization does not affect the pixel sample.
    let initial = CString::new("line1\nline2\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let theme = EcuTheme {
        background: EcuRgba8 {
            r: 10,
            g: 20,
            b: 30,
            a: 255,
        },
        foreground: EcuRgba8 {
            r: 250,
            g: 250,
            b: 250,
            a: 255,
        },
        selection_background: EcuRgba8 {
            r: 200,
            g: 0,
            b: 0,
            a: 255,
        },
        caret: EcuRgba8 {
            r: 0,
            g: 0,
            b: 200,
            a: 255,
        },
    };
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
        ECU_OK
    );

    // Built-in style id for LSP code lens virtual text: 0x0800_0002
    let styles = [EcuStyleColors {
        style_id: 0x0800_0002,
        flags: ECU_STYLE_FLAG_BACKGROUND,
        foreground: EcuRgba8 {
            r: 0,
            g: 0,
            b: 0,
            a: 0,
        },
        background: EcuRgba8 {
            r: 1,
            g: 200,
            b: 2,
            a: 255,
        },
    }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32)
        },
        ECU_OK
    );

    let result = CString::new(
            r#"[
              {
                "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } },
                "command": { "title": " ", "command": "noop" }
              }
            ]"#,
        )
        .unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_lsp_apply_code_lens_json(ui, result.as_ptr()),
        ECU_OK
    );

    let mut out_len: u32 = 0;
    let mut buf = vec![0u8; 200 * 40 * 4];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(out_len as usize, buf.len());

    // Code lens is an above-line virtual text line inserted at the top => row=0, col=0.
    assert_eq!(pixel(&buf, 200, 5, 10), [1, 200, 2, 255]);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_code_lens_hit_test_returns_payload_json() {
    let initial = CString::new("line1\nline2\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 400, 80, 1.0),
        ECU_OK
    );

    let result = CString::new(
            r#"[
              {
                "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } },
                "command": { "title": "Run tests", "command": "test.run", "arguments": [1] }
              }
            ]"#,
        )
        .unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_lsp_apply_code_lens_json(ui, result.as_ptr()),
        ECU_OK
    );

    let mut has_lens: u8 = 0;
    let mut json_ptr: *mut c_char = ptr::null_mut();
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_get_code_lens_json_at_view_point(
                ui,
                5.0,
                10.0,
                &mut has_lens,
                &mut json_ptr,
            )
        },
        ECU_OK
    );
    assert_eq!(has_lens, 1);
    assert!(!json_ptr.is_null());
    let json = unsafe { CStr::from_ptr(json_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(json_ptr) };
    let value: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(value["command"]["title"], "Run tests");
    assert_eq!(value["command"]["command"], "test.run");

    has_lens = 9;
    json_ptr = ptr::null_mut();
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_get_code_lens_json_at_view_point(
                ui,
                200.0,
                10.0,
                &mut has_lens,
                &mut json_ptr,
            )
        },
        ECU_OK
    );
    assert_eq!(has_lens, 0);
    assert!(json_ptr.is_null());

    has_lens = 9;
    json_ptr = ptr::null_mut();
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_get_code_lens_json_at_view_point(
                ui,
                5.0,
                30.0,
                &mut has_lens,
                &mut json_ptr,
            )
        },
        ECU_OK
    );
    assert_eq!(has_lens, 0);
    assert!(json_ptr.is_null());

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_lsp_document_links_affect_rendering() {
    // Use a space in the document link range so glyph rasterization does not affect the pixel sample.
    let initial = CString::new("a c\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let theme = EcuTheme {
        background: EcuRgba8 {
            r: 10,
            g: 20,
            b: 30,
            a: 255,
        },
        foreground: EcuRgba8 {
            r: 250,
            g: 250,
            b: 250,
            a: 255,
        },
        selection_background: EcuRgba8 {
            r: 200,
            g: 0,
            b: 0,
            a: 255,
        },
        caret: EcuRgba8 {
            r: 0,
            g: 0,
            b: 200,
            a: 255,
        },
    };
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 10.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 20, 1.0),
        ECU_OK
    );

    // Built-in style id for LSP document links underline: 0x0800_0003
    let styles = [EcuStyleColors {
        style_id: 0x0800_0003,
        flags: ECU_STYLE_FLAG_FOREGROUND,
        foreground: EcuRgba8 {
            r: 1,
            g: 200,
            b: 2,
            a: 255,
        },
        background: EcuRgba8 {
            r: 0,
            g: 0,
            b: 0,
            a: 0,
        },
    }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32)
        },
        ECU_OK
    );

    let result = CString::new(
            r#"[
              {
                "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 2 } },
                "target": "https://example.com"
              }
            ]"#,
        )
        .unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_lsp_apply_document_links_json(ui, result.as_ptr()),
        ECU_OK
    );

    let mut out_len: u32 = 0;
    let mut buf = vec![0u8; 200 * 20 * 4];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(out_len as usize, buf.len());

    // Underline is at y = line_height_px - 1 (scale=1), i.e. y=9. Link range is at col=1 => x in [10..20].
    assert_eq!(pixel(&buf, 200, 15, 9), [1, 200, 2, 255]);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_document_link_hit_test_returns_payload_json() {
    let initial = CString::new("a c\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 10.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 20, 1.0),
        ECU_OK
    );

    let result = CString::new(
            r#"[
              {
                "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 2 } },
                "target": "https://example.com"
              }
            ]"#,
        )
        .unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_lsp_apply_document_links_json(ui, result.as_ptr()),
        ECU_OK
    );

    let mut x: c_float = 0.0;
    let mut y: c_float = 0.0;
    let mut lh: c_float = 0.0;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_char_offset_to_view_point(ui, 1, &mut x, &mut y, &mut lh)
        },
        ECU_OK
    );
    assert!(lh > 0.0);

    let mut has: u8 = 0;
    let mut json_ptr: *mut c_char = ptr::null_mut();
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_get_document_link_json_at_view_point(
                ui,
                x + 1.0,
                y + 1.0,
                &mut has,
                &mut json_ptr,
            )
        },
        ECU_OK
    );
    assert_eq!(has, 1);
    assert!(!json_ptr.is_null());

    let json = unsafe { CStr::from_ptr(json_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(json_ptr) };
    assert!(json.contains("https://example.com"));

    // No link at col=0.
    let mut has2: u8 = 0;
    let mut json_ptr2: *mut c_char = ptr::null_mut();
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_get_document_link_json_at_view_point(
                ui,
                1.0,
                1.0,
                &mut has2,
                &mut json_ptr2,
            )
        },
        ECU_OK
    );
    assert_eq!(has2, 0);
    assert!(json_ptr2.is_null());

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_lsp_document_highlights_affect_rendering() {
    // Use a space in the highlighted range so glyph rasterization does not affect the pixel sample.
    let initial = CString::new("a c\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let theme = EcuTheme {
        background: EcuRgba8 {
            r: 10,
            g: 20,
            b: 30,
            a: 255,
        },
        foreground: EcuRgba8 {
            r: 250,
            g: 250,
            b: 250,
            a: 255,
        },
        selection_background: EcuRgba8 {
            r: 200,
            g: 0,
            b: 0,
            a: 255,
        },
        caret: EcuRgba8 {
            r: 0,
            g: 0,
            b: 200,
            a: 255,
        },
    };
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
        ECU_OK
    );

    // Built-in style id for LSP document highlight text: 0x0400_0001
    let styles = [EcuStyleColors {
        style_id: 0x0400_0001,
        flags: ECU_STYLE_FLAG_BACKGROUND,
        foreground: EcuRgba8 {
            r: 0,
            g: 0,
            b: 0,
            a: 0,
        },
        background: EcuRgba8 {
            r: 1,
            g: 200,
            b: 2,
            a: 255,
        },
    }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32)
        },
        ECU_OK
    );

    let result = CString::new(
            r#"[
              {
                "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 2 } },
                "kind": 1
              }
            ]"#,
        )
        .unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_lsp_apply_document_highlights_json(ui, result.as_ptr()),
        ECU_OK
    );

    let mut out_len: u32 = 0;
    let mut buf = vec![0u8; 200 * 40 * 4];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(out_len as usize, buf.len());

    // Highlighted cell at col=1 => x in [10..20]
    assert_eq!(pixel(&buf, 200, 15, 10), [1, 200, 2, 255]);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_match_highlights_affect_rendering() {
    // Use a space in the highlighted range so glyph rasterization does not affect the pixel sample.
    let initial = CString::new("a c\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let theme = EcuTheme {
        background: EcuRgba8 {
            r: 10,
            g: 20,
            b: 30,
            a: 255,
        },
        foreground: EcuRgba8 {
            r: 250,
            g: 250,
            b: 250,
            a: 255,
        },
        selection_background: EcuRgba8 {
            r: 200,
            g: 0,
            b: 0,
            a: 255,
        },
        caret: EcuRgba8 {
            r: 0,
            g: 0,
            b: 200,
            a: 255,
        },
    };
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
        ECU_OK
    );

    // Built-in match highlight style id: 0x0800_0004
    let styles = [EcuStyleColors {
        style_id: 0x0800_0004,
        flags: ECU_STYLE_FLAG_BACKGROUND,
        foreground: EcuRgba8 {
            r: 0,
            g: 0,
            b: 0,
            a: 0,
        },
        background: EcuRgba8 {
            r: 1,
            g: 200,
            b: 2,
            a: 255,
        },
    }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32)
        },
        ECU_OK
    );

    let ranges = [EcuSelectionRange { start: 1, end: 2 }];
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_match_highlights(ui, ranges.as_ptr(), 1) },
        ECU_OK
    );

    let mut out_len: u32 = 0;
    let mut buf = vec![0u8; 200 * 40 * 4];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(out_len as usize, buf.len());

    // Highlighted cell at col=1 => x in [10..20]
    assert_eq!(pixel(&buf, 200, 15, 10), [1, 200, 2, 255]);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_lsp_apply_workspace_edit_json_applies_current_document() {
    let initial = CString::new("abc\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let workspace_edit = CString::new(
            r#"{
                "changes": {
                    "file:///test.rs": [
                        { "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 2 } }, "newText": "B" }
                    ],
                    "file:///other.rs": [
                        { "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } }, "newText": "X" }
                    ]
                }
            }"#,
        )
        .unwrap();
    let uri = CString::new("file:///test.rs").unwrap();

    let result_ptr = editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_json(
        ui,
        workspace_edit.as_ptr(),
        uri.as_ptr(),
    );
    assert!(!result_ptr.is_null());
    let result_json = unsafe { CStr::from_ptr(result_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(result_ptr) };

    let result: serde_json::Value = serde_json::from_str(&result_json).unwrap();
    assert_eq!(result["applied"], true);
    assert_eq!(result["applied_uri"], "file:///test.rs");
    assert_eq!(result["applied_edit_count"], 1);
    assert_eq!(
        result["skipped_uris"],
        serde_json::json!(["file:///other.rs"])
    );

    let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
    assert!(!text_ptr.is_null());
    let text = unsafe { CStr::from_ptr(text_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(text_ptr) };
    assert_eq!(text, "aBc\n");

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_search_set_query_sets_match_highlights_and_returns_count() {
    // Use spaces as matches so glyph rasterization does not affect the pixel sample.
    let initial = CString::new("a c a\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let theme = EcuTheme {
        background: EcuRgba8 {
            r: 10,
            g: 20,
            b: 30,
            a: 255,
        },
        foreground: EcuRgba8 {
            r: 250,
            g: 250,
            b: 250,
            a: 255,
        },
        selection_background: EcuRgba8 {
            r: 200,
            g: 0,
            b: 0,
            a: 255,
        },
        caret: EcuRgba8 {
            r: 0,
            g: 0,
            b: 200,
            a: 255,
        },
    };
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
        ECU_OK
    );

    // Built-in match highlight style id: 0x0800_0004
    let styles = [EcuStyleColors {
        style_id: 0x0800_0004,
        flags: ECU_STYLE_FLAG_BACKGROUND,
        foreground: EcuRgba8 {
            r: 0,
            g: 0,
            b: 0,
            a: 0,
        },
        background: EcuRgba8 {
            r: 1,
            g: 200,
            b: 2,
            a: 255,
        },
    }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32)
        },
        ECU_OK
    );

    let query = CString::new(" ").unwrap();
    let mut count: u32 = 0;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_search_set_query(ui, query.as_ptr(), 1, 0, 0, &mut count)
        },
        ECU_OK
    );
    assert_eq!(count, 2);

    let mut out_len: u32 = 0;
    let mut buf = vec![0u8; 200 * 40 * 4];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(out_len as usize, buf.len());

    // First space at col=1 => x in [10..20]
    assert_eq!(pixel(&buf, 200, 15, 10), [1, 200, 2, 255]);
    // Second space at col=3 => x in [30..40]
    assert_eq!(pixel(&buf, 200, 35, 10), [1, 200, 2, 255]);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_find_next_and_replace_roundtrip() {
    let initial = CString::new("foo foo foo\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let query = CString::new("foo").unwrap();
    let mut found: u8 = 0;
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_find_next(ui, query.as_ptr(), 1, 0, 0, &mut found) },
        ECU_OK
    );
    assert_eq!(found, 1);

    let mut sel_start: u32 = 0;
    let mut sel_end: u32 = 0;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut sel_start, &mut sel_end)
        },
        ECU_OK
    );
    assert_eq!((sel_start, sel_end), (0, 3));

    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_find_next(ui, query.as_ptr(), 1, 0, 0, &mut found) },
        ECU_OK
    );
    assert_eq!(found, 1);
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut sel_start, &mut sel_end)
        },
        ECU_OK
    );
    assert_eq!((sel_start, sel_end), (4, 7));

    let replacement = CString::new("bar").unwrap();
    let mut replaced: u32 = 0;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_replace_current(
                ui,
                query.as_ptr(),
                replacement.as_ptr(),
                1,
                0,
                0,
                &mut replaced,
            )
        },
        ECU_OK
    );
    assert_eq!(replaced, 1);

    let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
    let text = unsafe { CStr::from_ptr(text_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(text_ptr) };
    assert_eq!(text, "foo bar foo\n");

    let replacement_all = CString::new("baz").unwrap();
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_replace_all(
                ui,
                query.as_ptr(),
                replacement_all.as_ptr(),
                1,
                0,
                0,
                &mut replaced,
            )
        },
        ECU_OK
    );
    assert_eq!(replaced, 2);

    let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
    let text = unsafe { CStr::from_ptr(text_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(text_ptr) };
    assert_eq!(text, "baz bar baz\n");

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_lsp_semantic_tokens_affect_rendering() {
    // Use a space in the highlighted range so glyph rasterization does not affect the pixel sample.
    let initial = CString::new("a c\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let theme = EcuTheme {
        background: EcuRgba8 {
            r: 10,
            g: 20,
            b: 30,
            a: 255,
        },
        foreground: EcuRgba8 {
            r: 250,
            g: 250,
            b: 250,
            a: 255,
        },
        selection_background: EcuRgba8 {
            r: 200,
            g: 0,
            b: 0,
            a: 255,
        },
        caret: EcuRgba8 {
            r: 0,
            g: 0,
            b: 200,
            a: 255,
        },
    };
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
        ECU_OK
    );

    let style_id = 7u32 << 16;
    let styles = [EcuStyleColors {
        style_id,
        flags: ECU_STYLE_FLAG_BACKGROUND,
        foreground: EcuRgba8 {
            r: 0,
            g: 0,
            b: 0,
            a: 0,
        },
        background: EcuRgba8 {
            r: 1,
            g: 200,
            b: 2,
            a: 255,
        },
    }];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_set_style_colors(ui, styles.as_ptr(), styles.len() as u32)
        },
        ECU_OK
    );

    let data = [0u32, 1, 1, 7, 0];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens(
                ui,
                data.as_ptr(),
                data.len() as u32,
            )
        },
        ECU_OK
    );

    let mut out_len: u32 = 0;
    let mut buf = vec![0u8; 200 * 40 * 4];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(out_len as usize, buf.len());

    assert_eq!(pixel(&buf, 200, 15, 10), [1, 200, 2, 255]);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_set_font_families_csv_accepts_unknown_and_rejects_invalid_utf8() {
    let initial = CString::new("").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let fonts = CString::new("Menlo, PingFang SC, Apple Color Emoji").unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_font_families_csv(ui, fonts.as_ptr()),
        ECU_OK
    );

    // Unknown fonts should still succeed (renderer falls back to a default typeface).
    let unknown = CString::new("ThisFontShouldNotExist-xyz").unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_font_families_csv(ui, unknown.as_ptr()),
        ECU_OK
    );

    // Invalid UTF-8 must be rejected with a non-empty last error message.
    let bad_bytes: [u8; 2] = [0xFF, 0x00];
    let code =
        editor_core_ui_ffi_editor_ui_set_font_families_csv(ui, bad_bytes.as_ptr() as *const c_char);
    assert_ne!(code, ECU_OK);

    let msg_ptr = editor_core_ui_ffi_last_error_message();
    let msg = unsafe { CStr::from_ptr(msg_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(msg_ptr) };
    assert!(msg.to_lowercase().contains("utf-8") || !msg.is_empty());

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_set_font_ligatures_enabled_smoke() {
    let initial = CString::new("a->b != c").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0);
    editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0);

    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_font_ligatures_enabled(ui, 1),
        ECU_OK
    );

    let mut out_len: u32 = 0;
    let mut buf = vec![0u8; 200 * 40 * 4];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(out_len as usize, buf.len());

    // Turning ligatures off again should also succeed.
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_font_ligatures_enabled(ui, 0),
        ECU_OK
    );

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_set_caret_width_and_visibility_affect_render_rgba() {
    let initial = CString::new("").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 10.0, 10.0, 10.0, 0.0, 0.0);
    editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 20, 10, 1.0);

    let theme = EcuTheme {
        background: EcuRgba8 {
            r: 0xFF,
            g: 0xFF,
            b: 0xFF,
            a: 0xFF,
        },
        foreground: EcuRgba8 {
            r: 0x11,
            g: 0x11,
            b: 0x11,
            a: 0xFF,
        },
        selection_background: EcuRgba8 {
            r: 0xC7,
            g: 0xDD,
            b: 0xFF,
            a: 0xFF,
        },
        caret: EcuRgba8 {
            r: 0x00,
            g: 0x00,
            b: 0x00,
            a: 0xFF,
        },
    };
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_theme(ui, &theme) },
        ECU_OK
    );

    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_caret_width_px(ui, 4.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_caret_visible(ui, 1),
        ECU_OK
    );

    let mut out_len: u32 = 0;
    let mut buf = vec![0u8; 20 * 10 * 4];
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    assert_eq!(out_len as usize, buf.len());

    let caret_px = [0u8, 0u8, 0u8, 255u8];
    let caret_count0 = buf.chunks_exact(4).filter(|p| *p == caret_px).count();
    assert_eq!(
        caret_count0,
        4 * 10,
        "expected caret to fill a 4x10 rectangle"
    );

    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_caret_visible(ui, 0),
        ECU_OK
    );
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_render_rgba(
                ui,
                buf.as_mut_ptr(),
                buf.len() as u32,
                &mut out_len,
            )
        },
        ECU_OK
    );
    let caret_count1 = buf.chunks_exact(4).filter(|p| *p == caret_px).count();
    assert_eq!(
        caret_count1, 0,
        "expected caret pixels to disappear when hidden"
    );

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_render_buffer_too_small_sets_out_len() {
    let initial = CString::new("").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0);
    editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 80, 40, 1.0);

    let mut out_len: u32 = 0;
    let mut buf = vec![0u8; 10];
    let code = unsafe {
        editor_core_ui_ffi_editor_ui_render_rgba(
            ui,
            buf.as_mut_ptr(),
            buf.len() as u32,
            &mut out_len,
        )
    };
    assert_eq!(code, ECU_ERR_BUFFER_TOO_SMALL);
    assert_eq!(out_len, 80 * 40 * 4);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_render_allows_out_buf_null_as_size_query() {
    let initial = CString::new("").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0);
    editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 80, 40, 1.0);

    let mut out_len: u32 = 0;
    let code =
        unsafe { editor_core_ui_ffi_editor_ui_render_rgba(ui, ptr::null_mut(), 0, &mut out_len) };
    assert_eq!(code, ECU_ERR_BUFFER_TOO_SMALL);
    assert_eq!(out_len, 80 * 40 * 4);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_render_rejects_null_out_len() {
    let initial = CString::new("").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let code = unsafe {
        editor_core_ui_ffi_editor_ui_render_rgba(ui, ptr::null_mut(), 0, ptr::null_mut())
    };
    assert_eq!(code, ECU_ERR_INVALID_ARGUMENT);

    let msg_ptr = editor_core_ui_ffi_last_error_message();
    let msg = unsafe { CStr::from_ptr(msg_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(msg_ptr) };
    assert!(msg.contains("out_len is null"));

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_render_rejects_required_length_that_exceeds_u32() {
    let initial = CString::new("").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 1.0, 1.0, 1.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, u32::MAX, 2, 1.0),
        ECU_OK
    );

    let mut out_len: u32 = 123;
    let code =
        unsafe { editor_core_ui_ffi_editor_ui_render_rgba(ui, ptr::null_mut(), 0, &mut out_len) };
    assert_eq!(code, ECU_ERR_INVALID_ARGUMENT);
    assert_eq!(out_len, 123);

    let msg_ptr = editor_core_ui_ffi_last_error_message();
    let msg = unsafe { CStr::from_ptr(msg_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(msg_ptr) };
    assert!(msg.contains("rgba buffer required length"));

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_set_match_highlights_rejects_null_nonzero_ranges() {
    let initial = CString::new("abc").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let code = unsafe { editor_core_ui_ffi_editor_ui_set_match_highlights(ui, ptr::null(), 1) };
    assert_eq!(code, ECU_ERR_INVALID_ARGUMENT);

    let msg_ptr = editor_core_ui_ffi_last_error_message();
    let msg = unsafe { CStr::from_ptr(msg_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(msg_ptr) };
    assert!(msg.contains("ranges is null"));

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_null_args_set_last_error() {
    let code = editor_core_ui_ffi_editor_ui_insert_text(ptr::null_mut(), ptr::null());
    assert_eq!(code, ECU_ERR_INVALID_ARGUMENT);
    let msg_ptr = editor_core_ui_ffi_last_error_message();
    let msg = unsafe { CStr::from_ptr(msg_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(msg_ptr) };
    assert!(msg.contains("ui is null") || msg.contains("text_utf8 is null"));
}

#[test]
fn ffi_selection_and_marked_range_queries() {
    let initial = CString::new("abcd").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    // Configure minimal metrics/viewport so offset mapping can work.
    editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0);
    editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 60, 1.0);

    // Default selection is caret at 0.
    let mut start: u32 = 0;
    let mut end: u32 = 0;
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
        ECU_OK
    );
    assert_eq!((start, end), (0, 0));

    // Marked text.
    let marked = CString::new("你").unwrap();
    editor_core_ui_ffi_editor_ui_set_marked_text(ui, marked.as_ptr());

    let mut has: u8 = 0;
    let mut ms: u32 = 0;
    let mut ml: u32 = 0;
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_marked_range(ui, &mut has, &mut ms, &mut ml) },
        ECU_OK
    );
    assert_eq!(has, 1);
    assert_eq!(ml, 1);

    // Inline/preedit: selection inside marked string.
    let marked2 = CString::new("你好").unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_marked_text_ex(
            ui,
            marked2.as_ptr(),
            1,        // selected_start inside "你好"
            0,        // selected_len
            u32::MAX, // replace_start: use existing marked range
            0         // replace_len (ignored)
        ),
        ECU_OK
    );
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui, &mut start, &mut end) },
        ECU_OK
    );
    assert_eq!((start, end), (1, 1));

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_view_point_hit_test_returns_char_offset() {
    let initial = CString::new("abcd\nefgh\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0);
    editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 60, 1.0);

    // Point at row 0, col ~2.
    let mut off: u32 = 0;
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_view_point_to_char_offset(ui, 25.0, 10.0, &mut off) },
        ECU_OK
    );
    assert_eq!(off, 2);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_char_offset_to_logical_position_roundtrip() {
    let initial = CString::new("ab\ncde\nf").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let mut line: u32 = 0;
    let mut col: u32 = 0;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_char_offset_to_logical_position(ui, 4, &mut line, &mut col)
        },
        ECU_OK
    );
    assert_eq!(line, 1);
    assert_eq!(col, 1);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_get_viewport_state_and_set_smooth_scroll_state_roundtrip() {
    let initial = CString::new("0\n1\n2\n3\n4\n5\n6\n7").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 10.0, 10.0, 10.0, 0.0, 0.0);
    editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 80, 20, 1.0);

    let mut vp = EcuViewportState {
        width_cells: 0,
        height_rows: 0,
        has_height: 0,
        scroll_top: 0,
        sub_row_offset: 0,
        overscan_rows: 0,
        visible_start: 0,
        visible_end: 0,
        prefetch_start: 0,
        prefetch_end: 0,
        total_visual_lines: 0,
    };
    assert_eq!(
        editor_core_ui_ffi_editor_ui_get_viewport_state(ui, &mut vp),
        ECU_OK
    );
    assert_eq!(vp.total_visual_lines, 8);
    assert_eq!(vp.has_height, 1);
    assert_eq!(vp.height_rows, 2);
    assert_eq!(vp.scroll_top, 0);
    assert_eq!(vp.sub_row_offset, 0);

    unsafe { editor_core_ui_ffi_editor_ui_set_smooth_scroll_state(ui, 3, 32768) };
    assert_eq!(
        editor_core_ui_ffi_editor_ui_get_viewport_state(ui, &mut vp),
        ECU_OK
    );
    assert_eq!(vp.scroll_top, 3);
    assert_eq!(vp.sub_row_offset, 32768);

    // Clamp to maximum scroll position (total - height = 6).
    unsafe { editor_core_ui_ffi_editor_ui_set_smooth_scroll_state(ui, 999, 65535) };
    assert_eq!(
        editor_core_ui_ffi_editor_ui_get_viewport_state(ui, &mut vp),
        ECU_OK
    );
    assert_eq!(vp.scroll_top, 6);
    assert_eq!(vp.sub_row_offset, 0);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_clone_view_shares_text_and_has_independent_scroll_state() {
    let initial = CString::new("abc\ndef\nghi\njkl\nmno\npqr\nstu\nvwx\nyz\n").unwrap();
    let ui1 = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui1.is_null());
    let ui2 = editor_core_ui_ffi_editor_ui_clone_view(ui1, 80);
    assert!(!ui2.is_null());

    // Initial view state is independent.
    let r1 = EcuSelectionRange { start: 0, end: 0 };
    let r2 = EcuSelectionRange { start: 4, end: 4 };
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_selections(ui1, &r1 as *const _, 1, 0) },
        ECU_OK
    );
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_selections(ui2, &r2 as *const _, 1, 0) },
        ECU_OK
    );

    let mut start: u32 = 0;
    let mut end: u32 = 0;
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui1, &mut start, &mut end) },
        ECU_OK
    );
    assert_eq!((start, end), (0, 0));
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui2, &mut start, &mut end) },
        ECU_OK
    );
    assert_eq!((start, end), (4, 4));

    // Text edits are shared across views.
    let insert = CString::new("X").unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_insert_text(ui1, insert.as_ptr()),
        ECU_OK
    );
    let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui2);
    assert!(!text_ptr.is_null());
    let text = unsafe { CStr::from_ptr(text_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(text_ptr) };
    assert_eq!(text, "Xabc\ndef\nghi\njkl\nmno\npqr\nstu\nvwx\nyz\n");

    // Each view tracks its own selection, but receives the same text delta.
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_get_selection_offsets(ui2, &mut start, &mut end) },
        ECU_OK
    );
    assert_eq!((start, end), (5, 5));

    // Scroll state is view-local.
    editor_core_ui_ffi_editor_ui_set_render_metrics(ui1, 10.0, 10.0, 10.0, 0.0, 0.0);
    editor_core_ui_ffi_editor_ui_set_render_metrics(ui2, 10.0, 10.0, 10.0, 0.0, 0.0);
    editor_core_ui_ffi_editor_ui_set_viewport_px(ui1, 80, 20, 1.0);
    editor_core_ui_ffi_editor_ui_set_viewport_px(ui2, 80, 20, 1.0);

    unsafe { editor_core_ui_ffi_editor_ui_set_smooth_scroll_state(ui1, 1, 0) };
    unsafe { editor_core_ui_ffi_editor_ui_set_smooth_scroll_state(ui2, 3, 0) };

    let mut vp1 = EcuViewportState {
        width_cells: 0,
        height_rows: 0,
        has_height: 0,
        scroll_top: 0,
        sub_row_offset: 0,
        overscan_rows: 0,
        visible_start: 0,
        visible_end: 0,
        prefetch_start: 0,
        prefetch_end: 0,
        total_visual_lines: 0,
    };
    let mut vp2 = vp1;
    assert_eq!(
        editor_core_ui_ffi_editor_ui_get_viewport_state(ui1, &mut vp1),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_get_viewport_state(ui2, &mut vp2),
        ECU_OK
    );
    assert_eq!(vp1.scroll_top, 1);
    assert_eq!(vp2.scroll_top, 3);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui2) };
    unsafe { editor_core_ui_ffi_editor_ui_free(ui1) };
}

#[test]
fn ffi_smooth_scroll_by_pixels_affects_hit_test_and_view_point_mapping() {
    let initial = CString::new("a\nb\nc\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 10.0, 10.0, 10.0, 0.0, 0.0);
    editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 80, 20, 1.0);

    // Scroll down by half a row: content should move up by 5px.
    unsafe { editor_core_ui_ffi_editor_ui_scroll_by_pixels(ui, 5.0) };

    // "b" starts at char offset 2 ("a\nb..."), its y should be (1*10 - 5) = 5.
    let mut x: c_float = 0.0;
    let mut y: c_float = 0.0;
    let mut line_h: c_float = 0.0;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_char_offset_to_view_point(
                ui,
                2,
                &mut x,
                &mut y,
                &mut line_h,
            )
        },
        ECU_OK
    );
    assert_eq!(y, 5.0);

    let mut off: u32 = 0;
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_view_point_to_char_offset(ui, 0.0, 4.0, &mut off) },
        ECU_OK
    );
    assert_eq!(off, 0);
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_view_point_to_char_offset(ui, 0.0, 5.0, &mut off) },
        ECU_OK
    );
    assert_eq!(off, 2);
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_view_point_to_char_offset(ui, 0.0, 9.0, &mut off) },
        ECU_OK
    );
    assert_eq!(off, 2);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_metal_enable_rejects_null_handles() {
    let initial = CString::new("abc").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    assert_eq!(
        editor_core_ui_ffi_editor_ui_enable_metal(ui, ptr::null_mut(), ptr::null_mut()),
        ECU_ERR_INVALID_ARGUMENT
    );

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_metal_render_rejects_null_texture() {
    let initial = CString::new("abc").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    assert_eq!(
        editor_core_ui_ffi_editor_ui_render_metal(ui, ptr::null_mut()),
        ECU_ERR_INVALID_ARGUMENT
    );

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_get_logical_line_count_and_gutter_width_roundtrip() {
    let initial = CString::new("a\nb\nc").unwrap(); // 3 logical lines
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let mut lines: u32 = 0;
    assert_eq!(
        editor_core_ui_ffi_editor_ui_get_logical_line_count(ui, &mut lines),
        ECU_OK
    );
    assert_eq!(lines, 3);

    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_gutter_width_cells(ui, 7),
        ECU_OK
    );
    let mut gutter: u32 = 0;
    assert_eq!(
        editor_core_ui_ffi_editor_ui_get_gutter_width_cells(ui, &mut gutter),
        ECU_OK
    );
    assert_eq!(gutter, 7);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_reveal_primary_caret_scrolls_to_make_caret_visible() {
    let text = (0..100).map(|_| "x").collect::<Vec<_>>().join("\n");
    let initial = CString::new(text).unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 14.0, 10.0, 8.0, 0.0, 0.0);
    editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 800, 50, 1.0);
    unsafe { editor_core_ui_ffi_editor_ui_set_smooth_scroll_state(ui, 0, 0) };

    // Line 50, col 0 in "x\nx\n..." => offset 50*(1+1) = 100.
    let range = EcuSelectionRange {
        start: 100,
        end: 100,
    };
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_set_selections(ui, &range as *const _, 1, 0) },
        ECU_OK
    );

    assert_eq!(
        editor_core_ui_ffi_editor_ui_reveal_primary_caret(ui),
        ECU_OK
    );

    let mut vp = EcuViewportState {
        width_cells: 0,
        height_rows: 0,
        has_height: 0,
        scroll_top: 0,
        sub_row_offset: 0,
        overscan_rows: 0,
        visible_start: 0,
        visible_end: 0,
        prefetch_start: 0,
        prefetch_end: 0,
        total_visual_lines: 0,
    };
    assert_eq!(
        editor_core_ui_ffi_editor_ui_get_viewport_state(ui, &mut vp),
        ECU_OK
    );
    assert_eq!(vp.has_height, 1);
    assert_eq!(vp.height_rows, 5);
    assert_eq!(vp.scroll_top, 46);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_lsp_request_definition_errors_when_lsp_disabled() {
    let initial = CString::new("hello").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let mut out_id: u64 = 0;
    let code =
        unsafe { editor_core_ui_ffi_editor_ui_lsp_request_definition(ui, 0, 0, &mut out_id) };
    assert_eq!(code, ECU_ERR_INTERNAL);
    let code = unsafe { editor_core_ui_ffi_editor_ui_lsp_request_folding_ranges(ui, &mut out_id) };
    assert_eq!(code, ECU_ERR_INTERNAL);

    let msg_ptr = editor_core_ui_ffi_last_error_message();
    let msg = unsafe { CStr::from_ptr(msg_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(msg_ptr) };
    assert!(msg.to_lowercase().contains("lsp") && msg.to_lowercase().contains("enabled"));

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_lsp_format_document_errors_when_lsp_disabled() {
    let initial = CString::new("hello").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let mut applied: u8 = 0;
    let code = unsafe {
        editor_core_ui_ffi_editor_ui_lsp_format_document(ui, ptr::null(), 50, &mut applied)
    };
    assert_eq!(code, ECU_ERR_INTERNAL);

    let code = unsafe {
        editor_core_ui_ffi_editor_ui_lsp_format_range(ui, 0, 1, ptr::null(), 50, &mut applied)
    };
    assert_eq!(code, ECU_ERR_INTERNAL);

    let trigger = CString::new("\n").unwrap();
    let code = unsafe {
        editor_core_ui_ffi_editor_ui_lsp_format_on_type(
            ui,
            0,
            1,
            trigger.as_ptr(),
            ptr::null(),
            50,
            &mut applied,
        )
    };
    assert_eq!(code, ECU_ERR_INTERNAL);

    let msg_ptr = editor_core_ui_ffi_last_error_message();
    let msg = unsafe { CStr::from_ptr(msg_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(msg_ptr) };
    assert!(msg.to_lowercase().contains("lsp") && msg.to_lowercase().contains("enabled"));

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

fn pixel(buf: &[u8], width_px: u32, x: u32, y: u32) -> [u8; 4] {
    let idx = ((y * width_px + x) * 4) as usize;
    [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
}
