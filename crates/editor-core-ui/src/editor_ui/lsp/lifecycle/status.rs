use super::*;

fn lsp_process_status_json(process: &editor_core_lsp::LspProcessStatus) -> serde_json::Value {
    let state = match process.state {
        editor_core_lsp::LspProcessState::Running => "running",
        editor_core_lsp::LspProcessState::Exited => "exited",
    };
    serde_json::json!({
        "pid": process.pid,
        "state": state,
        "exit_code": process.exit_code,
        "signal": process.signal,
        "stderr_tail": process.stderr_tail,
    })
}

fn lsp_process_exit_detail(process: &editor_core_lsp::LspProcessStatus) -> String {
    if let Some(code) = process.exit_code {
        return format!("LSP server exited with code {code}");
    }
    if let Some(signal) = process.signal {
        return format!("LSP server exited with signal {signal}");
    }
    "LSP server exited".to_string()
}

impl EditorUi {
    /// Return a best-effort LSP status snapshot as a JSON string.
    ///
    /// This is intended for UI status bars and debugging overlays. The schema is stable-ish but
    /// not yet versioned; callers should treat unknown fields as optional.
    pub fn lsp_status_json(&self) -> String {
        self.lsp_status_value().to_string()
    }

    pub(crate) fn lsp_status_value(&self) -> serde_json::Value {
        let (shared, last_cmd, last_error) = {
            let doc = self.lock_doc();
            (
                doc.lsp.clone(),
                doc.lsp_last_cmd.clone(),
                doc.lsp_last_error.clone(),
            )
        };

        let mut availability = "disabled";
        let mut state = "disabled";
        let mut detail: Option<String> = None;
        let mut server: Option<serde_json::Value> = None;
        let mut activity: Option<serde_json::Value> = None;
        let mut capabilities: Option<serde_json::Value> = None;
        let mut process: Option<serde_json::Value> = None;
        let mut workspace_folders: Vec<serde_json::Value> = Vec::new();

        if let Some(shared) = shared {
            match shared.session.lock() {
                Ok(mut guard) => {
                    if let Some(session) = guard.as_mut() {
                        let health_error = session.refresh_process_status().err();
                        let s = session.status();
                        workspace_folders = s.workspace_folders;
                        process = Some(lsp_process_status_json(&s.process));

                        server = Some(serde_json::json!({
                            "name": s.server.name,
                            "version": s.server.version,
                            "command": s.server.command,
                            "args": s.server.args,
                        }));

                        activity = s.activity.map(|a| {
                            serde_json::json!({
                                "title": a.title,
                                "message": a.message,
                                "percentage": a.percentage,
                            })
                        });

                        capabilities = Some(serde_json::json!({
                            "semantic_tokens": s.capabilities.semantic_tokens,
                            "semantic_tokens_delta": s.capabilities.semantic_tokens_delta,
                            "completion_item_resolve": s.capabilities.completion_item_resolve,
                            "completion": lsp_completion_capability_json(session.server_capabilities()),
                            "folding_ranges": s.capabilities.folding_ranges,
                            "on_type_formatting": s.capabilities.on_type_formatting,
                            "signature_help": lsp_signature_help_capability_json(session.server_capabilities()),
                        }));

                        if let Some(err) = health_error {
                            availability = "failed";
                            state = "failed";
                            detail = Some(err);
                        } else if s.process.state == editor_core_lsp::LspProcessState::Exited {
                            availability = "failed";
                            state = "failed";
                            detail = Some(lsp_process_exit_detail(&s.process));
                        } else {
                            availability = "enabled";
                            state = match s.state {
                                editor_core_lsp::LspWorkState::Ready => "ready",
                                editor_core_lsp::LspWorkState::Indexing => "indexing",
                                editor_core_lsp::LspWorkState::Busy => "busy",
                            };
                        }
                    } else {
                        availability = "failed";
                        state = "failed";
                        detail = last_error
                            .clone()
                            .or_else(|| Some("LSP session is not available".to_string()));
                        if let Some(cmd) = last_cmd.as_deref() {
                            server = Some(serde_json::json!({ "command": cmd }));
                        }
                    }
                }
                Err(_) => {
                    availability = "failed";
                    state = "failed";
                    detail = Some("LSP session lock poisoned".to_string());
                    if let Some(cmd) = last_cmd.as_deref() {
                        server = Some(serde_json::json!({ "command": cmd }));
                    }
                }
            }
        } else if let Some(err) = last_error.clone() {
            availability = "failed";
            state = "failed";
            detail = Some(err);
            if let Some(cmd) = last_cmd.as_deref() {
                server = Some(serde_json::json!({ "command": cmd }));
            }
        } else if let Some(cmd) = last_cmd.as_deref() {
            server = Some(serde_json::json!({ "command": cmd }));
        }

        serde_json::json!({
            "availability": availability,
            "state": state,
            "server": server,
            "process": process,
            "activity": activity,
            "detail": detail,
            "capabilities": capabilities,
            "workspace_folders": workspace_folders,
        })
    }
}
