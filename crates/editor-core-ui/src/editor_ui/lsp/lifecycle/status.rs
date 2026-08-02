use super::*;

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
        let mut workspace_folders: Vec<serde_json::Value> = Vec::new();

        if let Some(shared) = shared {
            match shared.session.lock() {
                Ok(guard) => {
                    if let Some(session) = guard.as_ref() {
                        let s = session.status();
                        availability = "enabled";
                        state = match s.state {
                            editor_core_lsp::LspWorkState::Ready => "ready",
                            editor_core_lsp::LspWorkState::Indexing => "indexing",
                            editor_core_lsp::LspWorkState::Busy => "busy",
                        };
                        workspace_folders = s.workspace_folders;

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
            "activity": activity,
            "detail": detail,
            "capabilities": capabilities,
            "workspace_folders": workspace_folders,
        })
    }
}
