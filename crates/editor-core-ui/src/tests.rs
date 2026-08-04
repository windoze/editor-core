use super::*;

fn wait_for_async_processing(ui: &mut EditorUi) {
    let start = std::time::Instant::now();
    loop {
        let polled = ui.poll_processing().unwrap();
        if !polled.pending {
            break;
        }
        if start.elapsed() > std::time::Duration::from_secs(2) {
            panic!("timeout waiting for async processing");
        }
        std::thread::sleep(std::time::Duration::from_millis(1));
    }
}

fn set_test_treesitter_registry(ui: &mut EditorUi) {
    // Keep the tree-sitter worker at normal priority in tests so a single grammar load/parse
    // finishes within the bounded wait window (see set_current_thread_qos_for_treesitter_worker).
    // Set here, before any worker is spawned by set_treesitter_* below.
    // SAFETY: test-only; called on the main test thread before spawning the worker.
    unsafe { std::env::set_var("EDITOR_CORE_DISABLE_TS_WORKER_QOS", "1") };

    let root = std::path::PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../editor-core-treesitter/tests/fixtures/treesitter");

    let json = serde_json::json!({
        "schema_version": 1,
        "root_dir": root.to_string_lossy(),
        "extension_map": {
            "rs": "rust"
        },
        "languages": {
            "rust": {
                "wasm": "rust/language.wasm",
                "highlights": "rust/highlights.scm",
                "folds": "rust/folds.scm"
            }
        }
    })
    .to_string();

    ui.set_treesitter_registry_json(&json).unwrap();
}

fn shell_quote(raw: &str) -> String {
    format!("'{}'", raw.replace('\'', "'\\''"))
}

fn unique_temp_path(label: &str) -> std::path::PathBuf {
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    std::env::temp_dir().join(format!(
        "editor-core-ui-{label}-{}-{stamp}.log",
        std::process::id()
    ))
}

fn lsp_capture_server_script(
    capture_path: &std::path::Path,
    capabilities: serde_json::Value,
) -> String {
    lsp_capture_server_script_with_messages(
        capture_path,
        &[serde_json::json!({
            "jsonrpc": "2.0",
            "id": 1,
            "result": { "capabilities": capabilities },
        })],
    )
}

fn lsp_capture_server_script_with_messages(
    capture_path: &std::path::Path,
    messages: &[serde_json::Value],
) -> String {
    let mut script = String::new();
    for message in messages {
        let body = message.to_string();
        script.push_str(
            format!(
                "body={}; printf 'Content-Length: %s\\r\\n\\r\\n%s' \"${{#body}}\" \"$body\"; ",
                shell_quote(&body),
            )
            .as_str(),
        );
    }
    script.push_str(
        format!(
            "cat > {}",
            shell_quote(capture_path.to_string_lossy().as_ref())
        )
        .as_str(),
    );
    script
}

fn lsp_append_capture_server_script(capture_path: &std::path::Path) -> String {
    let body = lsp_initialize_response(serde_json::json!({})).to_string();
    format!(
        "body={}; printf 'Content-Length: %s\\r\\n\\r\\n%s' \"${{#body}}\" \"$body\"; cat >> {}",
        shell_quote(&body),
        shell_quote(capture_path.to_string_lossy().as_ref())
    )
}

fn lsp_graceful_shutdown_capture_server_script(capture_path: &std::path::Path) -> String {
    let init_body = lsp_initialize_response(serde_json::json!({})).to_string();
    format!(
        "init={}; capture={}; \
         printf 'Content-Length: %s\\r\\n\\r\\n%s' \"${{#init}}\" \"$init\"; \
         while IFS= read -r header; do \
           printf '%s\\n' \"$header\" >> \"$capture\"; \
           case \"$header\" in \
             Content-Length:*) \
               len=$(printf '%s' \"${{header#Content-Length: }}\" | tr -d '\\r'); \
               IFS= read -r blank; printf '%s\\n' \"$blank\" >> \"$capture\"; \
               body=$(dd bs=1 count=\"$len\" 2>/dev/null); \
               printf '%s' \"$body\" >> \"$capture\"; \
               case \"$body\" in \
                 *'\"method\":\"shutdown\"'*|*'\"method\": \"shutdown\"'*) \
                   shutdown_id=$(printf '%s' \"$body\" | sed -n 's/.*\"id\"[[:space:]]*:[[:space:]]*\\([0-9][0-9]*\\).*/\\1/p'); \
                   if [ -z \"$shutdown_id\" ]; then shutdown_id=2; fi; \
                   response=$(printf '{{\"jsonrpc\":\"2.0\",\"id\":%s,\"result\":null}}' \"$shutdown_id\"); \
                   printf 'Content-Length: %s\\r\\n\\r\\n%s' \"${{#response}}\" \"$response\" ;; \
               esac; \
               case \"$body\" in \
                 *'\"method\":\"exit\"'*|*'\"method\": \"exit\"'*) exit 0 ;; \
               esac ;; \
           esac; \
         done",
        shell_quote(&init_body),
        shell_quote(capture_path.to_string_lossy().as_ref()),
    )
}

fn lsp_initialize_response(capabilities: serde_json::Value) -> serde_json::Value {
    serde_json::json!({
        "jsonrpc": "2.0",
        "id": 1,
        "result": { "capabilities": capabilities },
    })
}

fn captured_lsp_stdin(path: &std::path::Path) -> String {
    std::fs::read_to_string(path).unwrap_or_default()
}

fn captured_lsp_json_messages(path: &std::path::Path) -> Vec<serde_json::Value> {
    let captured = captured_lsp_stdin(path);
    let bytes = captured.as_bytes();
    let mut offset = 0;
    let mut out = Vec::new();

    while offset < bytes.len() {
        let Some(header_end_rel) = bytes[offset..]
            .windows(4)
            .position(|window| window == b"\r\n\r\n")
        else {
            break;
        };
        let header_end = offset + header_end_rel;
        let header = std::str::from_utf8(&bytes[offset..header_end]).unwrap_or("");
        let Some(content_len) = header.lines().find_map(|line| {
            let (name, value) = line.split_once(':')?;
            name.trim()
                .eq_ignore_ascii_case("Content-Length")
                .then(|| value.trim().parse::<usize>().ok())
                .flatten()
        }) else {
            break;
        };

        let body_start = header_end + 4;
        let body_end = body_start + content_len;
        if body_end > bytes.len() {
            break;
        }

        if let Ok(value) = serde_json::from_slice::<serde_json::Value>(&bytes[body_start..body_end])
        {
            out.push(value);
        }
        offset = body_end;
    }

    out
}

fn wait_for_captured_lsp_stdin(path: &std::path::Path, needle: &str) -> String {
    for _ in 0..100 {
        let captured = captured_lsp_stdin(path);
        if captured.contains(needle) {
            return captured;
        }
        std::thread::sleep(std::time::Duration::from_millis(10));
    }
    panic!(
        "timed out waiting for LSP stdin to contain {needle:?}; captured: {}",
        captured_lsp_stdin(path)
    );
}

use editor_core::CursorCommand;
use editor_core_treesitter::TreeSitterUpdateMode;

#[test]
fn lsp_result_slots_store_special_success_null_and_error_envelopes() {
    let success = stored_lsp_success_result_json(
        LspResultSlot::ExecuteCommand,
        serde_json::json!({ "changed": true }),
    )
    .unwrap();
    let success_json: serde_json::Value = serde_json::from_str(&success).unwrap();
    assert_eq!(
        success_json["result"],
        serde_json::json!({ "changed": true })
    );

    let null =
        stored_lsp_success_result_json(LspResultSlot::ExecuteCommand, serde_json::Value::Null)
            .unwrap();
    let null_json: serde_json::Value = serde_json::from_str(&null).unwrap();
    assert!(null_json["result"].is_null());

    let code_lens_null =
        stored_lsp_success_result_json(LspResultSlot::CodeLens, serde_json::Value::Null).unwrap();
    let code_lens_null_json: serde_json::Value = serde_json::from_str(&code_lens_null).unwrap();
    assert!(code_lens_null_json.is_null());

    let error = stored_lsp_error_result_json(
        LspResultSlot::ExecuteCommand,
        LspResponseError {
            code: -32603,
            message: "command failed".to_string(),
            data: Some(serde_json::json!({ "detail": "boom" })),
        },
    )
    .unwrap();
    let error_json: serde_json::Value = serde_json::from_str(&error).unwrap();
    assert_eq!(error_json["error"]["code"], -32603);
    assert_eq!(error_json["error"]["message"], "command failed");
    assert_eq!(
        error_json["error"]["data"],
        serde_json::json!({ "detail": "boom" })
    );

    let code_lens_error = stored_lsp_error_result_json(
        LspResultSlot::CodeLens,
        LspResponseError {
            code: -32603,
            message: "code lens failed".to_string(),
            data: None,
        },
    )
    .unwrap();
    let code_lens_error_json: serde_json::Value = serde_json::from_str(&code_lens_error).unwrap();
    assert_eq!(code_lens_error_json["error"]["message"], "code lens failed");

    assert_eq!(
        stored_lsp_success_result_json(LspResultSlot::Hover, serde_json::json!("hover")),
        Some("\"hover\"".to_string())
    );
    assert_eq!(
        stored_lsp_success_result_json(LspResultSlot::Hover, serde_json::Value::Null),
        None
    );
    assert_eq!(
        stored_lsp_error_result_json(
            LspResultSlot::Hover,
            LspResponseError {
                code: -1,
                message: "ignored".to_string(),
                data: None,
            }
        ),
        None
    );

    assert_eq!(
        LspResultSlot::from_response_method("inlayHint/resolve"),
        Some(LspResultSlot::InlayHintResolve)
    );
    assert_eq!(
        LspResultSlot::InlayHintResolve.method(),
        "inlayHint/resolve"
    );
    assert_eq!(
        LspResultSlot::InlayHintResolve.slot_name(),
        "inlay_hint_resolve"
    );
    assert_eq!(LspResultSlot::InlayHintResolve.family(), "inlay_hints");
    assert_eq!(
        LspResultSlot::from_response_method("documentLink/resolve"),
        Some(LspResultSlot::DocumentLinkResolve)
    );
    assert_eq!(
        LspResultSlot::DocumentLinkResolve.method(),
        "documentLink/resolve"
    );
    assert_eq!(
        LspResultSlot::DocumentLinkResolve.slot_name(),
        "document_link_resolve"
    );
    assert_eq!(
        LspResultSlot::DocumentLinkResolve.family(),
        "document_links"
    );
}

#[test]
fn lsp_result_events_record_success_empty_and_error_slots() {
    let mut ui = EditorUi::new("abc", 80);
    let view_id = ui.view_id;
    {
        let mut doc = ui.lock_doc();
        for (id, slot) in [
            (7, LspResultSlot::Hover),
            (8, LspResultSlot::References),
            (9, LspResultSlot::CodeAction),
        ] {
            doc.lsp_client_requests.insert(
                id,
                LspClientRequest::Result {
                    view: view_id,
                    slot,
                },
            );
            doc.lsp_latest_result_request_id.insert((view_id, slot), id);
        }
    }

    assert_eq!(ui.lsp_result_events_latest_sequence(), 0);
    assert!(ui.lsp_result_events_after(0).events.is_empty());

    let applied = ui
        .handle_lsp_events(vec![
            LspEvent::Response(editor_core_lsp::LspResponse {
                id: 7,
                method: "textDocument/hover".to_string(),
                uri: None,
                result: Some(serde_json::json!({ "contents": "hello" })),
                error: None,
            }),
            LspEvent::Response(editor_core_lsp::LspResponse {
                id: 8,
                method: "textDocument/references".to_string(),
                uri: None,
                result: Some(serde_json::Value::Null),
                error: None,
            }),
            LspEvent::Response(editor_core_lsp::LspResponse {
                id: 9,
                method: "textDocument/codeAction".to_string(),
                uri: None,
                result: None,
                error: Some(LspResponseError {
                    code: -32603,
                    message: "actions failed".to_string(),
                    data: None,
                }),
            }),
        ])
        .unwrap();

    assert!(!applied);
    let snapshot = ui.lsp_result_events_after(0);
    assert_eq!(snapshot.latest_sequence, 3);
    assert_eq!(snapshot.events.len(), 3);

    let hover = &snapshot.events[0];
    assert_eq!(hover.sequence, 1);
    assert_eq!(hover.family, "hover");
    assert_eq!(hover.slot, "hover");
    assert_eq!(hover.method, "textDocument/hover");
    assert_eq!(hover.request_id, 7);
    assert_eq!(hover.status, "success");
    assert!(hover.has_result);
    assert!(hover.result_json_len > 0);
    assert_eq!(hover.error_code, None);

    let references = &snapshot.events[1];
    assert_eq!(references.sequence, 2);
    assert_eq!(references.family, "locations");
    assert_eq!(references.slot, "references");
    assert_eq!(references.status, "empty");
    assert!(!references.has_result);
    assert_eq!(references.result_json_len, 0);

    let code_action = &snapshot.events[2];
    assert_eq!(code_action.sequence, 3);
    assert_eq!(code_action.family, "actions");
    assert_eq!(code_action.slot, "code_action");
    assert_eq!(code_action.status, "error");
    assert!(!code_action.has_result);
    assert_eq!(code_action.error_code, Some(-32603));
    assert_eq!(code_action.error_message.as_deref(), Some("actions failed"));

    let after_first: serde_json::Value =
        serde_json::from_str(&ui.lsp_result_events_json(1).unwrap()).unwrap();
    assert_eq!(after_first["latest_sequence"], 3);
    assert_eq!(after_first["events"].as_array().unwrap().len(), 2);
    assert_eq!(after_first["events"][0]["sequence"], 2);
}

#[test]
fn lsp_request_events_record_start_completion_and_result_sequence() {
    let capture_path = unique_temp_path("request-events");
    let script = lsp_capture_server_script(&capture_path, serde_json::json!({}));
    let args = vec!["-c".to_string(), script];
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root_uri = format!("file:///tmp/editor-core-ui-request-events-{stamp}");
    let doc_uri = format!("{root_uri}/main.rs");

    let mut ui = EditorUi::new("abc", 80);
    ui.lsp_enable_stdio("/bin/sh", &args, &root_uri, &doc_uri, "rust")
        .unwrap();

    assert_eq!(ui.lsp_request_events_latest_sequence(), 0);
    assert!(ui.lsp_request_events_after(0).events.is_empty());

    let request_id = ui.lsp_request_hover(0, 1).unwrap();
    let started = ui.lsp_request_events_after(0);
    assert_eq!(started.latest_sequence, 1);
    assert_eq!(started.events.len(), 1);
    assert_eq!(started.events[0].sequence, 1);
    assert_eq!(started.events[0].family, "hover");
    assert_eq!(started.events[0].slot, "hover");
    assert_eq!(started.events[0].method, "textDocument/hover");
    assert_eq!(started.events[0].request_id, request_id);
    assert_eq!(started.events[0].phase, "started");
    assert_eq!(started.events[0].status, "pending");
    assert_eq!(started.events[0].result_sequence, None);

    let applied = ui
        .handle_lsp_events(vec![LspEvent::Response(editor_core_lsp::LspResponse {
            id: request_id,
            method: "textDocument/hover".to_string(),
            uri: None,
            result: Some(serde_json::json!({ "contents": "hello" })),
            error: None,
        })])
        .unwrap();
    assert!(!applied);

    let events = ui.lsp_request_events_after(0);
    assert_eq!(events.latest_sequence, 2);
    assert_eq!(events.events.len(), 2);
    let completed = &events.events[1];
    assert_eq!(completed.sequence, 2);
    assert_eq!(completed.request_id, request_id);
    assert_eq!(completed.phase, "completed");
    assert_eq!(completed.status, "success");
    assert_eq!(completed.result_sequence, Some(1));
    assert_eq!(completed.error_code, None);

    let result_events = ui.lsp_result_events_after(0);
    assert_eq!(result_events.latest_sequence, 1);
    assert_eq!(result_events.events[0].request_id, request_id);

    let after_started: serde_json::Value =
        serde_json::from_str(&ui.lsp_request_events_json(1).unwrap()).unwrap();
    assert_eq!(after_started["latest_sequence"], 2);
    assert_eq!(after_started["events"].as_array().unwrap().len(), 1);
    assert_eq!(after_started["events"][0]["status"], "success");

    ui.lsp_disable();
    let _ = std::fs::remove_file(capture_path);
}

#[test]
fn lsp_enable_stdio_projects_root_uri_to_workspace_folders() {
    let capture_path = unique_temp_path("workspace-folders");
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root_name = format!("editor-core-ui-workspace-folders-{stamp}");
    let root_uri = format!("file:///tmp/{root_name}");
    let doc_uri = format!("{root_uri}/main.rs");
    let script = lsp_capture_server_script_with_messages(
        &capture_path,
        &[
            lsp_initialize_response(serde_json::json!({})),
            serde_json::json!({
                "jsonrpc": "2.0",
                "id": 99,
                "method": "workspace/workspaceFolders",
                "params": null,
            }),
        ],
    );
    let args = vec!["-c".to_string(), script];

    let mut ui = EditorUi::new("fn main() {}\n", 80);
    ui.lsp_enable_stdio("/bin/sh", &args, &root_uri, &doc_uri, "rust")
        .unwrap();
    let _ = ui.poll_processing().unwrap();
    let _ = wait_for_captured_lsp_stdin(&capture_path, "\"id\":99");

    let messages = captured_lsp_json_messages(&capture_path);
    let initialize = messages
        .iter()
        .find(|message| message["method"] == "initialize")
        .expect("missing initialize request");
    assert_eq!(initialize["params"]["rootUri"], root_uri);
    assert_eq!(initialize["params"]["workspaceFolders"][0]["uri"], root_uri);
    assert_eq!(
        initialize["params"]["workspaceFolders"][0]["name"],
        root_name
    );

    let workspace_folders_response = messages
        .iter()
        .find(|message| message["id"] == 99)
        .expect("missing workspace/workspaceFolders response");
    assert_eq!(workspace_folders_response["result"][0]["uri"], root_uri);
    assert_eq!(workspace_folders_response["result"][0]["name"], root_name);

    ui.lsp_disable();
    let _ = std::fs::remove_file(capture_path);
}

#[test]
fn lsp_disable_gracefully_exits_last_shared_session() {
    let capture_path = unique_temp_path("shared-session-graceful-exit");
    let script = lsp_graceful_shutdown_capture_server_script(&capture_path);
    let args = vec!["-c".to_string(), script];
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root_uri = format!("file:///tmp/editor-core-ui-shared-exit-{stamp}");
    let doc_uri = format!("{root_uri}/main.rs");

    let mut ui = EditorUi::new("fn main() {}\n", 80);
    ui.lsp_enable_stdio("/bin/sh", &args, &root_uri, &doc_uri, "rust")
        .unwrap();
    ui.lsp_disable();

    let captured = wait_for_captured_lsp_stdin(&capture_path, "\"method\":\"exit\"");
    assert!(
        captured.contains("\"method\":\"shutdown\""),
        "missing shutdown request: {captured}"
    );
    assert!(
        captured.contains("\"method\":\"exit\""),
        "missing exit notification: {captured}"
    );
    let _ = std::fs::remove_file(capture_path);
}

#[test]
fn lsp_shutdown_gracefully_exits_active_session() {
    let capture_path = unique_temp_path("explicit-shared-session-shutdown");
    let script = lsp_graceful_shutdown_capture_server_script(&capture_path);
    let args = vec!["-c".to_string(), script];
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root_uri = format!("file:///tmp/editor-core-ui-explicit-shutdown-{stamp}");
    let doc_uri = format!("{root_uri}/main.rs");
    let shared_doc_uri = format!("{root_uri}/lib.rs");
    let restarted_doc_uri = format!("{root_uri}/again.rs");

    let mut ui = EditorUi::new("fn main() {}\n", 80);
    ui.lsp_enable_stdio("/bin/sh", &args, &root_uri, &doc_uri, "rust")
        .unwrap();
    let mut shared_holder = EditorUi::new("fn lib() {}\n", 80);
    shared_holder
        .lsp_enable_stdio("/bin/sh", &args, &root_uri, &shared_doc_uri, "rust")
        .unwrap();
    assert!(ui.lsp_shutdown().unwrap());
    assert!(!ui.lsp_is_enabled());
    assert!(!shared_holder.lsp_is_enabled());
    assert!(!ui.lsp_shutdown().unwrap());

    let mut restarted = EditorUi::new("fn again() {}\n", 80);
    restarted
        .lsp_enable_stdio("/bin/sh", &args, &root_uri, &restarted_doc_uri, "rust")
        .unwrap();
    assert!(restarted.lsp_shutdown().unwrap());

    let captured = wait_for_captured_lsp_stdin(&capture_path, "again.rs");
    assert!(
        captured.matches("\"method\":\"initialize\"").count() >= 2,
        "expected restart after explicit shutdown to create a new LSP process: {captured}"
    );
    assert!(
        captured.contains("\"method\":\"shutdown\""),
        "missing shutdown request: {captured}"
    );
    assert!(
        captured.contains("\"method\":\"exit\""),
        "missing exit notification: {captured}"
    );
    let _ = std::fs::remove_file(capture_path);
}

#[test]
fn lsp_did_change_workspace_folders_notifies_and_updates_workspace_response() {
    let capture_path = unique_temp_path("workspace-folders-change");
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let old_root_name = format!("editor-core-ui-old-workspace-{stamp}");
    let new_root_name = format!("editor-core-ui-new-workspace-{stamp}");
    let old_root_uri = format!("file:///tmp/{old_root_name}");
    let new_root_uri = format!("file:///tmp/{new_root_name}");
    let doc_uri = format!("{old_root_uri}/main.rs");
    let init_body = lsp_initialize_response(serde_json::json!({})).to_string();
    let workspace_folders_request = serde_json::json!({
        "jsonrpc": "2.0",
        "id": 100,
        "method": "workspace/workspaceFolders",
        "params": null,
    })
    .to_string();
    let script = format!(
        "body={}; printf 'Content-Length: %s\\r\\n\\r\\n%s' \"${{#body}}\" \"$body\"; \
         sleep 0.2; body={}; printf 'Content-Length: %s\\r\\n\\r\\n%s' \"${{#body}}\" \"$body\"; \
         cat > {}",
        shell_quote(&init_body),
        shell_quote(&workspace_folders_request),
        shell_quote(capture_path.to_string_lossy().as_ref())
    );
    let args = vec!["-c".to_string(), script];

    let mut ui = EditorUi::new("fn main() {}\n", 80);
    ui.lsp_enable_stdio("/bin/sh", &args, &old_root_uri, &doc_uri, "rust")
        .unwrap();
    ui.lsp_did_change_workspace_folders_json(
        &serde_json::json!([{ "uri": new_root_uri, "name": new_root_name }]).to_string(),
        &serde_json::json!([{ "uri": old_root_uri, "name": old_root_name }]).to_string(),
    )
    .unwrap();
    ui.lsp_did_change_workspace_folders_json(
        &serde_json::json!([{ "uri": new_root_uri, "name": new_root_name }]).to_string(),
        &serde_json::json!([{ "uri": old_root_uri, "name": old_root_name }]).to_string(),
    )
    .unwrap();
    'poll: loop {
        for _ in 0..100 {
            let _ = ui.poll_processing().unwrap();
            let captured = captured_lsp_stdin(&capture_path);
            if captured.contains("\"id\":100") {
                break 'poll;
            }
            std::thread::sleep(std::time::Duration::from_millis(10));
        }
        panic!(
            "timed out waiting for workspace/workspaceFolders response; captured: {}",
            captured_lsp_stdin(&capture_path)
        );
    }

    let messages = captured_lsp_json_messages(&capture_path);
    let did_change = messages
        .iter()
        .find(|message| message["method"] == "workspace/didChangeWorkspaceFolders")
        .expect("missing workspace/didChangeWorkspaceFolders notification");
    assert_eq!(
        did_change["params"]["event"]["added"][0]["uri"],
        new_root_uri
    );
    assert_eq!(
        did_change["params"]["event"]["removed"][0]["uri"],
        old_root_uri
    );
    assert_eq!(
        messages
            .iter()
            .filter(|message| message["method"] == "workspace/didChangeWorkspaceFolders")
            .count(),
        1
    );

    let workspace_folders_response = messages
        .iter()
        .find(|message| message["id"] == 100)
        .expect("missing workspace/workspaceFolders response");
    assert_eq!(
        workspace_folders_response["result"]
            .as_array()
            .unwrap()
            .len(),
        1
    );
    assert_eq!(workspace_folders_response["result"][0]["uri"], new_root_uri);
    assert_eq!(
        workspace_folders_response["result"][0]["name"],
        new_root_name
    );

    ui.lsp_disable();
    let _ = std::fs::remove_file(capture_path);
}

#[test]
fn lsp_workspace_folder_change_updates_shared_session_root_alias() {
    let capture_path = unique_temp_path("workspace-folder-shared-root-alias");
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let old_root_uri = format!("file:///tmp/editor-core-ui-root-alias-old-{stamp}");
    let new_root_name = format!("editor-core-ui-root-alias-new-{stamp}");
    let new_root_uri = format!("file:///tmp/{new_root_name}");
    let old_doc_uri = format!("{old_root_uri}/main.rs");
    let new_doc_uri = format!("{new_root_uri}/other.rs");
    let script = lsp_append_capture_server_script(&capture_path);
    let args = vec!["-c".to_string(), script];

    let mut first = EditorUi::new("fn main() {}\n", 80);
    first
        .lsp_enable_stdio("/bin/sh", &args, &old_root_uri, &old_doc_uri, "rust")
        .unwrap();
    first
        .lsp_did_change_workspace_folders_json(
            &serde_json::json!([{ "uri": new_root_uri, "name": new_root_name }]).to_string(),
            &serde_json::json!([{ "uri": old_root_uri, "name": "old" }]).to_string(),
        )
        .unwrap();

    let mut second = EditorUi::new("fn other() {}\n", 80);
    second
        .lsp_enable_stdio("/bin/sh", &args, &new_root_uri, &new_doc_uri, "rust")
        .unwrap();

    let captured = wait_for_captured_lsp_stdin(&capture_path, "other.rs");
    let messages = captured_lsp_json_messages(&capture_path);
    assert_eq!(
        messages
            .iter()
            .filter(|message| message["method"] == "initialize")
            .count(),
        1,
        "new root should reuse the existing shared LSP session after didChange: {captured}"
    );
    assert!(
        messages.iter().any(|message| {
            message["method"] == "workspace/didChangeWorkspaceFolders"
                && message["params"]["event"]["added"][0]["uri"] == new_root_uri
        }),
        "missing workspace folder didChange for new root: {captured}"
    );
    assert!(
        messages.iter().any(|message| {
            message["method"] == "textDocument/didOpen"
                && message["params"]["textDocument"]["uri"] == new_doc_uri
        }),
        "missing didOpen for document under new root on reused session: {captured}"
    );

    first.lsp_disable();
    second.lsp_disable();
    let _ = std::fs::remove_file(capture_path);
}

#[test]
fn lsp_status_reports_current_workspace_folders() {
    let capture_path = unique_temp_path("workspace-folders-status");
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let old_root_name = format!("editor-core-ui-old-status-workspace-{stamp}");
    let new_root_name = format!("editor-core-ui-new-status-workspace-{stamp}");
    let old_root_uri = format!("file:///tmp/{old_root_name}");
    let new_root_uri = format!("file:///tmp/{new_root_name}");
    let doc_uri = format!("{old_root_uri}/main.rs");
    let script = lsp_capture_server_script(&capture_path, serde_json::json!({}));
    let args = vec!["-c".to_string(), script];

    let mut ui = EditorUi::new("fn main() {}\n", 80);
    ui.lsp_enable_stdio("/bin/sh", &args, &old_root_uri, &doc_uri, "rust")
        .unwrap();

    let status: serde_json::Value = serde_json::from_str(ui.lsp_status_json().as_str()).unwrap();
    assert_eq!(status["availability"], "enabled");
    assert_eq!(status["workspace_folders"].as_array().unwrap().len(), 1);
    assert_eq!(status["workspace_folders"][0]["uri"], old_root_uri);
    assert_eq!(status["workspace_folders"][0]["name"], old_root_name);

    let enabled_events = ui.state_events_after(0);
    assert_eq!(enabled_events.events.len(), 1);
    assert_eq!(enabled_events.events[0].kind, "lsp_status_changed");
    assert_eq!(enabled_events.events[0].family, "lsp");
    assert_eq!(
        enabled_events.events[0].lsp_status.as_ref().unwrap()["workspace_folders"][0]["uri"],
        old_root_uri
    );

    ui.lsp_did_change_workspace_folders_json(
        &serde_json::json!([{ "uri": new_root_uri, "name": new_root_name }]).to_string(),
        &serde_json::json!([{ "uri": old_root_uri, "name": old_root_name }]).to_string(),
    )
    .unwrap();

    let status: serde_json::Value = serde_json::from_str(ui.lsp_status_json().as_str()).unwrap();
    assert_eq!(status["workspace_folders"].as_array().unwrap().len(), 1);
    assert_eq!(status["workspace_folders"][0]["uri"], new_root_uri);
    assert_eq!(status["workspace_folders"][0]["name"], new_root_name);

    let changed_events = ui.state_events_after(enabled_events.latest_sequence);
    assert_eq!(changed_events.events.len(), 1);
    assert_eq!(changed_events.events[0].kind, "lsp_status_changed");
    assert_eq!(
        changed_events.events[0].lsp_status.as_ref().unwrap()["workspace_folders"][0]["uri"],
        new_root_uri
    );

    ui.lsp_disable();
    let disabled_events = ui.state_events_after(changed_events.latest_sequence);
    assert_eq!(disabled_events.events.len(), 1);
    assert_eq!(disabled_events.events[0].kind, "lsp_status_changed");
    assert_eq!(
        disabled_events.events[0].lsp_status.as_ref().unwrap()["availability"],
        "disabled"
    );
    let _ = std::fs::remove_file(capture_path);
}

#[test]
fn lsp_progress_activity_emits_deduped_status_events() {
    let capture_path = unique_temp_path("progress-status-events");
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root_uri = format!("file:///tmp/editor-core-ui-progress-status-{stamp}");
    let doc_uri = format!("{root_uri}/main.rs");
    let script = lsp_capture_server_script_with_messages(
        &capture_path,
        &[
            lsp_initialize_response(serde_json::json!({})),
            serde_json::json!({
                "jsonrpc": "2.0",
                "method": "$/progress",
                "params": {
                    "token": "index",
                    "value": {
                        "kind": "begin",
                        "title": "Indexing",
                        "message": "crate graph",
                        "percentage": 42
                    }
                }
            }),
        ],
    );
    let args = vec!["-c".to_string(), script];

    let mut ui = EditorUi::new("fn main() {}\n", 80);
    ui.lsp_enable_stdio("/bin/sh", &args, &root_uri, &doc_uri, "rust")
        .unwrap();

    let enabled_events = ui.state_events_after(0);
    assert_eq!(enabled_events.events.len(), 1);
    assert_eq!(
        enabled_events.events[0].lsp_status.as_ref().unwrap()["state"],
        "ready"
    );

    let _ = ui.poll_processing().unwrap();
    let activity_events = ui.state_events_after(enabled_events.latest_sequence);
    let activity_status_events = activity_events
        .events
        .iter()
        .filter(|event| event.kind == "lsp_status_changed")
        .collect::<Vec<_>>();
    assert_eq!(activity_status_events.len(), 1);
    let status = activity_status_events[0].lsp_status.as_ref().unwrap();
    assert_eq!(status["state"], "indexing");
    assert_eq!(status["activity"]["title"], "Indexing");
    assert_eq!(status["activity"]["message"], "crate graph");
    assert_eq!(status["activity"]["percentage"], 42);

    let _ = ui.poll_processing().unwrap();
    let repeated = ui.state_events_after(activity_events.latest_sequence);
    assert!(
        repeated.events.is_empty(),
        "unchanged LSP activity should not emit duplicate status events: {:?}",
        repeated.events
    );

    ui.lsp_disable();
    let _ = std::fs::remove_file(capture_path);
}

#[test]
fn lsp_process_exit_emits_failed_status_event() {
    let capture_path = unique_temp_path("process-exit-status-events");
    let init = serde_json::json!({
        "jsonrpc": "2.0",
        "id": 1,
        "result": { "capabilities": {} },
    });
    let body = init.to_string();
    let script = format!(
        "body={}; printf 'Content-Length: %s\\r\\n\\r\\n%s' \"${{#body}}\" \"$body\"; sleep 0.05; exit 7",
        shell_quote(&body),
    );
    let args = vec!["-c".to_string(), script];
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root_uri = format!("file:///tmp/editor-core-ui-process-exit-{stamp}");
    let doc_uri = format!("{root_uri}/main.rs");

    let mut ui = EditorUi::new("fn main() {}\n", 80);
    ui.lsp_enable_stdio("/bin/sh", &args, &root_uri, &doc_uri, "rust")
        .unwrap();

    let enabled_events = ui.state_events_after(0);
    assert_eq!(enabled_events.events.len(), 1);
    assert_eq!(
        enabled_events.events[0].lsp_status.as_ref().unwrap()["process"]["state"],
        "running"
    );

    let mut failed_status = None;
    let mut latest_sequence = enabled_events.latest_sequence;
    for _ in 0..50 {
        let _ = ui.poll_processing().unwrap();
        let events = ui.state_events_after(latest_sequence);
        latest_sequence = events.latest_sequence;
        if let Some(event) = events
            .events
            .iter()
            .find(|event| event.kind == "lsp_status_changed")
        {
            let status = event.lsp_status.as_ref().unwrap();
            if status["process"]["state"] == "exited" {
                failed_status = Some(status.clone());
                break;
            }
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    }

    let status = failed_status.expect("expected process exit status event");
    assert_eq!(status["availability"], "failed");
    assert_eq!(status["state"], "failed");
    assert_eq!(status["process"]["state"], "exited");
    assert_eq!(status["process"]["exit_code"], 7);
    assert!(
        status["detail"]
            .as_str()
            .is_some_and(|detail| detail.contains("exited with code 7")),
        "unexpected status detail: {status:?}"
    );

    let _ = ui.poll_processing().unwrap();
    let repeated = ui.state_events_after(latest_sequence);
    assert!(
        repeated.events.is_empty(),
        "unchanged process health should not emit duplicate status events: {:?}",
        repeated.events
    );

    ui.lsp_disable();
    let _ = std::fs::remove_file(capture_path);
}

#[test]
fn lsp_status_reports_stderr_tail() {
    let init = lsp_initialize_response(serde_json::json!({}));
    let body = init.to_string();
    let script = format!(
        "printf 'stderr one\\nstderr two\\n' >&2; body={}; printf 'Content-Length: %s\\r\\n\\r\\n%s' \"${{#body}}\" \"$body\"; sleep 30",
        shell_quote(&body),
    );
    let args = vec!["-c".to_string(), script];
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root_uri = format!("file:///tmp/editor-core-ui-stderr-status-{stamp}");
    let doc_uri = format!("{root_uri}/main.rs");

    let mut ui = EditorUi::new("fn main() {}\n", 80);
    ui.lsp_enable_stdio("/bin/sh", &args, &root_uri, &doc_uri, "rust")
        .unwrap();

    let mut status = serde_json::Value::Null;
    for _ in 0..50 {
        status = serde_json::from_str(ui.lsp_status_json().as_str()).unwrap();
        if status["process"]["stderr_tail"]
            .as_str()
            .is_some_and(|tail| tail.contains("stderr two"))
        {
            break;
        }
        std::thread::sleep(std::time::Duration::from_millis(20));
    }

    let stderr_tail = status["process"]["stderr_tail"]
        .as_str()
        .expect("expected stderr_tail in lsp status json");
    assert!(stderr_tail.contains("stderr one"), "{stderr_tail}");
    assert!(stderr_tail.contains("stderr two"), "{stderr_tail}");

    let events = ui.state_events_after(0);
    let enabled_status = events.events[0].lsp_status.as_ref().unwrap();
    assert_eq!(enabled_status["process"]["state"], "running");

    ui.lsp_disable();
}

#[test]
fn lsp_document_lifecycle_notifications_are_exposed() {
    let capture_path = unique_temp_path("document-save-close");
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root_uri = format!("file:///tmp/editor-core-ui-doc-lifecycle-{stamp}");
    let doc_uri = format!("{root_uri}/main.rs");
    let other_uri = format!("{root_uri}/other.rs");
    let script = lsp_capture_server_script(&capture_path, serde_json::json!({}));
    let args = vec!["-c".to_string(), script];

    let mut ui = EditorUi::new("fn main() {}\n", 80);
    ui.lsp_enable_stdio("/bin/sh", &args, &root_uri, &doc_uri, "rust")
        .unwrap();
    ui.lsp_did_open_document(&other_uri, "rust", 1, "pub fn other() {}\n".to_string())
        .unwrap();
    ui.lsp_did_change_document(&other_uri, "pub fn other_changed() {}\n".to_string())
        .unwrap();
    ui.lsp_did_save_document(&doc_uri, Some("fn main() { saved(); }\n".to_string()))
        .unwrap();
    ui.lsp_did_close_document(&doc_uri).unwrap();

    wait_for_captured_lsp_stdin(&capture_path, "textDocument/didClose");
    let messages = captured_lsp_json_messages(&capture_path);
    let did_open = messages
        .iter()
        .find(|message| {
            message["method"] == "textDocument/didOpen"
                && message["params"]["textDocument"]["uri"] == other_uri
        })
        .expect("missing explicit textDocument/didOpen notification");
    assert_eq!(did_open["params"]["textDocument"]["languageId"], "rust");
    assert_eq!(did_open["params"]["textDocument"]["version"], 1);
    assert_eq!(
        did_open["params"]["textDocument"]["text"],
        "pub fn other() {}\n"
    );

    let did_change = messages
        .iter()
        .find(|message| {
            message["method"] == "textDocument/didChange"
                && message["params"]["textDocument"]["uri"] == other_uri
        })
        .expect("missing textDocument/didChange notification");
    assert_eq!(did_change["params"]["textDocument"]["version"], 2);
    assert_eq!(
        did_change["params"]["contentChanges"][0]["text"],
        "pub fn other_changed() {}\n"
    );

    let did_save = messages
        .iter()
        .find(|message| message["method"] == "textDocument/didSave")
        .expect("missing textDocument/didSave notification");
    assert_eq!(did_save["params"]["textDocument"]["uri"], doc_uri);
    assert_eq!(did_save["params"]["text"], "fn main() { saved(); }\n");

    let did_close = messages
        .iter()
        .find(|message| message["method"] == "textDocument/didClose")
        .expect("missing textDocument/didClose notification");
    assert_eq!(did_close["params"]["textDocument"]["uri"], doc_uri);

    ui.lsp_disable();
    let _ = std::fs::remove_file(capture_path);
}

#[test]
fn editor_ui_state_events_project_lsp_request_and_result_events() {
    let capture_path = unique_temp_path("state-events");
    let script = lsp_capture_server_script(&capture_path, serde_json::json!({}));
    let args = vec!["-c".to_string(), script];
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root_uri = format!("file:///tmp/editor-core-ui-state-events-{stamp}");
    let doc_uri = format!("{root_uri}/main.rs");

    let mut ui = EditorUi::new("abc", 80);
    ui.lsp_enable_stdio("/bin/sh", &args, &root_uri, &doc_uri, "rust")
        .unwrap();

    let enabled = ui.state_events_after(0);
    assert_eq!(enabled.latest_sequence, 1);
    assert_eq!(enabled.events.len(), 1);
    assert_eq!(enabled.events[0].kind, "lsp_status_changed");
    assert_eq!(enabled.events[0].family, "lsp");
    assert_eq!(
        enabled.events[0].lsp_status.as_ref().unwrap()["availability"],
        "enabled"
    );
    let baseline = enabled.latest_sequence;

    let request_id = ui.lsp_request_hover(0, 1).unwrap();
    let started = ui.state_events_after(baseline);
    assert_eq!(started.latest_sequence, baseline + 1);
    assert_eq!(started.events.len(), 1);
    assert_eq!(started.events[0].sequence, baseline + 1);
    assert_eq!(started.events[0].kind, "lsp_request");
    assert_eq!(started.events[0].family, "hover");
    assert_eq!(started.events[0].source_sequence, 1);
    assert_eq!(
        started.events[0].lsp_request.as_ref().unwrap().request_id,
        request_id
    );
    assert!(started.events[0].lsp_result.is_none());

    ui.handle_lsp_events(vec![LspEvent::Response(editor_core_lsp::LspResponse {
        id: request_id,
        method: "textDocument/hover".to_string(),
        uri: None,
        result: Some(serde_json::json!({ "contents": "hello" })),
        error: None,
    })])
    .unwrap();

    let events = ui.state_events_after(baseline);
    assert_eq!(events.latest_sequence, baseline + 3);
    assert_eq!(
        events
            .events
            .iter()
            .map(|event| event.kind.as_str())
            .collect::<Vec<_>>(),
        vec!["lsp_request", "lsp_result", "lsp_request"]
    );
    assert_eq!(events.events[1].source_sequence, 1);
    assert_eq!(
        events.events[1].lsp_result.as_ref().unwrap().status,
        "success"
    );
    assert_eq!(
        events.events[2]
            .lsp_request
            .as_ref()
            .unwrap()
            .result_sequence,
        Some(1)
    );

    let after_started: serde_json::Value =
        serde_json::from_str(&ui.state_events_json(started.latest_sequence).unwrap()).unwrap();
    assert_eq!(after_started["latest_sequence"], baseline + 3);
    assert_eq!(after_started["events"].as_array().unwrap().len(), 2);
    assert_eq!(after_started["events"][0]["kind"], "lsp_result");
    assert_eq!(
        after_started["events"][1]["lsp_request"]["phase"],
        "completed"
    );

    ui.lsp_disable();
    let _ = std::fs::remove_file(capture_path);
}

#[test]
fn editor_ui_state_events_record_text_and_dirty_changes() {
    let mut ui = EditorUi::new("", 80);

    ui.insert_text("x").unwrap();
    let snapshot = ui.state_events_after(0);
    assert_eq!(snapshot.latest_sequence, 3);
    assert_eq!(snapshot.events.len(), 3);

    assert_eq!(snapshot.events[0].kind, "dirty_changed");
    assert_eq!(snapshot.events[0].family, "document");
    assert_eq!(snapshot.events[0].source_sequence, 1);
    assert_eq!(snapshot.events[0].dirty.as_ref().unwrap().is_modified, true);
    assert!(snapshot.events[0].text.is_none());
    assert!(snapshot.events[0].lsp_request.is_none());
    assert!(snapshot.events[0].lsp_result.is_none());

    assert_eq!(snapshot.events[1].kind, "selection_changed");
    assert_eq!(snapshot.events[1].family, "document");
    assert_eq!(snapshot.events[1].source_sequence, 1);
    let selection = snapshot.events[1].selection.as_ref().unwrap();
    assert_eq!(selection.primary.offset, 1);
    assert_eq!(selection.primary_selection_index, 0);
    assert_eq!(selection.selection_count, 1);
    assert!(!selection.has_selection);
    assert_eq!(selection.selections[0].start, 1);
    assert_eq!(selection.selections[0].end, 1);
    assert!(snapshot.events[1].dirty.is_none());
    assert!(snapshot.events[1].text.is_none());

    assert_eq!(snapshot.events[2].kind, "text_changed");
    assert_eq!(snapshot.events[2].family, "document");
    assert_eq!(snapshot.events[2].source_sequence, 1);
    let text = snapshot.events[2].text.as_ref().unwrap();
    assert_eq!(text.text_version, 1);
    assert_eq!(text.char_len, 1);
    assert!(text.is_modified);
    assert!(snapshot.events[2].dirty.is_none());

    ui.mark_saved();
    let saved = ui.state_events_after(snapshot.latest_sequence);
    assert_eq!(saved.latest_sequence, 4);
    assert_eq!(saved.events.len(), 1);
    assert_eq!(saved.events[0].kind, "dirty_changed");
    assert_eq!(saved.events[0].dirty.as_ref().unwrap().is_modified, false);

    let json: serde_json::Value = serde_json::from_str(&ui.state_events_json(1).unwrap()).unwrap();
    assert_eq!(json["latest_sequence"], 4);
    assert_eq!(json["events"][0]["kind"], "selection_changed");
    assert_eq!(json["events"][0]["selection"]["primary"]["offset"], 1);
    assert_eq!(json["events"][1]["kind"], "text_changed");
    assert_eq!(json["events"][1]["text"]["text_version"], 1);
    assert_eq!(json["events"][2]["dirty"]["is_modified"], false);
}

#[test]
fn editor_ui_state_events_record_selection_changes() {
    let mut ui = EditorUi::new("abcd", 80);

    ui.set_selections_offsets(&[(1, 3), (4, 4)], 0).unwrap();

    let snapshot = ui.state_events_after(0);
    assert_eq!(snapshot.latest_sequence, 1);
    assert_eq!(snapshot.events.len(), 1);
    assert_eq!(snapshot.events[0].kind, "selection_changed");
    assert_eq!(snapshot.events[0].family, "document");
    assert!(snapshot.events[0].lsp_request.is_none());
    assert!(snapshot.events[0].lsp_result.is_none());
    assert!(snapshot.events[0].text.is_none());
    assert!(snapshot.events[0].dirty.is_none());

    let selection = snapshot.events[0].selection.as_ref().unwrap();
    assert_eq!(selection.primary.line, 0);
    assert_eq!(selection.primary.column, 3);
    assert_eq!(selection.primary.offset, 3);
    assert_eq!(selection.primary_selection_index, 0);
    assert_eq!(selection.selection_count, 2);
    assert!(selection.has_selection);
    assert_eq!(selection.selections[0].start, 1);
    assert_eq!(selection.selections[0].end, 3);
    assert_eq!(selection.selections[0].anchor, 1);
    assert_eq!(selection.selections[0].active, 3);
    assert_eq!(selection.selections[1].start, 4);
    assert_eq!(selection.selections[1].end, 4);

    ui.set_selections_offsets(&[(1, 3), (4, 4)], 0).unwrap();
    assert_eq!(
        ui.state_events_after(snapshot.latest_sequence).events.len(),
        0
    );

    ui.execute(Command::Cursor(CursorCommand::SetSelection {
        start: Position::new(0, 3),
        end: Position::new(0, 1),
    }))
    .unwrap();
    let backward = ui.state_events_after(snapshot.latest_sequence);
    assert_eq!(backward.events.len(), 1);
    let selection = backward.events[0].selection.as_ref().unwrap();
    assert_eq!(selection.primary.offset, 1);
    assert_eq!(selection.selections[0].start, 1);
    assert_eq!(selection.selections[0].end, 3);
    assert_eq!(selection.selections[0].anchor, 3);
    assert_eq!(selection.selections[0].active, 1);
}

#[test]
fn editor_ui_state_events_record_layout_changes() {
    let mut ui = EditorUi::new("abc", 80);

    ui.set_render_metrics(14.0, 20.0, 9.0, 3.0, 4.0);
    let metrics = ui.state_events_after(0);
    assert_eq!(metrics.latest_sequence, 1);
    assert_eq!(metrics.events.len(), 1);
    assert_eq!(metrics.events[0].kind, "layout_changed");
    assert_eq!(metrics.events[0].family, "document");
    assert!(metrics.events[0].viewport.is_none());
    assert!(metrics.events[0].selection.is_none());
    let layout = metrics.events[0].layout.as_ref().unwrap();
    assert_eq!(layout.width_px, 800);
    assert_eq!(layout.height_px, 600);
    assert_eq!(layout.font_size, 14.0);
    assert_eq!(layout.line_height_px, 20.0);
    assert_eq!(layout.cell_width_px, 9.0);
    assert_eq!(layout.padding_x_px, 3.0);
    assert_eq!(layout.padding_y_px, 4.0);
    assert_eq!(layout.gutter_width_cells, 0);
    assert_eq!(layout.tab_width_cells, 4);
    assert_eq!(layout.text_vertical_align, "center");

    ui.set_render_metrics(14.0, 20.0, 9.0, 3.0, 4.0);
    assert!(
        ui.state_events_after(metrics.latest_sequence)
            .events
            .is_empty()
    );

    ui.set_text_vertical_align(TextVerticalAlign::Bottom);
    let align = ui.state_events_after(metrics.latest_sequence);
    assert_eq!(align.latest_sequence, 2);
    assert_eq!(align.events.len(), 1);
    let layout = align.events[0].layout.as_ref().unwrap();
    assert_eq!(layout.text_vertical_align, "bottom");

    ui.set_tab_width(2).unwrap();
    let tab_width = ui.state_events_after(align.latest_sequence);
    assert_eq!(tab_width.latest_sequence, 3);
    assert_eq!(tab_width.events.len(), 1);
    let layout = tab_width.events[0].layout.as_ref().unwrap();
    assert_eq!(layout.tab_width_cells, 2);

    let json: serde_json::Value =
        serde_json::from_str(&ui.state_events_json(align.latest_sequence).unwrap()).unwrap();
    assert_eq!(json["latest_sequence"], 3);
    assert_eq!(json["events"][0]["kind"], "layout_changed");
    assert_eq!(json["events"][0]["layout"]["tab_width_cells"], 2);
}

#[test]
fn editor_ui_state_events_record_viewport_changes() {
    let mut ui = EditorUi::new("abcdefghij\nsecond line\nthird line\nfourth line", 80);
    ui.set_render_metrics(10.0, 10.0, 10.0, 0.0, 0.0);
    let baseline = ui.state_events_latest_sequence();

    ui.set_viewport_px(80, 20, 1.0).unwrap();
    let resize = ui.state_events_after(baseline);
    assert_eq!(
        resize
            .events
            .iter()
            .map(|event| event.kind.as_str())
            .collect::<Vec<_>>(),
        vec!["viewport_changed", "layout_changed"]
    );
    let resize_event = resize
        .events
        .iter()
        .find(|event| event.kind == "viewport_changed")
        .unwrap();
    assert_eq!(resize_event.family, "document");
    assert!(resize_event.lsp_request.is_none());
    assert!(resize_event.lsp_result.is_none());
    assert!(resize_event.text.is_none());
    assert!(resize_event.dirty.is_none());
    assert!(resize_event.selection.is_none());

    let viewport = resize_event.viewport.as_ref().unwrap();
    assert_eq!(viewport.width, 8);
    assert_eq!(viewport.height, Some(2));
    assert_eq!(viewport.scroll_top, 0);
    assert_eq!(viewport.sub_row_offset, 0);
    assert_eq!(viewport.visible_lines.start, 0);
    assert_eq!(viewport.visible_lines.end, 2);
    assert!(viewport.total_visual_lines >= 5);

    ui.set_smooth_scroll_state(1, 32768);
    let scrolled = ui.state_events_after(resize.latest_sequence);
    assert_eq!(scrolled.events.len(), 1);
    assert_eq!(scrolled.events[0].kind, "viewport_changed");
    let viewport = scrolled.events[0].viewport.as_ref().unwrap();
    assert_eq!(viewport.scroll_top, 1);
    assert_eq!(viewport.sub_row_offset, 32768);
    assert_eq!(viewport.visible_lines.start, 1);

    ui.execute(Command::View(ViewCommand::SetViewportWidth { width: 4 }))
        .unwrap();
    let width_changed = ui.state_events_after(scrolled.latest_sequence);
    assert_eq!(width_changed.events.len(), 1);
    let viewport = width_changed.events[0].viewport.as_ref().unwrap();
    assert_eq!(viewport.width, 4);
    assert!(
        viewport.total_visual_lines
            >= scrolled.events[0]
                .viewport
                .as_ref()
                .unwrap()
                .total_visual_lines
    );

    let json: serde_json::Value =
        serde_json::from_str(&ui.state_events_json(scrolled.latest_sequence).unwrap()).unwrap();
    assert_eq!(json["latest_sequence"], width_changed.latest_sequence);
    assert_eq!(json["events"][0]["kind"], "viewport_changed");
    assert_eq!(json["events"][0]["viewport"]["width"], 4);
    assert_eq!(json["events"][0]["viewport"]["visible_lines"]["start"], 1);
}

#[test]
fn editor_ui_state_events_record_derived_state_changes_and_stale() {
    let mut ui = EditorUi::new("abc\n", 80);

    ui.lsp_apply_publish_diagnostics_json(
        r#"{
          "uri": "file:///tmp/main.rs",
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

    let changed = ui.state_events_after(0);
    assert_eq!(changed.latest_sequence, 1);
    assert_eq!(changed.events.len(), 1);
    let changed_event = &changed.events[0];
    assert_eq!(changed_event.kind, "derived_state_changed");
    assert_eq!(changed_event.family, "derived_state");
    assert!(changed_event.text.is_none());
    assert!(changed_event.dirty.is_none());
    assert!(changed_event.selection.is_none());
    assert!(changed_event.viewport.is_none());
    assert!(changed_event.layout.is_none());

    let derived = changed_event.derived_state.as_ref().unwrap();
    assert_eq!(derived.status, "changed");
    assert_eq!(derived.reason, "processing_edits");
    assert_eq!(derived.text_version, 0);
    assert_eq!(derived.edit_count, 2);
    assert_eq!(derived.families, vec!["style_intervals", "diagnostics"]);

    ui.insert_text("z").unwrap();
    let stale = ui.state_events_after(changed.latest_sequence);
    assert_eq!(
        stale
            .events
            .iter()
            .map(|event| event.kind.as_str())
            .collect::<Vec<_>>(),
        vec![
            "dirty_changed",
            "selection_changed",
            "text_changed",
            "derived_state_stale"
        ]
    );
    let stale_event = stale.events.last().unwrap();
    assert_eq!(stale_event.family, "derived_state");
    let derived = stale_event.derived_state.as_ref().unwrap();
    assert_eq!(derived.status, "stale");
    assert_eq!(derived.reason, "text_changed");
    assert_eq!(derived.text_version, 1);
    assert_eq!(derived.edit_count, 0);
    assert_eq!(
        derived.families,
        vec![
            "style_intervals",
            "folding_regions",
            "diagnostics",
            "decorations",
            "document_symbols"
        ]
    );

    let json: serde_json::Value =
        serde_json::from_str(&ui.state_events_json(changed.latest_sequence).unwrap()).unwrap();
    assert_eq!(json["latest_sequence"], stale.latest_sequence);
    assert_eq!(json["events"][3]["kind"], "derived_state_stale");
    assert_eq!(json["events"][3]["derived_state"]["status"], "stale");
    assert_eq!(
        json["events"][3]["derived_state"]["families"][2],
        "diagnostics"
    );
}

#[test]
fn lsp_derived_request_events_record_semantic_and_folding_lifecycle() {
    let mut ui = EditorUi::new("abc", 80);

    let applied = ui
        .handle_lsp_events(vec![
            LspEvent::DerivedRequest(editor_core_lsp::LspDerivedRequestEvent {
                id: 71,
                method: "textDocument/semanticTokens/full".to_string(),
                uri: "file:///tmp/main.rs".to_string(),
                phase: editor_core_lsp::LspDerivedRequestPhase::Started,
                status: editor_core_lsp::LspDerivedRequestStatus::Pending,
                error: None,
            }),
            LspEvent::DerivedRequest(editor_core_lsp::LspDerivedRequestEvent {
                id: 71,
                method: "textDocument/semanticTokens/full".to_string(),
                uri: "file:///tmp/main.rs".to_string(),
                phase: editor_core_lsp::LspDerivedRequestPhase::Completed,
                status: editor_core_lsp::LspDerivedRequestStatus::Success,
                error: None,
            }),
            LspEvent::DerivedRequest(editor_core_lsp::LspDerivedRequestEvent {
                id: 72,
                method: "textDocument/foldingRange".to_string(),
                uri: "file:///tmp/main.rs".to_string(),
                phase: editor_core_lsp::LspDerivedRequestPhase::Started,
                status: editor_core_lsp::LspDerivedRequestStatus::Pending,
                error: None,
            }),
            LspEvent::DerivedRequest(editor_core_lsp::LspDerivedRequestEvent {
                id: 72,
                method: "textDocument/foldingRange".to_string(),
                uri: "file:///tmp/main.rs".to_string(),
                phase: editor_core_lsp::LspDerivedRequestPhase::Completed,
                status: editor_core_lsp::LspDerivedRequestStatus::Error,
                error: Some(LspResponseError {
                    code: -32603,
                    message: "folding failed".to_string(),
                    data: None,
                }),
            }),
        ])
        .unwrap();

    assert!(!applied);
    let events = ui.lsp_request_events_after(0);
    assert_eq!(events.latest_sequence, 4);
    assert_eq!(events.events.len(), 4);

    assert_eq!(events.events[0].family, "semantic_tokens");
    assert_eq!(events.events[0].slot, "semantic_tokens_full");
    assert_eq!(events.events[0].method, "textDocument/semanticTokens/full");
    assert_eq!(events.events[0].phase, "started");
    assert_eq!(events.events[0].status, "pending");
    assert_eq!(events.events[1].request_id, 71);
    assert_eq!(events.events[1].phase, "completed");
    assert_eq!(events.events[1].status, "success");

    assert_eq!(events.events[2].family, "ranges");
    assert_eq!(events.events[2].slot, "folding_ranges");
    assert_eq!(events.events[2].phase, "started");
    assert_eq!(events.events[2].status, "pending");
    assert_eq!(events.events[3].request_id, 72);
    assert_eq!(events.events[3].phase, "completed");
    assert_eq!(events.events[3].status, "error");
    assert_eq!(events.events[3].error_code, Some(-32603));
    assert_eq!(
        events.events[3].error_message.as_deref(),
        Some("folding failed")
    );
}

#[test]
fn lsp_publish_diagnostics_notification_records_completed_lifecycle() {
    let mut ui = EditorUi::new("abc", 80);
    let doc_uri = "file:///tmp/main.rs";
    {
        let mut doc = ui.lock_doc();
        doc.lsp_document_uri = Some(doc_uri.to_string());
    }

    let applied = ui
        .handle_lsp_events(vec![
            LspEvent::DerivedRequest(editor_core_lsp::LspDerivedRequestEvent {
                id: 0,
                method: "textDocument/publishDiagnostics".to_string(),
                uri: "file:///tmp/other.rs".to_string(),
                phase: editor_core_lsp::LspDerivedRequestPhase::Completed,
                status: editor_core_lsp::LspDerivedRequestStatus::Success,
                error: None,
            }),
            LspEvent::DerivedRequest(editor_core_lsp::LspDerivedRequestEvent {
                id: 0,
                method: "textDocument/publishDiagnostics".to_string(),
                uri: doc_uri.to_string(),
                phase: editor_core_lsp::LspDerivedRequestPhase::Completed,
                status: editor_core_lsp::LspDerivedRequestStatus::Empty,
                error: None,
            }),
        ])
        .unwrap();

    assert!(!applied);
    let events = ui.lsp_request_events_after(0);
    assert_eq!(events.latest_sequence, 1);
    assert_eq!(events.events.len(), 1);
    assert_eq!(events.events[0].family, "diagnostics");
    assert_eq!(events.events[0].slot, "publish_diagnostics");
    assert_eq!(events.events[0].method, "textDocument/publishDiagnostics");
    assert_eq!(events.events[0].request_id, 0);
    assert_eq!(events.events[0].phase, "completed");
    assert_eq!(events.events[0].status, "empty");
    assert_eq!(events.events[0].result_sequence, None);
}

#[test]
fn lsp_request_events_record_stale_completion() {
    let mut ui = EditorUi::new("abc", 80);
    let view_id = ui.view_id;
    {
        let mut doc = ui.lock_doc();
        doc.lsp_client_requests.insert(
            21,
            LspClientRequest::Result {
                view: view_id,
                slot: LspResultSlot::Hover,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((view_id, LspResultSlot::Hover), 22);
        doc.record_lsp_request_started(view_id, LspResultSlot::Hover, 21);
    }

    let applied = ui
        .handle_lsp_events(vec![LspEvent::Response(editor_core_lsp::LspResponse {
            id: 21,
            method: "textDocument/hover".to_string(),
            uri: None,
            result: Some(serde_json::json!({ "contents": "old" })),
            error: None,
        })])
        .unwrap();
    assert!(!applied);

    let events = ui.lsp_request_events_after(0);
    assert_eq!(events.latest_sequence, 2);
    assert_eq!(events.events.len(), 2);
    assert_eq!(events.events[1].phase, "completed");
    assert_eq!(events.events[1].status, "stale");
    assert_eq!(events.events[1].result_sequence, None);
    assert!(ui.lsp_result_events_after(0).events.is_empty());
}

#[test]
fn lsp_request_events_record_cancel_and_timeout_completion() {
    let mut ui = EditorUi::new("abc", 80);
    let view_id = ui.view_id;
    {
        let mut doc = ui.lock_doc();
        doc.lsp_client_requests.insert(
            41,
            LspClientRequest::Result {
                view: view_id,
                slot: LspResultSlot::Hover,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((view_id, LspResultSlot::Hover), 41);
        doc.record_lsp_request_started(view_id, LspResultSlot::Hover, 41);

        doc.lsp_client_requests.insert(
            42,
            LspClientRequest::Result {
                view: view_id,
                slot: LspResultSlot::CodeAction,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((view_id, LspResultSlot::CodeAction), 42);
        doc.record_lsp_request_started(view_id, LspResultSlot::CodeAction, 42);

        doc.lsp_client_requests.insert(
            43,
            LspClientRequest::OnTypeFormatting {
                view: view_id,
                version: 7,
            },
        );
    }

    assert!(ui.lsp_cancel_request(41).unwrap());
    assert!(ui.lsp_mark_request_timed_out(42));
    assert!(ui.lsp_mark_request_timed_out(43));
    assert!(!ui.lsp_mark_request_timed_out(404));

    let events = ui.lsp_request_events_after(0);
    assert_eq!(events.latest_sequence, 5);
    assert_eq!(events.events.len(), 5);
    assert_eq!(events.events[2].request_id, 41);
    assert_eq!(events.events[2].phase, "completed");
    assert_eq!(events.events[2].status, "canceled");
    assert_eq!(events.events[2].result_sequence, None);
    assert_eq!(events.events[3].request_id, 42);
    assert_eq!(events.events[3].phase, "completed");
    assert_eq!(events.events[3].status, "timeout");
    assert_eq!(events.events[3].result_sequence, None);
    assert_eq!(events.events[4].request_id, 43);
    assert_eq!(events.events[4].family, "formatting");
    assert_eq!(events.events[4].slot, "on_type_formatting");
    assert_eq!(events.events[4].phase, "completed");
    assert_eq!(events.events[4].status, "timeout");
    assert_eq!(events.events[4].result_sequence, None);
    assert!(ui.lsp_result_events_after(0).events.is_empty());

    let applied = ui
        .handle_lsp_events(vec![LspEvent::Response(editor_core_lsp::LspResponse {
            id: 41,
            method: "textDocument/hover".to_string(),
            uri: None,
            result: Some(serde_json::json!({ "contents": "late" })),
            error: None,
        })])
        .unwrap();
    assert!(!applied);
    assert_eq!(ui.lsp_request_events_after(0).events.len(), 5);
    assert!(ui.lsp_result_events_after(0).events.is_empty());
}

#[test]
fn lsp_auxiliary_refresh_records_derived_state_request_events() {
    let capture_path = unique_temp_path("aux-request-events");
    let capabilities = serde_json::json!({});
    let script = lsp_capture_server_script(&capture_path, capabilities);
    let args = vec!["-c".to_string(), script];
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root_uri = format!("file:///tmp/editor-core-ui-aux-request-events-{stamp}");
    let doc_uri = format!("{root_uri}/main.rs");

    let mut ui = EditorUi::new("fn main() {\n    println!(\"hi\");\n}\n", 80);
    ui.set_viewport_px(200, 40, 1.0).unwrap();
    ui.lsp_enable_stdio("/bin/sh", &args, &root_uri, &doc_uri, "rust")
        .unwrap();

    let _ = ui.poll_processing().unwrap();
    let captured = wait_for_captured_lsp_stdin(&capture_path, "textDocument/documentLink");
    assert!(captured.contains("textDocument/codeLens"));

    let events = ui.lsp_request_events_after(0);
    assert!(events.latest_sequence >= 2);
    assert!(
        events.events.iter().any(|event| {
            event.family == "code_lens"
                && event.slot == "code_lens"
                && event.method == "textDocument/codeLens"
                && event.phase == "started"
                && event.status == "pending"
        }),
        "missing code lens request event: {:?}",
        events.events
    );
    assert!(
        events.events.iter().any(|event| {
            event.family == "document_links"
                && event.slot == "document_links"
                && event.method == "textDocument/documentLink"
                && event.phase == "started"
                && event.status == "pending"
        }),
        "missing document links request event: {:?}",
        events.events
    );

    ui.lsp_disable();
    let _ = std::fs::remove_file(capture_path);
}

#[test]
fn lsp_auxiliary_derived_state_responses_record_request_and_result_events() {
    let mut ui = EditorUi::new("abc\nlink", 80);
    let view_id = ui.view_id;
    {
        let mut doc = ui.lock_doc();
        doc.lsp_inlay_in_flight = true;
        doc.track_lsp_result_request(view_id, LspResultSlot::InlayHints, 61);
        doc.lsp_document_links_in_flight = true;
        doc.track_lsp_result_request(view_id, LspResultSlot::DocumentLinks, 62);
    }

    let applied = ui
        .handle_lsp_events(vec![
            LspEvent::Response(editor_core_lsp::LspResponse {
                id: 61,
                method: "textDocument/inlayHint".to_string(),
                uri: None,
                result: Some(serde_json::json!([])),
                error: None,
            }),
            LspEvent::Response(editor_core_lsp::LspResponse {
                id: 62,
                method: "textDocument/documentLink".to_string(),
                uri: None,
                result: None,
                error: Some(LspResponseError {
                    code: -32603,
                    message: "links failed".to_string(),
                    data: None,
                }),
            }),
        ])
        .unwrap();

    assert!(applied);
    {
        let doc = ui.lock_doc();
        assert!(!doc.lsp_inlay_in_flight);
        assert!(!doc.lsp_document_links_in_flight);
    }

    let request_events = ui.lsp_request_events_after(0);
    assert_eq!(request_events.latest_sequence, 4);
    assert_eq!(request_events.events.len(), 4);
    assert_eq!(request_events.events[0].family, "inlay_hints");
    assert_eq!(request_events.events[0].slot, "inlay_hints");
    assert_eq!(request_events.events[0].phase, "started");
    assert_eq!(request_events.events[0].status, "pending");
    assert_eq!(request_events.events[1].family, "document_links");
    assert_eq!(request_events.events[1].slot, "document_links");
    assert_eq!(request_events.events[1].phase, "started");
    assert_eq!(request_events.events[1].status, "pending");
    assert_eq!(request_events.events[2].request_id, 61);
    assert_eq!(request_events.events[2].phase, "completed");
    assert_eq!(request_events.events[2].status, "success");
    assert_eq!(request_events.events[2].result_sequence, Some(1));
    assert_eq!(request_events.events[3].request_id, 62);
    assert_eq!(request_events.events[3].phase, "completed");
    assert_eq!(request_events.events[3].status, "error");
    assert_eq!(request_events.events[3].result_sequence, Some(2));
    assert_eq!(request_events.events[3].error_code, Some(-32603));
    assert_eq!(
        request_events.events[3].error_message.as_deref(),
        Some("links failed")
    );

    let result_events = ui.lsp_result_events_after(0);
    assert_eq!(result_events.latest_sequence, 2);
    assert_eq!(result_events.events.len(), 2);
    assert_eq!(result_events.events[0].family, "inlay_hints");
    assert_eq!(result_events.events[0].slot, "inlay_hints");
    assert_eq!(result_events.events[0].status, "success");
    assert_eq!(result_events.events[0].request_id, 61);
    assert_eq!(result_events.events[1].family, "document_links");
    assert_eq!(result_events.events[1].slot, "document_links");
    assert_eq!(result_events.events[1].status, "error");
    assert_eq!(result_events.events[1].request_id, 62);
    assert_eq!(result_events.events[1].error_code, Some(-32603));
}

#[test]
fn multi_document_tracks_project_lsp_server_configs() {
    let mut multi = MultiDocumentEditorUi::new();

    multi
        .set_project_lsp_server_configs(vec![
            ProjectLspServerConfig {
                key: " Rust ".to_string(),
                command: " /bin/rust-analyzer ".to_string(),
                args: vec![" ".to_string(), "--stdio ".to_string()],
                language_id: " rust ".to_string(),
                language_name: " Rust Language ".to_string(),
                server_capabilities: serde_json::json!({
                    "semantic_tokens": true,
                    "completion": { "supported": true }
                }),
                shared_session: true,
                session_policy: ProjectLspSessionPolicy::default(),
                workspace_roots: vec![
                    " file:///workspace ".to_string(),
                    "file:///workspace".to_string(),
                    "file:///other".to_string(),
                ],
                workspace_folders: vec![ProjectLspWorkspaceFolder {
                    uri: " file:///workspace ".to_string(),
                    name: " Workspace ".to_string(),
                    root_alias: Some(" main ".to_string()),
                }],
                auto_start: true,
                recovery_policy: ProjectLspRecoveryPolicy {
                    enabled: false,
                    max_attempts: 99,
                    base_delay_millis: 9_999_999,
                },
            },
            ProjectLspServerConfig {
                key: "".to_string(),
                command: "/bin/sourcekit-lsp".to_string(),
                args: vec![],
                language_id: "swift".to_string(),
                language_name: "".to_string(),
                server_capabilities: serde_json::Value::Null,
                shared_session: false,
                session_policy: ProjectLspSessionPolicy::default(),
                workspace_roots: vec![],
                workspace_folders: vec![],
                auto_start: false,
                recovery_policy: ProjectLspRecoveryPolicy::default(),
            },
        ])
        .unwrap();

    let configs = multi.project_lsp_server_configs();
    assert_eq!(configs.len(), 2);
    assert_eq!(configs[0].key, "rust");
    assert_eq!(configs[0].command, "/bin/rust-analyzer");
    assert_eq!(configs[0].args, vec!["--stdio"]);
    assert_eq!(configs[0].language_name, "Rust Language");
    assert_eq!(configs[0].server_capabilities["semantic_tokens"], true);
    assert_eq!(
        configs[0].server_capabilities["completion"]["supported"],
        true
    );
    assert!(configs[0].shared_session);
    assert_eq!(
        configs[0].session_policy,
        ProjectLspSessionPolicy {
            scope: "workspace".to_string(),
            merge_strategy: "server_workspace_roots".to_string(),
            deduplicate: true,
            shutdown_policy: "last_document".to_string(),
        }
    );
    assert_eq!(configs[1].language_name, "swift");
    assert_eq!(configs[1].server_capabilities, serde_json::json!({}));
    assert!(!configs[1].shared_session);
    assert_eq!(
        configs[1].session_policy,
        ProjectLspSessionPolicy {
            scope: "document".to_string(),
            merge_strategy: "document".to_string(),
            deduplicate: false,
            shutdown_policy: "document_close".to_string(),
        }
    );
    assert_eq!(
        configs[0].recovery_policy,
        ProjectLspRecoveryPolicy {
            enabled: false,
            max_attempts: 10,
            base_delay_millis: 3_600_000,
        }
    );
    assert_eq!(
        configs[1].recovery_policy,
        ProjectLspRecoveryPolicy::default()
    );
    assert_eq!(
        configs[0].workspace_roots,
        vec!["file:///other", "file:///workspace"]
    );
    assert_eq!(
        configs[0].workspace_folders,
        vec![
            ProjectLspWorkspaceFolder {
                uri: "file:///other".to_string(),
                name: "other".to_string(),
                root_alias: None,
            },
            ProjectLspWorkspaceFolder {
                uri: "file:///workspace".to_string(),
                name: "Workspace".to_string(),
                root_alias: Some("main".to_string()),
            },
        ]
    );
    assert_eq!(configs[1].key, "swift");
    assert!(!configs[1].auto_start);
    assert_eq!(
        multi.project_lsp_server_config("RUST").unwrap().language_id,
        "rust"
    );

    assert!(
        multi
            .set_project_lsp_server_configs(vec![ProjectLspServerConfig {
                key: "bad".to_string(),
                command: "/bin/bad-lsp".to_string(),
                args: vec![],
                language_id: "bad".to_string(),
                language_name: "".to_string(),
                server_capabilities: serde_json::json!(["not", "an", "object"]),
                shared_session: true,
                session_policy: ProjectLspSessionPolicy::default(),
                workspace_roots: vec![],
                workspace_folders: vec![],
                auto_start: true,
                recovery_policy: ProjectLspRecoveryPolicy::default(),
            }])
            .is_err()
    );
}

#[test]
fn multi_document_tracks_recent_file_uris() {
    let mut multi = MultiDocumentEditorUi::new();
    multi.set_workspace_roots(["file:///workspace"]);

    multi.remember_recent_file_uri(" file:///workspace/a.rs ");
    multi.remember_recent_file_uri("file:///workspace/b.rs");
    multi.remember_recent_file_uri("file:///workspace/a.rs");
    multi.remember_recent_file_uri("");

    assert_eq!(
        multi.recent_file_uris(),
        &[
            "file:///workspace/a.rs".to_string(),
            "file:///workspace/b.rs".to_string()
        ]
    );
    assert_eq!(
        multi
            .recent_file_entries()
            .into_iter()
            .map(|entry| entry.uri)
            .collect::<Vec<_>>(),
        vec!["file:///workspace/a.rs", "file:///workspace/b.rs"]
    );

    multi.restore_recent_file_uris([
        "file:///workspace/restored.rs",
        "file:///workspace/a.rs",
        "file:///workspace/restored.rs",
    ]);
    assert_eq!(
        multi.recent_file_uris(),
        &[
            "file:///workspace/restored.rs".to_string(),
            "file:///workspace/a.rs".to_string()
        ]
    );

    multi.set_workspace_roots(["file:///other"]);
    assert!(multi.recent_file_uris().is_empty());
}

#[test]
fn multi_document_tracks_recent_project_uris() {
    let mut multi = MultiDocumentEditorUi::new();

    multi.remember_recent_project_uri(" file:///workspace/a ");
    multi.remember_recent_project_uri("file:///workspace/b");
    multi.remember_recent_project_uri("file:///workspace/a");
    multi.remember_recent_project_uri("");

    assert_eq!(
        multi.recent_project_uris(),
        &[
            "file:///workspace/a".to_string(),
            "file:///workspace/b".to_string()
        ]
    );
    assert_eq!(
        multi
            .recent_project_entries()
            .into_iter()
            .map(|entry| entry.uri)
            .collect::<Vec<_>>(),
        vec!["file:///workspace/a", "file:///workspace/b"]
    );

    multi.restore_recent_project_uris([
        "file:///workspace/restored",
        "file:///workspace/a",
        "file:///workspace/restored",
    ]);
    assert_eq!(
        multi.recent_project_uris(),
        &[
            "file:///workspace/restored".to_string(),
            "file:///workspace/a".to_string()
        ]
    );

    multi.clear_recent_project_uris();
    assert!(multi.recent_project_uris().is_empty());
}

#[test]
fn multi_document_project_file_index_caches_workspace_files() {
    let mut root = std::env::temp_dir();
    root.push(format!(
        "editor_core_ui_project_file_index_{}_{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::write(root.join("src").join("lib.rs"), "pub fn demo() {}\n").unwrap();

    let mut multi = MultiDocumentEditorUi::new();
    multi.set_workspace_roots([editor_core_lsp::path_to_file_uri(&root)]);

    let initial = multi.project_file_index_snapshot();
    assert!(!initial.is_built);
    assert!(initial.files.is_empty());

    let refreshed = multi
        .refresh_project_file_index(WorkspaceFileListOptions::default())
        .unwrap();
    assert!(refreshed.is_built);
    assert_eq!(refreshed.files.len(), 1);
    assert_eq!(refreshed.files[0].relative_path, "src/lib.rs");

    std::fs::write(root.join("src").join("main.rs"), "fn main() {}\n").unwrap();
    let cached = multi.project_file_index_snapshot();
    assert_eq!(
        cached
            .files
            .iter()
            .map(|file| file.relative_path.as_str())
            .collect::<Vec<_>>(),
        vec!["src/lib.rs"]
    );

    let refreshed = multi
        .refresh_project_file_index(WorkspaceFileListOptions::default())
        .unwrap();
    assert_eq!(
        refreshed
            .files
            .iter()
            .map(|file| file.relative_path.as_str())
            .collect::<Vec<_>>(),
        vec!["src/lib.rs", "src/main.rs"]
    );

    multi.set_workspace_roots(["file:///other"]);
    let cleared = multi.project_file_index_snapshot();
    assert!(!cleared.is_built);
    assert!(cleared.files.is_empty());

    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn multi_document_workspace_file_search_uses_core_scan_policy() {
    let root = unique_temp_path("workspace_file_scan_policy");
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::write(root.join(".gitignore"), "ignored.txt\n").unwrap();
    std::fs::write(root.join("ignored.txt"), "needle ignored\n").unwrap();
    std::fs::write(root.join("binary.bin"), b"needle\0binary\n").unwrap();
    std::fs::write(
        root.join("large.txt"),
        format!("needle {}\n", "x".repeat(256)),
    )
    .unwrap();
    std::fs::write(root.join("src").join("a.txt"), "needle a1\nneedle a2\n").unwrap();
    std::fs::write(root.join("src").join("b.txt"), "needle b\n").unwrap();

    let mut multi = MultiDocumentEditorUi::new();
    multi.set_workspace_roots([editor_core_lsp::path_to_file_uri(&root)]);

    let scan_options = WorkspaceFileScanOptions {
        include_globs: vec!["*.txt".to_string(), "*.bin".to_string()],
        exclude_globs: Vec::new(),
        max_results: 2,
        offset: 0,
        max_file_size_bytes: 128,
        skip_binary: true,
        respect_ignore_files: true,
        cancelled: false,
        cancel_after_files: None,
    };
    let page = multi
        .search_workspace_files_with_scan_options(
            "needle",
            SearchOptions::default(),
            scan_options.clone(),
        )
        .unwrap();

    assert_eq!(
        page.results
            .iter()
            .map(|result| (result.relative_path.as_str(), result.line1))
            .collect::<Vec<_>>(),
        vec![("src/a.txt", 1), ("src/a.txt", 2)]
    );
    assert_eq!(page.scan.returned_results, 2);
    assert_eq!(page.scan.matched_results, 3);
    assert_eq!(page.scan.next_offset, Some(2));
    assert!(page.scan.truncated);
    assert!(!page.scan.cancelled);
    assert_eq!(page.scan.skipped_binary_files, 1);
    assert_eq!(page.scan.skipped_large_files, 1);
    assert!(page.scan.ignore_files_enabled);

    let second_page = multi
        .search_workspace_files_with_scan_options(
            "needle",
            SearchOptions::default(),
            WorkspaceFileScanOptions {
                offset: 2,
                ..scan_options
            },
        )
        .unwrap();
    assert_eq!(
        second_page
            .results
            .iter()
            .map(|result| result.relative_path.as_str())
            .collect::<Vec<_>>(),
        vec!["src/b.txt"]
    );
    assert!(!second_page.scan.truncated);
    assert_eq!(second_page.scan.returned_results, 1);
    assert_eq!(second_page.scan.matched_results, 3);

    let cancelled = multi
        .list_workspace_files_with_scan_options(WorkspaceFileScanOptions {
            max_results: 10,
            cancel_after_files: Some(1),
            ..WorkspaceFileScanOptions::default()
        })
        .unwrap();
    assert_eq!(cancelled.files.len(), 1);
    assert_eq!(cancelled.scan.visited_files, 1);
    assert!(cancelled.scan.cancelled);

    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn multi_document_project_file_index_queries_cached_files() {
    let mut root = std::env::temp_dir();
    root.push(format!(
        "editor_core_ui_project_file_index_query_{}_{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(root.join("src")).unwrap();
    std::fs::create_dir_all(root.join("docs")).unwrap();
    std::fs::write(root.join("src").join("core_model.rs"), "pub fn demo() {}\n").unwrap();
    std::fs::write(root.join("src").join("main.rs"), "fn main() {}\n").unwrap();
    std::fs::write(root.join("docs").join("manual.md"), "# docs\n").unwrap();

    let mut multi = MultiDocumentEditorUi::new();
    multi.set_workspace_roots([editor_core_lsp::path_to_file_uri(&root)]);
    assert!(multi.query_project_file_index("cm", 10).is_empty());

    multi
        .refresh_project_file_index(WorkspaceFileListOptions::default())
        .unwrap();

    assert_eq!(
        multi
            .query_project_file_index("", 2)
            .into_iter()
            .map(|file| file.relative_path)
            .collect::<Vec<_>>(),
        vec!["docs/manual.md", "src/core_model.rs"]
    );

    let matches = multi.query_project_file_index("c_m", 10);
    assert_eq!(
        matches
            .iter()
            .map(|file| file.relative_path.as_str())
            .collect::<Vec<_>>(),
        vec!["src/core_model.rs"]
    );
    assert!(matches[0].score > 0);

    let _ = std::fs::remove_dir_all(root);
}

#[test]
fn multi_document_builds_project_lsp_start_plan_from_open_tabs() {
    let mut multi = MultiDocumentEditorUi::new();
    multi.set_workspace_roots(["file:///workspace"]);
    let rust_tab = multi.open_tab("fn main() {}\n", 80);
    let swift_tab = multi.open_tab("print(\"hello\")\n", 80);
    let unknown_tab = multi.open_tab("plain\n", 80);
    multi
        .set_tab_document_uri(rust_tab, Some("file:///workspace/main.rs".to_string()))
        .unwrap();
    multi
        .set_tab_language_id(rust_tab, Some(" rust ".to_string()))
        .unwrap();
    multi
        .set_tab_document_uri(swift_tab, Some("file:///workspace/App.swift".to_string()))
        .unwrap();
    multi
        .set_tab_language_id(swift_tab, Some("swift".to_string()))
        .unwrap();
    multi
        .set_tab_language_id(unknown_tab, Some("rust".to_string()))
        .unwrap();

    multi
        .set_project_lsp_server_configs(vec![
            ProjectLspServerConfig {
                key: "rust".to_string(),
                command: "/bin/rust-analyzer".to_string(),
                args: vec!["--stdio".to_string()],
                language_id: "rust".to_string(),
                language_name: "Rust".to_string(),
                server_capabilities: serde_json::json!({
                    "semantic_tokens": true
                }),
                shared_session: true,
                session_policy: ProjectLspSessionPolicy::default(),
                workspace_roots: vec![],
                workspace_folders: vec![],
                auto_start: true,
                recovery_policy: ProjectLspRecoveryPolicy::default(),
            },
            ProjectLspServerConfig {
                key: "swift".to_string(),
                command: "/bin/sourcekit-lsp".to_string(),
                args: vec![],
                language_id: "swift".to_string(),
                language_name: "".to_string(),
                server_capabilities: serde_json::json!({}),
                shared_session: false,
                session_policy: ProjectLspSessionPolicy::default(),
                workspace_roots: vec!["file:///swift-root".to_string()],
                workspace_folders: vec![],
                auto_start: false,
                recovery_policy: ProjectLspRecoveryPolicy::default(),
            },
        ])
        .unwrap();

    let plan = multi.project_lsp_start_plan();
    assert_eq!(plan.len(), 1);
    assert_eq!(plan[0].operation, "start");
    assert_eq!(plan[0].attempt_id, Some(1));
    assert_eq!(plan[0].tab_id, rust_tab.get());
    assert_eq!(plan[0].active_view_index, 0);
    assert_eq!(plan[0].document_uri, "file:///workspace/main.rs");
    assert_eq!(plan[0].language_id, "rust");
    assert_eq!(plan[0].language_name, "Rust");
    assert_eq!(plan[0].server_capabilities["semantic_tokens"], true);
    assert!(plan[0].shared_session);
    assert_eq!(plan[0].session_key, "workspace:rust:file:///workspace");
    assert_eq!(plan[0].session_policy.scope, "workspace");
    assert!(plan[0].session_policy.deduplicate);
    assert_eq!(plan[0].server_key, "rust");
    assert_eq!(plan[0].command, "/bin/rust-analyzer");
    assert_eq!(plan[0].args, vec!["--stdio"]);
    assert_eq!(plan[0].workspace_roots, vec!["file:///workspace"]);
    assert_eq!(plan[0].recovery_policy, ProjectLspRecoveryPolicy::default());
    assert_eq!(
        plan[0].workspace_folders,
        vec![ProjectLspWorkspaceFolder {
            uri: "file:///workspace".to_string(),
            name: "workspace".to_string(),
            root_alias: None,
        }]
    );

    let json: serde_json::Value =
        serde_json::from_str(&multi.project_lsp_start_plan_json().unwrap()).unwrap();
    assert_eq!(json[0]["operation"], "start");
    assert_eq!(json[0]["attempt_id"], 1);
    assert_eq!(json[0]["server_key"], "rust");
    assert_eq!(json[0]["session_key"], "workspace:rust:file:///workspace");
    assert_eq!(
        json[0]["session_policy"],
        serde_json::json!({
            "scope": "workspace",
            "merge_strategy": "server_workspace_roots",
            "deduplicate": true,
            "shutdown_policy": "last_document"
        })
    );
    assert_eq!(json[0]["server_capabilities"]["semantic_tokens"], true);
    assert_eq!(
        json[0]["recovery_policy"],
        serde_json::json!({
            "enabled": true,
            "max_attempts": 3,
            "base_delay_millis": 5_000
        })
    );
    assert_eq!(json[0]["workspace_folders"][0]["name"], "workspace");
}

#[test]
fn multi_document_project_lsp_session_policy_keys_across_documents() {
    let mut multi = MultiDocumentEditorUi::new();
    multi.set_workspace_roots(["file:///workspace"]);
    let rust_main = multi.open_tab("fn main() {}\n", 80);
    let rust_lib = multi.open_tab("pub fn lib() {}\n", 80);
    let swift_tab = multi.open_tab("print(\"hello\")\n", 80);
    multi
        .set_tab_document_uri(rust_main, Some("file:///workspace/main.rs".to_string()))
        .unwrap();
    multi
        .set_tab_language_id(rust_main, Some("rust".to_string()))
        .unwrap();
    multi
        .set_tab_document_uri(rust_lib, Some("file:///workspace/lib.rs".to_string()))
        .unwrap();
    multi
        .set_tab_language_id(rust_lib, Some("rust".to_string()))
        .unwrap();
    multi
        .set_tab_document_uri(swift_tab, Some("file:///workspace/App.swift".to_string()))
        .unwrap();
    multi
        .set_tab_language_id(swift_tab, Some("swift".to_string()))
        .unwrap();

    multi
        .set_project_lsp_server_configs(vec![
            ProjectLspServerConfig {
                key: "rust".to_string(),
                command: "/bin/rust-analyzer".to_string(),
                args: vec![],
                language_id: "rust".to_string(),
                language_name: "".to_string(),
                server_capabilities: serde_json::json!({}),
                shared_session: true,
                session_policy: ProjectLspSessionPolicy::default(),
                workspace_roots: vec![],
                workspace_folders: vec![],
                auto_start: true,
                recovery_policy: ProjectLspRecoveryPolicy::default(),
            },
            ProjectLspServerConfig {
                key: "swift".to_string(),
                command: "/bin/sourcekit-lsp".to_string(),
                args: vec![],
                language_id: "swift".to_string(),
                language_name: "".to_string(),
                server_capabilities: serde_json::json!({}),
                shared_session: false,
                session_policy: ProjectLspSessionPolicy::default(),
                workspace_roots: vec![],
                workspace_folders: vec![],
                auto_start: true,
                recovery_policy: ProjectLspRecoveryPolicy::default(),
            },
        ])
        .unwrap();

    let plan = multi.project_lsp_start_plan();
    assert_eq!(plan.len(), 3);
    assert_eq!(plan[0].session_key, "workspace:rust:file:///workspace");
    assert_eq!(plan[1].session_key, plan[0].session_key);
    assert!(plan[0].session_policy.deduplicate);
    assert!(plan[1].session_policy.deduplicate);
    assert_eq!(
        plan[2].session_key,
        "document:swift:file:///workspace/App.swift"
    );
    assert_eq!(plan[2].session_policy.scope, "document");
    assert!(!plan[2].session_policy.deduplicate);
}

#[test]
fn multi_document_builds_project_lsp_stop_plan_from_open_tabs() {
    let mut multi = MultiDocumentEditorUi::new();
    multi.set_workspace_roots(["file:///workspace"]);
    let rust_tab = multi.open_tab("fn main() {}\n", 80);
    let swift_tab = multi.open_tab("print(\"hello\")\n", 80);
    let missing_uri_tab = multi.open_tab("plain\n", 80);
    multi
        .set_tab_document_uri(rust_tab, Some("file:///workspace/main.rs".to_string()))
        .unwrap();
    multi
        .set_tab_language_id(rust_tab, Some("rust".to_string()))
        .unwrap();
    multi
        .set_tab_document_uri(swift_tab, Some("file:///workspace/App.swift".to_string()))
        .unwrap();
    multi
        .set_tab_language_id(swift_tab, Some(" swift ".to_string()))
        .unwrap();
    multi
        .set_tab_language_id(missing_uri_tab, Some("swift".to_string()))
        .unwrap();

    multi
        .set_project_lsp_server_configs(vec![
            ProjectLspServerConfig {
                key: "rust".to_string(),
                command: "/bin/rust-analyzer".to_string(),
                args: vec!["--stdio".to_string()],
                language_id: "rust".to_string(),
                language_name: "".to_string(),
                server_capabilities: serde_json::json!({}),
                shared_session: true,
                session_policy: ProjectLspSessionPolicy::default(),
                workspace_roots: vec![],
                workspace_folders: vec![],
                auto_start: true,
                recovery_policy: ProjectLspRecoveryPolicy::default(),
            },
            ProjectLspServerConfig {
                key: "swift".to_string(),
                command: "/bin/sourcekit-lsp".to_string(),
                args: vec![],
                language_id: "swift".to_string(),
                language_name: "Swift".to_string(),
                server_capabilities: serde_json::json!({
                    "workspace_symbols": true
                }),
                shared_session: false,
                session_policy: ProjectLspSessionPolicy::default(),
                workspace_roots: vec!["file:///swift-root".to_string()],
                workspace_folders: vec![ProjectLspWorkspaceFolder {
                    uri: " file:///swift-root ".to_string(),
                    name: " Swift Root ".to_string(),
                    root_alias: Some(" app ".to_string()),
                }],
                auto_start: false,
                recovery_policy: ProjectLspRecoveryPolicy {
                    enabled: true,
                    max_attempts: 2,
                    base_delay_millis: 1_500,
                },
            },
        ])
        .unwrap();

    let plan = multi.project_lsp_stop_plan();
    assert_eq!(plan.len(), 2);
    assert_eq!(plan[0].operation, "stop");
    assert_eq!(plan[0].attempt_id, Some(1));
    assert_eq!(plan[0].tab_id, rust_tab.get());
    assert_eq!(plan[0].document_uri, "file:///workspace/main.rs");
    assert_eq!(plan[0].server_key, "rust");
    assert_eq!(plan[0].language_name, "rust");
    assert_eq!(plan[0].workspace_roots, vec!["file:///workspace"]);
    assert_eq!(plan[0].workspace_folders[0].name, "workspace");
    assert_eq!(plan[1].tab_id, swift_tab.get());
    assert_eq!(plan[1].attempt_id, Some(2));
    assert_eq!(plan[1].document_uri, "file:///workspace/App.swift");
    assert_eq!(plan[1].server_key, "swift");
    assert_eq!(plan[1].language_name, "Swift");
    assert_eq!(plan[1].server_capabilities["workspace_symbols"], true);
    assert!(!plan[1].shared_session);
    assert_eq!(
        plan[1].session_key,
        "document:swift:file:///workspace/App.swift"
    );
    assert_eq!(plan[1].session_policy.scope, "document");
    assert!(!plan[1].session_policy.deduplicate);
    assert_eq!(plan[1].workspace_roots, vec!["file:///swift-root"]);
    assert_eq!(
        plan[1].recovery_policy,
        ProjectLspRecoveryPolicy {
            enabled: true,
            max_attempts: 2,
            base_delay_millis: 1_500,
        }
    );
    assert_eq!(
        plan[1].workspace_folders,
        vec![ProjectLspWorkspaceFolder {
            uri: "file:///swift-root".to_string(),
            name: "Swift Root".to_string(),
            root_alias: Some("app".to_string()),
        }]
    );

    let json: serde_json::Value =
        serde_json::from_str(&multi.project_lsp_stop_plan_json().unwrap()).unwrap();
    assert_eq!(json[1]["operation"], "stop");
    assert_eq!(json[1]["attempt_id"], 2);
    assert_eq!(json[1]["command"], "/bin/sourcekit-lsp");
    assert_eq!(
        json[1]["session_key"],
        "document:swift:file:///workspace/App.swift"
    );
    assert_eq!(
        json[1]["session_policy"],
        serde_json::json!({
            "scope": "document",
            "merge_strategy": "document",
            "deduplicate": false,
            "shutdown_policy": "document_close"
        })
    );
    assert_eq!(json[1]["server_capabilities"]["workspace_symbols"], true);
    assert_eq!(
        json[1]["recovery_policy"],
        serde_json::json!({
            "enabled": true,
            "max_attempts": 2,
            "base_delay_millis": 1_500
        })
    );
    assert_eq!(json[1]["workspace_folders"][0]["root_alias"], "app");
}

#[test]
fn multi_document_builds_project_lsp_restart_plan_from_open_tabs() {
    let mut multi = MultiDocumentEditorUi::new();
    multi.set_workspace_roots(["file:///workspace"]);
    let rust_tab = multi.open_tab("fn main() {}\n", 80);
    let swift_tab = multi.open_tab("print(\"hello\")\n", 80);
    let missing_uri_tab = multi.open_tab("plain\n", 80);
    multi
        .set_tab_document_uri(rust_tab, Some("file:///workspace/main.rs".to_string()))
        .unwrap();
    multi
        .set_tab_language_id(rust_tab, Some(" rust ".to_string()))
        .unwrap();
    multi
        .set_tab_document_uri(swift_tab, Some("file:///workspace/App.swift".to_string()))
        .unwrap();
    multi
        .set_tab_language_id(swift_tab, Some("swift".to_string()))
        .unwrap();
    multi
        .set_tab_language_id(missing_uri_tab, Some("rust".to_string()))
        .unwrap();

    multi
        .set_project_lsp_server_configs(vec![
            ProjectLspServerConfig {
                key: "rust".to_string(),
                command: "/bin/rust-analyzer".to_string(),
                args: vec!["--stdio".to_string()],
                language_id: "rust".to_string(),
                language_name: "Rust".to_string(),
                server_capabilities: serde_json::json!({}),
                shared_session: true,
                session_policy: ProjectLspSessionPolicy::default(),
                workspace_roots: vec![],
                workspace_folders: vec![],
                auto_start: true,
                recovery_policy: ProjectLspRecoveryPolicy::default(),
            },
            ProjectLspServerConfig {
                key: "swift".to_string(),
                command: "/bin/sourcekit-lsp".to_string(),
                args: vec![],
                language_id: "swift".to_string(),
                language_name: "".to_string(),
                server_capabilities: serde_json::json!({
                    "diagnostics": true
                }),
                shared_session: false,
                session_policy: ProjectLspSessionPolicy::default(),
                workspace_roots: vec!["file:///swift-root".to_string()],
                workspace_folders: vec![],
                auto_start: false,
                recovery_policy: ProjectLspRecoveryPolicy {
                    enabled: false,
                    max_attempts: 0,
                    base_delay_millis: 0,
                },
            },
        ])
        .unwrap();

    let plan = multi.project_lsp_restart_plan();
    assert_eq!(plan.len(), 2);
    assert_eq!(plan[0].operation, "restart");
    assert_eq!(plan[0].attempt_id, Some(1));
    assert_eq!(plan[0].tab_id, rust_tab.get());
    assert_eq!(plan[0].document_uri, "file:///workspace/main.rs");
    assert_eq!(plan[0].server_key, "rust");
    assert_eq!(plan[0].language_name, "Rust");
    assert_eq!(plan[0].workspace_roots, vec!["file:///workspace"]);
    assert_eq!(plan[0].workspace_folders[0].uri, "file:///workspace");
    assert_eq!(plan[1].tab_id, swift_tab.get());
    assert_eq!(plan[1].attempt_id, Some(2));
    assert_eq!(plan[1].document_uri, "file:///workspace/App.swift");
    assert_eq!(plan[1].server_key, "swift");
    assert_eq!(plan[1].language_name, "swift");
    assert_eq!(plan[1].server_capabilities["diagnostics"], true);
    assert!(!plan[1].shared_session);
    assert_eq!(
        plan[1].session_key,
        "document:swift:file:///workspace/App.swift"
    );
    assert_eq!(plan[1].session_policy.scope, "document");
    assert!(!plan[1].session_policy.deduplicate);
    assert_eq!(plan[1].workspace_roots, vec!["file:///swift-root"]);
    assert_eq!(
        plan[1].recovery_policy,
        ProjectLspRecoveryPolicy {
            enabled: false,
            max_attempts: 0,
            base_delay_millis: 0,
        }
    );
    assert_eq!(plan[1].workspace_folders[0].name, "swift-root");

    let json: serde_json::Value =
        serde_json::from_str(&multi.project_lsp_restart_plan_json().unwrap()).unwrap();
    assert_eq!(json[1]["operation"], "restart");
    assert_eq!(json[1]["attempt_id"], 2);
    assert_eq!(json[1]["command"], "/bin/sourcekit-lsp");
    assert_eq!(
        json[1]["session_key"],
        "document:swift:file:///workspace/App.swift"
    );
    assert_eq!(
        json[1]["session_policy"],
        serde_json::json!({
            "scope": "document",
            "merge_strategy": "document",
            "deduplicate": false,
            "shutdown_policy": "document_close"
        })
    );
    assert_eq!(json[1]["server_capabilities"]["diagnostics"], true);
    assert_eq!(
        json[1]["recovery_policy"],
        serde_json::json!({
            "enabled": false,
            "max_attempts": 0,
            "base_delay_millis": 0
        })
    );
    assert_eq!(json[1]["workspace_folders"][0]["uri"], "file:///swift-root");
}

#[test]
fn multi_document_records_project_lsp_start_outcomes() {
    let mut multi = MultiDocumentEditorUi::new();
    let tab_id = multi.open_tab("fn main() {}\n", 80);
    multi
        .set_tab_document_uri(tab_id, Some("file:///workspace/main.rs".to_string()))
        .unwrap();
    multi
        .set_tab_language_id(tab_id, Some("rust".to_string()))
        .unwrap();

    let started = multi
        .record_project_lsp_start_outcome(ProjectLspStartOutcome {
            tab_id: tab_id.get(),
            active_view_index: 0,
            operation: "start".to_string(),
            document_uri: "file:///workspace/main.rs".to_string(),
            language_id: "rust".to_string(),
            language_name: " Rust ".to_string(),
            server_capabilities: serde_json::json!({
                "hover": true
            }),
            shared_session: false,
            session_key: "".to_string(),
            session_policy: ProjectLspSessionPolicy::default(),
            server_key: "rust".to_string(),
            command: "/bin/rust-analyzer".to_string(),
            args: vec!["--stdio".to_string()],
            workspace_roots: vec!["file:///workspace".to_string()],
            workspace_folders: vec![ProjectLspWorkspaceFolder {
                uri: " file:///workspace ".to_string(),
                name: " Workspace ".to_string(),
                root_alias: Some(" main ".to_string()),
            }],
            recovery_policy: ProjectLspRecoveryPolicy {
                enabled: true,
                max_attempts: 99,
                base_delay_millis: 9_999_999,
            },
            trigger: " auto_start ".to_string(),
            attempt_id: None,
            status: " started ".to_string(),
            error_message: None,
        })
        .unwrap();
    assert_eq!(started.sequence, 1);
    assert_eq!(started.operation, "start");
    assert_eq!(started.status, "started");
    assert_eq!(started.tab_id, tab_id.get());
    assert_eq!(started.language_name, "Rust");
    assert_eq!(started.server_capabilities["hover"], true);
    assert!(!started.shared_session);
    assert_eq!(
        started.session_key,
        "document:rust:file:///workspace/main.rs"
    );
    assert_eq!(started.session_policy.scope, "document");
    assert!(!started.session_policy.deduplicate);
    assert_eq!(
        started.recovery_policy,
        ProjectLspRecoveryPolicy {
            enabled: true,
            max_attempts: 10,
            base_delay_millis: 3_600_000,
        }
    );
    assert_eq!(
        started.workspace_folders,
        vec![ProjectLspWorkspaceFolder {
            uri: "file:///workspace".to_string(),
            name: "Workspace".to_string(),
            root_alias: Some("main".to_string()),
        }]
    );

    let restarted = multi
        .record_project_lsp_start_outcome(ProjectLspStartOutcome {
            tab_id: tab_id.get(),
            active_view_index: 0,
            operation: " restart ".to_string(),
            document_uri: "file:///workspace/main.rs".to_string(),
            language_id: "rust".to_string(),
            language_name: "".to_string(),
            server_capabilities: serde_json::json!({}),
            shared_session: true,
            session_key: "".to_string(),
            session_policy: ProjectLspSessionPolicy::default(),
            server_key: "rust".to_string(),
            command: "/bin/rust-analyzer".to_string(),
            args: vec![],
            workspace_roots: vec![],
            workspace_folders: vec![],
            recovery_policy: ProjectLspRecoveryPolicy::default(),
            trigger: "manual_restart".to_string(),
            attempt_id: None,
            status: "started".to_string(),
            error_message: None,
        })
        .unwrap();
    assert_eq!(restarted.sequence, 2);
    assert_eq!(restarted.operation, "restart");
    assert_eq!(restarted.trigger, "manual_restart");
    assert_eq!(restarted.status, "started");
    assert_eq!(restarted.language_name, "rust");

    let stopped = multi
        .record_project_lsp_start_outcome(ProjectLspStartOutcome {
            tab_id: tab_id.get(),
            active_view_index: 0,
            operation: " stop ".to_string(),
            document_uri: "file:///workspace/main.rs".to_string(),
            language_id: "rust".to_string(),
            language_name: "".to_string(),
            server_capabilities: serde_json::json!({}),
            shared_session: true,
            session_key: "".to_string(),
            session_policy: ProjectLspSessionPolicy::default(),
            server_key: "rust".to_string(),
            command: "/bin/rust-analyzer".to_string(),
            args: vec![],
            workspace_roots: vec![],
            workspace_folders: vec![],
            recovery_policy: ProjectLspRecoveryPolicy::default(),
            trigger: "tab_close".to_string(),
            attempt_id: None,
            status: " stopped ".to_string(),
            error_message: None,
        })
        .unwrap();
    assert_eq!(stopped.sequence, 3);
    assert_eq!(stopped.operation, "stop");
    assert_eq!(stopped.trigger, "tab_close");
    assert_eq!(stopped.status, "stopped");

    let requested = multi
        .record_project_lsp_start_outcome(ProjectLspStartOutcome {
            tab_id: tab_id.get(),
            active_view_index: 0,
            operation: "restart".to_string(),
            document_uri: "file:///workspace/main.rs".to_string(),
            language_id: "rust".to_string(),
            language_name: "".to_string(),
            server_capabilities: serde_json::json!({}),
            shared_session: true,
            session_key: "".to_string(),
            session_policy: ProjectLspSessionPolicy::default(),
            server_key: "rust".to_string(),
            command: "/bin/rust-analyzer".to_string(),
            args: vec![],
            workspace_roots: vec!["file:///workspace".to_string()],
            workspace_folders: vec![],
            recovery_policy: ProjectLspRecoveryPolicy::default(),
            trigger: "manual_restart".to_string(),
            attempt_id: None,
            status: " requested ".to_string(),
            error_message: None,
        })
        .unwrap();
    assert_eq!(requested.sequence, 4);
    assert_eq!(requested.operation, "restart");
    assert_eq!(requested.trigger, "manual_restart");
    assert_eq!(requested.status, "requested");
    assert_eq!(requested.attempt_id, Some(requested.sequence));
    assert_eq!(requested.workspace_folders[0].name, "workspace");

    let requested_started = multi
        .record_project_lsp_start_outcome(ProjectLspStartOutcome {
            tab_id: tab_id.get(),
            active_view_index: 0,
            operation: "restart".to_string(),
            document_uri: "file:///workspace/main.rs".to_string(),
            language_id: "rust".to_string(),
            language_name: "".to_string(),
            server_capabilities: serde_json::json!({}),
            shared_session: true,
            session_key: "".to_string(),
            session_policy: ProjectLspSessionPolicy::default(),
            server_key: "rust".to_string(),
            command: "/bin/rust-analyzer".to_string(),
            args: vec![],
            workspace_roots: vec!["file:///workspace".to_string()],
            workspace_folders: vec![],
            recovery_policy: ProjectLspRecoveryPolicy::default(),
            trigger: "manual_restart".to_string(),
            attempt_id: requested.attempt_id,
            status: "started".to_string(),
            error_message: None,
        })
        .unwrap();
    assert_eq!(requested_started.sequence, 5);
    assert_eq!(requested_started.operation, "restart");
    assert_eq!(requested_started.trigger, "manual_restart");
    assert_eq!(requested_started.status, "started");
    assert_eq!(requested_started.attempt_id, requested.attempt_id);

    let skipped = multi
        .record_project_lsp_start_outcome(ProjectLspStartOutcome {
            tab_id: tab_id.get(),
            active_view_index: 0,
            operation: " restart ".to_string(),
            document_uri: "file:///workspace/main.rs".to_string(),
            language_id: "rust".to_string(),
            language_name: "".to_string(),
            server_capabilities: serde_json::json!({}),
            shared_session: true,
            session_key: "".to_string(),
            session_policy: ProjectLspSessionPolicy::default(),
            server_key: "rust".to_string(),
            command: "/bin/rust-analyzer".to_string(),
            args: vec![],
            workspace_roots: vec![],
            workspace_folders: vec![],
            recovery_policy: ProjectLspRecoveryPolicy::default(),
            trigger: "manual_restart".to_string(),
            attempt_id: None,
            status: " skipped ".to_string(),
            error_message: Some("plan did not match".to_string()),
        })
        .unwrap();
    assert_eq!(skipped.sequence, 6);
    assert_eq!(skipped.operation, "restart");
    assert_eq!(skipped.trigger, "manual_restart");
    assert_eq!(skipped.status, "skipped");

    let snapshot = multi.project_lsp_lifecycle_events_after(2);
    assert_eq!(snapshot.latest_sequence, 6);
    assert_eq!(
        snapshot.events,
        vec![
            stopped.clone(),
            requested.clone(),
            requested_started.clone(),
            skipped.clone()
        ]
    );

    let json: serde_json::Value =
        serde_json::from_str(&multi.project_lsp_lifecycle_events_json(0).unwrap()).unwrap();
    assert_eq!(json["latest_sequence"], 6);
    assert_eq!(json["events"][0]["status"], "started");
    assert_eq!(json["events"][0]["server_capabilities"]["hover"], true);
    assert_eq!(json["events"][0]["shared_session"], false);
    assert_eq!(
        json["events"][0]["session_key"],
        "document:rust:file:///workspace/main.rs"
    );
    assert_eq!(
        json["events"][0]["session_policy"],
        serde_json::json!({
            "scope": "document",
            "merge_strategy": "document",
            "deduplicate": false,
            "shutdown_policy": "document_close"
        })
    );
    assert_eq!(
        json["events"][0]["recovery_policy"],
        serde_json::json!({
            "enabled": true,
            "max_attempts": 10,
            "base_delay_millis": 3_600_000
        })
    );
    assert_eq!(
        json["events"][0]["workspace_folders"][0]["root_alias"],
        "main"
    );
    assert_eq!(json["events"][1]["operation"], "restart");
    assert_eq!(json["events"][2]["operation"], "stop");
    assert_eq!(json["events"][2]["status"], "stopped");
    assert_eq!(json["events"][3]["status"], "requested");
    assert_eq!(json["events"][3]["attempt_id"], requested.sequence);
    assert_eq!(json["events"][4]["status"], "started");
    assert_eq!(json["events"][4]["attempt_id"], requested.sequence);
    assert_eq!(json["events"][5]["status"], "skipped");
    assert_eq!(json["events"][5].get("attempt_id"), None);

    let missing_tab_skipped = multi
        .record_project_lsp_start_outcome(ProjectLspStartOutcome {
            tab_id: 999,
            active_view_index: 0,
            operation: "stop".to_string(),
            document_uri: "file:///workspace/missing.rs".to_string(),
            language_id: "rust".to_string(),
            language_name: "".to_string(),
            server_capabilities: serde_json::json!({}),
            shared_session: true,
            session_key: "".to_string(),
            session_policy: ProjectLspSessionPolicy::default(),
            server_key: "rust".to_string(),
            command: "/bin/rust-analyzer".to_string(),
            args: vec![],
            workspace_roots: vec!["file:///workspace".to_string()],
            workspace_folders: vec![],
            recovery_policy: ProjectLspRecoveryPolicy::default(),
            trigger: "manual_shutdown".to_string(),
            attempt_id: None,
            status: "skipped".to_string(),
            error_message: Some("plan did not match".to_string()),
        })
        .unwrap();
    assert_eq!(missing_tab_skipped.sequence, 7);
    assert_eq!(missing_tab_skipped.operation, "stop");
    assert_eq!(missing_tab_skipped.trigger, "manual_shutdown");
    assert_eq!(missing_tab_skipped.status, "skipped");
    assert_eq!(missing_tab_skipped.tab_id, 999);
    assert_eq!(multi.project_lsp_lifecycle_events_latest_sequence(), 7);

    assert!(
        multi
            .record_project_lsp_start_outcome(ProjectLspStartOutcome {
                tab_id: 999,
                active_view_index: 0,
                operation: "start".to_string(),
                document_uri: "file:///workspace/main.rs".to_string(),
                language_id: "rust".to_string(),
                language_name: "".to_string(),
                server_capabilities: serde_json::json!({}),
                shared_session: true,
                session_key: "".to_string(),
                session_policy: ProjectLspSessionPolicy::default(),
                server_key: "rust".to_string(),
                command: "/bin/rust-analyzer".to_string(),
                args: vec![],
                workspace_roots: vec![],
                workspace_folders: vec![],
                recovery_policy: ProjectLspRecoveryPolicy::default(),
                trigger: "auto_start".to_string(),
                attempt_id: None,
                status: "started".to_string(),
                error_message: None,
            })
            .is_err()
    );
}

#[test]
fn multi_document_tracks_tab_language_metadata() {
    let mut multi = MultiDocumentEditorUi::new();
    let tab_id = multi.open_tab("fn main() {}\n", 80);

    assert_eq!(multi.tab_language_id(tab_id), None);

    multi
        .set_tab_language_id(tab_id, Some(" rust ".to_string()))
        .unwrap();
    assert_eq!(multi.tab_language_id(tab_id), Some("rust"));

    multi
        .set_tab_language_id(tab_id, Some("  ".to_string()))
        .unwrap();
    assert_eq!(multi.tab_language_id(tab_id), None);

    assert!(
        multi
            .set_tab_language_id(TabId::from_raw(999), Some("rust".to_string()))
            .is_err()
    );
}

#[test]
fn multi_document_lsp_result_events_aggregate_tab_and_view_context() {
    let mut multi = MultiDocumentEditorUi::new();
    let first_tab = multi.open_tab("abc", 80);
    let second_tab = multi.open_tab("def", 80);

    multi.set_active_tab(first_tab).unwrap();
    {
        let editor = multi.active_editor_mut().unwrap();
        let view_id = editor.view_id;
        let mut doc = editor.lock_doc();
        doc.lsp_client_requests.insert(
            11,
            LspClientRequest::Result {
                view: view_id,
                slot: LspResultSlot::Hover,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((view_id, LspResultSlot::Hover), 11);
    }
    let applied = multi
        .active_editor_mut()
        .unwrap()
        .handle_lsp_events(vec![LspEvent::Response(editor_core_lsp::LspResponse {
            id: 11,
            method: "textDocument/hover".to_string(),
            uri: None,
            result: Some(serde_json::json!({ "contents": "hello" })),
            error: None,
        })])
        .unwrap();
    assert!(!applied);

    multi.set_active_tab(second_tab).unwrap();
    {
        let editor = multi.active_editor_mut().unwrap();
        let view_id = editor.view_id;
        let mut doc = editor.lock_doc();
        doc.lsp_client_requests.insert(
            12,
            LspClientRequest::Result {
                view: view_id,
                slot: LspResultSlot::CodeAction,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((view_id, LspResultSlot::CodeAction), 12);
    }
    let applied = multi
        .active_editor_mut()
        .unwrap()
        .handle_lsp_events(vec![LspEvent::Response(editor_core_lsp::LspResponse {
            id: 12,
            method: "textDocument/codeAction".to_string(),
            uri: None,
            result: None,
            error: Some(LspResponseError {
                code: -32603,
                message: "actions failed".to_string(),
                data: None,
            }),
        })])
        .unwrap();
    assert!(!applied);

    let snapshot = multi.lsp_result_events_after(0);
    assert_eq!(snapshot.latest_sequence, 2);
    assert_eq!(snapshot.events.len(), 2);

    let first = &snapshot.events[0];
    assert_eq!(first.sequence, 1);
    assert_eq!(first.tab_id, first_tab.get());
    assert_eq!(first.view_index, 0);
    assert_eq!(first.source_sequence, 1);
    assert_eq!(first.family, "hover");
    assert_eq!(first.slot, "hover");
    assert_eq!(first.status, "success");
    assert!(first.has_result);

    let second = &snapshot.events[1];
    assert_eq!(second.sequence, 2);
    assert_eq!(second.tab_id, second_tab.get());
    assert_eq!(second.view_index, 0);
    assert_eq!(second.source_sequence, 1);
    assert_eq!(second.family, "actions");
    assert_eq!(second.slot, "code_action");
    assert_eq!(second.status, "error");
    assert!(!second.has_result);
    assert_eq!(second.error_code, Some(-32603));
    assert_eq!(second.error_message.as_deref(), Some("actions failed"));

    let repeat = multi.lsp_result_events_after(0);
    assert_eq!(repeat.latest_sequence, 2);
    assert_eq!(repeat.events.len(), 2);

    let after_first: serde_json::Value =
        serde_json::from_str(&multi.lsp_result_events_json(1).unwrap()).unwrap();
    assert_eq!(after_first["latest_sequence"], 2);
    assert_eq!(after_first["events"].as_array().unwrap().len(), 1);
    assert_eq!(after_first["events"][0]["sequence"], 2);
}

#[test]
fn multi_document_lsp_request_events_aggregate_tab_and_view_context() {
    let mut multi = MultiDocumentEditorUi::new();
    let first_tab = multi.open_tab("abc", 80);
    let second_tab = multi.open_tab("def", 80);

    multi.set_active_tab(first_tab).unwrap();
    {
        let editor = multi.active_editor_mut().unwrap();
        let view_id = editor.view_id;
        let mut doc = editor.lock_doc();
        doc.lsp_client_requests.insert(
            31,
            LspClientRequest::Result {
                view: view_id,
                slot: LspResultSlot::Hover,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((view_id, LspResultSlot::Hover), 31);
        doc.record_lsp_request_started(view_id, LspResultSlot::Hover, 31);
    }
    let applied = multi
        .active_editor_mut()
        .unwrap()
        .handle_lsp_events(vec![LspEvent::Response(editor_core_lsp::LspResponse {
            id: 31,
            method: "textDocument/hover".to_string(),
            uri: None,
            result: Some(serde_json::json!({ "contents": "hello" })),
            error: None,
        })])
        .unwrap();
    assert!(!applied);

    multi.set_active_tab(second_tab).unwrap();
    {
        let editor = multi.active_editor_mut().unwrap();
        let view_id = editor.view_id;
        let mut doc = editor.lock_doc();
        doc.lsp_client_requests.insert(
            32,
            LspClientRequest::Result {
                view: view_id,
                slot: LspResultSlot::CodeAction,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((view_id, LspResultSlot::CodeAction), 32);
        doc.record_lsp_request_started(view_id, LspResultSlot::CodeAction, 32);
    }
    let applied = multi
        .active_editor_mut()
        .unwrap()
        .handle_lsp_events(vec![LspEvent::Response(editor_core_lsp::LspResponse {
            id: 32,
            method: "textDocument/codeAction".to_string(),
            uri: None,
            result: None,
            error: Some(LspResponseError {
                code: -32603,
                message: "actions failed".to_string(),
                data: None,
            }),
        })])
        .unwrap();
    assert!(!applied);

    let snapshot = multi.lsp_request_events_after(0);
    assert_eq!(snapshot.latest_sequence, 4);
    assert_eq!(snapshot.events.len(), 4);

    let first_started = &snapshot.events[0];
    assert_eq!(first_started.sequence, 1);
    assert_eq!(first_started.tab_id, first_tab.get());
    assert_eq!(first_started.view_index, 0);
    assert_eq!(first_started.source_sequence, 1);
    assert_eq!(first_started.family, "hover");
    assert_eq!(first_started.slot, "hover");
    assert_eq!(first_started.phase, "started");
    assert_eq!(first_started.status, "pending");
    assert_eq!(first_started.source_result_sequence, None);

    let first_completed = &snapshot.events[1];
    assert_eq!(first_completed.sequence, 2);
    assert_eq!(first_completed.tab_id, first_tab.get());
    assert_eq!(first_completed.source_sequence, 2);
    assert_eq!(first_completed.phase, "completed");
    assert_eq!(first_completed.status, "success");
    assert_eq!(first_completed.source_result_sequence, Some(1));

    let second_started = &snapshot.events[2];
    assert_eq!(second_started.sequence, 3);
    assert_eq!(second_started.tab_id, second_tab.get());
    assert_eq!(second_started.source_sequence, 1);
    assert_eq!(second_started.family, "actions");
    assert_eq!(second_started.slot, "code_action");
    assert_eq!(second_started.phase, "started");
    assert_eq!(second_started.status, "pending");

    let second_completed = &snapshot.events[3];
    assert_eq!(second_completed.sequence, 4);
    assert_eq!(second_completed.tab_id, second_tab.get());
    assert_eq!(second_completed.source_sequence, 2);
    assert_eq!(second_completed.phase, "completed");
    assert_eq!(second_completed.status, "error");
    assert_eq!(second_completed.source_result_sequence, Some(1));
    assert_eq!(second_completed.error_code, Some(-32603));
    assert_eq!(
        second_completed.error_message.as_deref(),
        Some("actions failed")
    );

    let repeat = multi.lsp_request_events_after(0);
    assert_eq!(repeat.latest_sequence, 4);
    assert_eq!(repeat.events.len(), 4);

    let after_first_pair: serde_json::Value =
        serde_json::from_str(&multi.lsp_request_events_json(2).unwrap()).unwrap();
    assert_eq!(after_first_pair["latest_sequence"], 4);
    assert_eq!(after_first_pair["events"].as_array().unwrap().len(), 2);
    assert_eq!(after_first_pair["events"][0]["sequence"], 3);
}

#[test]
fn multi_document_state_events_aggregate_editor_state_event_context() {
    let mut multi = MultiDocumentEditorUi::new();
    let first_tab = multi.open_tab("abc", 80);
    let second_tab = multi.open_tab("def", 80);

    multi.set_active_tab(first_tab).unwrap();
    {
        let editor = multi.active_editor_mut().unwrap();
        let view_id = editor.view_id;
        let mut doc = editor.lock_doc();
        doc.lsp_client_requests.insert(
            51,
            LspClientRequest::Result {
                view: view_id,
                slot: LspResultSlot::Hover,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((view_id, LspResultSlot::Hover), 51);
    }
    multi
        .active_editor_mut()
        .unwrap()
        .handle_lsp_events(vec![LspEvent::Response(editor_core_lsp::LspResponse {
            id: 51,
            method: "textDocument/hover".to_string(),
            uri: None,
            result: Some(serde_json::json!({ "contents": "hello" })),
            error: None,
        })])
        .unwrap();

    multi.set_active_tab(second_tab).unwrap();
    {
        let editor = multi.active_editor_mut().unwrap();
        let view_id = editor.view_id;
        let mut doc = editor.lock_doc();
        doc.record_lsp_request_started(view_id, LspResultSlot::CodeAction, 52);
    }

    let snapshot = multi.state_events_after(0);
    assert_eq!(snapshot.latest_sequence, 3);
    assert_eq!(snapshot.events.len(), 3);
    assert_eq!(
        snapshot
            .events
            .iter()
            .map(|event| (event.tab_id, event.kind.as_str(), event.family.as_str()))
            .collect::<Vec<_>>(),
        vec![
            (first_tab.get(), "lsp_result", "hover"),
            (first_tab.get(), "lsp_request", "hover"),
            (second_tab.get(), "lsp_request", "actions"),
        ]
    );
    assert_eq!(snapshot.events[0].view_index, 0);
    assert_eq!(snapshot.events[0].source_sequence, 1);
    assert_eq!(
        snapshot.events[0]
            .state_event
            .lsp_result
            .as_ref()
            .unwrap()
            .status,
        "success"
    );
    assert_eq!(
        snapshot.events[1]
            .state_event
            .lsp_request
            .as_ref()
            .unwrap()
            .phase,
        "completed"
    );
    assert_eq!(
        snapshot.events[2]
            .state_event
            .lsp_request
            .as_ref()
            .unwrap()
            .phase,
        "started"
    );

    let repeat = multi.state_events_after(0);
    assert_eq!(repeat.latest_sequence, 3);
    assert_eq!(repeat.events.len(), 3);

    let after_first: serde_json::Value =
        serde_json::from_str(&multi.state_events_json(1).unwrap()).unwrap();
    assert_eq!(after_first["latest_sequence"], 3);
    assert_eq!(after_first["events"].as_array().unwrap().len(), 2);
    assert_eq!(after_first["events"][0]["kind"], "lsp_request");
    assert_eq!(
        after_first["events"][0]["state_event"]["lsp_request"]["phase"],
        "completed"
    );
}

#[test]
fn multi_document_state_events_aggregate_text_and_dirty_events() {
    let mut multi = MultiDocumentEditorUi::new();
    let tab = multi.open_tab("", 80);

    multi.active_editor_mut().unwrap().insert_text("z").unwrap();

    let snapshot = multi.state_events_after(0);
    assert_eq!(snapshot.latest_sequence, 3);
    assert_eq!(snapshot.events.len(), 3);
    assert_eq!(
        snapshot
            .events
            .iter()
            .map(|event| (event.tab_id, event.kind.as_str(), event.family.as_str()))
            .collect::<Vec<_>>(),
        vec![
            (tab.get(), "dirty_changed", "document"),
            (tab.get(), "selection_changed", "document"),
            (tab.get(), "text_changed", "document"),
        ]
    );
    assert_eq!(snapshot.events[0].view_index, 0);
    assert_eq!(
        snapshot.events[0]
            .state_event
            .dirty
            .as_ref()
            .unwrap()
            .is_modified,
        true
    );
    assert_eq!(
        snapshot.events[1]
            .state_event
            .selection
            .as_ref()
            .unwrap()
            .primary
            .offset,
        1
    );
    let text = snapshot.events[2].state_event.text.as_ref().unwrap();
    assert_eq!(text.text_version, 1);
    assert_eq!(text.char_len, 1);
    assert!(text.is_modified);

    let after_first: serde_json::Value =
        serde_json::from_str(&multi.state_events_json(1).unwrap()).unwrap();
    assert_eq!(after_first["latest_sequence"], 3);
    assert_eq!(after_first["events"].as_array().unwrap().len(), 2);
    assert_eq!(after_first["events"][0]["kind"], "selection_changed");
    assert_eq!(
        after_first["events"][0]["state_event"]["selection"]["primary"]["offset"],
        1
    );
    assert_eq!(after_first["events"][1]["kind"], "text_changed");
    assert_eq!(
        after_first["events"][1]["state_event"]["text"]["char_len"],
        1
    );
}

#[test]
fn multi_document_workspace_edit_transaction_undo_is_multilevel() {
    let mut multi = MultiDocumentEditorUi::new();
    let tab = multi.open_tab("abc\n", 80);
    multi
        .set_tab_document_uri(tab, Some("file:///project/main.txt".to_string()))
        .unwrap();

    let first_edit = r#"{
      "changes": {
        "file:///project/main.txt": [
          {
            "range": {
              "start": { "line": 0, "character": 1 },
              "end": { "line": 0, "character": 2 }
            },
            "newText": "B"
          }
        ]
      }
    }"#;
    let first_result = multi.apply_workspace_edit_transaction(first_edit).unwrap();
    assert!(first_result.applied);
    assert_eq!(multi.tab_text(tab).unwrap(), "aBc\n");

    let second_edit = r#"{
      "changes": {
        "file:///project/main.txt": [
          {
            "range": {
              "start": { "line": 0, "character": 2 },
              "end": { "line": 0, "character": 3 }
            },
            "newText": "C"
          }
        ]
      }
    }"#;
    let second_result = multi.apply_workspace_edit_transaction(second_edit).unwrap();
    assert!(second_result.applied);
    assert_eq!(multi.tab_text(tab).unwrap(), "aBC\n");
    assert_eq!(multi.workspace_edit_transaction_events_latest_sequence(), 2);

    let second_undo = multi.undo_last_workspace_edit_transaction().unwrap();
    assert!(second_undo.undone);
    assert_eq!(multi.tab_text(tab).unwrap(), "aBc\n");

    let first_undo = multi.undo_last_workspace_edit_transaction().unwrap();
    assert!(first_undo.undone);
    assert_eq!(multi.tab_text(tab).unwrap(), "abc\n");

    let unavailable = multi.undo_last_workspace_edit_transaction().unwrap();
    assert!(!unavailable.undone);
}

#[test]
fn multi_document_state_events_aggregate_derived_state_events() {
    let mut multi = MultiDocumentEditorUi::new();
    let tab = multi.open_tab("abc\n", 80);

    multi
        .active_editor_mut()
        .unwrap()
        .lsp_apply_publish_diagnostics_json(
            r#"{
              "uri": "file:///tmp/main.rs",
              "diagnostics": [
                {
                  "range": {
                    "start": { "line": 0, "character": 0 },
                    "end": { "line": 0, "character": 1 }
                  },
                  "severity": 2,
                  "message": "unit"
                }
              ],
              "version": 1
            }"#,
        )
        .unwrap();

    let snapshot = multi.state_events_after(0);
    assert_eq!(snapshot.latest_sequence, 1);
    assert_eq!(snapshot.events.len(), 1);
    assert_eq!(snapshot.events[0].tab_id, tab.get());
    assert_eq!(snapshot.events[0].view_index, 0);
    assert_eq!(snapshot.events[0].kind, "derived_state_changed");
    assert_eq!(snapshot.events[0].family, "derived_state");
    let derived = snapshot.events[0]
        .state_event
        .derived_state
        .as_ref()
        .unwrap();
    assert_eq!(derived.status, "changed");
    assert_eq!(derived.families, vec!["style_intervals", "diagnostics"]);

    let json: serde_json::Value =
        serde_json::from_str(&multi.state_events_json(0).unwrap()).unwrap();
    assert_eq!(json["events"][0]["kind"], "derived_state_changed");
    assert_eq!(
        json["events"][0]["state_event"]["derived_state"]["families"][1],
        "diagnostics"
    );
}

#[test]
fn multi_document_state_events_aggregate_layout_events() {
    let mut multi = MultiDocumentEditorUi::new();
    let tab = multi.open_tab("abc", 80);

    {
        let editor = multi.active_editor_mut().unwrap();
        editor.set_render_metrics(15.0, 22.0, 11.0, 2.0, 3.0);
    }

    let snapshot = multi.state_events_after(0);
    assert_eq!(snapshot.latest_sequence, 1);
    assert_eq!(snapshot.events.len(), 1);
    assert_eq!(snapshot.events[0].tab_id, tab.get());
    assert_eq!(snapshot.events[0].view_index, 0);
    assert_eq!(snapshot.events[0].kind, "layout_changed");
    let layout = snapshot.events[0].state_event.layout.as_ref().unwrap();
    assert_eq!(layout.font_size, 15.0);
    assert_eq!(layout.line_height_px, 22.0);
    assert_eq!(layout.cell_width_px, 11.0);
    assert_eq!(layout.padding_x_px, 2.0);
    assert_eq!(layout.padding_y_px, 3.0);

    let json: serde_json::Value =
        serde_json::from_str(&multi.state_events_json(0).unwrap()).unwrap();
    assert_eq!(json["latest_sequence"], 1);
    assert_eq!(json["events"][0]["kind"], "layout_changed");
    assert_eq!(
        json["events"][0]["state_event"]["layout"]["font_size"],
        15.0
    );
}

#[test]
fn multi_document_state_events_aggregate_viewport_events() {
    let mut multi = MultiDocumentEditorUi::new();
    let tab = multi.open_tab("one\ntwo\nthree\nfour", 80);

    {
        let editor = multi.active_editor_mut().unwrap();
        editor.set_render_metrics(10.0, 10.0, 10.0, 0.0, 0.0);
        editor.set_viewport_px(80, 20, 1.0).unwrap();
    }
    let baseline = multi.state_events_after(0).latest_sequence;

    {
        let editor = multi.active_editor_mut().unwrap();
        editor.set_smooth_scroll_state(1, 0);
    }

    let snapshot = multi.state_events_after(baseline);
    assert_eq!(snapshot.events.len(), 1);
    assert_eq!(
        snapshot
            .events
            .iter()
            .map(|event| (event.tab_id, event.kind.as_str(), event.family.as_str()))
            .collect::<Vec<_>>(),
        vec![(tab.get(), "viewport_changed", "document")]
    );
    assert_eq!(snapshot.events[0].view_index, 0);
    assert_eq!(
        snapshot.events[0]
            .state_event
            .viewport
            .as_ref()
            .unwrap()
            .scroll_top,
        1
    );

    let json: serde_json::Value =
        serde_json::from_str(&multi.state_events_json(baseline).unwrap()).unwrap();
    assert_eq!(json["latest_sequence"], snapshot.latest_sequence);
    assert_eq!(json["events"].as_array().unwrap().len(), 1);
    assert_eq!(json["events"][0]["kind"], "viewport_changed");
    assert_eq!(
        json["events"][0]["state_event"]["viewport"]["scroll_top"],
        1
    );
}

#[test]
fn lsp_processing_edit_apply_failure_records_status_and_returns_error() {
    let ui = EditorUi::new("abc", 80);
    let view_id = ui.view_id;

    let err = {
        let mut doc = ui.lock_doc();
        doc.lsp_last_cmd = Some("fake-lsp".to_string());
        let buffer_id = doc.buffer_id;
        doc.ws.close_buffer(buffer_id).unwrap();
        doc.apply_lsp_processing_edits(view_id, [ProcessingEdit::ClearDiagnostics])
            .unwrap_err()
    };

    let UiError::Processor(message) = err else {
        panic!("expected processor error");
    };
    assert!(
        message.contains("failed to apply LSP processing edits"),
        "unexpected error message: {message}"
    );

    let status: serde_json::Value = serde_json::from_str(ui.lsp_status_json().as_str()).unwrap();
    assert_eq!(status["availability"], "failed");
    assert_eq!(status["state"], "failed");
    assert!(
        status["detail"]
            .as_str()
            .is_some_and(|detail| detail.contains("failed to apply LSP processing edits")),
        "unexpected LSP status: {status}"
    );
}

#[test]
fn poll_processing_reports_lsp_failure_without_applied_success() {
    let mut ui = EditorUi::new("abc", 80);
    {
        let mut doc = ui.lock_doc();
        doc.lsp_last_cmd = Some("fake-lsp".to_string());
        doc.lsp_document_uri = Some("file:///test.rs".to_string());
        doc.lsp = Some(Arc::new(SharedLspSession {
            cmd: "fake-lsp".to_string(),
            args: Vec::new(),
            root_uris: Mutex::new(std::collections::BTreeSet::new()),
            session: Mutex::new(None),
        }));
    }

    let result = ui.poll_processing().unwrap();
    assert!(!result.applied);
    assert!(!result.pending);

    let status: serde_json::Value = serde_json::from_str(ui.lsp_status_json().as_str()).unwrap();
    assert_eq!(status["availability"], "failed");
    assert!(
        status["detail"]
            .as_str()
            .is_some_and(|detail| detail.contains("LSP session is not available")),
        "unexpected LSP status: {status}"
    );

    let events = ui.state_events_after(0);
    assert_eq!(events.events.len(), 1);
    assert_eq!(events.events[0].kind, "lsp_status_changed");
    assert_eq!(
        events.events[0].lsp_status.as_ref().unwrap()["availability"],
        "failed"
    );
    assert!(
        events.events[0].lsp_status.as_ref().unwrap()["detail"]
            .as_str()
            .is_some_and(|detail| detail.contains("LSP session is not available")),
        "unexpected LSP status event: {:?}",
        events.events[0].lsp_status
    );
}

#[test]
fn flush_did_change_failure_records_lsp_status_event() {
    let mut ui = EditorUi::new("abc", 80);
    {
        let mut doc = ui.lock_doc();
        doc.lsp_last_cmd = Some("fake-lsp".to_string());
        doc.lsp_document_uri = Some("file:///test.rs".to_string());
        doc.lsp_delta_calc = Some(editor_core_lsp::DeltaCalculator::from_text("abc"));
        doc.lsp = Some(Arc::new(SharedLspSession {
            cmd: "fake-lsp".to_string(),
            args: Vec::new(),
            root_uris: Mutex::new(std::collections::BTreeSet::new()),
            session: Mutex::new(None),
        }));
    }

    ui.insert_text("d").unwrap();
    ui.flush_lsp_did_change_from_delta();

    let status: serde_json::Value = serde_json::from_str(ui.lsp_status_json().as_str()).unwrap();
    assert_eq!(status["availability"], "failed");
    assert!(
        status["detail"]
            .as_str()
            .is_some_and(|detail| detail.contains("LSP session is not available")),
        "unexpected LSP status: {status}"
    );

    let events = ui.state_events_after(0);
    let status_event = events
        .events
        .iter()
        .find(|event| event.kind == "lsp_status_changed")
        .expect("expected lsp_status_changed event");
    assert_eq!(
        status_event.lsp_status.as_ref().unwrap()["availability"],
        "failed"
    );
    assert!(
        status_event.lsp_status.as_ref().unwrap()["detail"]
            .as_str()
            .is_some_and(|detail| detail.contains("LSP session is not available")),
        "unexpected LSP status event: {:?}",
        status_event.lsp_status
    );
}

#[test]
fn on_type_formatting_response_error_records_lsp_status() {
    let mut ui = EditorUi::new("abc", 80);
    let request_id = 42;
    let view_id = ui.view_id;
    {
        let mut doc = ui.lock_doc();
        doc.lsp_last_cmd = Some("fake-lsp".to_string());
        let version = doc.text_version;
        doc.lsp_client_requests.insert(
            request_id,
            LspClientRequest::OnTypeFormatting {
                view: view_id,
                version,
            },
        );
        doc.lsp_latest_on_type_formatting_request_id
            .insert(view_id, request_id);
        doc.record_lsp_request_started(view_id, LspResultSlot::OnTypeFormatting, request_id);
    }

    let applied = ui
        .handle_lsp_events(vec![LspEvent::Response(editor_core_lsp::LspResponse {
            id: request_id,
            method: "textDocument/onTypeFormatting".to_string(),
            uri: None,
            result: None,
            error: Some(LspResponseError {
                code: -32603,
                message: "formatter exploded".to_string(),
                data: None,
            }),
        })])
        .unwrap();
    assert!(!applied);

    let status: serde_json::Value = serde_json::from_str(ui.lsp_status_json().as_str()).unwrap();
    assert_eq!(status["availability"], "failed");
    assert_eq!(status["state"], "failed");
    assert!(
        status["detail"].as_str().is_some_and(|detail| {
            detail.contains("LSP on-type formatting failed")
                && detail.contains("formatter exploded")
                && detail.contains("-32603")
        }),
        "unexpected LSP status: {status}"
    );

    let events = ui.lsp_request_events_after(0);
    assert_eq!(events.latest_sequence, 2);
    assert_eq!(events.events.len(), 2);
    assert_eq!(events.events[0].family, "formatting");
    assert_eq!(events.events[0].slot, "on_type_formatting");
    assert_eq!(events.events[0].phase, "started");
    assert_eq!(events.events[0].status, "pending");
    assert_eq!(events.events[1].family, "formatting");
    assert_eq!(events.events[1].slot, "on_type_formatting");
    assert_eq!(events.events[1].phase, "completed");
    assert_eq!(events.events[1].status, "error");
    assert_eq!(events.events[1].error_code, Some(-32603));
    assert_eq!(
        events.events[1].error_message.as_deref(),
        Some("formatter exploded")
    );

    let state_events = ui.state_events_after(0);
    let status_event = state_events
        .events
        .iter()
        .find(|event| event.kind == "lsp_status_changed")
        .expect("expected lsp_status_changed event");
    assert_eq!(
        status_event.lsp_status.as_ref().unwrap()["availability"],
        "failed"
    );
    assert!(
        status_event.lsp_status.as_ref().unwrap()["detail"]
            .as_str()
            .is_some_and(|detail| {
                detail.contains("LSP on-type formatting failed")
                    && detail.contains("formatter exploded")
                    && detail.contains("-32603")
            }),
        "unexpected LSP status event: {:?}",
        status_event.lsp_status
    );
}

#[test]
fn on_type_formatting_response_records_empty_and_stale_request_events() {
    let mut ui = EditorUi::new("abc", 80);
    let view_id = ui.view_id;
    {
        let mut doc = ui.lock_doc();
        let version = doc.text_version;
        doc.lsp_client_requests.insert(
            51,
            LspClientRequest::OnTypeFormatting {
                view: view_id,
                version,
            },
        );
        doc.lsp_latest_on_type_formatting_request_id
            .insert(view_id, 51);
        doc.record_lsp_request_started(view_id, LspResultSlot::OnTypeFormatting, 51);
    }

    let applied = ui
        .handle_lsp_events(vec![LspEvent::Response(editor_core_lsp::LspResponse {
            id: 51,
            method: "textDocument/onTypeFormatting".to_string(),
            uri: None,
            result: None,
            error: None,
        })])
        .unwrap();
    assert!(!applied);

    {
        let mut doc = ui.lock_doc();
        let version = doc.text_version;
        doc.lsp_client_requests.insert(
            52,
            LspClientRequest::OnTypeFormatting {
                view: view_id,
                version,
            },
        );
        doc.lsp_latest_on_type_formatting_request_id
            .insert(view_id, 53);
        doc.record_lsp_request_started(view_id, LspResultSlot::OnTypeFormatting, 52);
    }

    let applied = ui
        .handle_lsp_events(vec![LspEvent::Response(editor_core_lsp::LspResponse {
            id: 52,
            method: "textDocument/onTypeFormatting".to_string(),
            uri: None,
            result: Some(serde_json::json!([])),
            error: None,
        })])
        .unwrap();
    assert!(!applied);

    let events = ui.lsp_request_events_after(0);
    assert_eq!(events.latest_sequence, 4);
    assert_eq!(events.events.len(), 4);
    assert_eq!(events.events[0].status, "pending");
    assert_eq!(events.events[1].phase, "completed");
    assert_eq!(events.events[1].status, "empty");
    assert_eq!(events.events[1].result_sequence, None);
    assert_eq!(events.events[2].status, "pending");
    assert_eq!(events.events[3].phase, "completed");
    assert_eq!(events.events[3].status, "stale");
    assert_eq!(events.events[3].result_sequence, None);
}

#[test]
fn lsp_status_reports_signature_help_trigger_characters() {
    let capture_path = unique_temp_path("signature-help-status");
    let capabilities = serde_json::json!({
        "signatureHelpProvider": {
            "triggerCharacters": ["(", ","],
            "retriggerCharacters": [")"]
        }
    });
    let script = lsp_capture_server_script(&capture_path, capabilities);
    let args = vec!["-c".to_string(), script];
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root_uri = format!("file:///tmp/editor-core-ui-signature-help-{stamp}");
    let doc_uri = format!("{root_uri}/main.rs");

    let mut ui = EditorUi::new("fn main() {}", 80);
    ui.lsp_enable_stdio("/bin/sh", &args, &root_uri, &doc_uri, "rust")
        .unwrap();

    let status: serde_json::Value = serde_json::from_str(ui.lsp_status_json().as_str()).unwrap();
    assert_eq!(status["capabilities"]["signature_help"]["supported"], true);
    assert_eq!(
        status["capabilities"]["signature_help"]["trigger_characters"],
        serde_json::json!(["(", ","])
    );
    assert_eq!(
        status["capabilities"]["signature_help"]["retrigger_characters"],
        serde_json::json!([")"])
    );

    ui.lsp_disable();
    let _ = std::fs::remove_file(capture_path);
}

#[test]
fn lsp_status_reports_completion_trigger_characters() {
    let capture_path = unique_temp_path("completion-status");
    let capabilities = serde_json::json!({
        "completionProvider": {
            "triggerCharacters": [".", "/"],
            "allCommitCharacters": [";"]
        }
    });
    let script = lsp_capture_server_script(&capture_path, capabilities);
    let args = vec!["-c".to_string(), script];
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root_uri = format!("file:///tmp/editor-core-ui-completion-{stamp}");
    let doc_uri = format!("{root_uri}/main.rs");

    let mut ui = EditorUi::new("fn main() {}", 80);
    ui.lsp_enable_stdio("/bin/sh", &args, &root_uri, &doc_uri, "rust")
        .unwrap();

    let status: serde_json::Value = serde_json::from_str(ui.lsp_status_json().as_str()).unwrap();
    assert_eq!(status["capabilities"]["completion"]["supported"], true);
    assert_eq!(
        status["capabilities"]["completion"]["trigger_characters"],
        serde_json::json!([".", "/"])
    );
    assert_eq!(
        status["capabilities"]["completion"]["all_commit_characters"],
        serde_json::json!([";"])
    );

    ui.lsp_disable();
    let _ = std::fs::remove_file(capture_path);
}

#[test]
fn ui_lsp_on_type_formatting_triggers_for_server_declared_single_chars() {
    let capture_path = unique_temp_path("on-type-formatting");
    let capabilities = serde_json::json!({
        "documentOnTypeFormattingProvider": {
            "firstTriggerCharacter": ";",
            "moreTriggerCharacter": ["}"]
        }
    });
    let script = lsp_capture_server_script(&capture_path, capabilities);
    let args = vec!["-c".to_string(), script];
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root_uri = format!("file:///tmp/editor-core-ui-on-type-{stamp}");
    let doc_uri = format!("{root_uri}/main.rs");

    let mut ui = EditorUi::new("let value = 1", 80);
    ui.lsp_enable_stdio("/bin/sh", &args, &root_uri, &doc_uri, "rust")
        .unwrap();

    ui.paste_text(";").unwrap();
    std::thread::sleep(std::time::Duration::from_millis(80));
    let captured_after_paste = captured_lsp_stdin(&capture_path);
    assert!(
        !captured_after_paste.contains("textDocument/onTypeFormatting"),
        "paste_text must not trigger on-type formatting; captured: {captured_after_paste}"
    );

    ui.insert_text("a").unwrap();
    std::thread::sleep(std::time::Duration::from_millis(80));
    let captured_after_non_trigger = captured_lsp_stdin(&capture_path);
    assert!(
        !captured_after_non_trigger.contains("textDocument/onTypeFormatting"),
        "non-trigger typing must not request on-type formatting; captured: {captured_after_non_trigger}"
    );

    ui.insert_text(";").unwrap();
    let captured = wait_for_captured_lsp_stdin(&capture_path, "textDocument/onTypeFormatting");
    assert!(
        captured.contains("\"ch\":\";\""),
        "on-type formatting request should carry trigger ';'; captured: {captured}"
    );

    ui.lsp_disable();
    let _ = std::fs::remove_file(capture_path);
}

#[test]
fn ui_lsp_on_type_formatting_can_be_disabled() {
    let capture_path = unique_temp_path("on-type-formatting-disabled");
    let capabilities = serde_json::json!({
        "documentOnTypeFormattingProvider": {
            "firstTriggerCharacter": ";",
            "moreTriggerCharacter": ["}"]
        }
    });
    let script = lsp_capture_server_script(&capture_path, capabilities);
    let args = vec!["-c".to_string(), script];
    let stamp = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap()
        .as_nanos();
    let root_uri = format!("file:///tmp/editor-core-ui-on-type-disabled-{stamp}");
    let doc_uri = format!("{root_uri}/main.rs");

    let mut ui = EditorUi::new("let value = 1", 80);
    ui.lsp_enable_stdio("/bin/sh", &args, &root_uri, &doc_uri, "rust")
        .unwrap();
    ui.set_lsp_on_type_formatting_enabled(false).unwrap();

    ui.insert_text(";").unwrap();
    let captured = wait_for_captured_lsp_stdin(&capture_path, "textDocument/didChange");
    assert!(
        captured.contains("textDocument/didChange"),
        "disabled on-type formatting must still sync typed text to LSP; captured: {captured}"
    );
    assert!(
        !captured.contains("textDocument/onTypeFormatting"),
        "disabled on-type formatting must not request LSP on-type formatting; captured: {captured}"
    );

    ui.set_lsp_on_type_formatting_enabled(true).unwrap();
    ui.insert_text("}").unwrap();
    let captured_after_enable =
        wait_for_captured_lsp_stdin(&capture_path, "textDocument/onTypeFormatting");
    assert!(
        captured_after_enable.contains("\"ch\":\"}\""),
        "re-enabled on-type formatting should carry trigger '}}'; captured: {captured_after_enable}"
    );

    ui.lsp_disable();
    let _ = std::fs::remove_file(capture_path);
}

#[test]
fn poll_processing_reports_treesitter_worker_disconnected() {
    let mut ui = EditorUi::new("fn main() {}", 80);
    let (tx_worker, rx_worker) = mpsc::channel::<TreeSitterWorkerMsg>();
    drop(rx_worker);
    let (tx_events, rx_events) = mpsc::channel::<TreeSitterWorkerEvent>();
    drop(tx_events);

    {
        let mut doc = ui.lock_doc();
        doc.treesitter = Some(TreeSitterAsyncWorker {
            tx: tx_worker,
            rx: rx_events,
            join: None,
            requested_version: Some(1),
            applied_version: None,
            last_update_mode: None,
        });
    }

    let err = ui.poll_processing().unwrap_err();
    let UiError::Processor(message) = err else {
        panic!("expected processor error");
    };
    assert!(
        message.contains("tree-sitter worker disconnected"),
        "unexpected error message: {message}"
    );
}

#[test]
fn ui_text_roundtrip() {
    let ui = EditorUi::new("hello", 80);
    assert_eq!(ui.text(), "hello");
}

#[test]
fn ui_clone_view_shares_text_but_keeps_view_state_independent() {
    let mut ui1 = EditorUi::new("abc\ndef\n", 80);
    let mut ui2 = ui1.clone_view(80).unwrap();

    ui1.set_selections_offsets(&[(0, 0)], 0).unwrap();
    ui2.set_selections_offsets(&[(4, 4)], 0).unwrap();
    assert_eq!(ui1.primary_selection_offsets(), (0, 0));
    assert_eq!(ui2.primary_selection_offsets(), (4, 4));

    // Text edits are shared across views.
    ui1.insert_text("X").unwrap();
    assert_eq!(ui1.text(), "Xabc\ndef\n");
    assert_eq!(ui2.text(), "Xabc\ndef\n");

    // Each view tracks its own caret/selection, but receives the same text delta.
    assert_eq!(ui1.primary_selection_offsets(), (1, 1));
    assert_eq!(ui2.primary_selection_offsets(), (5, 5));

    // Cursor moves in one view do not affect the other view.
    ui1.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 0,
        column: 0,
    }))
    .unwrap();
    assert_eq!(ui1.cursor_state().offset, 0);
    assert_eq!(ui2.cursor_state().offset, 5);
}

#[test]
fn ui_clone_view_has_independent_scroll_state() {
    let text = (0..200)
        .map(|i| format!("line {i}"))
        .collect::<Vec<_>>()
        .join("\n");
    let mut ui1 = EditorUi::new(text.as_str(), 80);
    let mut ui2 = ui1.clone_view(80).unwrap();

    ui1.set_render_metrics(14.0, 10.0, 8.0, 0.0, 0.0);
    ui2.set_render_metrics(14.0, 10.0, 8.0, 0.0, 0.0);
    ui1.set_viewport_px(800, 50, 1.0).unwrap(); // 5 rows visible
    ui2.set_viewport_px(800, 50, 1.0).unwrap();

    ui1.set_smooth_scroll_state(10, 0);
    ui2.set_smooth_scroll_state(20, 0);

    assert_eq!(ui1.viewport_state().scroll_top, 10);
    assert_eq!(ui2.viewport_state().scroll_top, 20);
}

#[test]
fn ui_insert_and_delete() {
    let mut ui = EditorUi::new("", 80);
    ui.insert_text("abc").unwrap();
    assert_eq!(ui.text(), "abc");
    ui.backspace().unwrap();
    assert_eq!(ui.text(), "ab");
    ui.delete_forward().unwrap(); // no-op at end
    assert_eq!(ui.text(), "ab");
}

#[test]
fn ui_move_visual_by_rows_collapses_selection_to_caret() {
    let mut ui = EditorUi::new("aaa\nbbb\nccc", 80);

    // Select "bbb" (offset 4..7). This also places the caret at the active end (offset 7).
    ui.set_selections_offsets(&[(4, 7)], 0).unwrap();
    assert!(ui.cursor_state().selection.is_some());
    assert_eq!(ui.cursor_state().offset, 7);

    // Move up: should first clear selection (caret stays at 7), then move to line 0 col 3 => offset 3.
    ui.move_visual_by_rows(-1).unwrap();
    assert!(ui.cursor_state().selection.is_none());
    assert_eq!(ui.primary_selection_offsets(), (3, 3));

    // Re-create selection and move down: should clear selection, then move to line 2 col 3 => offset 11.
    ui.set_selections_offsets(&[(4, 7)], 0).unwrap();
    ui.move_visual_by_rows(1).unwrap();
    assert!(ui.cursor_state().selection.is_none());
    assert_eq!(ui.primary_selection_offsets(), (11, 11));
}

#[test]
fn ui_keyboard_navigation_scrolls_to_keep_caret_visible() {
    let mut ui = EditorUi::new("0\n1\n2\n3\n4\n5\n", 80);
    ui.set_render_config(RenderConfig {
        width_px: 80,
        height_px: 20, // 2 rows at 10px line height
        cell_width_px: 10.0,
        line_height_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(80, 20, 1.0).unwrap();

    let vp0 = ui.viewport_state();
    assert_eq!(vp0.height, Some(2));
    assert_eq!(vp0.scroll_top, 0);

    // Move down within the viewport: no scroll.
    ui.move_visual_by_rows(1).unwrap();
    let vp1 = ui.viewport_state();
    assert_eq!(vp1.scroll_top, 0);

    // Move down out of the viewport: scroll should advance.
    ui.move_visual_by_rows(1).unwrap();
    let vp2 = ui.viewport_state();
    assert_eq!(vp2.scroll_top, 1);
    assert_eq!(vp2.sub_row_offset, 0);

    // Jump to end: viewport should scroll so caret stays visible.
    ui.move_to_document_end().unwrap();
    let vp3 = ui.viewport_state();
    let caret_off = ui.cursor_state().offset;
    let (caret_row, _caret_x) = ui.char_offset_to_visual(caret_off).unwrap();
    let h = vp3.height.unwrap_or(1);
    assert!(
        caret_row >= vp3.scroll_top && caret_row < vp3.scroll_top.saturating_add(h),
        "expected caret row to be within visible lines after navigation"
    );
}

#[test]
fn ui_insert_text_scrolls_to_keep_caret_visible() {
    let mut ui = EditorUi::new("", 80);
    ui.set_render_config(RenderConfig {
        width_px: 80,
        height_px: 20, // 2 rows at 10px line height
        cell_width_px: 10.0,
        line_height_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(80, 20, 1.0).unwrap();

    // Pasting multi-line text should scroll so the caret stays visible.
    let mut s = String::new();
    for _ in 0..200 {
        s.push_str("x\n");
    }
    ui.insert_text(&s).unwrap();

    let vp = ui.viewport_state();
    let caret_off = ui.cursor_state().offset;
    let (caret_row, _caret_x) = ui.char_offset_to_visual(caret_off).unwrap();
    let h = vp.height.unwrap_or(1);
    assert!(
        caret_row >= vp.scroll_top && caret_row < vp.scroll_top.saturating_add(h),
        "expected caret row to be within visible lines after paste/insert"
    );
    assert!(
        vp.scroll_top > 0,
        "expected viewport to scroll for multi-line insert"
    );
}

#[test]
fn ui_insert_text_does_not_snap_smooth_scroll_when_caret_visible() {
    let mut ui = EditorUi::new("", 80);
    ui.set_render_config(RenderConfig {
        width_px: 80,
        height_px: 20,
        cell_width_px: 10.0,
        line_height_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(80, 20, 1.0).unwrap();

    ui.set_smooth_scroll_state(0, 12345);
    ui.insert_text("a").unwrap();

    let vp = ui.viewport_state();
    assert_eq!(vp.scroll_top, 0);
}

#[test]
fn ui_undo_redo_scrolls_to_keep_caret_visible() {
    // Long document so `scroll_top` can remain > 0 after undo/redo (i.e. not clamped away).
    let doc = (0..200)
        .map(|i| i.to_string())
        .collect::<Vec<_>>()
        .join("\n");
    let mut ui = EditorUi::new(&doc, 80);
    ui.set_render_config(RenderConfig {
        width_px: 80,
        height_px: 20, // 2 rows at 10px line height
        cell_width_px: 10.0,
        line_height_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(80, 20, 1.0).unwrap();

    // Make a small edit near the top so undo/redo moves the caret to row 0.
    ui.insert_text("!").unwrap();

    // Manually scroll away from the caret (simulates the user having scrolled elsewhere).
    let vp = ui.viewport_state();
    let total = vp.total_visual_lines.max(1);
    let visible = vp.height.unwrap_or(total).max(1);
    let bottom = total.saturating_sub(visible);
    ui.set_smooth_scroll_state(bottom, 0);
    assert!(
        ui.viewport_state().scroll_top > 0,
        "expected manual scroll to move viewport away from caret"
    );

    // Undo should scroll back to keep caret visible.
    ui.undo().unwrap();
    assert_eq!(ui.viewport_state().scroll_top, 0);

    // Redo should also scroll back if we're scrolled away again.
    ui.set_smooth_scroll_state(bottom, 0);
    assert!(ui.viewport_state().scroll_top > 0);
    ui.redo().unwrap();
    assert_eq!(ui.viewport_state().scroll_top, 0);
}

#[test]
fn ui_set_smooth_scroll_state_clamps_and_updates_viewport_state() {
    let mut ui = EditorUi::new("0\n1\n2\n3\n4\n5\n6\n7", 80);
    ui.set_render_config(RenderConfig {
        width_px: 80,
        height_px: 20, // 2 rows at 10px line height
        cell_width_px: 10.0,
        line_height_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(80, 20, 1.0).unwrap();

    let vp0 = ui.viewport_state();
    assert_eq!(vp0.height, Some(2));
    assert_eq!(vp0.total_visual_lines, 8);

    // Set a fractional scroll position (3 + 0.5 rows).
    ui.set_smooth_scroll_state(3, 32768);
    let vp1 = ui.viewport_state();
    assert_eq!(vp1.scroll_top, 3);
    assert_eq!(vp1.sub_row_offset, 32768);

    // Clamp to the maximum scroll position (total - height = 6).
    ui.set_smooth_scroll_state(999, 65535);
    let vp2 = ui.viewport_state();
    assert_eq!(vp2.scroll_top, 6);
    assert_eq!(vp2.sub_row_offset, 0);
}

#[test]
fn ui_backspace_and_delete_forward_are_grapheme_aware() {
    // "á" = 'a' + COMBINING ACUTE ACCENT (2 Unicode scalar values, 1 grapheme cluster).
    let s = "a\u{0301}";

    // Backspace at end should delete the whole grapheme cluster.
    let mut ui = EditorUi::new(s, 80);
    ui.set_selections_offsets(&[(2, 2)], 0).unwrap(); // caret at end (scalar offset 2)
    ui.backspace().unwrap();
    assert_eq!(ui.text(), "");

    // Delete-forward at start should also delete the whole grapheme cluster.
    let mut ui2 = EditorUi::new(s, 80);
    ui2.set_selections_offsets(&[(0, 0)], 0).unwrap(); // caret at start
    ui2.delete_forward().unwrap();
    assert_eq!(ui2.text(), "");
}

#[test]
fn ui_auto_pairs_auto_close_skip_over_and_delete_pair_work_when_enabled() {
    let mut ui = EditorUi::new("", 80);
    ui.set_auto_pairs_enabled(true).unwrap();

    ui.commit_text("(").unwrap();
    assert_eq!(ui.text(), "()");
    assert_eq!(ui.primary_selection_offsets(), (1, 1));

    // Skip-over closing delimiter.
    ui.commit_text(")").unwrap();
    assert_eq!(ui.text(), "()");
    assert_eq!(ui.primary_selection_offsets(), (2, 2));

    // Delete-pair via UI backspace (grapheme-aware fallback + pair special-case).
    ui.set_selections_offsets(&[(1, 1)], 0).unwrap();
    ui.backspace().unwrap();
    assert_eq!(ui.text(), "");
    assert_eq!(ui.primary_selection_offsets(), (0, 0));
}

#[test]
fn ui_paste_text_does_not_trigger_auto_pairs_rules() {
    let mut ui = EditorUi::new("", 80);
    ui.set_auto_pairs_enabled(true).unwrap();

    ui.paste_text("(").unwrap();
    assert_eq!(ui.text(), "(");
    assert_eq!(ui.primary_selection_offsets(), (1, 1));
}

#[test]
fn ui_clone_view_preserves_auto_pairs_config() {
    let mut ui = EditorUi::new("", 80);
    ui.set_auto_pairs_enabled(true).unwrap();

    let mut cloned = ui.clone_view(80).unwrap();
    cloned.commit_text("(").unwrap();

    assert_eq!(cloned.text(), "()");
    assert_eq!(cloned.primary_selection_offsets(), (1, 1));
}

#[test]
fn ui_clone_view_preserves_bracket_match_highlights_enabled() {
    let mut ui = EditorUi::new("(a)", 80);
    ui.set_bracket_match_highlights_enabled(true).unwrap();

    let mut cloned = ui.clone_view(80).unwrap();
    cloned.set_selections_offsets(&[(1, 1)], 0).unwrap();

    let grid = {
        let mut doc = cloned.lock_doc();
        doc.ws
            .get_viewport_content_styled(cloned.view_id, 0, 1)
            .unwrap()
    };
    let styles_at_open = grid
        .lines
        .first()
        .and_then(|l| l.cells.first())
        .map(|c| c.styles.clone())
        .unwrap_or_default();
    let styles_at_close = grid
        .lines
        .first()
        .and_then(|l| l.cells.get(2))
        .map(|c| c.styles.clone())
        .unwrap_or_default();

    assert!(
        styles_at_open.contains(&MATCH_HIGHLIGHT_STYLE_ID),
        "expected opening bracket to have MATCH_HIGHLIGHT_STYLE_ID"
    );
    assert!(
        styles_at_close.contains(&MATCH_HIGHLIGHT_STYLE_ID),
        "expected closing bracket to have MATCH_HIGHLIGHT_STYLE_ID"
    );
}

#[test]
fn ui_clone_view_preserves_lsp_on_type_formatting_enabled() {
    let mut ui = EditorUi::new("", 80);
    ui.set_lsp_on_type_formatting_enabled(false).unwrap();

    let cloned = ui.clone_view(80).unwrap();

    assert!(!cloned.lsp_on_type_formatting_enabled());
}

#[test]
fn ui_bracket_match_highlights_apply_match_style_to_brackets() {
    let mut ui = EditorUi::new("(a)", 80);
    ui.set_bracket_match_highlights_enabled(true).unwrap();

    // Place caret between '(' and 'a' so the match is unambiguous.
    ui.set_selections_offsets(&[(1, 1)], 0).unwrap();

    let grid = {
        let mut doc = ui.lock_doc();
        doc.ws
            .get_viewport_content_styled(ui.view_id, 0, 1)
            .unwrap()
    };
    let styles_at_open = grid
        .lines
        .first()
        .and_then(|l| l.cells.first())
        .map(|c| c.styles.clone())
        .unwrap_or_default();
    let styles_at_close = grid
        .lines
        .first()
        .and_then(|l| l.cells.get(2))
        .map(|c| c.styles.clone())
        .unwrap_or_default();

    assert!(
        styles_at_open.contains(&MATCH_HIGHLIGHT_STYLE_ID),
        "expected opening bracket to have MATCH_HIGHLIGHT_STYLE_ID"
    );
    assert!(
        styles_at_close.contains(&MATCH_HIGHLIGHT_STYLE_ID),
        "expected closing bracket to have MATCH_HIGHLIGHT_STYLE_ID"
    );
}

#[test]
fn ui_move_to_matching_bracket_jumps_to_pair() {
    let mut ui = EditorUi::new("(a[b]c)", 80);
    ui.set_selections_offsets(&[(1, 1)], 0).unwrap();
    ui.move_to_matching_bracket().unwrap();
    assert_eq!(ui.primary_selection_offsets(), (6, 6));
}

#[test]
fn ui_selected_text_and_delete_selections_only() {
    let mut ui = EditorUi::new("one two three", 80);

    // Multi-selection: "one" and "three" (skip the caret between them).
    ui.set_selections_offsets(&[(0, 3), (4, 4), (8, 13)], 0)
        .unwrap();
    assert_eq!(ui.selected_text(), "one\nthree");

    // Cut should delete only the non-empty selections.
    ui.delete_selections_only().unwrap();
    assert_eq!(ui.text(), " two ");
    assert_eq!(ui.selected_text(), "");
    assert_eq!(ui.primary_selection_offsets(), (0, 0));

    // With no selection, delete_selections_only is a no-op.
    ui.set_selections_offsets(&[(1, 1)], 0).unwrap();
    ui.delete_selections_only().unwrap();
    assert_eq!(ui.text(), " two ");
}

#[test]
fn ui_word_movement_and_word_deletion() {
    let mut ui = EditorUi::new("one two", 80);

    // Move by word boundaries.
    assert_eq!(ui.primary_selection_offsets(), (0, 0));
    ui.move_word_right().unwrap(); // 0 -> 3 ("one| two")
    assert_eq!(ui.primary_selection_offsets(), (3, 3));
    ui.move_word_right().unwrap(); // 3 -> 4 ("one |two")
    assert_eq!(ui.primary_selection_offsets(), (4, 4));
    ui.move_word_left().unwrap(); // 4 -> 3
    assert_eq!(ui.primary_selection_offsets(), (3, 3));

    // Shift+Option behavior (modify selection).
    ui.set_selections_offsets(&[(0, 0)], 0).unwrap();
    ui.move_word_right_and_modify_selection().unwrap();
    assert_eq!(ui.primary_selection_offsets(), (0, 3));
    ui.move_word_right_and_modify_selection().unwrap();
    assert_eq!(ui.primary_selection_offsets(), (0, 4));

    // Delete word back/forward.
    let mut ui2 = EditorUi::new("one two", 80);
    ui2.set_selections_offsets(&[(7, 7)], 0).unwrap();
    ui2.delete_word_back().unwrap();
    assert_eq!(ui2.text(), "one ");

    let mut ui3 = EditorUi::new("one two", 80);
    ui3.set_selections_offsets(&[(0, 0)], 0).unwrap();
    ui3.delete_word_forward().unwrap();
    assert_eq!(ui3.text(), " two");
}

#[test]
fn ui_line_document_and_page_navigation() {
    let mut ui = EditorUi::new("abc\ndef", 80);

    // Visual line start/end.
    ui.set_selections_offsets(&[(2, 2)], 0).unwrap(); // "ab|c"
    ui.move_to_visual_line_start().unwrap();
    assert_eq!(ui.primary_selection_offsets(), (0, 0));
    ui.move_to_visual_line_end().unwrap();
    assert_eq!(ui.primary_selection_offsets(), (3, 3)); // end of "abc"

    // Document start/end.
    ui.move_to_document_end().unwrap();
    assert_eq!(ui.primary_selection_offsets(), (7, 7)); // end of "def"
    ui.move_to_document_start().unwrap();
    assert_eq!(ui.primary_selection_offsets(), (0, 0));

    // Page movement uses viewport height in rows.
    let mut ui2 = EditorUi::new("0\n1\n2\n3\n4\n5\n6\n7\n8\n9\n", 80);
    ui2.set_render_metrics(12.0, 10.0, 10.0, 0.0, 0.0);
    ui2.set_viewport_px(100, 30, 1.0).unwrap(); // 3 rows

    ui2.set_selections_offsets(&[(0, 0)], 0).unwrap();
    ui2.move_visual_by_pages(1).unwrap();
    assert_eq!(ui2.cursor_state().position.line, 3);

    ui2.move_visual_by_pages(-1).unwrap();
    assert_eq!(ui2.cursor_state().position.line, 0);

    // Shift+PageDown extends selection by pages.
    ui2.set_selections_offsets(&[(0, 0)], 0).unwrap();
    ui2.move_visual_by_pages_and_modify_selection(1).unwrap();
    assert_eq!(ui2.primary_selection_offsets(), (0, 6)); // line 3 start offset = 3 * 2
}

#[test]
fn ui_undo_redo_roundtrip() {
    let mut ui = EditorUi::new("", 80);
    ui.insert_text("a").unwrap();
    ui.end_undo_group().unwrap();
    ui.insert_text("b").unwrap();
    assert_eq!(ui.text(), "ab");
    ui.undo().unwrap();
    assert_eq!(ui.text(), "a");
    ui.redo().unwrap();
    assert_eq!(ui.text(), "ab");
}

#[test]
fn ui_expand_selection_by_word_is_expand_only() {
    let mut ui = EditorUi::new("one two three", 80);
    ui.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 0,
        column: 4,
    }))
    .unwrap(); // at "two"

    ui.expand_selection_by(
        ExpandSelectionUnit::Word,
        1,
        ExpandSelectionDirection::Forward,
    )
    .unwrap();
    assert_eq!(ui.primary_selection_offsets(), (4, 7)); // "two"

    ui.expand_selection_by(
        ExpandSelectionUnit::Word,
        1,
        ExpandSelectionDirection::Forward,
    )
    .unwrap();
    assert_eq!(ui.primary_selection_offsets(), (4, 13)); // "two three"

    ui.expand_selection_by(
        ExpandSelectionUnit::Word,
        1,
        ExpandSelectionDirection::Backward,
    )
    .unwrap();
    assert_eq!(ui.primary_selection_offsets(), (0, 13)); // "one two three"
}

#[test]
fn ui_word_boundary_config_affects_select_word() {
    let mut ui = EditorUi::new("foo-bar", 80);
    ui.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 0,
        column: 1,
    }))
    .unwrap();
    ui.select_word().unwrap();
    assert_eq!(ui.primary_selection_offsets(), (0, 3)); // "foo"

    ui.set_word_boundary_ascii_boundary_chars(".").unwrap();
    ui.execute(Command::Cursor(CursorCommand::ClearSelection))
        .unwrap();
    ui.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 0,
        column: 1,
    }))
    .unwrap();
    ui.select_word().unwrap();
    assert_eq!(ui.primary_selection_offsets(), (0, 7)); // "foo-bar"

    ui.reset_word_boundary_defaults().unwrap();
    ui.execute(Command::Cursor(CursorCommand::ClearSelection))
        .unwrap();
    ui.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 0,
        column: 1,
    }))
    .unwrap();
    ui.select_word().unwrap();
    assert_eq!(ui.primary_selection_offsets(), (0, 3)); // "foo"
}

#[test]
fn ui_word_boundary_config_affects_whole_word_search_highlights() {
    let mut ui = EditorUi::new("foo-bar bar", 80);
    let options = SearchOptions {
        case_sensitive: true,
        whole_word: true,
        regex: false,
    };

    assert_eq!(ui.search_set_query("bar", options).unwrap(), 2);

    ui.set_word_boundary_ascii_boundary_chars(".").unwrap();
    assert_eq!(ui.search_set_query("bar", options).unwrap(), 1);

    ui.reset_word_boundary_defaults().unwrap();
    assert_eq!(ui.search_set_query("bar", options).unwrap(), 2);
}

#[test]
fn ui_marked_text_replace_and_commit() {
    let mut ui = EditorUi::new("", 80);
    ui.set_marked_text("你").unwrap();
    assert_eq!(ui.text(), "你");
    ui.set_marked_text("你好").unwrap();
    assert_eq!(ui.text(), "你好");
    ui.commit_text("你好!").unwrap();
    assert_eq!(ui.text(), "你好!");
}

#[test]
fn ui_marked_text_empty_cancels_and_restores_original_text_and_selection() {
    // Start composition by replacing a selection, then cancel it by setting empty marked text.
    let mut ui = EditorUi::new("abcXYZdef", 80);
    ui.set_marked_text_with_selection("你", 1, 0, Some((3, 3)))
        .unwrap();
    assert_eq!(ui.text(), "abc你def");

    // Cancel: empty marked text should restore the original "XYZ" and selection.
    ui.set_marked_text_with_selection("", 0, 0, None).unwrap();
    assert_eq!(ui.text(), "abcXYZdef");
    assert_eq!(ui.primary_selection_offsets(), (3, 6));

    // Also cover the common case: composition started at a caret (no selection).
    let mut ui2 = EditorUi::new("abc", 80);
    ui2.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 0,
        column: 3,
    }))
    .unwrap();
    ui2.set_marked_text("你").unwrap();
    assert_eq!(ui2.text(), "abc你");
    ui2.set_marked_text("").unwrap();
    assert_eq!(ui2.text(), "abc");
    assert_eq!(ui2.primary_selection_offsets(), (3, 3));
}

#[test]
fn ui_marked_text_honors_selection_and_applies_style_layer() {
    let mut ui = EditorUi::new("", 80);

    // Marked text = "你好", caret inside composition after the first char.
    ui.set_marked_text_with_selection("你好", 1, 0, None)
        .unwrap();
    assert_eq!(ui.text(), "你好");

    // Cursor is at offset 1 => (line 0, column 1).
    assert_eq!(ui.cursor_state().position, Position::new(0, 1));

    let grid = {
        let mut doc = ui.lock_doc();
        doc.ws
            .get_viewport_content_styled(ui.view_id, 0, 1)
            .unwrap()
    };
    assert_eq!(grid.lines.len(), 1);
    assert_eq!(grid.lines[0].cells.len(), 2);
    assert!(
        grid.lines[0].cells[0]
            .styles
            .contains(&IME_MARKED_TEXT_STYLE_ID)
    );
    assert!(
        grid.lines[0].cells[1]
            .styles
            .contains(&IME_MARKED_TEXT_STYLE_ID)
    );

    // Committing clears the marked style layer.
    ui.commit_text("你好!").unwrap();
    let grid2 = {
        let mut doc = ui.lock_doc();
        doc.ws
            .get_viewport_content_styled(ui.view_id, 0, 1)
            .unwrap()
    };
    assert!(
        grid2.lines[0]
            .cells
            .iter()
            .all(|c| !c.styles.contains(&IME_MARKED_TEXT_STYLE_ID)),
        "expected IME marked text style to be cleared after commit"
    );
}

#[test]
fn ui_marked_text_replacement_range_overrides_current_selection() {
    // Replacement range should allow host IME to replace an arbitrary document slice
    // (e.g. when the input method decides to replace a previously inserted segment).
    let mut ui = EditorUi::new("abcXYZdef", 80);

    // Replace "XYZ" with IME marked text "你" (selection at end of marked text).
    ui.set_marked_text_with_selection("你", 1, 0, Some((3, 3)))
        .unwrap();
    assert_eq!(ui.text(), "abc你def");

    let marked = ui.marked_range().unwrap();
    assert_eq!(marked, (3, 1));

    // Commit should replace the marked range (not insert).
    ui.commit_text("你好").unwrap();
    assert_eq!(ui.text(), "abc你好def");
    assert!(ui.marked_range().is_none());
}

#[test]
fn ui_mouse_sets_cursor_and_selection() {
    let mut ui = EditorUi::new("abcd\nefgh\n", 80);
    ui.set_render_config(RenderConfig {
        width_px: 200,
        height_px: 60,
        cell_width_px: 10.0,
        line_height_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(200, 60, 1.0).unwrap();

    // Click near column 2 on first line.
    ui.mouse_down(25.0, 10.0).unwrap();
    assert_eq!(ui.cursor_state().position, Position::new(0, 2));

    // Drag to second line column 1.
    ui.mouse_dragged(15.0, 30.0).unwrap();
    let cursor = ui.cursor_state();
    assert!(cursor.selection.is_some());
    ui.mouse_up();
}

#[test]
fn ui_mouse_drag_selection_keeps_cursor_at_active_end_for_keyboard_moves() {
    let mut ui = EditorUi::new("aaaa\nbbbb\ncccc", 80);
    ui.set_render_config(RenderConfig {
        width_px: 200,
        height_px: 60,
        cell_width_px: 10.0,
        line_height_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(200, 60, 1.0).unwrap();

    // Drag-select within the first line: anchor at col 0, active end at col 3.
    ui.mouse_down(5.0, 10.0).unwrap();
    ui.mouse_dragged(35.0, 10.0).unwrap();

    let s0 = ui.primary_selection_offsets();
    assert_eq!(s0, (0, 3));

    // Now a vertical move should collapse selection to the active end (col 3), not the anchor.
    ui.move_visual_by_rows(1).unwrap();
    let s1 = ui.primary_selection_offsets();
    assert_eq!(s1, (8, 8));
}

#[test]
fn ui_render_includes_caret_overlay() {
    let mut ui = EditorUi::new("abc", 80);
    ui.set_render_config(RenderConfig {
        width_px: 80,
        height_px: 40,
        cell_width_px: 10.0,
        line_height_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_theme(RenderTheme {
        background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
        foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
        selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
        caret: editor_core_render_skia::Rgba8::new(0, 0, 200, 255),
        styles: std::collections::BTreeMap::new(),
        style_fonts: std::collections::BTreeMap::new(),
        text_decorations: std::collections::BTreeMap::new(),
    });
    ui.set_viewport_px(80, 40, 1.0).unwrap();

    // Put caret after 'c' (x=3).
    ui.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 0,
        column: 3,
    }))
    .unwrap();
    let rgba = ui.render_rgba_visible().unwrap();
    assert_eq!(pixel(&rgba, 80, 30, 10), [0, 0, 200, 255]);
    assert_eq!(pixel(&rgba, 80, 70, 30), [10, 20, 30, 255]);
}

#[test]
fn ui_caret_width_and_visibility_affect_render_rgba() {
    let mut ui = EditorUi::new("", 80);
    ui.set_render_config(RenderConfig {
        width_px: 20,
        height_px: 10,
        cell_width_px: 10.0,
        line_height_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_theme(RenderTheme {
        background: editor_core_render_skia::Rgba8::new(0xFF, 0xFF, 0xFF, 0xFF),
        foreground: editor_core_render_skia::Rgba8::new(0x00, 0x00, 0x00, 0xFF),
        selection_background: editor_core_render_skia::Rgba8::new(0xC7, 0xDD, 0xFF, 0xFF),
        caret: editor_core_render_skia::Rgba8::new(0x00, 0x00, 0x00, 0xFF),
        styles: std::collections::BTreeMap::new(),
        style_fonts: std::collections::BTreeMap::new(),
        text_decorations: std::collections::BTreeMap::new(),
    });
    ui.set_viewport_px(20, 10, 1.0).unwrap();

    ui.set_caret_width_px(4.0);
    ui.set_caret_visible(true);
    let rgba0 = ui.render_rgba_visible().unwrap();
    let caret_px = [0x00, 0x00, 0x00, 0xFF];
    let caret_count0 = rgba0.chunks_exact(4).filter(|p| *p == caret_px).count();
    assert_eq!(
        caret_count0,
        4 * 10,
        "expected caret to fill a 4x10 rectangle"
    );

    ui.set_caret_visible(false);
    let rgba1 = ui.render_rgba_visible().unwrap();
    let caret_count1 = rgba1.chunks_exact(4).filter(|p| *p == caret_px).count();
    assert_eq!(
        caret_count1, 0,
        "expected caret pixels to disappear when hidden"
    );
}

#[test]
fn ui_render_includes_partially_visible_bottom_row_even_without_sub_row_offset() {
    // Height is not a multiple of line height: the bottom 5px should still show the next row.
    let mut ui = EditorUi::new("0\n1\n \n", 80);
    ui.set_render_config(RenderConfig {
        width_px: 40,
        height_px: 25,
        cell_width_px: 10.0,
        line_height_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(40, 25, 1.0).unwrap();

    // Theme background fills the whole buffer; a style background lets us detect if the row was rendered.
    ui.set_theme(RenderTheme {
        background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
        foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
        selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
        caret: editor_core_render_skia::Rgba8::new(0, 0, 200, 255),
        styles: std::collections::BTreeMap::new(),
        style_fonts: std::collections::BTreeMap::new(),
        text_decorations: std::collections::BTreeMap::new(),
    });

    let style_id = 0xDEAD_BEEFu32;
    let mut styles = std::collections::BTreeMap::new();
    styles.insert(
        style_id,
        editor_core_render_skia::StyleColors::new(
            None,
            Some(editor_core_render_skia::Rgba8::new(200, 0, 0, 255)),
        ),
    );
    ui.set_style_colors(styles);

    // Style the space in the 3rd line (" \n") so glyph rasterization does not affect the sample.
    // "0\n1\n \n" => the space is at char offset 4.
    ui.add_style(4, 5, style_id).unwrap();

    let rgba = ui.render_rgba_visible().unwrap();
    // The bottom pixel is inside the partially visible 3rd row (y=20..25).
    assert_eq!(pixel(&rgba, 40, 1, 24), [200, 0, 0, 255]);
}

#[test]
fn ui_render_includes_partially_visible_bottom_row_with_top_padding() {
    // Same as the previous test, but with a top inset (padding_y_px) to match the AppKit demo.
    //
    // Regression guard: if we treat `padding_y_px` as top+bottom padding, the bottom row can
    // disappear until it crosses a threshold (the "bottom padding" area).
    let mut ui = EditorUi::new("0\n1\n \n", 80);
    ui.set_render_config(RenderConfig {
        width_px: 40,
        height_px: 35,
        cell_width_px: 10.0,
        line_height_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 8.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(40, 35, 1.0).unwrap();

    ui.set_theme(RenderTheme {
        background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
        foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
        selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
        caret: editor_core_render_skia::Rgba8::new(0, 0, 200, 255),
        styles: std::collections::BTreeMap::new(),
        style_fonts: std::collections::BTreeMap::new(),
        text_decorations: std::collections::BTreeMap::new(),
    });

    let style_id = 0xBEEF_CAFEu32;
    let mut styles = std::collections::BTreeMap::new();
    styles.insert(
        style_id,
        editor_core_render_skia::StyleColors::new(
            None,
            Some(editor_core_render_skia::Rgba8::new(200, 0, 0, 255)),
        ),
    );
    ui.set_style_colors(styles);

    // Style the space in the 3rd line (" \n") so glyph rasterization does not affect the sample.
    // "0\n1\n \n" => the space is at char offset 4.
    ui.add_style(4, 5, style_id).unwrap();

    let rgba = ui.render_rgba_visible().unwrap();
    // The bottom pixel is inside the partially visible 3rd row (y=28..35).
    assert_eq!(pixel(&rgba, 40, 1, 34), [200, 0, 0, 255]);
}

#[test]
fn ui_exposes_selection_offsets_and_offset_mapping() {
    let mut ui = EditorUi::new("abcd\nefgh\n", 80);
    ui.set_render_config(RenderConfig {
        width_px: 200,
        height_px: 60,
        cell_width_px: 10.0,
        line_height_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(200, 60, 1.0).unwrap();

    // Select "bc" in first line (offsets 1..3).
    ui.execute(Command::Cursor(CursorCommand::SetSelection {
        start: Position::new(0, 1),
        end: Position::new(0, 3),
    }))
    .unwrap();
    assert_eq!(ui.primary_selection_offsets(), (1, 3));

    // Offset -> visual mapping.
    let (row, x) = ui.char_offset_to_visual(2).unwrap();
    assert_eq!((row, x), (0, 2));
    assert_eq!(ui.visual_to_char_offset(0, 2).unwrap(), 2);

    // Offset -> view point mapping (top-left origin).
    let (x_px, y_px) = ui.char_offset_to_view_point_px(2).unwrap();
    assert_eq!((x_px, y_px), (20.0, 0.0));
    assert_eq!(ui.line_height_px(), 20.0);

    // View hit-test.
    assert_eq!(ui.view_point_to_char_offset(25.0, 10.0).unwrap(), 2);
}

#[test]
fn ui_char_offset_to_logical_position_maps_offsets() {
    let ui = EditorUi::new("ab\ncde\nf", 80);
    // "ab\ncde\nf"
    // 0:a 1:b 2:\n 3:c 4:d 5:e 6:\n 7:f
    assert_eq!(ui.char_offset_to_logical_position(0), (0, 0));
    assert_eq!(ui.char_offset_to_logical_position(1), (0, 1));
    assert_eq!(ui.char_offset_to_logical_position(3), (1, 0)); // 'c'
    assert_eq!(ui.char_offset_to_logical_position(4), (1, 1)); // 'd'
    assert_eq!(ui.char_offset_to_logical_position(7), (2, 0)); // 'f'

    // Clamp: beyond end maps to the last valid position.
    assert_eq!(ui.char_offset_to_logical_position(999), (2, 1));
}

#[test]
fn ui_minimap_json_roundtrip_has_lines() {
    let mut ui = EditorUi::new("a\nb\nc", 80);
    let json = ui.minimap_json(0, 20);
    let v: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert!(v.get("lines").is_some());
    assert_eq!(v.get("start_visual_row").and_then(|n| n.as_u64()), Some(0));
    assert_eq!(v.get("count").and_then(|n| n.as_u64()), Some(20));
    assert!(
        v.get("actual_line_count")
            .and_then(|n| n.as_u64())
            .unwrap_or(0)
            > 0
    );
}

#[test]
fn ui_smooth_scroll_by_pixels_updates_sub_row_offset_and_hit_testing() {
    let mut ui = EditorUi::new("a\nb\nc\n", 80);
    ui.set_render_config(RenderConfig {
        width_px: 80,
        height_px: 20,
        cell_width_px: 10.0,
        line_height_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(80, 20, 1.0).unwrap();

    let vp0 = ui.viewport_state();
    assert_eq!(vp0.scroll_top, 0);
    assert_eq!(vp0.sub_row_offset, 0);
    assert_eq!(ui.viewport_row_count_for_render(&vp0), 2);

    // Scrolling up at the top should clamp to 0 (no wrap-around / shake).
    ui.scroll_by_pixels(-5.0);
    let vp0b = ui.viewport_state();
    assert_eq!(vp0b.scroll_top, 0);
    assert_eq!(vp0b.sub_row_offset, 0);

    // Scroll down by half a row.
    ui.scroll_by_pixels(5.0);

    let vp = ui.viewport_state();
    assert_eq!(vp.scroll_top, 0);
    assert_eq!(vp.sub_row_offset, 32768); // 0.5 * 65536
    assert_eq!(ui.viewport_row_count_for_render(&vp), 3);

    // The start of the 2nd line should now map to y=5 (10 - 5).
    let b_off = 2usize; // "b" in "a\nb\nc\n"
    let (_x, y) = ui.char_offset_to_view_point_px(b_off).unwrap();
    assert_eq!(y, 5.0);

    // Hit-test should take the scroll offset into account:
    // - top 5px still belong to line 0
    // - y>=5 moves into line 1
    assert_eq!(ui.view_point_to_char_offset(0.0, 4.0).unwrap(), 0);
    assert_eq!(ui.view_point_to_char_offset(0.0, 5.0).unwrap(), 2);
    assert_eq!(ui.view_point_to_char_offset(0.0, 9.0).unwrap(), 2);

    // Scrolling back up by the same amount resets the sub-row offset.
    ui.scroll_by_pixels(-5.0);
    let vp2 = ui.viewport_state();
    assert_eq!(vp2.scroll_top, 0);
    assert_eq!(vp2.sub_row_offset, 0);
}

#[test]
fn ui_gutter_shifts_view_point_mapping() {
    let mut ui = EditorUi::new("abc\n", 80);
    ui.set_render_config(RenderConfig {
        width_px: 200,
        height_px: 40,
        cell_width_px: 10.0,
        line_height_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(200, 40, 1.0).unwrap();
    ui.set_gutter_width_cells(2).unwrap(); // gutter = 20px

    let (x_px, y_px) = ui.char_offset_to_view_point_px(0).unwrap();
    assert_eq!((x_px, y_px), (20.0, 0.0));

    // Hit-testing inside gutter should clamp to column 0.
    assert_eq!(ui.view_point_to_char_offset(5.0, 10.0).unwrap(), 0);
}

#[test]
fn ui_inlay_hints_affect_hit_testing_and_view_point_mapping() {
    let mut ui = EditorUi::new("ab\n", 80);
    ui.set_render_config(RenderConfig {
        width_px: 200,
        height_px: 40,
        cell_width_px: 10.0,
        line_height_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(200, 40, 1.0).unwrap();

    // Insert an inlay hint at position (line=0, character=1), with a single space label so
    // renderer tests can sample background deterministically.
    ui.lsp_apply_inlay_hints_json(
        r#"[
              { "position": { "line": 0, "character": 1 }, "label": " " }
            ]"#,
    )
    .unwrap();

    // With the inlay hint inserted between 'a' and 'b', the 'b' glyph shifts right by 1 cell.
    // So x=25 (col=2) should still map to char offset 1 (before 'b'), not to end-of-line.
    assert_eq!(ui.view_point_to_char_offset(25.0, 10.0).unwrap(), 1);

    // Caret at end-of-line should include the inlay hint width: x = 3 cells * 10px.
    assert_eq!(ui.char_offset_to_view_point_px(2).unwrap(), (30.0, 0.0));
}

#[test]
fn ui_inlay_hint_hit_test_returns_payload_json() {
    let mut ui = EditorUi::new("ab\n", 80);
    ui.set_render_config(RenderConfig {
        width_px: 200,
        height_px: 40,
        cell_width_px: 10.0,
        line_height_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(200, 40, 1.0).unwrap();

    ui.lsp_apply_inlay_hints_json(
        r#"[
              {
                "position": { "line": 0, "character": 1 },
                "label": ": Int",
                "data": { "id": 42 }
              }
            ]"#,
    )
    .unwrap();

    let (x, y) = ui.char_offset_to_view_point_px(1).unwrap();
    let json = ui
        .inlay_hint_json_at_view_point_px(x + 1.0, y + 1.0)
        .expect("expected inlay hint json at point");
    let v: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(v["label"], ": Int");
    assert_eq!(v["data"]["id"], 42);

    assert!(ui.inlay_hint_json_at_view_point_px(1.0, y + 1.0).is_none());
}

#[test]
fn ui_gutter_click_toggles_fold_state() {
    let text = "fn main() {\n  let x = 1;\n}\n";
    let mut ui = EditorUi::new(text, 80);
    set_test_treesitter_registry(&mut ui);
    ui.set_treesitter_rust_default().unwrap();
    wait_for_async_processing(&mut ui);
    ui.set_render_config(RenderConfig {
        width_px: 200,
        height_px: 80,
        cell_width_px: 10.0,
        line_height_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(200, 80, 1.0).unwrap();
    ui.set_gutter_width_cells(2).unwrap();

    let regions = {
        let doc = ui.lock_doc();
        doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
    };
    assert!(
        regions.iter().any(|r| r.start_line == 0 && !r.is_collapsed),
        "expected a fold region starting at line 0"
    );

    // Click in gutter at visual row 0.
    ui.mouse_down(5.0, 10.0).unwrap();
    let regions = {
        let doc = ui.lock_doc();
        doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
    };
    assert!(
        regions.iter().any(|r| r.start_line == 0 && r.is_collapsed),
        "expected fold region to become collapsed after gutter click"
    );

    ui.mouse_down(5.0, 10.0).unwrap();
    let regions = {
        let doc = ui.lock_doc();
        doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
    };
    assert!(
        regions.iter().any(|r| r.start_line == 0 && !r.is_collapsed),
        "expected fold region to expand after second gutter click"
    );
}

#[test]
fn ui_nested_fold_unfold_sequence_keeps_inner_toggleable() {
    // Regression for: fold inner -> fold outer -> unfold outer -> inner must still unfold.
    let text = "fn main() {\n  if true {\n    if true {\n      println!(\"hi\");\n    }\n  }\n}\n";
    let mut ui = EditorUi::new(text, 80);
    set_test_treesitter_registry(&mut ui);
    ui.set_treesitter_rust_default().unwrap();
    wait_for_async_processing(&mut ui);
    ui.set_render_config(RenderConfig {
        width_px: 260,
        height_px: 200,
        cell_width_px: 10.0,
        line_height_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(260, 200, 1.0).unwrap();
    ui.set_gutter_width_cells(2).unwrap();

    let regions = {
        let doc = ui.lock_doc();
        doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
    };
    assert!(
        regions.len() >= 2,
        "expected nested fold regions from Tree-sitter"
    );

    // Pick an innermost region and its closest outer region.
    let inner = regions
        .iter()
        .filter(|r| r.end_line > r.start_line)
        .min_by_key(|r| r.end_line - r.start_line)
        .cloned()
        .expect("expected at least one fold region");
    let outer = regions
        .iter()
        .filter(|r| r.start_line < inner.start_line && r.end_line >= inner.end_line)
        .min_by_key(|r| r.end_line - r.start_line)
        .cloned()
        .expect("expected an outer region containing inner");

    let click_gutter_at_start_line = |ui: &mut EditorUi, start_line: usize| {
        let (row, _x_cells) = {
            let mut doc = ui.lock_doc();
            doc.ws
                .logical_to_visual_for_view(ui.view_id, start_line, 0)
                .unwrap()
                .expect("start line should be visible")
        };
        let y =
            row as f32 * ui.render_config.line_height_px + ui.render_config.line_height_px * 0.5;
        ui.mouse_down(5.0, y).unwrap();
        ui.mouse_up();
    };

    // 1) Fold inner.
    click_gutter_at_start_line(&mut ui, inner.start_line);
    let regions = {
        let doc = ui.lock_doc();
        doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
    };
    assert!(
        regions.iter().any(|r| {
            r.start_line == inner.start_line && r.end_line == inner.end_line && r.is_collapsed
        }),
        "expected inner region to be collapsed"
    );

    // 2) Fold outer.
    click_gutter_at_start_line(&mut ui, outer.start_line);
    let regions = {
        let doc = ui.lock_doc();
        doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
    };
    assert!(
        regions.iter().any(|r| {
            r.start_line == outer.start_line && r.end_line == outer.end_line && r.is_collapsed
        }),
        "expected outer region to be collapsed"
    );

    // 3) Unfold outer.
    click_gutter_at_start_line(&mut ui, outer.start_line);
    let regions = {
        let doc = ui.lock_doc();
        doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
    };
    assert!(
        regions.iter().any(|r| {
            r.start_line == outer.start_line && r.end_line == outer.end_line && !r.is_collapsed
        }),
        "expected outer region to be expanded"
    );

    // 4) Unfold inner (must still be toggleable).
    click_gutter_at_start_line(&mut ui, inner.start_line);
    let regions = {
        let doc = ui.lock_doc();
        doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
    };
    assert!(
        regions.iter().any(|r| {
            r.start_line == inner.start_line && r.end_line == inner.end_line && !r.is_collapsed
        }),
        "expected inner region to be expanded after outer unfolded"
    );
}

#[test]
fn ui_set_selections_offsets_and_insert_text_applies_to_all_carets() {
    let mut ui = EditorUi::new("abc\ndef\n", 80);

    // Two carets: start of line 0 (offset 0) and start of line 1 (offset 4).
    ui.set_selections_offsets(&[(0, 0), (4, 4)], 0).unwrap();
    let (ranges, primary) = ui.selections_offsets();
    assert_eq!(ranges, vec![(0, 0), (4, 4)]);
    assert_eq!(primary, 0);

    ui.insert_text("X").unwrap();
    assert_eq!(ui.text(), "Xabc\nXdef\n");
}

#[test]
fn ui_rect_selection_replaces_each_line_range() {
    let mut ui = EditorUi::new("abc\ndef\nghi\n", 80);

    // Box select column 1..2 across lines 0..2.
    // anchor: line0 col1 => offset 1 ('b')
    // active:  line2 col2 => offset 10 ('i')
    ui.set_rect_selection_offsets(1, 10).unwrap();

    let (ranges, _primary) = ui.selections_offsets();
    assert_eq!(ranges.len(), 3);
    assert_eq!(ranges[0], (1, 2));
    assert_eq!(ranges[1], (5, 6));
    assert_eq!(ranges[2], (9, 10));

    ui.insert_text("X").unwrap();
    assert_eq!(ui.text(), "aXc\ndXf\ngXi\n");
}

#[test]
fn ui_add_all_occurrences_selects_all_matches() {
    let mut ui = EditorUi::new("foo foo foo\n", 80);

    // Put caret at start.
    ui.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 0,
        column: 0,
    }))
    .unwrap();
    ui.select_word().unwrap();
    ui.add_all_occurrences(SearchOptions::default()).unwrap();

    let (ranges, _primary) = ui.selections_offsets();
    assert_eq!(ranges.len(), 3);

    ui.insert_text("X").unwrap();
    assert_eq!(ui.text(), "X X X\n");
}

#[test]
fn ui_add_cursor_above_and_clear_secondary() {
    let mut ui = EditorUi::new("aa\naa\naa\n", 80);
    ui.execute(Command::Cursor(CursorCommand::MoveTo {
        line: 1,
        column: 1,
    }))
    .unwrap();

    ui.add_cursor_above().unwrap();
    let (ranges, _primary) = ui.selections_offsets();
    assert_eq!(ranges.len(), 2);

    ui.insert_text("X").unwrap();
    assert_eq!(ui.text(), "aXa\naXa\naa\n");

    ui.clear_secondary_selections().unwrap();
    let (ranges, _primary) = ui.selections_offsets();
    assert_eq!(ranges.len(), 1);
}

#[test]
fn ui_move_and_modify_selection_extends_from_anchor() {
    let mut ui = EditorUi::new("abc\n", 80);
    ui.set_selections_offsets(&[(2, 2)], 0).unwrap(); // caret at offset 2

    ui.move_grapheme_left_and_modify_selection().unwrap();
    assert_eq!(ui.primary_selection_offsets(), (1, 2));

    ui.move_grapheme_left_and_modify_selection().unwrap();
    assert_eq!(ui.primary_selection_offsets(), (0, 2));

    ui.move_grapheme_right_and_modify_selection().unwrap();
    assert_eq!(ui.primary_selection_offsets(), (1, 2));
}

fn pixel(buf: &[u8], width_px: u32, x: u32, y: u32) -> [u8; 4] {
    let idx = ((y * width_px + x) * 4) as usize;
    [buf[idx], buf[idx + 1], buf[idx + 2], buf[idx + 3]]
}

#[test]
fn ui_sublime_highlight_and_folding_roundtrip() {
    let yaml = include_str!("../../editor-core-sublime/tests/fixtures/TOML.sublime-syntax");
    let text = r#"title = "TOML Example" # comment
numbers = [
  1,
  2,
  3,
]
multiline = """
hello
world
"""
"#;

    let mut ui = EditorUi::new(text, 80);
    ui.set_sublime_syntax_yaml(yaml).unwrap();

    let comment_style = ui
        .sublime_style_id_for_scope("comment.line.number-sign.toml")
        .unwrap();
    assert_eq!(
        ui.sublime_scope_for_style_id(comment_style).as_deref(),
        Some("comment.line.number-sign.toml")
    );

    let grid = {
        let mut doc = ui.lock_doc();
        doc.ws
            .get_viewport_content_styled(ui.view_id, 0, 8)
            .unwrap()
    };
    assert!(
        grid.lines
            .iter()
            .flat_map(|l| l.cells.iter())
            .any(|c| c.styles.contains(&comment_style)),
        "expected at least one comment-styled cell"
    );

    let regions = {
        let doc = ui.lock_doc();
        doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
    };
    assert!(
        regions.iter().any(|r| r.start_line == 1 && r.end_line == 5),
        "expected fold region for multi-line array (lines 1..=5)"
    );
    assert!(
        regions.iter().any(|r| r.start_line == 6 && r.end_line == 9),
        "expected fold region for multi-line basic string (lines 6..=9)"
    );
}

#[test]
fn ui_sublime_refreshes_after_edit() {
    let yaml = include_str!("../../editor-core-sublime/tests/fixtures/TOML.sublime-syntax");
    let mut ui = EditorUi::new("title = 1\n", 80);
    ui.set_sublime_syntax_yaml(yaml).unwrap();

    // Insert a comment; `insert_text` should auto-refresh processors.
    ui.insert_text("# comment\n").unwrap();

    let comment_style = ui
        .sublime_style_id_for_scope("comment.line.number-sign.toml")
        .unwrap();
    let grid = {
        let mut doc = ui.lock_doc();
        doc.ws
            .get_viewport_content_styled(ui.view_id, 0, 2)
            .unwrap()
    };
    assert!(
        grid.lines
            .iter()
            .flat_map(|l| l.cells.iter())
            .any(|c| c.styles.contains(&comment_style)),
        "expected comment style after edit"
    );
}

#[test]
fn ui_treesitter_highlight_and_folding_roundtrip() {
    let text = r#"// hi
fn main() {
  let s = "x";
}
"#;

    let mut ui = EditorUi::new(text, 80);
    set_test_treesitter_registry(&mut ui);
    ui.set_treesitter_language("rust").unwrap();
    wait_for_async_processing(&mut ui);

    let comment_style = ui.treesitter_style_id_for_capture("comment");
    let string_style = ui.treesitter_style_id_for_capture("string");
    assert_eq!(
        ui.treesitter_capture_for_style_id(comment_style).as_deref(),
        Some("comment")
    );
    assert_eq!(
        ui.treesitter_capture_for_style_id(string_style).as_deref(),
        Some("string")
    );

    let grid = {
        let mut doc = ui.lock_doc();
        doc.ws
            .get_viewport_content_styled(ui.view_id, 0, 4)
            .unwrap()
    };
    assert!(
        grid.lines
            .iter()
            .flat_map(|l| l.cells.iter())
            .any(|c| c.styles.contains(&comment_style)),
        "expected at least one comment-styled cell"
    );
    assert!(
        grid.lines
            .iter()
            .flat_map(|l| l.cells.iter())
            .any(|c| c.styles.contains(&string_style)),
        "expected at least one string-styled cell"
    );

    let regions = {
        let doc = ui.lock_doc();
        doc.ws.folding_regions_for_buffer(ui.buffer_id).unwrap()
    };
    assert!(
        regions.iter().any(|r| r.start_line == 1 && r.end_line == 3),
        "expected fold region for multi-line function"
    );
}

#[test]
fn ui_treesitter_uses_incremental_updates_when_deltas_available() {
    let mut ui = EditorUi::new("// a\n", 80);
    set_test_treesitter_registry(&mut ui);
    ui.set_treesitter_language("rust").unwrap();
    wait_for_async_processing(&mut ui);
    assert_eq!(
        ui.treesitter_last_update_mode(),
        Some(TreeSitterUpdateMode::Initial)
    );

    ui.insert_text("// b\n").unwrap();
    wait_for_async_processing(&mut ui);
    assert_eq!(
        ui.treesitter_last_update_mode(),
        Some(TreeSitterUpdateMode::Incremental)
    );
}

#[test]
fn ui_treesitter_runtime_config_can_be_updated_while_running() {
    let mut ui = EditorUi::new("// a\n", 80);

    // Use a zero-debounce config to keep the test fast and deterministic.
    ui.set_treesitter_processing_config(TreeSitterProcessingConfig {
        debounce_ms: 0,
        ..TreeSitterProcessingConfig::default()
    })
    .unwrap();

    set_test_treesitter_registry(&mut ui);
    ui.set_treesitter_language("rust").unwrap();
    wait_for_async_processing(&mut ui);

    // Updating the config should send a message to the worker and not break processing.
    ui.set_treesitter_processing_config(TreeSitterProcessingConfig {
        debounce_ms: 0,
        query_budget_ms: 1,
        cooldown_ms: 1,
        large_doc_char_threshold: 1,
        prefer_visible_range_on_large_docs: true,
    })
    .unwrap();

    ui.insert_text("// b\n").unwrap();
    wait_for_async_processing(&mut ui);
    assert!(
        ui.treesitter_last_update_mode().is_some(),
        "expected Tree-sitter processing to remain functional after runtime config update"
    );
}

#[test]
fn ui_lsp_diagnostics_apply_style_layer() {
    // Use a space at the highlighted location so glyph rasterization does not affect the pixel sample.
    let mut ui = EditorUi::new("a c\n", 80);
    ui.set_render_config(RenderConfig {
        width_px: 200,
        height_px: 40,
        cell_width_px: 10.0,
        line_height_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_theme(RenderTheme {
        background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
        foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
        selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
        caret: editor_core_render_skia::Rgba8::new(0, 0, 200, 255),
        styles: {
            let mut m = std::collections::BTreeMap::new();
            // LSP diagnostics style id encoding: 0x0400_0100 | severity
            m.insert(
                0x0400_0100 | 1,
                editor_core_render_skia::StyleColors::new(
                    None,
                    Some(editor_core_render_skia::Rgba8::new(1, 200, 2, 255)),
                ),
            );
            m
        },
        style_fonts: std::collections::BTreeMap::new(),
        text_decorations: std::collections::BTreeMap::new(),
    });
    ui.set_viewport_px(200, 40, 1.0).unwrap();

    let params_json = r#"{
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
        }"#;
    ui.lsp_apply_publish_diagnostics_json(params_json).unwrap();

    let rgba = ui.render_rgba_visible().unwrap();
    // Highlighted cell at col=1 => x in [10..20]
    assert_eq!(pixel(&rgba, 200, 15, 10), [1, 200, 2, 255]);
}

#[test]
fn ui_lsp_semantic_tokens_apply_style_layer() {
    // Use a space at the highlighted location so glyph rasterization does not affect the pixel sample.
    let mut ui = EditorUi::new("a c\n", 80);
    ui.set_render_config(RenderConfig {
        width_px: 200,
        height_px: 40,
        cell_width_px: 10.0,
        line_height_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    let style_id = 7u32 << 16;
    ui.set_theme(RenderTheme {
        background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
        foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
        selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
        caret: editor_core_render_skia::Rgba8::new(0, 0, 200, 255),
        styles: {
            let mut m = std::collections::BTreeMap::new();
            m.insert(
                style_id,
                editor_core_render_skia::StyleColors::new(
                    None,
                    Some(editor_core_render_skia::Rgba8::new(1, 200, 2, 255)),
                ),
            );
            m
        },
        style_fonts: std::collections::BTreeMap::new(),
        text_decorations: std::collections::BTreeMap::new(),
    });
    ui.set_viewport_px(200, 40, 1.0).unwrap();

    // Highlight the 'b' as a semantic token:
    // (deltaLine=0, deltaStart=1, length=1, tokenType=7, tokenModifiers=0)
    ui.lsp_apply_semantic_tokens(&[0, 1, 1, 7, 0]).unwrap();

    let rgba = ui.render_rgba_visible().unwrap();
    assert_eq!(pixel(&rgba, 200, 15, 10), [1, 200, 2, 255]);
}

#[test]
fn ui_lsp_document_links_apply_decorations_and_underline_style_layer() {
    // Use a space inside the link range so glyph rasterization does not affect pixel samples.
    let mut ui = EditorUi::new("a c\n", 80);
    ui.set_render_config(RenderConfig {
        width_px: 200,
        height_px: 20,
        cell_width_px: 10.0,
        line_height_px: 10.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_theme(RenderTheme {
        background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
        foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
        selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
        caret: editor_core_render_skia::Rgba8::new(0, 0, 200, 255),
        styles: {
            let mut m = std::collections::BTreeMap::new();
            m.insert(
                editor_core::DOCUMENT_LINK_STYLE_ID,
                editor_core_render_skia::StyleColors::new(
                    Some(editor_core_render_skia::Rgba8::new(1, 200, 2, 255)),
                    None,
                ),
            );
            m
        },
        style_fonts: std::collections::BTreeMap::new(),
        text_decorations: std::collections::BTreeMap::new(),
    });
    ui.set_viewport_px(200, 20, 1.0).unwrap();

    let result_json = r#"[
          {
            "range": {
              "start": { "line": 0, "character": 1 },
              "end": { "line": 0, "character": 2 }
            },
            "target": "https://example.com"
          }
        ]"#;
    ui.lsp_apply_document_links_json(result_json).unwrap();

    let decorations = {
        let doc = ui.lock_doc();
        doc.ws
            .buffer_decorations(ui.buffer_id)
            .unwrap()
            .get(&editor_core::DecorationLayerId::DOCUMENT_LINKS)
            .cloned()
            .unwrap_or_default()
    };
    assert_eq!(
        decorations.len(),
        1,
        "expected one document link decoration"
    );

    let grid = {
        let mut doc = ui.lock_doc();
        doc.ws
            .get_viewport_content_styled(ui.view_id, 0, 1)
            .unwrap()
    };
    assert!(
        grid.lines
            .iter()
            .flat_map(|l| l.cells.iter())
            .any(|c| c.styles.contains(&editor_core::DOCUMENT_LINK_STYLE_ID)),
        "expected at least one cell to carry DOCUMENT_LINK_STYLE_ID"
    );

    let rgba = ui.render_rgba_visible().unwrap();
    // Underline is drawn at y = line_height_px - 1 (scale=1), i.e. y=9.
    assert_eq!(pixel(&rgba, 200, 15, 9), [1, 200, 2, 255]);
}

#[test]
fn ui_document_link_hit_test_returns_payload_json() {
    let mut ui = EditorUi::new("abc\n", 80);
    ui.set_render_config(RenderConfig {
        width_px: 200,
        height_px: 40,
        cell_width_px: 10.0,
        line_height_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_viewport_px(200, 40, 1.0).unwrap();

    let result_json = r#"[
          {
            "range": {
              "start": { "line": 0, "character": 0 },
              "end": { "line": 0, "character": 1 }
            },
            "target": "https://example.com"
          }
        ]"#;
    ui.lsp_apply_document_links_json(result_json).unwrap();

    let (x, y) = ui.char_offset_to_view_point_px(0).unwrap();
    let json = ui
        .document_link_json_at_view_point_px(x + 1.0, y + 1.0)
        .expect("expected document link json at point");
    let v: serde_json::Value = serde_json::from_str(&json).unwrap();
    assert_eq!(
        v.get("target").and_then(|t| t.as_str()),
        Some("https://example.com")
    );
}

#[test]
fn ui_lsp_document_highlights_apply_style_layer() {
    // Use a space at the highlighted location so glyph rasterization does not affect the pixel sample.
    let mut ui = EditorUi::new("a c\n", 80);
    ui.set_render_config(RenderConfig {
        width_px: 200,
        height_px: 40,
        cell_width_px: 10.0,
        line_height_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_theme(RenderTheme {
        background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
        foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
        selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
        caret: editor_core_render_skia::Rgba8::new(10, 20, 30, 255), // invisible
        styles: {
            let mut m = std::collections::BTreeMap::new();
            m.insert(
                editor_core::DOCUMENT_HIGHLIGHT_TEXT_STYLE_ID,
                editor_core_render_skia::StyleColors::new(
                    None,
                    Some(editor_core_render_skia::Rgba8::new(1, 200, 2, 255)),
                ),
            );
            m
        },
        style_fonts: std::collections::BTreeMap::new(),
        text_decorations: std::collections::BTreeMap::new(),
    });
    ui.set_viewport_px(200, 40, 1.0).unwrap();

    let result_json = r#"[
          {
            "range": {
              "start": { "line": 0, "character": 1 },
              "end": { "line": 0, "character": 2 }
            },
            "kind": 1
          }
        ]"#;
    ui.lsp_apply_document_highlights_json(result_json).unwrap();

    let rgba = ui.render_rgba_visible().unwrap();
    // Highlighted cell at col=1 => x in [10..20]
    assert_eq!(pixel(&rgba, 200, 15, 10), [1, 200, 2, 255]);
}

#[test]
fn ui_match_highlights_apply_style_layer() {
    // Use a space at the highlighted location so glyph rasterization does not affect pixel samples.
    let mut ui = EditorUi::new("a c\n", 80);
    ui.set_render_config(RenderConfig {
        width_px: 200,
        height_px: 40,
        cell_width_px: 10.0,
        line_height_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_theme(RenderTheme {
        background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
        foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
        selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
        caret: editor_core_render_skia::Rgba8::new(10, 20, 30, 255), // invisible
        styles: {
            let mut m = std::collections::BTreeMap::new();
            m.insert(
                editor_core::MATCH_HIGHLIGHT_STYLE_ID,
                editor_core_render_skia::StyleColors::new(
                    None,
                    Some(editor_core_render_skia::Rgba8::new(1, 200, 2, 255)),
                ),
            );
            m
        },
        style_fonts: std::collections::BTreeMap::new(),
        text_decorations: std::collections::BTreeMap::new(),
    });
    ui.set_viewport_px(200, 40, 1.0).unwrap();

    // Highlight the space at offset 1..2.
    ui.set_match_highlights_offsets(&[(1, 2)]);

    let rgba = ui.render_rgba_visible().unwrap();
    assert_eq!(pixel(&rgba, 200, 15, 10), [1, 200, 2, 255]);
}

#[test]
fn ui_search_set_query_finds_matches_and_sets_match_highlights() {
    // Use spaces as matches so glyph rasterization does not affect pixel samples.
    let mut ui = EditorUi::new("a c a\n", 80);
    ui.set_render_config(RenderConfig {
        width_px: 200,
        height_px: 40,
        cell_width_px: 10.0,
        line_height_px: 20.0,
        padding_x_px: 0.0,
        padding_y_px: 0.0,
        ..RenderConfig::default()
    });
    ui.set_theme(RenderTheme {
        background: editor_core_render_skia::Rgba8::new(10, 20, 30, 255),
        foreground: editor_core_render_skia::Rgba8::new(250, 250, 250, 255),
        selection_background: editor_core_render_skia::Rgba8::new(200, 0, 0, 255),
        caret: editor_core_render_skia::Rgba8::new(10, 20, 30, 255), // invisible
        styles: {
            let mut m = std::collections::BTreeMap::new();
            m.insert(
                editor_core::MATCH_HIGHLIGHT_STYLE_ID,
                editor_core_render_skia::StyleColors::new(
                    None,
                    Some(editor_core_render_skia::Rgba8::new(1, 200, 2, 255)),
                ),
            );
            m
        },
        style_fonts: std::collections::BTreeMap::new(),
        text_decorations: std::collections::BTreeMap::new(),
    });
    ui.set_viewport_px(200, 40, 1.0).unwrap();

    let count = ui
        .search_set_query(" ", editor_core::SearchOptions::default())
        .unwrap();
    assert_eq!(count, 2);

    let rgba = ui.render_rgba_visible().unwrap();
    // First space at col=1 => x in [10..20]
    assert_eq!(pixel(&rgba, 200, 15, 10), [1, 200, 2, 255]);
    // Second space at col=3 => x in [30..40]
    assert_eq!(pixel(&rgba, 200, 35, 10), [1, 200, 2, 255]);
}

#[test]
fn ui_find_next_and_replace_current_and_all() {
    let mut ui = EditorUi::new("foo foo foo\n", 80);
    ui.set_selections_offsets(&[(0, 0)], 0).unwrap();

    let found = ui
        .find_next("foo", editor_core::SearchOptions::default())
        .unwrap();
    assert!(found);
    assert_eq!(
        ui.primary_selection_offsets(),
        (0, 3),
        "first find_next should select first 'foo'"
    );

    let found = ui
        .find_next("foo", editor_core::SearchOptions::default())
        .unwrap();
    assert!(found);
    assert_eq!(
        ui.primary_selection_offsets(),
        (4, 7),
        "second find_next should select second 'foo'"
    );

    let replaced = ui
        .replace_current("foo", "bar", editor_core::SearchOptions::default())
        .unwrap();
    assert_eq!(replaced, 1);
    assert_eq!(ui.text(), "foo bar foo\n");

    let replaced_all = ui
        .replace_all("foo", "baz", editor_core::SearchOptions::default())
        .unwrap();
    assert_eq!(replaced_all, 2);
    assert_eq!(ui.text(), "baz bar baz\n");
}

#[test]
fn ui_reveal_primary_caret_scrolls_to_make_caret_visible() {
    // 100 lines, no wrapping: visual rows == logical lines.
    let text = (0..100).map(|_| "x").collect::<Vec<_>>().join("\n");
    let mut ui = EditorUi::new(text.as_str(), 80);
    ui.set_render_metrics(14.0, 10.0, 8.0, 0.0, 0.0);
    // 5 visible rows.
    ui.set_viewport_px(800, 50, 1.0).unwrap();
    ui.set_smooth_scroll_state(0, 0);
    assert_eq!(ui.viewport_state().scroll_top, 0);

    // Place caret at line 50 (0-based).
    let offset = {
        let doc = ui.lock_doc();
        let line_index = doc.ws.buffer_line_index(ui.buffer_id).unwrap();
        line_index.position_to_char_offset(50, 0)
    };
    ui.set_selections_offsets(&[(offset, offset)], 0).unwrap();

    ui.reveal_primary_caret();
    // Expected: caret row 50 must be visible within 5 rows -> top should be 46.
    assert_eq!(ui.viewport_state().scroll_top, 46);
}

#[test]
fn ui_lsp_request_definition_errors_when_lsp_disabled() {
    let mut ui = EditorUi::new("hello", 80);
    let err = ui.lsp_request_definition(0, 0).unwrap_err();
    match err {
        UiError::Processor(msg) => assert_eq!(msg, "LSP is not enabled"),
        other => panic!("expected UiError::Processor, got: {other:?}"),
    }

    let err = ui
        .lsp_request_completion_item_resolve(r#"{"label":"hello"}"#)
        .unwrap_err();
    match err {
        UiError::Processor(msg) => assert_eq!(msg, "LSP is not enabled"),
        other => panic!("expected UiError::Processor, got: {other:?}"),
    }

    let err = ui.lsp_format_document("", 50).unwrap_err();
    match err {
        UiError::Processor(msg) => assert_eq!(msg, "LSP is not enabled"),
        other => panic!("expected UiError::Processor, got: {other:?}"),
    }

    let err = ui.lsp_format_range(0, 1, "", 50).unwrap_err();
    match err {
        UiError::Processor(msg) => assert_eq!(msg, "LSP is not enabled"),
        other => panic!("expected UiError::Processor, got: {other:?}"),
    }

    let err = ui.lsp_format_on_type(0, 1, "\n", "", 50).unwrap_err();
    match err {
        UiError::Processor(msg) => assert_eq!(msg, "LSP is not enabled"),
        other => panic!("expected UiError::Processor, got: {other:?}"),
    }

    let err = ui.lsp_request_inlay_hints(0, 1).unwrap_err();
    match err {
        UiError::Processor(msg) => assert_eq!(msg, "LSP is not enabled"),
        other => panic!("expected UiError::Processor, got: {other:?}"),
    }

    let err = ui
        .lsp_request_inlay_hint_resolve(r#"{"position":{"line":0,"character":1},"label":"x"}"#)
        .unwrap_err();
    match err {
        UiError::Processor(msg) => assert_eq!(msg, "LSP is not enabled"),
        other => panic!("expected UiError::Processor, got: {other:?}"),
    }

    let err = ui.lsp_request_document_links().unwrap_err();
    match err {
        UiError::Processor(msg) => assert_eq!(msg, "LSP is not enabled"),
        other => panic!("expected UiError::Processor, got: {other:?}"),
    }

    let err = ui
        .lsp_request_document_link_resolve(
            r#"{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":1}}}"#,
        )
        .unwrap_err();
    match err {
        UiError::Processor(msg) => assert_eq!(msg, "LSP is not enabled"),
        other => panic!("expected UiError::Processor, got: {other:?}"),
    }
}

#[test]
fn ui_lsp_apply_text_edits_json_converts_utf16_ranges_with_emoji() {
    let mut ui = EditorUi::new("a😀b\nc\n", 80);

    // Replace the 😀 (UTF-16 length 2) with "Z".
    let edits = r#"[{"range":{"start":{"line":0,"character":1},"end":{"line":0,"character":3}},"newText":"Z"}]"#;
    let applied = ui.lsp_apply_text_edits_json(edits).unwrap();
    assert!(applied);
    assert_eq!(ui.text(), "aZb\nc\n");
}

#[test]
fn ui_lsp_apply_text_edits_json_applies_multiple_edits_in_one_call() {
    let mut ui = EditorUi::new("abc\n", 80);

    // Two non-overlapping edits expressed in pre-edit coordinates:
    // - replace "b" with "B"
    // - insert "X" at the start
    let edits = r#"[{"range":{"start":{"line":0,"character":1},"end":{"line":0,"character":2}},"newText":"B"},{"range":{"start":{"line":0,"character":0},"end":{"line":0,"character":0}},"newText":"X"}]"#;
    let applied = ui.lsp_apply_text_edits_json(edits).unwrap();
    assert!(applied);
    assert_eq!(ui.text(), "XaBc\n");
}

#[test]
fn ui_lsp_apply_workspace_edit_json_applies_current_uri_and_reports_skips() {
    let mut ui = EditorUi::new("abc\n", 80);

    let edit = r#"{
            "changes": {
                "file:///test.rs": [
                    { "range": { "start": { "line": 0, "character": 1 }, "end": { "line": 0, "character": 2 } }, "newText": "B" }
                ],
                "file:///other.rs": [
                    { "range": { "start": { "line": 0, "character": 0 }, "end": { "line": 0, "character": 0 } }, "newText": "X" }
                ]
            }
        }"#;

    let result_json = ui
        .lsp_apply_workspace_edit_json(edit, Some("file:///test.rs"))
        .unwrap();
    assert_eq!(ui.text(), "aBc\n");

    let result: serde_json::Value = serde_json::from_str(&result_json).unwrap();
    assert_eq!(result["applied"], true);
    assert_eq!(result["applied_uri"], "file:///test.rs");
    assert_eq!(result["applied_edit_count"], 1);
    assert_eq!(
        result["skipped_uris"],
        serde_json::json!(["file:///other.rs"])
    );
    assert_eq!(result["documents"].as_array().unwrap().len(), 2);
}
