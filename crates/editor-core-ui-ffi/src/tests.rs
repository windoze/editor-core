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

fn take_owned_string(ptr: *mut libc::c_char) -> String {
    assert!(!ptr.is_null());
    let value = unsafe { std::ffi::CStr::from_ptr(ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(ptr) };
    value
}

#[test]
fn ffi_feature_flags_include_semantic_tokens_requests() {
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_LSP_SEMANTIC_TOKENS_REQUESTS,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_LSP_AUXILIARY_REQUESTS,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_LSP_AUXILIARY_RESOLVE_REQUESTS,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_WORKSPACE_OUTLINE_SNAPSHOT,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_MULTI_DOCUMENT_TAB_DOCUMENT_URI,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags()
            & ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION_EVENTS,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_ROOTS,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_MULTI_DOCUMENT_TAB_LANGUAGE_ID,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_JSON_COMMAND_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_LSP_RESULT_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_EVENT_STREAM_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags()
            & ECU_FEATURE_MULTI_DOCUMENT_SPECIAL_EVENT_STREAM_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_WORKSPACE_EDIT_TRANSACTION_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_WORKSPACE_DIAGNOSTICS_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_WORKSPACE_OUTLINE_SNAPSHOT_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_MULTI_DOCUMENT_SNAPSHOT_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_MULTI_DOCUMENT_SEARCH_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags()
            & ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_ROOTS_CHANGE_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags()
            & ECU_FEATURE_MULTI_DOCUMENT_PROJECT_LSP_SERVERS_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_EDITOR_UI_DERIVED_SNAPSHOT_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_LSP_STATUS_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_LSP_WORKSPACE_EDIT_APPLICATION_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_EDITOR_UI_MINIMAP_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags()
            & ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION_REDO,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_EDITOR_UI_VIEW_POINT_PAYLOAD_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_MULTI_DOCUMENT_PROJECT_LSP_START_PLAN,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags()
            & ECU_FEATURE_MULTI_DOCUMENT_PROJECT_LSP_LIFECYCLE_EVENTS,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags()
            & ECU_FEATURE_MULTI_DOCUMENT_PROJECT_LSP_LIFECYCLE_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_LSP_DERIVED_STATE_APPLICATION_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_LSP_SEMANTIC_TOKENS_APPLICATION_ENVELOPE,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_FILE_SEARCH,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_FILE_REPLACEMENT,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_MULTI_DOCUMENT_RECENT_FILES,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_FILE_LIST,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_MULTI_DOCUMENT_RECENT_PROJECTS,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_MULTI_DOCUMENT_PROJECT_FILE_INDEX,
        0
    );
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_MULTI_DOCUMENT_PROJECT_FILE_INDEX_QUERY,
        0
    );
}

#[test]
fn ffi_runtime_info_json_reports_version_and_feature_descriptors() {
    let runtime_json = take_owned_string(editor_core_ui_ffi_runtime_info_json());
    let runtime: serde_json::Value = serde_json::from_str(&runtime_json).unwrap();

    assert_eq!(runtime["kind"], "editor-core-ui-ffi");
    assert_eq!(runtime["abi_version"], ECU_ABI_VERSION);
    assert_eq!(runtime["version"], env!("CARGO_PKG_VERSION"));
    assert_eq!(runtime["feature_flags"], editor_core_ui_ffi_feature_flags());

    let features = runtime["features"].as_array().expect("features array");
    assert!(features.iter().any(|feature| {
        feature["name"] == "json_command_envelope"
            && feature["bit"] == 25
            && feature["flag"] == ECU_FEATURE_JSON_COMMAND_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "lsp_result_envelope"
            && feature["bit"] == 26
            && feature["flag"] == ECU_FEATURE_LSP_RESULT_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "event_stream_envelope"
            && feature["bit"] == 27
            && feature["flag"] == ECU_FEATURE_EVENT_STREAM_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_special_event_stream_envelope"
            && feature["bit"] == 28
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_SPECIAL_EVENT_STREAM_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "workspace_edit_transaction_envelope"
            && feature["bit"] == 29
            && feature["flag"] == ECU_FEATURE_WORKSPACE_EDIT_TRANSACTION_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "workspace_diagnostics_envelope"
            && feature["bit"] == 30
            && feature["flag"] == ECU_FEATURE_WORKSPACE_DIAGNOSTICS_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "workspace_outline_snapshot_envelope"
            && feature["bit"] == 31
            && feature["flag"] == ECU_FEATURE_WORKSPACE_OUTLINE_SNAPSHOT_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_snapshot_envelope"
            && feature["bit"] == 32
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_SNAPSHOT_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_search_envelope"
            && feature["bit"] == 33
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_SEARCH_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_workspace_roots_change_envelope"
            && feature["bit"] == 34
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_ROOTS_CHANGE_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_project_lsp_servers_envelope"
            && feature["bit"] == 35
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_PROJECT_LSP_SERVERS_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "editor_ui_derived_snapshot_envelope"
            && feature["bit"] == 36
            && feature["flag"] == ECU_FEATURE_EDITOR_UI_DERIVED_SNAPSHOT_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "lsp_status_envelope"
            && feature["bit"] == 37
            && feature["flag"] == ECU_FEATURE_LSP_STATUS_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "lsp_workspace_edit_application_envelope"
            && feature["bit"] == 38
            && feature["flag"] == ECU_FEATURE_LSP_WORKSPACE_EDIT_APPLICATION_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "editor_ui_minimap_envelope"
            && feature["bit"] == 39
            && feature["flag"] == ECU_FEATURE_EDITOR_UI_MINIMAP_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_workspace_edit_transaction_redo"
            && feature["bit"] == 40
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION_REDO
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "editor_ui_view_point_payload_envelope"
            && feature["bit"] == 41
            && feature["flag"] == ECU_FEATURE_EDITOR_UI_VIEW_POINT_PAYLOAD_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_project_lsp_start_plan"
            && feature["bit"] == 42
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_PROJECT_LSP_START_PLAN
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_project_lsp_lifecycle_events"
            && feature["bit"] == 43
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_PROJECT_LSP_LIFECYCLE_EVENTS
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_project_lsp_stop_plan"
            && feature["bit"] == 44
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_PROJECT_LSP_STOP_PLAN
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_project_lsp_restart_plan"
            && feature["bit"] == 45
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_PROJECT_LSP_RESTART_PLAN
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_project_lsp_lifecycle_envelope"
            && feature["bit"] == 46
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_PROJECT_LSP_LIFECYCLE_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "lsp_derived_state_application_envelope"
            && feature["bit"] == 47
            && feature["flag"] == ECU_FEATURE_LSP_DERIVED_STATE_APPLICATION_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "lsp_semantic_tokens_application_envelope"
            && feature["bit"] == 48
            && feature["flag"] == ECU_FEATURE_LSP_SEMANTIC_TOKENS_APPLICATION_ENVELOPE
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_workspace_file_search"
            && feature["bit"] == 49
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_FILE_SEARCH
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_workspace_file_replacement"
            && feature["bit"] == 50
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_FILE_REPLACEMENT
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_recent_files"
            && feature["bit"] == 51
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_RECENT_FILES
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_workspace_file_list"
            && feature["bit"] == 52
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_FILE_LIST
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_recent_projects"
            && feature["bit"] == 53
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_RECENT_PROJECTS
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_project_file_index"
            && feature["bit"] == 54
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_PROJECT_FILE_INDEX
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_project_file_index_query"
            && feature["bit"] == 55
            && feature["flag"] == ECU_FEATURE_MULTI_DOCUMENT_PROJECT_FILE_INDEX_QUERY
    }));
    assert!(features.iter().any(|feature| {
        feature["name"] == "multi_document_workspace_edit_transaction"
            && feature["flag"].as_u64().unwrap()
                & ECU_FEATURE_MULTI_DOCUMENT_WORKSPACE_EDIT_TRANSACTION
                != 0
    }));
}

#[test]
fn ffi_editor_ui_execute_command_envelope_json_reports_success_and_errors() {
    let initial = CString::new("abc").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let command = CString::new(r#"{"kind":"edit","op":"type_char","ch":"!"}"#).unwrap();
    let ok_json = take_owned_string(editor_core_ui_ffi_editor_ui_execute_command_envelope_json(
        ui,
        command.as_ptr(),
    ));
    let ok: serde_json::Value = serde_json::from_str(&ok_json).unwrap();
    assert_eq!(ok["ok"], true);
    assert_eq!(ok["version"], ECU_ABI_VERSION);
    assert_eq!(ok["value"]["kind"], "success");
    assert!(ok["error"].is_null());

    let command = CString::new(r#"{"kind":"edit","op":"type_char","ch":"too long"}"#).unwrap();
    let err_json = take_owned_string(editor_core_ui_ffi_editor_ui_execute_command_envelope_json(
        ui,
        command.as_ptr(),
    ));
    let err: serde_json::Value = serde_json::from_str(&err_json).unwrap();
    assert_eq!(err["ok"], false);
    assert_eq!(err["version"], ECU_ABI_VERSION);
    assert!(err["value"].is_null());
    assert_eq!(err["error"]["code"], "internal");
    assert_eq!(err["error"]["status"], ECU_ERR_INTERNAL);
    assert!(
        err["error"]["message"]
            .as_str()
            .unwrap()
            .contains("ch must be exactly one character")
    );

    let null_arg_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_execute_command_envelope_json(ui, ptr::null()),
    );
    let null_arg: serde_json::Value = serde_json::from_str(&null_arg_json).unwrap();
    assert_eq!(null_arg["ok"], false);
    assert_eq!(null_arg["error"]["code"], "invalid_argument");
    assert_eq!(null_arg["error"]["status"], ECU_ERR_INVALID_ARGUMENT);
    assert_eq!(null_arg["error"]["message"], "command_json_utf8 is null");

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_editor_ui_derived_snapshot_envelope_json_reports_success_and_errors() {
    let initial = CString::new("fn main() {}\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let diagnostics = CString::new("diagnostics").unwrap();
    let ok_json = take_owned_string(editor_core_ui_ffi_editor_ui_derived_snapshot_envelope_json(
        ui,
        diagnostics.as_ptr(),
        0,
        0,
    ));
    let ok: serde_json::Value = serde_json::from_str(&ok_json).unwrap();
    assert_eq!(ok["ok"], true);
    assert_eq!(ok["snapshot"], "diagnostics");
    assert_eq!(ok["status"], "success");
    assert_eq!(ok["range"]["start"], 0);
    assert_eq!(ok["range"]["end"], 0);
    assert_eq!(ok["version"], ECU_ABI_VERSION);
    assert!(!ok["value"].is_null());
    assert!(ok["error"].is_null());

    let styles = CString::new("style_intervals").unwrap();
    let style_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_derived_snapshot_envelope_json(ui, styles.as_ptr(), 0, 4),
    );
    let style: serde_json::Value = serde_json::from_str(&style_json).unwrap();
    assert_eq!(style["ok"], true);
    assert_eq!(style["snapshot"], "style_intervals");
    assert_eq!(style["status"], "success");
    assert_eq!(style["range"]["start"], 0);
    assert_eq!(style["range"]["end"], 4);
    assert!(!style["value"].is_null());

    let unknown = CString::new("future_snapshot").unwrap();
    let error_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_derived_snapshot_envelope_json(ui, unknown.as_ptr(), 1, 2),
    );
    let error: serde_json::Value = serde_json::from_str(&error_json).unwrap();
    assert_eq!(error["ok"], false);
    assert_eq!(error["snapshot"], "future_snapshot");
    assert_eq!(error["status"], "error");
    assert_eq!(error["range"]["start"], 1);
    assert_eq!(error["range"]["end"], 2);
    assert_eq!(error["value"], serde_json::Value::Null);
    assert_eq!(error["error"]["code"], "invalid_argument");
    assert_eq!(error["error"]["status"], ECU_ERR_INVALID_ARGUMENT);
    assert_eq!(
        error["error"]["message"],
        "unknown derived snapshot \"future_snapshot\""
    );
    assert_eq!(error["version"], ECU_ABI_VERSION);

    let null_snapshot_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_derived_snapshot_envelope_json(ui, ptr::null(), 0, 0),
    );
    let null_snapshot: serde_json::Value = serde_json::from_str(&null_snapshot_json).unwrap();
    assert_eq!(null_snapshot["ok"], false);
    assert!(null_snapshot["snapshot"].is_null());
    assert_eq!(null_snapshot["error"]["code"], "invalid_argument");
    assert_eq!(null_snapshot["error"]["message"], "snapshot_utf8 is null");

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_lsp_status_envelope_json_reports_success_and_errors() {
    let initial = CString::new("abc").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let ok_json = take_owned_string(editor_core_ui_ffi_editor_ui_lsp_status_envelope_json(ui));
    let ok: serde_json::Value = serde_json::from_str(&ok_json).unwrap();
    assert_eq!(ok["ok"], true);
    assert_eq!(ok["status"], "success");
    assert_eq!(ok["version"], ECU_ABI_VERSION);
    assert_eq!(ok["value"]["availability"], "disabled");
    assert_eq!(ok["value"]["state"], "disabled");
    assert!(ok["error"].is_null());

    let error_json = take_owned_string(editor_core_ui_ffi_editor_ui_lsp_status_envelope_json(
        ptr::null_mut(),
    ));
    let error: serde_json::Value = serde_json::from_str(&error_json).unwrap();
    assert_eq!(error["ok"], false);
    assert_eq!(error["status"], "error");
    assert_eq!(error["value"], serde_json::Value::Null);
    assert_eq!(error["error"]["code"], "invalid_argument");
    assert_eq!(error["error"]["status"], ECU_ERR_INVALID_ARGUMENT);
    assert_eq!(error["error"]["message"], "ui is null");
    assert_eq!(error["version"], ECU_ABI_VERSION);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_lsp_take_last_result_envelope_json_reports_empty_and_errors() {
    let initial = CString::new("abc").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let hover = CString::new("hover").unwrap();
    let empty_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_lsp_take_last_result_envelope_json(ui, hover.as_ptr()),
    );
    let empty: serde_json::Value = serde_json::from_str(&empty_json).unwrap();
    assert_eq!(empty["ok"], true);
    assert_eq!(empty["slot"], "hover");
    assert_eq!(empty["status"], "empty");
    assert_eq!(empty["has_result"], false);
    assert!(empty["value"].is_null());
    assert!(empty["error"].is_null());
    assert_eq!(empty["version"], ECU_ABI_VERSION);

    let unknown = CString::new("future_slot").unwrap();
    let error_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_lsp_take_last_result_envelope_json(ui, unknown.as_ptr()),
    );
    let error: serde_json::Value = serde_json::from_str(&error_json).unwrap();
    assert_eq!(error["ok"], false);
    assert_eq!(error["slot"], "future_slot");
    assert_eq!(error["status"], "error");
    assert_eq!(error["has_result"], false);
    assert_eq!(error["error"]["code"], "invalid_argument");
    assert_eq!(error["error"]["status"], ECU_ERR_INVALID_ARGUMENT);
    assert!(
        error["error"]["message"]
            .as_str()
            .unwrap()
            .contains("unknown lsp result slot")
    );

    let null_slot_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_lsp_take_last_result_envelope_json(ui, ptr::null()),
    );
    let null_slot: serde_json::Value = serde_json::from_str(&null_slot_json).unwrap();
    assert_eq!(null_slot["ok"], false);
    assert!(null_slot["slot"].is_null());
    assert_eq!(null_slot["error"]["code"], "invalid_argument");
    assert_eq!(null_slot["error"]["message"], "slot_utf8 is null");

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_event_stream_envelope_json_reports_snapshots_and_errors() {
    let initial = CString::new("abc").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let state_stream = CString::new("state_events").unwrap();
    let state_json = take_owned_string(editor_core_ui_ffi_editor_ui_event_stream_envelope_json(
        ui,
        state_stream.as_ptr(),
        0,
    ));
    let state: serde_json::Value = serde_json::from_str(&state_json).unwrap();
    assert_eq!(state["ok"], true);
    assert_eq!(state["owner"], "editor_ui");
    assert_eq!(state["stream"], "state_events");
    assert_eq!(state["status"], "success");
    assert_eq!(state["after_sequence"], 0);
    assert_eq!(state["value"]["latest_sequence"], 0);
    assert_eq!(state["value"]["events"].as_array().unwrap().len(), 0);
    assert!(state["error"].is_null());
    assert_eq!(state["version"], ECU_ABI_VERSION);

    let unknown = CString::new("future_events").unwrap();
    let error_json = take_owned_string(editor_core_ui_ffi_editor_ui_event_stream_envelope_json(
        ui,
        unknown.as_ptr(),
        7,
    ));
    let error: serde_json::Value = serde_json::from_str(&error_json).unwrap();
    assert_eq!(error["ok"], false);
    assert_eq!(error["owner"], "editor_ui");
    assert_eq!(error["stream"], "future_events");
    assert_eq!(error["after_sequence"], 7);
    assert_eq!(error["error"]["code"], "invalid_argument");
    assert_eq!(error["error"]["status"], ECU_ERR_INVALID_ARGUMENT);
    assert!(
        error["error"]["message"]
            .as_str()
            .unwrap()
            .contains("unknown editor_ui event stream")
    );

    let null_stream_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_event_stream_envelope_json(ui, ptr::null(), 0),
    );
    let null_stream: serde_json::Value = serde_json::from_str(&null_stream_json).unwrap();
    assert_eq!(null_stream["ok"], false);
    assert!(null_stream["stream"].is_null());
    assert_eq!(null_stream["error"]["code"], "invalid_argument");
    assert_eq!(null_stream["error"]["message"], "stream_utf8 is null");

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };

    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());
    let request_stream = CString::new("lsp_request_events").unwrap();
    let multi_json = take_owned_string(
        editor_core_ui_ffi_multi_document_event_stream_envelope_json(
            multi,
            request_stream.as_ptr(),
            0,
        ),
    );
    let multi_envelope: serde_json::Value = serde_json::from_str(&multi_json).unwrap();
    assert_eq!(multi_envelope["ok"], true);
    assert_eq!(multi_envelope["owner"], "multi_document");
    assert_eq!(multi_envelope["stream"], "lsp_request_events");
    assert_eq!(multi_envelope["value"]["latest_sequence"], 0);
    assert_eq!(
        multi_envelope["value"]["events"].as_array().unwrap().len(),
        0
    );

    let diagnostics_stream = CString::new("workspace_diagnostics_events").unwrap();
    let diagnostics_json = take_owned_string(
        editor_core_ui_ffi_multi_document_event_stream_envelope_json(
            multi,
            diagnostics_stream.as_ptr(),
            0,
        ),
    );
    let diagnostics_envelope: serde_json::Value = serde_json::from_str(&diagnostics_json).unwrap();
    assert_eq!(diagnostics_envelope["ok"], true);
    assert_eq!(diagnostics_envelope["owner"], "multi_document");
    assert_eq!(
        diagnostics_envelope["stream"],
        "workspace_diagnostics_events"
    );
    assert_eq!(diagnostics_envelope["value"]["latest_sequence"], 0);
    assert_eq!(
        diagnostics_envelope["value"]["events"]
            .as_array()
            .unwrap()
            .len(),
        0
    );

    let workspace_edit_stream = CString::new("workspace_edit_transaction_events").unwrap();
    let workspace_edit_json = take_owned_string(
        editor_core_ui_ffi_multi_document_event_stream_envelope_json(
            multi,
            workspace_edit_stream.as_ptr(),
            0,
        ),
    );
    let workspace_edit_envelope: serde_json::Value =
        serde_json::from_str(&workspace_edit_json).unwrap();
    assert_eq!(workspace_edit_envelope["ok"], true);
    assert_eq!(workspace_edit_envelope["owner"], "multi_document");
    assert_eq!(
        workspace_edit_envelope["stream"],
        "workspace_edit_transaction_events"
    );
    assert_eq!(workspace_edit_envelope["value"]["latest_sequence"], 0);
    assert_eq!(
        workspace_edit_envelope["value"]["events"]
            .as_array()
            .unwrap()
            .len(),
        0
    );

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
}

#[test]
fn ffi_multi_document_snapshot_envelope_json_reports_success_and_errors() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let text = CString::new("alpha\n").unwrap();
    let mut tab_id = 0u64;
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(multi, text.as_ptr(), 80, &mut tab_id),
        ECU_OK
    );
    let title = CString::new("Alpha").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_title(multi, tab_id, title.as_ptr()),
        ECU_OK
    );
    let uri = CString::new("file:///project/Alpha.swift").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_document_uri(multi, tab_id, uri.as_ptr()),
        ECU_OK
    );
    let language = CString::new("swift").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_language_id(multi, tab_id, language.as_ptr()),
        ECU_OK
    );

    let envelope_json = take_owned_string(
        editor_core_ui_ffi_multi_document_snapshot_envelope_json(multi),
    );
    let envelope: serde_json::Value = serde_json::from_str(&envelope_json).unwrap();
    assert_eq!(envelope["ok"], true);
    assert_eq!(envelope["status"], "success");
    assert!(envelope["error"].is_null());
    assert_eq!(envelope["version"], ECU_ABI_VERSION);
    assert_eq!(envelope["value"]["active_tab_id"], tab_id);
    let tab = &envelope["value"]["tabs"][0];
    assert_eq!(tab["id"], tab_id);
    assert_eq!(tab["title"], "Alpha");
    assert_eq!(tab["document_uri"], "file:///project/Alpha.swift");
    assert_eq!(tab["language_id"], "swift");
    assert_eq!(tab["is_active"], true);
    assert_eq!(tab["is_modified"], false);
    assert_eq!(tab["view_count"], 1);
    assert_eq!(
        envelope["value"]["workspace_roots"]
            .as_array()
            .unwrap()
            .len(),
        0
    );

    let error_json = take_owned_string(editor_core_ui_ffi_multi_document_snapshot_envelope_json(
        ptr::null_mut(),
    ));
    let error: serde_json::Value = serde_json::from_str(&error_json).unwrap();
    assert_eq!(error["ok"], false);
    assert_eq!(error["status"], "error");
    assert!(error["value"].is_null());
    assert_eq!(error["error"]["code"], "invalid_argument");
    assert_eq!(error["error"]["status"], ECU_ERR_INVALID_ARGUMENT);
    assert_eq!(error["error"]["message"], "multi is null");
    assert_eq!(error["version"], ECU_ABI_VERSION);

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
}

#[test]
fn ffi_multi_document_search_envelope_json_reports_success_and_errors() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let alpha = CString::new("alpha world").unwrap();
    let beta = CString::new("beta world").unwrap();
    let mut alpha_id = 0u64;
    let mut beta_id = 0u64;
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(multi, alpha.as_ptr(), 80, &mut alpha_id),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(multi, beta.as_ptr(), 80, &mut beta_id),
        ECU_OK
    );

    let query = CString::new("world").unwrap();
    let envelope_json = take_owned_string(
        editor_core_ui_ffi_multi_document_search_all_tabs_envelope_json(
            multi,
            query.as_ptr(),
            1,
            0,
            0,
        ),
    );
    let envelope: serde_json::Value = serde_json::from_str(&envelope_json).unwrap();
    assert_eq!(envelope["ok"], true);
    assert_eq!(envelope["status"], "success");
    assert!(envelope["error"].is_null());
    assert_eq!(envelope["version"], ECU_ABI_VERSION);
    let results = envelope["value"]["results"].as_array().unwrap();
    assert_eq!(results.len(), 2);
    assert_eq!(results[0]["tab_id"], alpha_id);
    assert_eq!(results[0]["matches"][0]["start"], 6);
    assert_eq!(results[0]["matches"][0]["end"], 11);
    assert_eq!(results[1]["tab_id"], beta_id);

    let error_json = take_owned_string(
        editor_core_ui_ffi_multi_document_search_all_tabs_envelope_json(
            multi,
            ptr::null(),
            1,
            0,
            0,
        ),
    );
    let error: serde_json::Value = serde_json::from_str(&error_json).unwrap();
    assert_eq!(error["ok"], false);
    assert_eq!(error["status"], "error");
    assert!(error["value"].is_null());
    assert_eq!(error["error"]["code"], "invalid_argument");
    assert_eq!(error["error"]["status"], ECU_ERR_INVALID_ARGUMENT);
    assert_eq!(error["error"]["message"], "query_utf8 is null");
    assert_eq!(error["version"], ECU_ABI_VERSION);

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
}

#[test]
fn ffi_multi_document_workspace_file_search_reports_success_and_errors() {
    let mut root = std::env::temp_dir();
    root.push(format!(
        "editor_core_ui_ffi_workspace_file_search_{}_{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::write(
        root.join("src").join("lib.rs"),
        "pub fn demo() {\n    let needle = 1;\n}\n",
    )
    .unwrap();
    std::fs::write(root.join("notes.txt"), "needle outside include\n").unwrap();

    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let roots =
        CString::new(serde_json::json!([format!("file://{}", root.to_string_lossy())]).to_string())
            .unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_workspace_roots_json(multi, roots.as_ptr()),
        ECU_OK
    );

    let query = CString::new("needle").unwrap();
    let include = CString::new(r#"["*.rs"]"#).unwrap();
    let exclude = CString::new(r#"[]"#).unwrap();
    let json = take_owned_string(
        editor_core_ui_ffi_multi_document_search_workspace_files_json(
            multi,
            query.as_ptr(),
            include.as_ptr(),
            exclude.as_ptr(),
            0,
            0,
            0,
            10,
        ),
    );
    let value: serde_json::Value = serde_json::from_str(&json).unwrap();
    let results = value["results"].as_array().unwrap();
    assert_eq!(results.len(), 1);
    assert_eq!(results[0]["relative_path"], "src/lib.rs");
    assert_eq!(results[0]["line1"], 2);
    assert_eq!(results[0]["column1"], 9);
    assert_eq!(results[0]["line_text"], "let needle = 1;");

    let invalid_globs = CString::new("{}").unwrap();
    let error_json = take_owned_string(
        editor_core_ui_ffi_multi_document_search_workspace_files_envelope_json(
            multi,
            query.as_ptr(),
            invalid_globs.as_ptr(),
            exclude.as_ptr(),
            0,
            0,
            0,
            10,
        ),
    );
    let error: serde_json::Value = serde_json::from_str(&error_json).unwrap();
    assert_eq!(error["ok"], false);
    assert_eq!(error["status"], "error");
    assert_eq!(error["error"]["code"], "invalid_argument");
    assert!(
        error["error"]["message"]
            .as_str()
            .unwrap()
            .contains("include_globs_json_utf8 must be a JSON string array")
    );

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn ffi_multi_document_workspace_file_list_reports_files_and_errors() {
    let mut root = std::env::temp_dir();
    root.push(format!(
        "editor_core_ui_ffi_workspace_file_list_{}_{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::create_dir_all(root.join("target")).unwrap();
    std::fs::write(root.join("src").join("lib.rs"), "pub fn demo() {}\n").unwrap();
    std::fs::write(root.join("src").join("App.swift"), "let value = 1\n").unwrap();
    std::fs::write(root.join("README.md"), "# docs\n").unwrap();
    std::fs::write(root.join("target").join("generated.rs"), "ignored\n").unwrap();

    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let roots =
        CString::new(serde_json::json!([format!("file://{}", root.to_string_lossy())]).to_string())
            .unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_workspace_roots_json(multi, roots.as_ptr()),
        ECU_OK
    );

    let include = CString::new(r#"["src/**"]"#).unwrap();
    let exclude = CString::new(r#"["*.swift"]"#).unwrap();
    let json = take_owned_string(editor_core_ui_ffi_multi_document_list_workspace_files_json(
        multi,
        include.as_ptr(),
        exclude.as_ptr(),
        10,
    ));
    let value: serde_json::Value = serde_json::from_str(&json).unwrap();
    let files = value["files"].as_array().unwrap();
    assert_eq!(files.len(), 1);
    assert_eq!(files[0]["relative_path"], "src/lib.rs");
    assert_eq!(
        files[0]["path"].as_str().unwrap(),
        root.join("src").join("lib.rs").to_string_lossy()
    );

    let invalid_globs = CString::new("{}").unwrap();
    let invalid = editor_core_ui_ffi_multi_document_list_workspace_files_json(
        multi,
        invalid_globs.as_ptr(),
        exclude.as_ptr(),
        10,
    );
    assert!(invalid.is_null());
    let last_error = take_owned_string(editor_core_ui_ffi_last_error_message());
    assert!(last_error.contains("include_globs_json_utf8 must be a JSON string array"));

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn ffi_multi_document_project_file_index_refreshes_and_snapshots_files() {
    let mut root = std::env::temp_dir();
    root.push(format!(
        "editor_core_ui_ffi_project_file_index_{}_{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::write(root.join("src").join("lib.rs"), "pub fn demo() {}\n").unwrap();
    std::fs::write(root.join("src").join("core_model.rs"), "pub fn core() {}\n").unwrap();

    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let roots =
        CString::new(serde_json::json!([format!("file://{}", root.to_string_lossy())]).to_string())
            .unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_workspace_roots_json(multi, roots.as_ptr()),
        ECU_OK
    );

    let snapshot_json = take_owned_string(
        editor_core_ui_ffi_multi_document_project_file_index_snapshot_json(multi),
    );
    let snapshot: serde_json::Value = serde_json::from_str(&snapshot_json).unwrap();
    assert_eq!(snapshot["is_built"], false);
    assert_eq!(snapshot["files"], serde_json::json!([]));

    let query = CString::new("cm").unwrap();
    let query_json = take_owned_string(
        editor_core_ui_ffi_multi_document_query_project_file_index_json(multi, query.as_ptr(), 10),
    );
    let query_value: serde_json::Value = serde_json::from_str(&query_json).unwrap();
    assert_eq!(query_value["results"], serde_json::json!([]));

    let refreshed_json = take_owned_string(
        editor_core_ui_ffi_multi_document_refresh_project_file_index_json(multi, 10),
    );
    let refreshed: serde_json::Value = serde_json::from_str(&refreshed_json).unwrap();
    assert_eq!(refreshed["is_built"], true);
    assert_eq!(refreshed["max_results"], 10);
    assert_eq!(refreshed["files"].as_array().unwrap().len(), 2);
    assert_eq!(refreshed["files"][0]["relative_path"], "src/core_model.rs");

    let query_json = take_owned_string(
        editor_core_ui_ffi_multi_document_query_project_file_index_json(multi, query.as_ptr(), 10),
    );
    let query_value: serde_json::Value = serde_json::from_str(&query_json).unwrap();
    assert_eq!(query_value["results"].as_array().unwrap().len(), 1);
    assert_eq!(
        query_value["results"][0]["relative_path"],
        "src/core_model.rs"
    );
    assert!(query_value["results"][0]["score"].as_i64().unwrap() > 0);

    std::fs::write(root.join("src").join("main.rs"), "fn main() {}\n").unwrap();
    let snapshot_json = take_owned_string(
        editor_core_ui_ffi_multi_document_project_file_index_snapshot_json(multi),
    );
    let snapshot: serde_json::Value = serde_json::from_str(&snapshot_json).unwrap();
    assert_eq!(snapshot["files"].as_array().unwrap().len(), 2);

    let refreshed_json = take_owned_string(
        editor_core_ui_ffi_multi_document_refresh_project_file_index_json(multi, 10),
    );
    let refreshed: serde_json::Value = serde_json::from_str(&refreshed_json).unwrap();
    assert_eq!(
        refreshed["files"]
            .as_array()
            .unwrap()
            .iter()
            .map(|file| file["relative_path"].as_str().unwrap())
            .collect::<Vec<_>>(),
        vec!["src/core_model.rs", "src/lib.rs", "src/main.rs"]
    );

    assert_eq!(
        editor_core_ui_ffi_multi_document_clear_project_file_index(multi),
        ECU_OK
    );
    let snapshot_json = take_owned_string(
        editor_core_ui_ffi_multi_document_project_file_index_snapshot_json(multi),
    );
    let snapshot: serde_json::Value = serde_json::from_str(&snapshot_json).unwrap();
    assert_eq!(snapshot["is_built"], false);
    assert_eq!(snapshot["files"], serde_json::json!([]));

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn ffi_multi_document_recent_files_round_trips_through_snapshot() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let roots = CString::new(r#"["file:///workspace"]"#).unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_workspace_roots_json(multi, roots.as_ptr()),
        ECU_OK
    );

    let a = CString::new(" file:///workspace/a.rs ").unwrap();
    let b = CString::new("file:///workspace/b.rs").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_remember_recent_file_uri(multi, a.as_ptr()),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_remember_recent_file_uri(multi, b.as_ptr()),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_remember_recent_file_uri(multi, a.as_ptr()),
        ECU_OK
    );

    let recent_json = take_owned_string(editor_core_ui_ffi_multi_document_recent_files_json(multi));
    let recent: serde_json::Value = serde_json::from_str(&recent_json).unwrap();
    assert_eq!(
        recent,
        serde_json::json!([
            { "uri": "file:///workspace/a.rs" },
            { "uri": "file:///workspace/b.rs" }
        ])
    );

    let snapshot_json = take_owned_string(editor_core_ui_ffi_multi_document_snapshot_json(multi));
    let snapshot: serde_json::Value = serde_json::from_str(&snapshot_json).unwrap();
    assert_eq!(snapshot["recent_files"], recent);

    let restored =
        CString::new(r#"["file:///workspace/restored.rs","file:///workspace/a.rs"]"#).unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_restore_recent_files_json(multi, restored.as_ptr()),
        ECU_OK
    );
    let recent_json = take_owned_string(editor_core_ui_ffi_multi_document_recent_files_json(multi));
    let recent: serde_json::Value = serde_json::from_str(&recent_json).unwrap();
    assert_eq!(
        recent,
        serde_json::json!([
            { "uri": "file:///workspace/restored.rs" },
            { "uri": "file:///workspace/a.rs" }
        ])
    );

    let next_roots = CString::new(r#"["file:///other"]"#).unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_workspace_roots_json(multi, next_roots.as_ptr()),
        ECU_OK
    );
    let cleared_json =
        take_owned_string(editor_core_ui_ffi_multi_document_recent_files_json(multi));
    let cleared: serde_json::Value = serde_json::from_str(&cleared_json).unwrap();
    assert_eq!(cleared, serde_json::json!([]));

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
}

#[test]
fn ffi_multi_document_recent_projects_round_trips_through_snapshot() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let a = CString::new(" file:///workspace/a ").unwrap();
    let b = CString::new("file:///workspace/b").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_remember_recent_project_uri(multi, a.as_ptr()),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_remember_recent_project_uri(multi, b.as_ptr()),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_remember_recent_project_uri(multi, a.as_ptr()),
        ECU_OK
    );

    let recent_json = take_owned_string(editor_core_ui_ffi_multi_document_recent_projects_json(
        multi,
    ));
    let recent: serde_json::Value = serde_json::from_str(&recent_json).unwrap();
    assert_eq!(
        recent,
        serde_json::json!([
            { "uri": "file:///workspace/a" },
            { "uri": "file:///workspace/b" }
        ])
    );

    let snapshot_json = take_owned_string(editor_core_ui_ffi_multi_document_snapshot_json(multi));
    let snapshot: serde_json::Value = serde_json::from_str(&snapshot_json).unwrap();
    assert_eq!(snapshot["recent_projects"], recent);

    let restored = CString::new(r#"["file:///workspace/restored","file:///workspace/a"]"#).unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_restore_recent_projects_json(multi, restored.as_ptr()),
        ECU_OK
    );
    let recent_json = take_owned_string(editor_core_ui_ffi_multi_document_recent_projects_json(
        multi,
    ));
    let recent: serde_json::Value = serde_json::from_str(&recent_json).unwrap();
    assert_eq!(
        recent,
        serde_json::json!([
            { "uri": "file:///workspace/restored" },
            { "uri": "file:///workspace/a" }
        ])
    );

    assert_eq!(
        editor_core_ui_ffi_multi_document_clear_recent_projects(multi),
        ECU_OK
    );
    let cleared_json = take_owned_string(editor_core_ui_ffi_multi_document_recent_projects_json(
        multi,
    ));
    let cleared: serde_json::Value = serde_json::from_str(&cleared_json).unwrap();
    assert_eq!(cleared, serde_json::json!([]));

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
}

#[test]
fn ffi_multi_document_workspace_file_replacement_builds_workspace_edit() {
    let mut root = std::env::temp_dir();
    root.push(format!(
        "editor_core_ui_ffi_workspace_file_replacement_{}_{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::write(root.join("src").join("lib.rs"), "👋 alpha1\nalpha2\n").unwrap();
    std::fs::write(root.join("notes.txt"), "alpha3\n").unwrap();

    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let roots =
        CString::new(serde_json::json!([format!("file://{}", root.to_string_lossy())]).to_string())
            .unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_workspace_roots_json(multi, roots.as_ptr()),
        ECU_OK
    );

    let query = CString::new(r"alpha(\d)").unwrap();
    let replacement = CString::new("beta$1").unwrap();
    let include = CString::new(r#"["*.rs"]"#).unwrap();
    let exclude = CString::new(r#"[]"#).unwrap();
    let apply_mode = CString::new("atomic").unwrap();
    let workspace_edit = take_owned_string(
        editor_core_ui_ffi_multi_document_workspace_file_replacement_workspace_edit_json(
            multi,
            query.as_ptr(),
            replacement.as_ptr(),
            include.as_ptr(),
            exclude.as_ptr(),
            apply_mode.as_ptr(),
            1,
            0,
            1,
            10,
        ),
    );
    let value: serde_json::Value = serde_json::from_str(&workspace_edit).unwrap();
    let document_changes = value["workspaceEdit"]["documentChanges"]
        .as_array()
        .unwrap();
    assert_eq!(document_changes.len(), 1);
    assert_eq!(document_changes[0]["edits"].as_array().unwrap().len(), 2);

    let workspace_edit_c = CString::new(workspace_edit).unwrap();
    let applied_json = take_owned_string(
        editor_core_ui_ffi_multi_document_apply_workspace_edit_transaction_json(
            multi,
            workspace_edit_c.as_ptr(),
        ),
    );
    let applied: serde_json::Value = serde_json::from_str(&applied_json).unwrap();
    assert_eq!(applied["applied"], true);
    assert_eq!(applied["applied_edit_count"], 2);
    assert_eq!(
        std::fs::read_to_string(root.join("src").join("lib.rs")).unwrap(),
        "👋 beta1\nbeta2\n"
    );
    assert_eq!(
        std::fs::read_to_string(root.join("notes.txt")).unwrap(),
        "alpha3\n"
    );

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn ffi_workspace_roots_change_envelope_json_reports_success_and_errors() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let roots = CString::new(r#"["file:///project/Alpha","file:///project/Beta"]"#).unwrap();
    let envelope_json = take_owned_string(
        editor_core_ui_ffi_multi_document_set_workspace_roots_with_change_envelope_json(
            multi,
            roots.as_ptr(),
        ),
    );
    let envelope: serde_json::Value = serde_json::from_str(&envelope_json).unwrap();
    assert_eq!(envelope["ok"], true);
    assert_eq!(envelope["status"], "success");
    assert!(envelope["error"].is_null());
    assert_eq!(envelope["version"], ECU_ABI_VERSION);
    let added = envelope["value"]["added"].as_array().unwrap();
    assert_eq!(added.len(), 2);
    assert_eq!(added[0]["uri"], "file:///project/Alpha");
    assert_eq!(added[0]["name"], "Alpha");
    assert_eq!(added[1]["uri"], "file:///project/Beta");
    assert_eq!(envelope["value"]["removed"].as_array().unwrap().len(), 0);

    let replacement = CString::new(r#"["file:///project/Beta"]"#).unwrap();
    let replacement_json = take_owned_string(
        editor_core_ui_ffi_multi_document_set_workspace_roots_with_change_envelope_json(
            multi,
            replacement.as_ptr(),
        ),
    );
    let replacement_envelope: serde_json::Value = serde_json::from_str(&replacement_json).unwrap();
    assert_eq!(replacement_envelope["ok"], true);
    assert_eq!(
        replacement_envelope["value"]["added"]
            .as_array()
            .unwrap()
            .len(),
        0
    );
    let removed = replacement_envelope["value"]["removed"].as_array().unwrap();
    assert_eq!(removed.len(), 1);
    assert_eq!(removed[0]["uri"], "file:///project/Alpha");
    assert_eq!(removed[0]["name"], "Alpha");

    let error_json = take_owned_string(
        editor_core_ui_ffi_multi_document_set_workspace_roots_with_change_envelope_json(
            multi,
            ptr::null(),
        ),
    );
    let error: serde_json::Value = serde_json::from_str(&error_json).unwrap();
    assert_eq!(error["ok"], false);
    assert_eq!(error["status"], "error");
    assert!(error["value"].is_null());
    assert_eq!(error["error"]["code"], "invalid_argument");
    assert_eq!(error["error"]["status"], ECU_ERR_INVALID_ARGUMENT);
    assert_eq!(error["error"]["message"], "roots_json_utf8 is null");
    assert_eq!(error["version"], ECU_ABI_VERSION);

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
}

#[test]
fn ffi_project_lsp_servers_envelope_json_reports_success_and_errors() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let configs = CString::new(
        r#"[
          {
            "key": " Rust ",
            "command": " /bin/rust-analyzer ",
            "args": [" ", "--stdio "],
            "language_id": " rust ",
            "workspace_roots": ["file:///workspace", " file:///workspace ", "file:///other"],
            "auto_start": true
          },
          {
            "key": "",
            "command": "/bin/sourcekit-lsp",
            "language_id": "swift",
            "auto_start": false
          }
        ]"#,
    )
    .unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_project_lsp_servers_json(multi, configs.as_ptr(),),
        ECU_OK
    );

    let envelope_json = take_owned_string(
        editor_core_ui_ffi_multi_document_project_lsp_servers_envelope_json(multi),
    );
    let envelope: serde_json::Value = serde_json::from_str(&envelope_json).unwrap();
    assert_eq!(envelope["ok"], true);
    assert_eq!(envelope["status"], "success");
    assert!(envelope["error"].is_null());
    assert_eq!(envelope["version"], ECU_ABI_VERSION);
    assert_eq!(
        envelope["value"],
        serde_json::json!([
            {
                "key": "rust",
                "command": "/bin/rust-analyzer",
                "args": ["--stdio"],
                "language_id": "rust",
                "workspace_roots": ["file:///other", "file:///workspace"],
                "auto_start": true
            },
            {
                "key": "swift",
                "command": "/bin/sourcekit-lsp",
                "args": [],
                "language_id": "swift",
                "workspace_roots": [],
                "auto_start": false
            }
        ])
    );

    let error_json = take_owned_string(
        editor_core_ui_ffi_multi_document_project_lsp_servers_envelope_json(ptr::null_mut()),
    );
    let error: serde_json::Value = serde_json::from_str(&error_json).unwrap();
    assert_eq!(error["ok"], false);
    assert_eq!(error["status"], "error");
    assert!(error["value"].is_null());
    assert_eq!(error["error"]["code"], "invalid_argument");
    assert_eq!(error["error"]["status"], ECU_ERR_INVALID_ARGUMENT);
    assert_eq!(error["error"]["message"], "multi is null");
    assert_eq!(error["version"], ECU_ABI_VERSION);

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
}

#[test]
fn ffi_project_lsp_lifecycle_envelope_json_reports_success_and_errors() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let text = CString::new("fn main() {}\n").unwrap();
    let mut tab_id = 0u64;
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(multi, text.as_ptr(), 80, &mut tab_id),
        ECU_OK
    );
    let uri = CString::new("file:///project/main.rs").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_document_uri(multi, tab_id, uri.as_ptr()),
        ECU_OK
    );
    let language_id = CString::new("rust").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_language_id(multi, tab_id, language_id.as_ptr()),
        ECU_OK
    );
    let roots = CString::new(r#"["file:///project"]"#).unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_workspace_roots_json(multi, roots.as_ptr()),
        ECU_OK
    );
    let configs = CString::new(
        r#"[
          {
            "key": "rust",
            "command": "/bin/rust-analyzer",
            "args": ["--stdio"],
            "language_id": "rust"
          }
        ]"#,
    )
    .unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_project_lsp_servers_json(multi, configs.as_ptr()),
        ECU_OK
    );

    let start = CString::new("start_plan").unwrap();
    let start_json = take_owned_string(
        editor_core_ui_ffi_multi_document_project_lsp_lifecycle_envelope_json(
            multi,
            start.as_ptr(),
            0,
        ),
    );
    let start_envelope: serde_json::Value = serde_json::from_str(&start_json).unwrap();
    assert_eq!(start_envelope["ok"], true);
    assert_eq!(start_envelope["operation"], "start_plan");
    assert_eq!(start_envelope["status"], "success");
    assert_eq!(start_envelope["version"], ECU_ABI_VERSION);
    assert_eq!(start_envelope["value"][0]["tab_id"], tab_id);
    assert_eq!(
        start_envelope["value"][0]["document_uri"],
        "file:///project/main.rs"
    );
    assert_eq!(start_envelope["value"][0]["server_key"], "rust");

    let stop = CString::new("stop_plan").unwrap();
    let stop_json = take_owned_string(
        editor_core_ui_ffi_multi_document_project_lsp_lifecycle_envelope_json(
            multi,
            stop.as_ptr(),
            0,
        ),
    );
    let stop_envelope: serde_json::Value = serde_json::from_str(&stop_json).unwrap();
    assert_eq!(stop_envelope["ok"], true);
    assert_eq!(stop_envelope["operation"], "stop_plan");
    assert_eq!(stop_envelope["value"][0]["server_key"], "rust");

    let restart = CString::new("restart_plan").unwrap();
    let restart_json = take_owned_string(
        editor_core_ui_ffi_multi_document_project_lsp_lifecycle_envelope_json(
            multi,
            restart.as_ptr(),
            0,
        ),
    );
    let restart_envelope: serde_json::Value = serde_json::from_str(&restart_json).unwrap();
    assert_eq!(restart_envelope["ok"], true);
    assert_eq!(restart_envelope["operation"], "restart_plan");
    assert_eq!(restart_envelope["value"][0]["server_key"], "rust");

    let lifecycle_outcome = CString::new(
        serde_json::json!({
            "tab_id": tab_id,
            "active_view_index": 0,
            "document_uri": "file:///project/main.rs",
            "language_id": "rust",
            "server_key": "rust",
            "command": "/bin/rust-analyzer",
            "args": ["--stdio"],
            "workspace_roots": ["file:///project"],
            "trigger": "auto_start",
            "status": "started"
        })
        .to_string(),
    )
    .unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_record_project_lsp_start_outcome_json(
            multi,
            lifecycle_outcome.as_ptr()
        ),
        ECU_OK
    );

    let lifecycle = CString::new("lifecycle_events").unwrap();
    let events_json = take_owned_string(
        editor_core_ui_ffi_multi_document_project_lsp_lifecycle_envelope_json(
            multi,
            lifecycle.as_ptr(),
            0,
        ),
    );
    let events_envelope: serde_json::Value = serde_json::from_str(&events_json).unwrap();
    assert_eq!(events_envelope["ok"], true);
    assert_eq!(events_envelope["operation"], "lifecycle_events");
    assert_eq!(events_envelope["value"]["latest_sequence"], 1);
    assert_eq!(events_envelope["value"]["events"][0]["operation"], "start");
    assert_eq!(events_envelope["value"]["events"][0]["status"], "started");

    let unknown = CString::new("future_operation").unwrap();
    let unknown_json = take_owned_string(
        editor_core_ui_ffi_multi_document_project_lsp_lifecycle_envelope_json(
            multi,
            unknown.as_ptr(),
            0,
        ),
    );
    let unknown_envelope: serde_json::Value = serde_json::from_str(&unknown_json).unwrap();
    assert_eq!(unknown_envelope["ok"], false);
    assert_eq!(unknown_envelope["operation"], "future_operation");
    assert_eq!(unknown_envelope["status"], "error");
    assert_eq!(unknown_envelope["error"]["code"], "invalid_argument");
    assert_eq!(
        unknown_envelope["error"]["status"],
        ECU_ERR_INVALID_ARGUMENT
    );
    assert!(
        unknown_envelope["error"]["message"]
            .as_str()
            .unwrap()
            .contains("unknown project LSP lifecycle operation")
    );

    let null_multi_json = take_owned_string(
        editor_core_ui_ffi_multi_document_project_lsp_lifecycle_envelope_json(
            ptr::null_mut(),
            start.as_ptr(),
            0,
        ),
    );
    let null_multi: serde_json::Value = serde_json::from_str(&null_multi_json).unwrap();
    assert_eq!(null_multi["ok"], false);
    assert_eq!(null_multi["operation"], "start_plan");
    assert_eq!(null_multi["error"]["code"], "invalid_argument");
    assert_eq!(null_multi["error"]["message"], "multi is null");

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
}

#[test]
fn ffi_workspace_outline_snapshot_envelope_json_reports_success_and_errors() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let text = CString::new("struct Beta {}\n").unwrap();
    let mut tab_id = 0u64;
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(multi, text.as_ptr(), 80, &mut tab_id),
        ECU_OK
    );
    let title = CString::new("Beta").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_title(multi, tab_id, title.as_ptr()),
        ECU_OK
    );
    let uri = CString::new("file:///project/Beta.swift").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_document_uri(multi, tab_id, uri.as_ptr()),
        ECU_OK
    );
    let symbols = CString::new(
        r#"[
          {
            "name": "Beta",
            "kind": 23,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 14 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 7 },
              "end": { "line": 0, "character": 11 }
            }
          }
        ]"#,
    )
    .unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_apply_tab_document_symbols_json(
            multi,
            tab_id,
            symbols.as_ptr(),
        ),
        ECU_OK
    );

    let envelope_json = take_owned_string(
        editor_core_ui_ffi_multi_document_workspace_outline_snapshot_envelope_json(multi),
    );
    let envelope: serde_json::Value = serde_json::from_str(&envelope_json).unwrap();
    assert_eq!(envelope["ok"], true);
    assert_eq!(envelope["status"], "success");
    assert!(envelope["error"].is_null());
    assert_eq!(envelope["version"], ECU_ABI_VERSION);
    let document = &envelope["value"]["documents"][0];
    assert_eq!(document["tab_id"], tab_id);
    assert_eq!(document["title"], "Beta");
    assert_eq!(document["document_uri"], "file:///project/Beta.swift");
    assert_eq!(document["symbol_count"], 1);
    assert_eq!(document["symbols"][0]["name"], "Beta");

    let error_json = take_owned_string(
        editor_core_ui_ffi_multi_document_workspace_outline_snapshot_envelope_json(ptr::null_mut()),
    );
    let error: serde_json::Value = serde_json::from_str(&error_json).unwrap();
    assert_eq!(error["ok"], false);
    assert_eq!(error["status"], "error");
    assert!(error["value"].is_null());
    assert_eq!(error["error"]["code"], "invalid_argument");
    assert_eq!(error["error"]["status"], ECU_ERR_INVALID_ARGUMENT);
    assert_eq!(error["error"]["message"], "multi is null");
    assert_eq!(error["version"], ECU_ABI_VERSION);

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
}

#[test]
fn ffi_workspace_edit_transaction_envelope_json_reports_success_and_errors() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let text = CString::new("hello\n").unwrap();
    let mut tab_id = 0u64;
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(multi, text.as_ptr(), 80, &mut tab_id),
        ECU_OK
    );
    let uri = CString::new("file:///project/App.swift").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_document_uri(multi, tab_id, uri.as_ptr()),
        ECU_OK
    );

    let workspace_edit = CString::new(
        r#"{
          "changes": {
            "file:///project/App.swift": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 5 }
                },
                "newText": "Hello"
              }
            ]
          }
        }"#,
    )
    .unwrap();
    let preview = CString::new("preview").unwrap();
    let preview_json = take_owned_string(
        editor_core_ui_ffi_multi_document_workspace_edit_transaction_envelope_json(
            multi,
            preview.as_ptr(),
            workspace_edit.as_ptr(),
        ),
    );
    let preview_envelope: serde_json::Value = serde_json::from_str(&preview_json).unwrap();
    assert_eq!(preview_envelope["ok"], true);
    assert_eq!(preview_envelope["operation"], "preview");
    assert_eq!(preview_envelope["status"], "success");
    assert_eq!(preview_envelope["value"]["mode"], "preview");
    assert_eq!(preview_envelope["value"]["applied"], false);
    assert!(preview_envelope["error"].is_null());
    assert_eq!(preview_envelope["version"], ECU_ABI_VERSION);

    let undo = CString::new("undo").unwrap();
    let undo_json = take_owned_string(
        editor_core_ui_ffi_multi_document_workspace_edit_transaction_envelope_json(
            multi,
            undo.as_ptr(),
            ptr::null(),
        ),
    );
    let undo_envelope: serde_json::Value = serde_json::from_str(&undo_json).unwrap();
    assert_eq!(undo_envelope["ok"], true);
    assert_eq!(undo_envelope["operation"], "undo");
    assert_eq!(undo_envelope["value"]["undone"], false);

    let unknown = CString::new("future_operation").unwrap();
    let error_json = take_owned_string(
        editor_core_ui_ffi_multi_document_workspace_edit_transaction_envelope_json(
            multi,
            unknown.as_ptr(),
            workspace_edit.as_ptr(),
        ),
    );
    let error_envelope: serde_json::Value = serde_json::from_str(&error_json).unwrap();
    assert_eq!(error_envelope["ok"], false);
    assert_eq!(error_envelope["operation"], "future_operation");
    assert_eq!(error_envelope["status"], "error");
    assert!(error_envelope["value"].is_null());
    assert_eq!(error_envelope["error"]["code"], "invalid_argument");
    assert_eq!(error_envelope["error"]["status"], ECU_ERR_INVALID_ARGUMENT);
    assert!(
        error_envelope["error"]["message"]
            .as_str()
            .unwrap()
            .contains("unknown workspace edit transaction operation")
    );

    let null_operation_json = take_owned_string(
        editor_core_ui_ffi_multi_document_workspace_edit_transaction_envelope_json(
            multi,
            ptr::null(),
            workspace_edit.as_ptr(),
        ),
    );
    let null_operation: serde_json::Value = serde_json::from_str(&null_operation_json).unwrap();
    assert_eq!(null_operation["ok"], false);
    assert!(null_operation["operation"].is_null());
    assert_eq!(null_operation["error"]["code"], "invalid_argument");
    assert_eq!(null_operation["error"]["message"], "operation_utf8 is null");

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
}

#[test]
fn ffi_workspace_diagnostics_envelope_json_reports_success_and_errors() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let apply = CString::new("apply").unwrap();
    let diagnostics = CString::new(
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
    let apply_json = take_owned_string(
        editor_core_ui_ffi_multi_document_workspace_diagnostics_envelope_json(
            multi,
            apply.as_ptr(),
            diagnostics.as_ptr(),
        ),
    );
    let apply_value: serde_json::Value = serde_json::from_str(&apply_json).unwrap();
    assert_eq!(apply_value["ok"], true);
    assert_eq!(apply_value["operation"], "apply");
    assert_eq!(apply_value["status"], "success");
    assert_eq!(
        apply_value["value"]["diagnostics"][0]["message"],
        "first problem"
    );
    assert_eq!(
        apply_value["value"]["diagnostics"][0]["severity_label"],
        "error"
    );
    assert!(apply_value["error"].is_null());
    assert_eq!(apply_value["version"], ECU_ABI_VERSION);

    let markers = CString::new("markers").unwrap();
    let markers_json = take_owned_string(
        editor_core_ui_ffi_multi_document_workspace_diagnostics_envelope_json(
            multi,
            markers.as_ptr(),
            ptr::null(),
        ),
    );
    let markers_value: serde_json::Value = serde_json::from_str(&markers_json).unwrap();
    assert_eq!(markers_value["ok"], true);
    assert_eq!(markers_value["operation"], "markers");
    assert_eq!(
        markers_value["value"]["markers"][0]["uri"],
        "file:///project/a.swift"
    );

    let previous = CString::new("previous_result_ids").unwrap();
    let previous_json = take_owned_string(
        editor_core_ui_ffi_multi_document_workspace_diagnostics_envelope_json(
            multi,
            previous.as_ptr(),
            ptr::null(),
        ),
    );
    let previous_value: serde_json::Value = serde_json::from_str(&previous_json).unwrap();
    assert_eq!(previous_value["ok"], true);
    assert_eq!(
        previous_value["value"],
        serde_json::json!([{"uri": "file:///project/a.swift", "value": "a-1"}])
    );

    let snapshot = CString::new("snapshot").unwrap();
    let snapshot_json = take_owned_string(
        editor_core_ui_ffi_multi_document_workspace_diagnostics_envelope_json(
            multi,
            snapshot.as_ptr(),
            ptr::null(),
        ),
    );
    let snapshot_value: serde_json::Value = serde_json::from_str(&snapshot_json).unwrap();
    assert_eq!(snapshot_value["ok"], true);
    assert_eq!(
        snapshot_value["value"]["documents"][0]["uri"],
        "file:///project/a.swift"
    );

    let unknown = CString::new("future_operation").unwrap();
    let error_json = take_owned_string(
        editor_core_ui_ffi_multi_document_workspace_diagnostics_envelope_json(
            multi,
            unknown.as_ptr(),
            ptr::null(),
        ),
    );
    let error_value: serde_json::Value = serde_json::from_str(&error_json).unwrap();
    assert_eq!(error_value["ok"], false);
    assert_eq!(error_value["operation"], "future_operation");
    assert_eq!(error_value["status"], "error");
    assert!(error_value["value"].is_null());
    assert_eq!(error_value["error"]["code"], "invalid_argument");
    assert_eq!(error_value["error"]["status"], ECU_ERR_INVALID_ARGUMENT);
    assert!(
        error_value["error"]["message"]
            .as_str()
            .unwrap()
            .contains("unknown workspace diagnostics operation")
    );

    let null_operation_json = take_owned_string(
        editor_core_ui_ffi_multi_document_workspace_diagnostics_envelope_json(
            multi,
            ptr::null(),
            ptr::null(),
        ),
    );
    let null_operation_value: serde_json::Value =
        serde_json::from_str(&null_operation_json).unwrap();
    assert_eq!(null_operation_value["ok"], false);
    assert!(null_operation_value["operation"].is_null());
    assert_eq!(null_operation_value["error"]["code"], "invalid_argument");
    assert_eq!(
        null_operation_value["error"]["message"],
        "operation_utf8 is null"
    );

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
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

    let alpha_uri = CString::new("file:///project/main.rs").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_document_uri(multi, alpha_id, alpha_uri.as_ptr(),),
        ECU_OK
    );
    let alpha_language = CString::new("rust").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_language_id(
            multi,
            alpha_id,
            alpha_language.as_ptr(),
        ),
        ECU_OK
    );

    let title = CString::new("Beta").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_title(multi, beta_id, title.as_ptr()),
        ECU_OK
    );
    let beta_uri = CString::new("file:///project/Beta.swift").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_document_uri(multi, beta_id, beta_uri.as_ptr(),),
        ECU_OK
    );
    let mut beta_uri_ptr: *mut c_char = std::ptr::null_mut();
    assert_eq!(
        editor_core_ui_ffi_multi_document_tab_document_uri(multi, beta_id, &mut beta_uri_ptr,),
        ECU_OK
    );
    assert!(!beta_uri_ptr.is_null());
    let beta_uri_value = unsafe { std::ffi::CStr::from_ptr(beta_uri_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(beta_uri_ptr) };
    assert_eq!(beta_uri_value, "file:///project/Beta.swift");
    let beta_language = CString::new(" swift ").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_language_id(
            multi,
            beta_id,
            beta_language.as_ptr(),
        ),
        ECU_OK
    );
    let mut beta_language_ptr: *mut c_char = std::ptr::null_mut();
    assert_eq!(
        editor_core_ui_ffi_multi_document_tab_language_id(multi, beta_id, &mut beta_language_ptr,),
        ECU_OK
    );
    assert!(!beta_language_ptr.is_null());
    let beta_language_value = unsafe { std::ffi::CStr::from_ptr(beta_language_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(beta_language_ptr) };
    assert_eq!(beta_language_value, "swift");
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_active_tab(multi, beta_id),
        ECU_OK
    );

    let roots = CString::new(
        r#"[
          "file:///project",
          "file:///project",
          "file:///other"
        ]"#,
    )
    .unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_workspace_roots_json(multi, roots.as_ptr()),
        ECU_OK
    );
    let snapshot_ptr = editor_core_ui_ffi_multi_document_snapshot_json(multi);
    assert!(!snapshot_ptr.is_null());
    let snapshot_json = unsafe { std::ffi::CStr::from_ptr(snapshot_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(snapshot_ptr) };
    let snapshot_value: serde_json::Value = serde_json::from_str(&snapshot_json).unwrap();
    assert_eq!(
        snapshot_value["workspace_roots"],
        serde_json::json!(["file:///project", "file:///other"])
    );
    assert_eq!(snapshot_value["tabs"][1]["language_id"], "swift");
    let changed_roots = CString::new(
        r#"[
          "file:///other",
          "file:///new",
          "file:///new"
        ]"#,
    )
    .unwrap();
    let change_ptr = editor_core_ui_ffi_multi_document_set_workspace_roots_with_change_json(
        multi,
        changed_roots.as_ptr(),
    );
    assert!(!change_ptr.is_null());
    let change_json = unsafe { std::ffi::CStr::from_ptr(change_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(change_ptr) };
    let change_value: serde_json::Value = serde_json::from_str(&change_json).unwrap();
    assert_eq!(
        change_value,
        serde_json::json!({
            "added": [{"uri": "file:///new", "name": "new"}],
            "removed": [{"uri": "file:///project", "name": "project"}],
        })
    );

    let lsp_servers = CString::new(
        r#"[
          {
            "key": " Rust ",
            "command": " /bin/rust-analyzer ",
            "args": [" ", "--stdio "],
            "language_id": " rust ",
            "workspace_roots": ["file:///new", "file:///new", " file:///other "],
            "auto_start": true
          },
          {
            "key": "",
            "command": "/bin/sourcekit-lsp",
            "language_id": "swift",
            "auto_start": false
          }
        ]"#,
    )
    .unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_project_lsp_servers_json(multi, lsp_servers.as_ptr()),
        ECU_OK
    );
    let lsp_snapshot_ptr = editor_core_ui_ffi_multi_document_project_lsp_servers_json(multi);
    assert!(!lsp_snapshot_ptr.is_null());
    let lsp_snapshot_json = unsafe { std::ffi::CStr::from_ptr(lsp_snapshot_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(lsp_snapshot_ptr) };
    let lsp_snapshot_value: serde_json::Value = serde_json::from_str(&lsp_snapshot_json).unwrap();
    assert_eq!(
        lsp_snapshot_value,
        serde_json::json!([
            {
                "key": "rust",
                "command": "/bin/rust-analyzer",
                "args": ["--stdio"],
                "language_id": "rust",
                "workspace_roots": ["file:///new", "file:///other"],
                "auto_start": true
            },
            {
                "key": "swift",
                "command": "/bin/sourcekit-lsp",
                "args": [],
                "language_id": "swift",
                "workspace_roots": [],
                "auto_start": false
            }
        ])
    );

    let lsp_start_plan_ptr = editor_core_ui_ffi_multi_document_project_lsp_start_plan_json(multi);
    assert!(!lsp_start_plan_ptr.is_null());
    let lsp_start_plan_json = unsafe { std::ffi::CStr::from_ptr(lsp_start_plan_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(lsp_start_plan_ptr) };
    let lsp_start_plan_value: serde_json::Value =
        serde_json::from_str(&lsp_start_plan_json).unwrap();
    assert_eq!(
        lsp_start_plan_value,
        serde_json::json!([
            {
                "operation": "start",
                "tab_id": alpha_id,
                "active_view_index": 0,
                "document_uri": "file:///project/main.rs",
                "language_id": "rust",
                "server_key": "rust",
                "command": "/bin/rust-analyzer",
                "args": ["--stdio"],
                "workspace_roots": ["file:///new", "file:///other"]
            }
        ])
    );

    let lsp_stop_plan_ptr = editor_core_ui_ffi_multi_document_project_lsp_stop_plan_json(multi);
    assert!(!lsp_stop_plan_ptr.is_null());
    let lsp_stop_plan_json = unsafe { std::ffi::CStr::from_ptr(lsp_stop_plan_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(lsp_stop_plan_ptr) };
    let lsp_stop_plan_value: serde_json::Value = serde_json::from_str(&lsp_stop_plan_json).unwrap();
    assert_eq!(
        lsp_stop_plan_value,
        serde_json::json!([
            {
                "operation": "stop",
                "tab_id": alpha_id,
                "active_view_index": 0,
                "document_uri": "file:///project/main.rs",
                "language_id": "rust",
                "server_key": "rust",
                "command": "/bin/rust-analyzer",
                "args": ["--stdio"],
                "workspace_roots": ["file:///new", "file:///other"]
            },
            {
                "operation": "stop",
                "tab_id": beta_id,
                "active_view_index": 0,
                "document_uri": "file:///project/Beta.swift",
                "language_id": "swift",
                "server_key": "swift",
                "command": "/bin/sourcekit-lsp",
                "args": [],
                "workspace_roots": ["file:///new", "file:///other"]
            }
        ])
    );

    let lsp_restart_plan_ptr =
        editor_core_ui_ffi_multi_document_project_lsp_restart_plan_json(multi);
    assert!(!lsp_restart_plan_ptr.is_null());
    let lsp_restart_plan_json = unsafe { std::ffi::CStr::from_ptr(lsp_restart_plan_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(lsp_restart_plan_ptr) };
    let lsp_restart_plan_value: serde_json::Value =
        serde_json::from_str(&lsp_restart_plan_json).unwrap();
    assert_eq!(
        lsp_restart_plan_value,
        serde_json::json!([
            {
                "operation": "restart",
                "tab_id": alpha_id,
                "active_view_index": 0,
                "document_uri": "file:///project/main.rs",
                "language_id": "rust",
                "server_key": "rust",
                "command": "/bin/rust-analyzer",
                "args": ["--stdio"],
                "workspace_roots": ["file:///new", "file:///other"]
            },
            {
                "operation": "restart",
                "tab_id": beta_id,
                "active_view_index": 0,
                "document_uri": "file:///project/Beta.swift",
                "language_id": "swift",
                "server_key": "swift",
                "command": "/bin/sourcekit-lsp",
                "args": [],
                "workspace_roots": ["file:///new", "file:///other"]
            }
        ])
    );

    let lifecycle_outcome = CString::new(
        serde_json::json!({
            "tab_id": alpha_id,
            "active_view_index": 0,
            "document_uri": "file:///project/main.rs",
            "language_id": "rust",
            "server_key": "rust",
            "command": "/bin/rust-analyzer",
            "args": ["--stdio"],
            "workspace_roots": ["file:///new", "file:///other"],
            "trigger": "auto_start",
            "status": "started"
        })
        .to_string(),
    )
    .unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_record_project_lsp_start_outcome_json(
            multi,
            lifecycle_outcome.as_ptr()
        ),
        ECU_OK
    );
    let mut lifecycle_sequence = 0;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_multi_document_project_lsp_lifecycle_events_latest_sequence(
                multi,
                &mut lifecycle_sequence,
            )
        },
        ECU_OK
    );
    assert_eq!(lifecycle_sequence, 1);
    let lifecycle_events_ptr =
        editor_core_ui_ffi_multi_document_project_lsp_lifecycle_events_json(multi, 0);
    assert!(!lifecycle_events_ptr.is_null());
    let lifecycle_events_json = unsafe { std::ffi::CStr::from_ptr(lifecycle_events_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(lifecycle_events_ptr) };
    let lifecycle_events_value: serde_json::Value =
        serde_json::from_str(&lifecycle_events_json).unwrap();
    assert_eq!(lifecycle_events_value["latest_sequence"], 1);
    assert_eq!(lifecycle_events_value["events"][0]["operation"], "start");
    assert_eq!(lifecycle_events_value["events"][0]["status"], "started");
    assert_eq!(lifecycle_events_value["events"][0]["tab_id"], alpha_id);
    assert_eq!(
        lifecycle_events_value["events"][0]["document_uri"],
        "file:///project/main.rs"
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

    let workspace_edit = CString::new(
        r#"{
          "changes": {
            "file:///project/Beta.swift": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 4 }
                },
                "newText": "BETA"
              }
            ],
            "file:///project/Missing.swift": [
              {
                "range": {
                  "start": { "line": 0, "character": 0 },
                  "end": { "line": 0, "character": 0 }
                },
                "newText": "missing"
              }
            ]
          }
        }"#,
    )
    .unwrap();
    let preview_ptr = editor_core_ui_ffi_multi_document_preview_workspace_edit_transaction_json(
        multi,
        workspace_edit.as_ptr(),
    );
    assert!(!preview_ptr.is_null());
    let preview_json = unsafe { std::ffi::CStr::from_ptr(preview_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(preview_ptr) };
    let preview_value: serde_json::Value = serde_json::from_str(&preview_json).unwrap();
    assert_eq!(preview_value["mode"], "preview");
    assert_eq!(preview_value["applied"], false);
    assert_eq!(
        preview_value["skipped_uris"][0],
        "file:///project/Missing.swift"
    );
    assert_eq!(
        preview_value["skipped_details"][0]["reason"],
        "file_not_found"
    );

    let apply_ptr = editor_core_ui_ffi_multi_document_apply_workspace_edit_transaction_json(
        multi,
        workspace_edit.as_ptr(),
    );
    assert!(!apply_ptr.is_null());
    let apply_json = unsafe { std::ffi::CStr::from_ptr(apply_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(apply_ptr) };
    let apply_value: serde_json::Value = serde_json::from_str(&apply_json).unwrap();
    assert_eq!(apply_value["mode"], "apply");
    assert_eq!(apply_value["applied"], true);
    assert_eq!(apply_value["applied_uris"][0], "file:///project/Beta.swift");
    assert_eq!(apply_value["applied_resource_operation_count"], 0);

    let mut transaction_event_sequence = 0u64;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_multi_document_workspace_edit_transaction_events_latest_sequence(
                multi,
                &mut transaction_event_sequence,
            )
        },
        ECU_OK
    );
    assert_eq!(transaction_event_sequence, 1);
    let transaction_events_ptr =
        editor_core_ui_ffi_multi_document_workspace_edit_transaction_events_json(multi, 0);
    assert!(!transaction_events_ptr.is_null());
    let transaction_events_json = unsafe { std::ffi::CStr::from_ptr(transaction_events_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(transaction_events_ptr) };
    let transaction_events_value: serde_json::Value =
        serde_json::from_str(&transaction_events_json).unwrap();
    assert_eq!(transaction_events_value["latest_sequence"], 1);
    assert_eq!(transaction_events_value["events"][0]["operation"], "apply");
    assert_eq!(
        transaction_events_value["events"][0]["workspace_edit_json"],
        workspace_edit.to_string_lossy().as_ref()
    );
    assert_eq!(
        transaction_events_value["events"][0]["result"]["applied_uris"][0],
        "file:///project/Beta.swift"
    );

    let edited_beta_text_ptr = editor_core_ui_ffi_multi_document_tab_text(multi, beta_id);
    assert!(!edited_beta_text_ptr.is_null());
    let edited_beta_text = unsafe { std::ffi::CStr::from_ptr(edited_beta_text_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(edited_beta_text_ptr) };
    assert_eq!(edited_beta_text, "BETA saved mirror");

    let undo_ptr =
        editor_core_ui_ffi_multi_document_undo_last_workspace_edit_transaction_json(multi);
    assert!(!undo_ptr.is_null());
    let undo_json = unsafe { std::ffi::CStr::from_ptr(undo_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(undo_ptr) };
    let undo_value: serde_json::Value = serde_json::from_str(&undo_json).unwrap();
    assert_eq!(undo_value["undone"], true);
    assert_eq!(undo_value["restored_uris"][0], "file:///project/Beta.swift");
    let restored_beta_text_ptr = editor_core_ui_ffi_multi_document_tab_text(multi, beta_id);
    assert!(!restored_beta_text_ptr.is_null());
    let restored_beta_text = unsafe { std::ffi::CStr::from_ptr(restored_beta_text_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(restored_beta_text_ptr) };
    assert_eq!(restored_beta_text, "beta saved mirror");

    let redo_ptr =
        editor_core_ui_ffi_multi_document_redo_last_workspace_edit_transaction_json(multi);
    assert!(!redo_ptr.is_null());
    let redo_json = unsafe { std::ffi::CStr::from_ptr(redo_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(redo_ptr) };
    let redo_value: serde_json::Value = serde_json::from_str(&redo_json).unwrap();
    assert_eq!(redo_value["mode"], "redo");
    assert_eq!(redo_value["applied"], true);
    assert_eq!(redo_value["applied_uris"][0], "file:///project/Beta.swift");
    let redone_beta_text_ptr = editor_core_ui_ffi_multi_document_tab_text(multi, beta_id);
    assert!(!redone_beta_text_ptr.is_null());
    let redone_beta_text = unsafe { std::ffi::CStr::from_ptr(redone_beta_text_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(redone_beta_text_ptr) };
    assert_eq!(redone_beta_text, "BETA saved mirror");

    let transaction_events_ptr =
        editor_core_ui_ffi_multi_document_workspace_edit_transaction_events_json(multi, 1);
    assert!(!transaction_events_ptr.is_null());
    let transaction_events_json = unsafe { std::ffi::CStr::from_ptr(transaction_events_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(transaction_events_ptr) };
    let transaction_events_value: serde_json::Value =
        serde_json::from_str(&transaction_events_json).unwrap();
    assert_eq!(transaction_events_value["latest_sequence"], 2);
    assert_eq!(transaction_events_value["events"][0]["operation"], "redo");

    let second_undo_ptr =
        editor_core_ui_ffi_multi_document_undo_last_workspace_edit_transaction_json(multi);
    assert!(!second_undo_ptr.is_null());
    unsafe { editor_core_ui_ffi_string_free(second_undo_ptr) };

    let unavailable_undo_ptr =
        editor_core_ui_ffi_multi_document_undo_last_workspace_edit_transaction_json(multi);
    assert!(!unavailable_undo_ptr.is_null());
    let unavailable_undo_json = unsafe { std::ffi::CStr::from_ptr(unavailable_undo_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(unavailable_undo_ptr) };
    let unavailable_undo_value: serde_json::Value =
        serde_json::from_str(&unavailable_undo_json).unwrap();
    assert_eq!(unavailable_undo_value["undone"], false);

    assert_eq!(
        editor_core_ui_ffi_multi_document_mark_tab_saved(multi, beta_id),
        ECU_OK
    );

    let document_symbols = CString::new(
        r#"[
          {
            "name": "Beta",
            "kind": 23,
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 11 }
            },
            "selectionRange": {
              "start": { "line": 0, "character": 5 },
              "end": { "line": 0, "character": 9 }
            }
          }
        ]"#,
    )
    .unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_apply_tab_document_symbols_json(
            multi,
            beta_id,
            document_symbols.as_ptr(),
        ),
        ECU_OK
    );
    let outline_ptr = editor_core_ui_ffi_multi_document_workspace_outline_snapshot_json(multi);
    assert!(!outline_ptr.is_null());
    let outline_json = unsafe { std::ffi::CStr::from_ptr(outline_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(outline_ptr) };
    let outline_value: serde_json::Value = serde_json::from_str(&outline_json).unwrap();
    let beta_outline = outline_value["documents"]
        .as_array()
        .unwrap()
        .iter()
        .find(|document| document["tab_id"] == beta_id)
        .unwrap();
    assert_eq!(beta_outline["title"], "Beta");
    assert_eq!(beta_outline["document_uri"], "file:///project/Beta.swift");
    assert_eq!(beta_outline["symbol_count"], 1);
    assert_eq!(beta_outline["symbols"][0]["name"], "Beta");

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
        && tab["document_uri"] == "file:///project/Beta.swift"
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
fn ffi_multi_document_atomic_workspace_edit_preflight_skips_without_mutating() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let app_text = CString::new("alpha\n").unwrap();
    let dirty_text = CString::new("dirty\n").unwrap();
    let mut app_id: u64 = 0;
    let mut dirty_id: u64 = 0;
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(multi, app_text.as_ptr(), 80, &mut app_id),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(multi, dirty_text.as_ptr(), 80, &mut dirty_id,),
        ECU_OK
    );
    let app_uri = CString::new("file:///project/App.swift").unwrap();
    let dirty_uri = CString::new("file:///project/Dirty.swift").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_document_uri(multi, app_id, app_uri.as_ptr(),),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_document_uri(multi, dirty_id, dirty_uri.as_ptr(),),
        ECU_OK
    );
    let dirty_changed = CString::new("dirty changed\n").unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_replace_tab_text(
            multi,
            dirty_id,
            dirty_changed.as_ptr(),
            0,
        ),
        ECU_OK
    );

    let workspace_edit = CString::new(
        r#"{
          "applyMode": "atomic",
          "workspaceEdit": {
            "documentChanges": [
              {
                "textDocument": {
                  "uri": "file:///project/App.swift",
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
                "uri": "file:///project/Dirty.swift"
              }
            ]
          }
        }"#,
    )
    .unwrap();

    let apply_ptr = editor_core_ui_ffi_multi_document_apply_workspace_edit_transaction_json(
        multi,
        workspace_edit.as_ptr(),
    );
    assert!(!apply_ptr.is_null());
    let apply_json = unsafe { std::ffi::CStr::from_ptr(apply_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(apply_ptr) };
    let apply_value: serde_json::Value = serde_json::from_str(&apply_json).unwrap();
    assert_eq!(apply_value["mode"], "apply");
    assert_eq!(apply_value["apply_mode"], "atomic");
    assert_eq!(apply_value["applied"], false);
    assert_eq!(apply_value["applied_edit_count"], 0);
    assert_eq!(apply_value["applied_resource_operation_count"], 0);
    assert_eq!(
        apply_value["skipped_details"][0]["reason"],
        "resource_operation_dirty_target"
    );
    assert_eq!(apply_value["conflicts"][0]["kind"], "dirty_document");
    assert_eq!(apply_value["conflicts"][0]["severity"], "error");
    assert_eq!(
        apply_value["conflicts"][0]["apply_impact"],
        "blocks_atomic_apply"
    );
    assert_eq!(apply_value["conflicts"][0]["resolution"], "save_or_discard");

    let app_text_ptr = editor_core_ui_ffi_multi_document_tab_text(multi, app_id);
    assert!(!app_text_ptr.is_null());
    let app_text_after = unsafe { std::ffi::CStr::from_ptr(app_text_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(app_text_ptr) };
    assert_eq!(app_text_after, "alpha\n");
    let dirty_text_ptr = editor_core_ui_ffi_multi_document_tab_text(multi, dirty_id);
    assert!(!dirty_text_ptr.is_null());
    let dirty_text_after = unsafe { std::ffi::CStr::from_ptr(dirty_text_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(dirty_text_ptr) };
    assert_eq!(dirty_text_after, "dirty changed\n");

    let mut sequence = 0;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_multi_document_workspace_edit_transaction_events_latest_sequence(
                multi,
                &mut sequence,
            )
        },
        ECU_OK
    );
    assert_eq!(sequence, 1);
    let events_ptr =
        editor_core_ui_ffi_multi_document_workspace_edit_transaction_events_json(multi, 0);
    assert!(!events_ptr.is_null());
    let events_json = unsafe { std::ffi::CStr::from_ptr(events_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(events_ptr) };
    let events_value: serde_json::Value = serde_json::from_str(&events_json).unwrap();
    assert_eq!(events_value["latest_sequence"], 1);
    assert_eq!(events_value["events"][0]["operation"], "apply");
    assert_eq!(
        events_value["events"][0]["workspace_edit_json"],
        workspace_edit.to_string_lossy().as_ref()
    );
    assert_eq!(
        events_value["events"][0]["result"]["conflicts"][0]["kind"],
        "dirty_document"
    );
    assert_eq!(
        events_value["events"][0]["result"]["conflicts"][0]["resolution"],
        "save_or_discard"
    );

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
}

#[test]
fn ffi_multi_document_applies_unopened_workspace_file_text_edits() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let root = std::env::temp_dir().join(format!(
        "editor-core-ui-ffi-workspace-edit-root-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&root).unwrap();
    let file = root.join("Unopened.swift");
    std::fs::write(&file, "alpha\nbeta\n").unwrap();

    let root_uri = format!("file://{}", root.to_string_lossy());
    let file_uri = format!("file://{}", file.to_string_lossy());
    let roots = CString::new(serde_json::json!([root_uri]).to_string()).unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_workspace_roots_json(multi, roots.as_ptr()),
        ECU_OK
    );

    let workspace_edit = CString::new(
        serde_json::json!({
            "changes": {
                (file_uri.as_str()): [
                    {
                        "range": {
                            "start": { "line": 1, "character": 0 },
                            "end": { "line": 1, "character": 4 }
                        },
                        "newText": "BETA"
                    }
                ]
            }
        })
        .to_string(),
    )
    .unwrap();

    let preview_ptr = editor_core_ui_ffi_multi_document_preview_workspace_edit_transaction_json(
        multi,
        workspace_edit.as_ptr(),
    );
    assert!(!preview_ptr.is_null());
    let preview_json = unsafe { std::ffi::CStr::from_ptr(preview_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(preview_ptr) };
    let preview: serde_json::Value = serde_json::from_str(&preview_json).unwrap();
    assert_eq!(preview["mode"], "preview");
    assert_eq!(preview["applied"], false);
    assert_eq!(preview["skipped_uris"].as_array().unwrap().len(), 0);
    assert_eq!(std::fs::read_to_string(&file).unwrap(), "alpha\nbeta\n");

    let apply_ptr = editor_core_ui_ffi_multi_document_apply_workspace_edit_transaction_json(
        multi,
        workspace_edit.as_ptr(),
    );
    assert!(!apply_ptr.is_null());
    let apply_json = unsafe { std::ffi::CStr::from_ptr(apply_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(apply_ptr) };
    let applied: serde_json::Value = serde_json::from_str(&apply_json).unwrap();
    assert_eq!(applied["mode"], "apply");
    assert_eq!(applied["applied"], true);
    assert_eq!(applied["applied_uris"][0], file_uri);
    assert_eq!(applied["applied_edit_count"], 1);
    assert_eq!(std::fs::read_to_string(&file).unwrap(), "alpha\nBETA\n");

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn ffi_multi_document_applies_open_tab_resource_operation_filesystem_side_effects() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let root = std::env::temp_dir().join(format!(
        "editor-core-ui-ffi-open-tab-resource-fs-root-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(root.join("src")).unwrap();
    let old = root.join("src").join("Old.swift");
    let renamed = root.join("src").join("Renamed.swift");
    let deleted = root.join("src").join("Deleted.swift");
    let overwritten = root.join("src").join("Overwrite.swift");
    std::fs::write(&old, "old\n").unwrap();
    std::fs::write(&deleted, "delete\n").unwrap();
    std::fs::write(&overwritten, "existing\n").unwrap();

    let root_uri = format!("file://{}", root.to_string_lossy());
    let old_uri = format!("file://{}", old.to_string_lossy());
    let renamed_uri = format!("file://{}", renamed.to_string_lossy());
    let deleted_uri = format!("file://{}", deleted.to_string_lossy());
    let overwritten_uri = format!("file://{}", overwritten.to_string_lossy());

    let roots = CString::new(serde_json::json!([root_uri]).to_string()).unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_workspace_roots_json(multi, roots.as_ptr()),
        ECU_OK
    );

    let old_text = CString::new("old\n").unwrap();
    let delete_text = CString::new("delete\n").unwrap();
    let overwrite_text = CString::new("existing\n").unwrap();
    let mut old_id: u64 = 0;
    let mut delete_id: u64 = 0;
    let mut overwrite_id: u64 = 0;
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(multi, old_text.as_ptr(), 80, &mut old_id),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(multi, delete_text.as_ptr(), 80, &mut delete_id,),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(
            multi,
            overwrite_text.as_ptr(),
            80,
            &mut overwrite_id,
        ),
        ECU_OK
    );

    for (tab_id, uri) in [
        (old_id, old_uri.as_str()),
        (delete_id, deleted_uri.as_str()),
        (overwrite_id, overwritten_uri.as_str()),
    ] {
        let uri = CString::new(uri).unwrap();
        assert_eq!(
            editor_core_ui_ffi_multi_document_set_tab_document_uri(multi, tab_id, uri.as_ptr(),),
            ECU_OK
        );
    }

    let workspace_edit = CString::new(
        serde_json::json!({
            "documentChanges": [
                {
                    "kind": "rename",
                    "oldUri": old_uri.as_str(),
                    "newUri": renamed_uri.as_str()
                },
                {
                    "textDocument": { "uri": renamed_uri.as_str(), "version": null },
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
                { "kind": "delete", "uri": deleted_uri.as_str() },
                {
                    "kind": "create",
                    "uri": overwritten_uri.as_str(),
                    "options": { "overwrite": true }
                }
            ]
        })
        .to_string(),
    )
    .unwrap();

    let apply_ptr = editor_core_ui_ffi_multi_document_apply_workspace_edit_transaction_json(
        multi,
        workspace_edit.as_ptr(),
    );
    assert!(!apply_ptr.is_null());
    let apply_json = unsafe { std::ffi::CStr::from_ptr(apply_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(apply_ptr) };
    let applied: serde_json::Value = serde_json::from_str(&apply_json).unwrap();
    assert_eq!(applied["applied_edit_count"], 1);
    assert_eq!(applied["applied_resource_operation_count"], 3);
    assert!(!old.exists());
    assert_eq!(std::fs::read_to_string(&renamed).unwrap(), "old\n");
    assert!(!deleted.exists());
    assert_eq!(std::fs::read_to_string(&overwritten).unwrap(), "");

    let text_ptr = editor_core_ui_ffi_multi_document_tab_text(multi, old_id);
    assert!(!text_ptr.is_null());
    let text = unsafe { std::ffi::CStr::from_ptr(text_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(text_ptr) };
    assert_eq!(text, "renamed old\n");

    let snapshot_ptr = editor_core_ui_ffi_multi_document_snapshot_json(multi);
    assert!(!snapshot_ptr.is_null());
    let snapshot_json = unsafe { std::ffi::CStr::from_ptr(snapshot_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(snapshot_ptr) };
    let snapshot: serde_json::Value = serde_json::from_str(&snapshot_json).unwrap();
    assert_eq!(
        snapshot["tabs"]
            .as_array()
            .unwrap()
            .iter()
            .any(|tab| tab["id"] == delete_id),
        false
    );

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn ffi_multi_document_applies_unopened_workspace_file_resource_operations() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let root = std::env::temp_dir().join(format!(
        "editor-core-ui-ffi-workspace-resource-root-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    let outside_root = std::env::temp_dir().join(format!(
        "editor-core-ui-ffi-workspace-resource-outside-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::create_dir_all(&outside_root).unwrap();
    let old = root.join("src").join("Old.swift");
    let renamed = root.join("src").join("Renamed.swift");
    let created = root.join("generated").join("Created.swift");
    let deleted = root.join("src").join("Deleted.swift");
    let outside = outside_root.join("Outside.swift");
    std::fs::write(&old, "old\n").unwrap();
    std::fs::write(&deleted, "delete me\n").unwrap();

    let root_uri = format!("file://{}", root.to_string_lossy());
    let old_uri = format!("file://{}", old.to_string_lossy());
    let renamed_uri = format!("file://{}", renamed.to_string_lossy());
    let created_uri = format!("file://{}", created.to_string_lossy());
    let deleted_uri = format!("file://{}", deleted.to_string_lossy());
    let outside_uri = format!("file://{}", outside.to_string_lossy());

    let roots = CString::new(serde_json::json!([root_uri]).to_string()).unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_workspace_roots_json(multi, roots.as_ptr()),
        ECU_OK
    );

    let workspace_edit = CString::new(
        serde_json::json!({
            "documentChanges": [
                { "kind": "create", "uri": created_uri.as_str() },
                {
                    "textDocument": { "uri": created_uri.as_str(), "version": null },
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
                { "kind": "delete", "uri": deleted_uri.as_str() },
                { "kind": "create", "uri": outside_uri.as_str() }
            ]
        })
        .to_string(),
    )
    .unwrap();

    let preview_ptr = editor_core_ui_ffi_multi_document_preview_workspace_edit_transaction_json(
        multi,
        workspace_edit.as_ptr(),
    );
    assert!(!preview_ptr.is_null());
    let preview_json = unsafe { std::ffi::CStr::from_ptr(preview_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(preview_ptr) };
    let preview: serde_json::Value = serde_json::from_str(&preview_json).unwrap();
    assert_eq!(preview["mode"], "preview");
    assert_eq!(preview["applied"], false);
    assert_eq!(created.exists(), false);
    assert_eq!(
        preview["skipped_details"]
            .as_array()
            .unwrap()
            .iter()
            .any(|detail| {
                detail["uri"] == outside_uri
                    && detail["operation"] == "create"
                    && detail["reason"] == "document_outside_workspace"
            }),
        true
    );

    let apply_ptr = editor_core_ui_ffi_multi_document_apply_workspace_edit_transaction_json(
        multi,
        workspace_edit.as_ptr(),
    );
    assert!(!apply_ptr.is_null());
    let apply_json = unsafe { std::ffi::CStr::from_ptr(apply_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(apply_ptr) };
    let applied: serde_json::Value = serde_json::from_str(&apply_json).unwrap();
    assert_eq!(applied["mode"], "apply");
    assert_eq!(applied["applied"], true);
    assert_eq!(applied["applied_edit_count"], 1);
    assert_eq!(applied["applied_resource_operation_count"], 3);
    assert_eq!(std::fs::read_to_string(&created).unwrap(), "created\n");
    assert!(!old.exists());
    assert!(renamed.exists());
    assert!(!deleted.exists());
    assert!(!outside.exists());

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
    let _ = std::fs::remove_dir_all(root);
    let _ = std::fs::remove_dir_all(outside_root);
}

#[test]
fn ffi_multi_document_rolls_back_unopened_resource_operations_after_runtime_failure() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let root = std::env::temp_dir().join(format!(
        "editor-core-ui-ffi-workspace-rollback-root-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(root.join("src")).unwrap();
    let old = root.join("src").join("Old.swift");
    let target = root.join("src").join("Target.swift");
    let created = root.join("generated").join("Created.swift");
    let blocker = root.join("blocker");
    let blocked_child = blocker.join("Child.swift");
    std::fs::write(&old, "old\n").unwrap();
    std::fs::write(&target, "target\n").unwrap();
    std::fs::write(&blocker, "blocker\n").unwrap();

    let root_uri = format!("file://{}", root.to_string_lossy());
    let old_uri = format!("file://{}", old.to_string_lossy());
    let target_uri = format!("file://{}", target.to_string_lossy());
    let created_uri = format!("file://{}", created.to_string_lossy());
    let blocked_child_uri = format!("file://{}", blocked_child.to_string_lossy());

    let roots = CString::new(serde_json::json!([root_uri]).to_string()).unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_workspace_roots_json(multi, roots.as_ptr()),
        ECU_OK
    );

    let workspace_edit = CString::new(
        serde_json::json!({
            "documentChanges": [
                { "kind": "create", "uri": created_uri.as_str() },
                {
                    "kind": "rename",
                    "oldUri": old_uri.as_str(),
                    "newUri": target_uri.as_str(),
                    "options": { "overwrite": true }
                },
                { "kind": "create", "uri": blocked_child_uri.as_str() }
            ]
        })
        .to_string(),
    )
    .unwrap();

    let preview_ptr = editor_core_ui_ffi_multi_document_preview_workspace_edit_transaction_json(
        multi,
        workspace_edit.as_ptr(),
    );
    assert!(!preview_ptr.is_null());
    let preview_json = unsafe { std::ffi::CStr::from_ptr(preview_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(preview_ptr) };
    let preview: serde_json::Value = serde_json::from_str(&preview_json).unwrap();
    assert_eq!(preview["skipped_uris"].as_array().unwrap().len(), 0);
    assert!(!created.exists());
    assert_eq!(std::fs::read_to_string(&target).unwrap(), "target\n");

    let apply_ptr = editor_core_ui_ffi_multi_document_apply_workspace_edit_transaction_json(
        multi,
        workspace_edit.as_ptr(),
    );
    assert!(apply_ptr.is_null());
    let msg_ptr = editor_core_ui_ffi_last_error_message();
    assert!(!msg_ptr.is_null());
    let msg = unsafe { std::ffi::CStr::from_ptr(msg_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(msg_ptr) };
    assert!(msg.contains("filesystem side effects were rolled back"));

    assert!(!created.exists());
    assert!(!root.join("generated").exists());
    assert_eq!(std::fs::read_to_string(&old).unwrap(), "old\n");
    assert_eq!(std::fs::read_to_string(&target).unwrap(), "target\n");
    assert_eq!(std::fs::read_to_string(&blocker).unwrap(), "blocker\n");
    assert!(!blocked_child.exists());

    let mut sequence = 99;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_multi_document_workspace_edit_transaction_events_latest_sequence(
                multi,
                &mut sequence,
            )
        },
        ECU_OK
    );
    assert_eq!(sequence, 0);

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn ffi_multi_document_rolls_back_unopened_text_edits_after_runtime_failure() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let root = std::env::temp_dir().join(format!(
        "editor-core-ui-ffi-workspace-text-rollback-root-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(root.join("src")).unwrap();
    let target = root.join("src").join("Target.swift");
    let blocker = root.join("blocker");
    let blocked_child = blocker.join("Child.swift");
    std::fs::write(&target, "alpha\nbeta\n").unwrap();
    std::fs::write(&blocker, "blocker\n").unwrap();

    let root_uri = format!("file://{}", root.to_string_lossy());
    let target_uri = format!("file://{}", target.to_string_lossy());
    let blocked_child_uri = format!("file://{}", blocked_child.to_string_lossy());

    let roots = CString::new(serde_json::json!([root_uri]).to_string()).unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_workspace_roots_json(multi, roots.as_ptr()),
        ECU_OK
    );

    let workspace_edit = CString::new(
        serde_json::json!({
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
                { "kind": "create", "uri": blocked_child_uri.as_str() }
            ]
        })
        .to_string(),
    )
    .unwrap();

    let preview_ptr = editor_core_ui_ffi_multi_document_preview_workspace_edit_transaction_json(
        multi,
        workspace_edit.as_ptr(),
    );
    assert!(!preview_ptr.is_null());
    let preview_json = unsafe { std::ffi::CStr::from_ptr(preview_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(preview_ptr) };
    let preview: serde_json::Value = serde_json::from_str(&preview_json).unwrap();
    assert_eq!(preview["skipped_uris"].as_array().unwrap().len(), 0);
    assert_eq!(std::fs::read_to_string(&target).unwrap(), "alpha\nbeta\n");

    let apply_ptr = editor_core_ui_ffi_multi_document_apply_workspace_edit_transaction_json(
        multi,
        workspace_edit.as_ptr(),
    );
    assert!(apply_ptr.is_null());
    let msg_ptr = editor_core_ui_ffi_last_error_message();
    assert!(!msg_ptr.is_null());
    let msg = unsafe { std::ffi::CStr::from_ptr(msg_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(msg_ptr) };
    assert!(msg.contains("filesystem side effects were rolled back"));

    assert_eq!(std::fs::read_to_string(&target).unwrap(), "alpha\nbeta\n");
    assert_eq!(std::fs::read_to_string(&blocker).unwrap(), "blocker\n");
    assert!(!blocked_child.exists());

    let mut sequence = 99;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_multi_document_workspace_edit_transaction_events_latest_sequence(
                multi,
                &mut sequence,
            )
        },
        ECU_OK
    );
    assert_eq!(sequence, 0);

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn ffi_multi_document_rolls_back_open_tabs_after_runtime_failure() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let root = std::env::temp_dir().join(format!(
        "editor-core-ui-ffi-open-tab-rollback-root-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(root.join("src")).unwrap();
    let old_path = root.join("src").join("Old.swift");
    let delete_path = root.join("src").join("Delete.swift");
    let overwrite_path = root.join("src").join("Overwrite.swift");
    let renamed_path = root.join("src").join("Renamed.swift");
    let blocker = root.join("blocker");
    let blocked_child = blocker.join("Child.swift");
    std::fs::write(&old_path, "old\n").unwrap();
    std::fs::write(&delete_path, "delete\n").unwrap();
    std::fs::write(&overwrite_path, "existing\n").unwrap();
    std::fs::write(&blocker, "blocker\n").unwrap();

    let root_uri = format!("file://{}", root.to_string_lossy());
    let old_uri = format!("file://{}", old_path.to_string_lossy());
    let delete_uri = format!("file://{}", delete_path.to_string_lossy());
    let overwrite_uri = format!("file://{}", overwrite_path.to_string_lossy());
    let renamed_uri = format!("file://{}", renamed_path.to_string_lossy());
    let blocked_child_uri = format!("file://{}", blocked_child.to_string_lossy());

    let roots = CString::new(serde_json::json!([root_uri]).to_string()).unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_workspace_roots_json(multi, roots.as_ptr()),
        ECU_OK
    );

    let old_text = CString::new("old\n").unwrap();
    let delete_text = CString::new("delete\n").unwrap();
    let overwrite_text = CString::new("existing\n").unwrap();
    let mut old_id: u64 = 0;
    let mut delete_id: u64 = 0;
    let mut overwrite_id: u64 = 0;
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(multi, old_text.as_ptr(), 80, &mut old_id),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(multi, delete_text.as_ptr(), 80, &mut delete_id,),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_open_tab(
            multi,
            overwrite_text.as_ptr(),
            80,
            &mut overwrite_id,
        ),
        ECU_OK
    );
    let old_uri_c = CString::new(old_uri.clone()).unwrap();
    let delete_uri_c = CString::new(delete_uri.clone()).unwrap();
    let overwrite_uri_c = CString::new(overwrite_uri.clone()).unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_document_uri(multi, old_id, old_uri_c.as_ptr(),),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_document_uri(
            multi,
            delete_id,
            delete_uri_c.as_ptr(),
        ),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_tab_document_uri(
            multi,
            overwrite_id,
            overwrite_uri_c.as_ptr(),
        ),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_active_tab(multi, delete_id),
        ECU_OK
    );

    let workspace_edit = CString::new(
        serde_json::json!({
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
                { "kind": "delete", "uri": delete_uri.as_str() },
                {
                    "kind": "create",
                    "uri": overwrite_uri.as_str(),
                    "options": { "overwrite": true }
                },
                { "kind": "create", "uri": blocked_child_uri.as_str() }
            ]
        })
        .to_string(),
    )
    .unwrap();

    let preview_ptr = editor_core_ui_ffi_multi_document_preview_workspace_edit_transaction_json(
        multi,
        workspace_edit.as_ptr(),
    );
    assert!(!preview_ptr.is_null());
    let preview_json = unsafe { std::ffi::CStr::from_ptr(preview_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(preview_ptr) };
    let preview: serde_json::Value = serde_json::from_str(&preview_json).unwrap();
    assert_eq!(preview["skipped_uris"].as_array().unwrap().len(), 0);

    let apply_ptr = editor_core_ui_ffi_multi_document_apply_workspace_edit_transaction_json(
        multi,
        workspace_edit.as_ptr(),
    );
    assert!(apply_ptr.is_null());
    let msg_ptr = editor_core_ui_ffi_last_error_message();
    assert!(!msg_ptr.is_null());
    let msg = unsafe { std::ffi::CStr::from_ptr(msg_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(msg_ptr) };
    assert!(msg.contains("filesystem side effects were rolled back"));
    assert!(msg.contains("open tab state was rolled back"));

    let old_text_ptr = editor_core_ui_ffi_multi_document_tab_text(multi, old_id);
    assert!(!old_text_ptr.is_null());
    let old_text_after = unsafe { std::ffi::CStr::from_ptr(old_text_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(old_text_ptr) };
    assert_eq!(old_text_after, "old\n");
    let delete_text_ptr = editor_core_ui_ffi_multi_document_tab_text(multi, delete_id);
    assert!(!delete_text_ptr.is_null());
    let delete_text_after = unsafe { std::ffi::CStr::from_ptr(delete_text_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(delete_text_ptr) };
    assert_eq!(delete_text_after, "delete\n");
    let overwrite_text_ptr = editor_core_ui_ffi_multi_document_tab_text(multi, overwrite_id);
    assert!(!overwrite_text_ptr.is_null());
    let overwrite_text_after = unsafe { std::ffi::CStr::from_ptr(overwrite_text_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(overwrite_text_ptr) };
    assert_eq!(overwrite_text_after, "existing\n");

    let mut old_uri_ptr: *mut c_char = std::ptr::null_mut();
    assert_eq!(
        editor_core_ui_ffi_multi_document_tab_document_uri(multi, old_id, &mut old_uri_ptr),
        ECU_OK
    );
    assert!(!old_uri_ptr.is_null());
    let old_uri_after = unsafe { std::ffi::CStr::from_ptr(old_uri_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(old_uri_ptr) };
    assert_eq!(old_uri_after, old_uri);

    let mut old_modified = 1;
    assert_eq!(
        editor_core_ui_ffi_multi_document_is_tab_modified(multi, old_id, &mut old_modified),
        ECU_OK
    );
    assert_eq!(old_modified, 0);
    let mut overwrite_modified = 1;
    assert_eq!(
        editor_core_ui_ffi_multi_document_is_tab_modified(
            multi,
            overwrite_id,
            &mut overwrite_modified,
        ),
        ECU_OK
    );
    assert_eq!(overwrite_modified, 0);
    let mut has_active = 0;
    let mut active_id = 0;
    assert_eq!(
        editor_core_ui_ffi_multi_document_active_tab_id(multi, &mut has_active, &mut active_id),
        ECU_OK
    );
    assert_eq!(has_active, 1);
    assert_eq!(active_id, delete_id);

    assert!(old_path.exists());
    assert!(!renamed_path.exists());
    assert!(delete_path.exists());
    assert_eq!(
        std::fs::read_to_string(&overwrite_path).unwrap(),
        "existing\n"
    );
    assert_eq!(std::fs::read_to_string(&blocker).unwrap(), "blocker\n");
    assert!(!blocked_child.exists());
    let mut sequence = 99;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_multi_document_workspace_edit_transaction_events_latest_sequence(
                multi,
                &mut sequence,
            )
        },
        ECU_OK
    );
    assert_eq!(sequence, 0);

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn ffi_multi_document_applies_workspace_edit_document_changes_in_order() {
    let multi = editor_core_ui_ffi_multi_document_new();
    assert!(!multi.is_null());

    let root = std::env::temp_dir().join(format!(
        "editor-core-ui-ffi-workspace-order-root-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(root.join("src")).unwrap();
    let draft = root.join("src").join("Draft.swift");
    let final_file = root.join("src").join("Final.swift");

    let root_uri = format!("file://{}", root.to_string_lossy());
    let draft_uri = format!("file://{}", draft.to_string_lossy());
    let final_uri = format!("file://{}", final_file.to_string_lossy());

    let roots = CString::new(serde_json::json!([root_uri]).to_string()).unwrap();
    assert_eq!(
        editor_core_ui_ffi_multi_document_set_workspace_roots_json(multi, roots.as_ptr()),
        ECU_OK
    );

    let workspace_edit = CString::new(
        serde_json::json!({
            "documentChanges": [
                { "kind": "create", "uri": draft_uri.as_str() },
                {
                    "textDocument": { "uri": draft_uri.as_str(), "version": null },
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
                    "textDocument": { "uri": final_uri.as_str(), "version": null },
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
        .to_string(),
    )
    .unwrap();

    let preview_ptr = editor_core_ui_ffi_multi_document_preview_workspace_edit_transaction_json(
        multi,
        workspace_edit.as_ptr(),
    );
    assert!(!preview_ptr.is_null());
    let preview_json = unsafe { std::ffi::CStr::from_ptr(preview_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(preview_ptr) };
    let preview: serde_json::Value = serde_json::from_str(&preview_json).unwrap();
    assert_eq!(preview["skipped_uris"].as_array().unwrap().len(), 0);
    assert!(!draft.exists());
    assert!(!final_file.exists());

    let apply_ptr = editor_core_ui_ffi_multi_document_apply_workspace_edit_transaction_json(
        multi,
        workspace_edit.as_ptr(),
    );
    assert!(!apply_ptr.is_null());
    let apply_json = unsafe { std::ffi::CStr::from_ptr(apply_ptr) }
        .to_string_lossy()
        .into_owned();
    unsafe { editor_core_ui_ffi_string_free(apply_ptr) };
    let applied: serde_json::Value = serde_json::from_str(&apply_json).unwrap();
    assert_eq!(applied["applied"], true);
    assert_eq!(applied["applied_edit_count"], 2);
    assert_eq!(applied["applied_resource_operation_count"], 2);
    assert_eq!(applied["skipped_uris"].as_array().unwrap().len(), 0);
    assert!(!draft.exists());
    assert_eq!(
        std::fs::read_to_string(&final_file).unwrap(),
        "final draft\n"
    );

    unsafe { editor_core_ui_ffi_multi_document_free(multi) };
    let _ = std::fs::remove_dir_all(root);
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
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_LSP_REQUEST_CANCEL_TIMEOUT_EVENTS,
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

    let mut recorded: u8 = u8::MAX;
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_lsp_cancel_request(ui, 999, &mut recorded) },
        ECU_OK
    );
    assert_eq!(recorded, 0);
    recorded = u8::MAX;
    assert_eq!(
        unsafe { editor_core_ui_ffi_editor_ui_lsp_mark_request_timed_out(ui, 999, &mut recorded) },
        ECU_OK
    );
    assert_eq!(recorded, 0);
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

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_editor_ui_state_events_snapshot_empty() {
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_EDITOR_UI_STATE_EVENTS,
        0
    );

    let initial = CString::new("abc").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let mut latest_sequence: u64 = u64::MAX;
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_state_events_latest_sequence(ui, &mut latest_sequence)
        },
        ECU_OK
    );
    assert_eq!(latest_sequence, 0);

    let events_ptr = editor_core_ui_ffi_editor_ui_state_events_json(ui, 0);
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
fn ffi_multi_document_state_events_snapshot_empty() {
    assert_ne!(
        editor_core_ui_ffi_feature_flags() & ECU_FEATURE_MULTI_DOCUMENT_STATE_EVENTS,
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
            editor_core_ui_ffi_multi_document_state_events_latest_sequence(
                multi,
                &mut latest_sequence,
            )
        },
        ECU_OK
    );
    assert_eq!(latest_sequence, 0);

    let events_ptr = editor_core_ui_ffi_multi_document_state_events_json(multi, 0);
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
fn ffi_minimap_envelope_json_reports_success_and_errors() {
    let initial = CString::new("a\nb\nc").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let result_json = take_owned_string(editor_core_ui_ffi_editor_ui_minimap_envelope_json(
        ui, 0, 20,
    ));
    let result: serde_json::Value = serde_json::from_str(&result_json).unwrap();
    assert_eq!(result["ok"], true);
    assert_eq!(result["status"], "success");
    assert_eq!(result["start_visual_row"], 0);
    assert_eq!(result["count"], 20);
    assert_eq!(result["version"], ECU_ABI_VERSION);
    assert_eq!(result["value"]["start_visual_row"], 0);
    assert_eq!(result["value"]["count"], 20);
    assert_eq!(result["value"]["actual_line_count"], 3);
    assert!(result["value"]["lines"].is_array());
    assert!(result["error"].is_null());

    let error_json = take_owned_string(editor_core_ui_ffi_editor_ui_minimap_envelope_json(
        ptr::null_mut(),
        2,
        5,
    ));
    let error: serde_json::Value = serde_json::from_str(&error_json).unwrap();
    assert_eq!(error["ok"], false);
    assert_eq!(error["status"], "error");
    assert_eq!(error["start_visual_row"], 2);
    assert_eq!(error["count"], 5);
    assert_eq!(error["value"], serde_json::Value::Null);
    assert_eq!(error["error"]["code"], "invalid_argument");
    assert_eq!(error["error"]["status"], ECU_ERR_INVALID_ARGUMENT);
    assert_eq!(error["error"]["message"], "ui is null");
    assert_eq!(error["version"], ECU_ABI_VERSION);

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
fn ffi_view_point_payload_envelope_json_reports_success_empty_and_errors() {
    let initial = CString::new("ab cd\nline2\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 20.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 400, 100, 1.0),
        ECU_OK
    );

    let code_lens_result = CString::new(
        r#"[
          {
            "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } },
            "command": { "title": "Run tests", "command": "test.run", "arguments": [1] }
          }
        ]"#,
    )
    .unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_lsp_apply_code_lens_json(ui, code_lens_result.as_ptr()),
        ECU_OK
    );

    let inlay_result = CString::new(
        r#"[
          {
            "position": { "line": 0, "character": 1 },
            "label": ": Int",
            "data": { "id": 42 }
          }
        ]"#,
    )
    .unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_lsp_apply_inlay_hints_json(ui, inlay_result.as_ptr()),
        ECU_OK
    );

    let links_result = CString::new(
        r#"[
          {
            "range": { "start": { "line": 0, "character": 3 }, "end": { "line": 0, "character": 4 } },
            "target": "https://example.com"
          }
        ]"#,
    )
    .unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_lsp_apply_document_links_json(ui, links_result.as_ptr()),
        ECU_OK
    );

    let code_lens_kind = CString::new("code_lens").unwrap();
    let code_lens_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_view_point_payload_envelope_json(
            ui,
            code_lens_kind.as_ptr(),
            5.0,
            10.0,
        ),
    );
    let code_lens: serde_json::Value = serde_json::from_str(&code_lens_json).unwrap();
    assert_eq!(code_lens["ok"], true);
    assert_eq!(code_lens["kind"], "code_lens");
    assert_eq!(code_lens["status"], "success");
    assert_eq!(code_lens["x_px"], 5.0);
    assert_eq!(code_lens["y_px"], 10.0);
    assert_eq!(code_lens["value"]["command"]["title"], "Run tests");
    assert_eq!(code_lens["value"]["command"]["command"], "test.run");
    assert!(code_lens["error"].is_null());
    assert_eq!(code_lens["version"], ECU_ABI_VERSION);

    let empty_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_view_point_payload_envelope_json(
            ui,
            code_lens_kind.as_ptr(),
            300.0,
            10.0,
        ),
    );
    let empty: serde_json::Value = serde_json::from_str(&empty_json).unwrap();
    assert_eq!(empty["ok"], true);
    assert_eq!(empty["kind"], "code_lens");
    assert_eq!(empty["status"], "empty");
    assert_eq!(empty["value"], serde_json::Value::Null);
    assert!(empty["error"].is_null());
    assert_eq!(empty["version"], ECU_ABI_VERSION);

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
    let inlay_kind = CString::new("inlay_hint").unwrap();
    let inlay_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_view_point_payload_envelope_json(
            ui,
            inlay_kind.as_ptr(),
            x + 1.0,
            y + 1.0,
        ),
    );
    let inlay: serde_json::Value = serde_json::from_str(&inlay_json).unwrap();
    assert_eq!(inlay["ok"], true);
    assert_eq!(inlay["kind"], "inlay_hint");
    assert_eq!(inlay["status"], "success");
    assert_eq!(inlay["value"]["label"], ": Int");
    assert_eq!(inlay["value"]["data"]["id"], 42);

    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_char_offset_to_view_point(ui, 3, &mut x, &mut y, &mut lh)
        },
        ECU_OK
    );
    assert!(lh > 0.0);
    let link_kind = CString::new("document_link").unwrap();
    let link_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_view_point_payload_envelope_json(
            ui,
            link_kind.as_ptr(),
            x + 1.0,
            y + 1.0,
        ),
    );
    let link: serde_json::Value = serde_json::from_str(&link_json).unwrap();
    assert_eq!(link["ok"], true);
    assert_eq!(link["kind"], "document_link");
    assert_eq!(link["status"], "success");
    assert_eq!(link["value"]["target"], "https://example.com");

    let unknown_kind = CString::new("hover").unwrap();
    let unknown_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_view_point_payload_envelope_json(
            ui,
            unknown_kind.as_ptr(),
            1.0,
            2.0,
        ),
    );
    let unknown: serde_json::Value = serde_json::from_str(&unknown_json).unwrap();
    assert_eq!(unknown["ok"], false);
    assert_eq!(unknown["kind"], "hover");
    assert_eq!(unknown["status"], "error");
    assert_eq!(unknown["value"], serde_json::Value::Null);
    assert_eq!(unknown["error"]["code"], "invalid_argument");
    assert_eq!(unknown["error"]["status"], ECU_ERR_INVALID_ARGUMENT);
    assert_eq!(
        unknown["error"]["message"],
        "unknown view point payload kind \"hover\""
    );
    assert_eq!(unknown["version"], ECU_ABI_VERSION);

    let null_ui_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_view_point_payload_envelope_json(
            ptr::null_mut(),
            code_lens_kind.as_ptr(),
            3.0,
            4.0,
        ),
    );
    let null_ui: serde_json::Value = serde_json::from_str(&null_ui_json).unwrap();
    assert_eq!(null_ui["ok"], false);
    assert_eq!(null_ui["kind"], "code_lens");
    assert_eq!(null_ui["status"], "error");
    assert_eq!(null_ui["error"]["code"], "invalid_argument");
    assert_eq!(null_ui["error"]["status"], ECU_ERR_INVALID_ARGUMENT);
    assert_eq!(null_ui["error"]["message"], "ui is null");

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_inlay_hint_hit_test_returns_payload_json() {
    let initial = CString::new("ab\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_render_metrics(ui, 12.0, 10.0, 10.0, 0.0, 0.0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_viewport_px(ui, 200, 40, 1.0),
        ECU_OK
    );

    let result = CString::new(
        r#"[
          {
            "position": { "line": 0, "character": 1 },
            "label": ": Int",
            "data": { "id": 42 }
          }
        ]"#,
    )
    .unwrap();
    assert_eq!(
        editor_core_ui_ffi_editor_ui_lsp_apply_inlay_hints_json(ui, result.as_ptr()),
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
            editor_core_ui_ffi_editor_ui_get_inlay_hint_json_at_view_point(
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
    let value: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(value["label"], ": Int");
    assert_eq!(value["data"]["id"], 42);

    let mut has2: u8 = 9;
    let mut json_ptr2: *mut c_char = ptr::null_mut();
    assert_eq!(
        unsafe {
            editor_core_ui_ffi_editor_ui_get_inlay_hint_json_at_view_point(
                ui,
                1.0,
                y + 1.0,
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
fn ffi_lsp_workspace_edit_application_envelope_json_reports_success_and_errors() {
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

    let result_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_envelope_json(
            ui,
            workspace_edit.as_ptr(),
            uri.as_ptr(),
        ),
    );
    let result: serde_json::Value = serde_json::from_str(&result_json).unwrap();
    assert_eq!(result["ok"], true);
    assert_eq!(result["status"], "success");
    assert_eq!(result["document_uri"], "file:///test.rs");
    assert_eq!(result["version"], ECU_ABI_VERSION);
    assert_eq!(result["value"]["applied"], true);
    assert_eq!(result["value"]["applied_uri"], "file:///test.rs");
    assert_eq!(result["value"]["applied_edit_count"], 1);
    assert_eq!(
        result["value"]["skipped_uris"],
        serde_json::json!(["file:///other.rs"])
    );
    assert!(result["error"].is_null());

    let text_ptr = editor_core_ui_ffi_editor_ui_get_text(ui);
    assert!(!text_ptr.is_null());
    let text = unsafe { CStr::from_ptr(text_ptr) }
        .to_str()
        .unwrap()
        .to_string();
    unsafe { editor_core_ui_ffi_string_free(text_ptr) };
    assert_eq!(text, "aBc\n");

    let invalid = CString::new("{").unwrap();
    let error_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_lsp_apply_workspace_edit_envelope_json(
            ui,
            invalid.as_ptr(),
            uri.as_ptr(),
        ),
    );
    let error: serde_json::Value = serde_json::from_str(&error_json).unwrap();
    assert_eq!(error["ok"], false);
    assert_eq!(error["status"], "error");
    assert_eq!(error["document_uri"], "file:///test.rs");
    assert_eq!(error["value"], serde_json::Value::Null);
    assert_eq!(error["error"]["code"], "internal");
    assert!(
        error["error"]["message"]
            .as_str()
            .unwrap()
            .contains("EOF while parsing")
    );
    assert_eq!(error["version"], ECU_ABI_VERSION);

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_lsp_derived_state_application_envelope_json_reports_success_and_errors() {
    let initial = CString::new("fn main() {}\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let diagnostics = CString::new(
        r#"{"uri":"file:///test.rs","diagnostics":[{"range":{"start":{"line":0,"character":3},"end":{"line":0,"character":7}},"severity":1,"message":"demo"}]}"#,
    )
    .unwrap();
    let inlay_hints =
        CString::new(r#"[{"position":{"line":0,"character":3},"label":": i32"}]"#).unwrap();
    let code_lens = CString::new(r#"[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":2}},"command":{"title":"run","command":"demo.run"}}]"#)
        .unwrap();
    let document_links = CString::new(
        r#"[{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":2}},"target":"file:///target.rs"}]"#,
    )
    .unwrap();
    let document_highlights = CString::new(
        r#"[{"range":{"start":{"line":0,"character":3},"end":{"line":0,"character":7}},"kind":1}]"#,
    )
    .unwrap();
    let document_symbols = CString::new(
        r#"[{"name":"main","kind":12,"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":12}},"selectionRange":{"start":{"line":0,"character":3},"end":{"line":0,"character":7}}}]"#,
    )
    .unwrap();
    let folding_ranges =
        CString::new(r#"[{"startLine":0,"startCharacter":0,"endLine":0,"endCharacter":12}]"#)
            .unwrap();

    let cases: &[(&str, *mut c_char)] = &[
        (
            "apply_diagnostics",
            editor_core_ui_ffi_editor_ui_lsp_apply_diagnostics_envelope_json(
                ui,
                diagnostics.as_ptr(),
            ),
        ),
        (
            "apply_inlay_hints",
            editor_core_ui_ffi_editor_ui_lsp_apply_inlay_hints_envelope_json(
                ui,
                inlay_hints.as_ptr(),
            ),
        ),
        (
            "apply_code_lens",
            editor_core_ui_ffi_editor_ui_lsp_apply_code_lens_envelope_json(ui, code_lens.as_ptr()),
        ),
        (
            "apply_document_links",
            editor_core_ui_ffi_editor_ui_lsp_apply_document_links_envelope_json(
                ui,
                document_links.as_ptr(),
            ),
        ),
        (
            "apply_document_highlights",
            editor_core_ui_ffi_editor_ui_lsp_apply_document_highlights_envelope_json(
                ui,
                document_highlights.as_ptr(),
            ),
        ),
        (
            "apply_document_symbols",
            editor_core_ui_ffi_editor_ui_lsp_apply_document_symbols_envelope_json(
                ui,
                document_symbols.as_ptr(),
            ),
        ),
        (
            "apply_folding_ranges",
            editor_core_ui_ffi_editor_ui_lsp_apply_folding_ranges_envelope_json(
                ui,
                folding_ranges.as_ptr(),
            ),
        ),
    ];

    for (operation, ptr) in cases {
        let json = take_owned_string(*ptr);
        let envelope: serde_json::Value = serde_json::from_str(&json).unwrap();
        assert_eq!(envelope["ok"], true, "{operation}");
        assert_eq!(envelope["operation"], *operation);
        assert_eq!(envelope["status"], "success");
        assert_eq!(envelope["value"]["applied"], true);
        assert!(envelope["error"].is_null());
        assert_eq!(envelope["version"], ECU_ABI_VERSION);
    }

    let invalid = CString::new("{").unwrap();
    let error_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_lsp_apply_inlay_hints_envelope_json(ui, invalid.as_ptr()),
    );
    let error: serde_json::Value = serde_json::from_str(&error_json).unwrap();
    assert_eq!(error["ok"], false);
    assert_eq!(error["operation"], "apply_inlay_hints");
    assert_eq!(error["status"], "error");
    assert_eq!(error["value"], serde_json::Value::Null);
    assert_eq!(error["error"]["code"], "internal");
    assert!(
        error["error"]["message"]
            .as_str()
            .unwrap()
            .contains("EOF while parsing")
    );
    assert_eq!(error["version"], ECU_ABI_VERSION);

    let null_json = take_owned_string(
        editor_core_ui_ffi_editor_ui_lsp_apply_diagnostics_envelope_json(ui, ptr::null()),
    );
    let null_error: serde_json::Value = serde_json::from_str(&null_json).unwrap();
    assert_eq!(null_error["ok"], false);
    assert_eq!(null_error["operation"], "apply_diagnostics");
    assert_eq!(null_error["error"]["code"], "invalid_argument");
    assert_eq!(
        null_error["error"]["message"],
        "publish_diagnostics_json_utf8 is null"
    );

    unsafe { editor_core_ui_ffi_editor_ui_free(ui) };
}

#[test]
fn ffi_lsp_semantic_tokens_application_envelope_json_reports_success_and_errors() {
    let initial = CString::new("a c\n").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let data = [0_u32, 1, 1, 7, 0];
    let ok_json = take_owned_string(unsafe {
        editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens_envelope_json(
            ui,
            data.as_ptr(),
            data.len() as u32,
        )
    });
    let ok: serde_json::Value = serde_json::from_str(&ok_json).unwrap();
    assert_eq!(ok["ok"], true);
    assert_eq!(ok["operation"], "apply_semantic_tokens");
    assert_eq!(ok["status"], "success");
    assert_eq!(ok["value"]["applied"], true);
    assert_eq!(ok["value"]["data_len"], 5);
    assert!(ok["error"].is_null());
    assert_eq!(ok["version"], ECU_ABI_VERSION);

    let malformed = [0_u32];
    let error_json = take_owned_string(unsafe {
        editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens_envelope_json(
            ui,
            malformed.as_ptr(),
            malformed.len() as u32,
        )
    });
    let error: serde_json::Value = serde_json::from_str(&error_json).unwrap();
    assert_eq!(error["ok"], false);
    assert_eq!(error["operation"], "apply_semantic_tokens");
    assert_eq!(error["status"], "error");
    assert_eq!(error["value"], serde_json::Value::Null);
    assert_eq!(error["error"]["code"], "internal");
    let message = error["error"]["message"].as_str().unwrap().to_lowercase();
    assert!(message.contains("semantic tokens data length"));
    assert!(message.contains("multiple of 5"));
    assert_eq!(error["version"], ECU_ABI_VERSION);

    let null_json = take_owned_string(unsafe {
        editor_core_ui_ffi_editor_ui_lsp_apply_semantic_tokens_envelope_json(
            ui,
            ptr::null(),
            data.len() as u32,
        )
    });
    let null_error: serde_json::Value = serde_json::from_str(&null_json).unwrap();
    assert_eq!(null_error["ok"], false);
    assert_eq!(null_error["operation"], "apply_semantic_tokens");
    assert_eq!(null_error["error"]["code"], "invalid_argument");
    assert_eq!(null_error["error"]["message"], "data is null");

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
fn ffi_set_lsp_on_type_formatting_enabled_smoke() {
    let initial = CString::new("let value = 1").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_lsp_on_type_formatting_enabled(ui, 0),
        ECU_OK
    );
    assert_eq!(
        editor_core_ui_ffi_editor_ui_set_lsp_on_type_formatting_enabled(ui, 1),
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
    let code =
        unsafe { editor_core_ui_ffi_editor_ui_lsp_request_inlay_hints(ui, 0, 1, &mut out_id) };
    assert_eq!(code, ECU_ERR_INTERNAL);
    let hint = CString::new(r#"{"position":{"line":0,"character":1},"label":"x"}"#).unwrap();
    let code = unsafe {
        editor_core_ui_ffi_editor_ui_lsp_request_inlay_hint_resolve(ui, hint.as_ptr(), &mut out_id)
    };
    assert_eq!(code, ECU_ERR_INTERNAL);
    let code = unsafe { editor_core_ui_ffi_editor_ui_lsp_request_document_links(ui, &mut out_id) };
    assert_eq!(code, ECU_ERR_INTERNAL);
    let added = CString::new(r#"[{"uri":"file:///tmp/added","name":"added"}]"#).unwrap();
    let removed = CString::new(r#"[]"#).unwrap();
    let code = unsafe {
        editor_core_ui_ffi_editor_ui_lsp_did_change_workspace_folders_json(
            ui,
            added.as_ptr(),
            removed.as_ptr(),
        )
    };
    assert_eq!(code, ECU_ERR_INTERNAL);
    let uri = CString::new("file:///tmp/closed.rs").unwrap();
    let language_id = CString::new("rust").unwrap();
    let text = CString::new("saved").unwrap();
    let code = unsafe {
        editor_core_ui_ffi_editor_ui_lsp_did_open_document(
            ui,
            uri.as_ptr(),
            language_id.as_ptr(),
            1,
            text.as_ptr(),
        )
    };
    assert_eq!(code, ECU_ERR_INTERNAL);
    let code = unsafe {
        editor_core_ui_ffi_editor_ui_lsp_did_change_document(ui, uri.as_ptr(), text.as_ptr())
    };
    assert_eq!(code, ECU_ERR_INTERNAL);
    let code = unsafe {
        editor_core_ui_ffi_editor_ui_lsp_did_save_document(ui, uri.as_ptr(), text.as_ptr())
    };
    assert_eq!(code, ECU_ERR_INTERNAL);
    let code = unsafe { editor_core_ui_ffi_editor_ui_lsp_did_close_document(ui, uri.as_ptr()) };
    assert_eq!(code, ECU_ERR_INTERNAL);
    let link = CString::new(
        r#"{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":1}}}"#,
    )
    .unwrap();
    let code = unsafe {
        editor_core_ui_ffi_editor_ui_lsp_request_document_link_resolve(
            ui,
            link.as_ptr(),
            &mut out_id,
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

#[test]
fn ffi_lsp_shutdown_returns_false_when_lsp_disabled() {
    let initial = CString::new("hello").unwrap();
    let ui = editor_core_ui_ffi_editor_ui_new(initial.as_ptr(), 80);
    assert!(!ui.is_null());

    let mut shutdown: u8 = 1;
    let code = unsafe { editor_core_ui_ffi_editor_ui_lsp_shutdown(ui, &mut shutdown) };
    assert_eq!(code, ECU_OK);
    assert_eq!(shutdown, 0);

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
