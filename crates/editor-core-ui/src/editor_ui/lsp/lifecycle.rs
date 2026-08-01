use super::*;

impl EditorUi {
    /// Enable an LSP session (stdio) for the current document.
    ///
    /// This is primarily intended for demos and simple hosts. It:
    /// - runs `initialize` / `initialized`
    /// - sends `textDocument/didOpen` with the current document text
    /// - keeps the server in sync via incremental `didChange` (based on `TextDelta`)
    /// - polls and applies derived state (semantic tokens, folding ranges, diagnostics)
    /// - additionally requests inlay hints / code lens / document links (demo UX)
    pub fn lsp_enable_stdio(
        &mut self,
        cmd: &str,
        args: &[String],
        root_uri: &str,
        doc_uri: &str,
        language_id: &str,
    ) -> Result<(), UiError> {
        // Clear any existing LSP-derived state first so a failed start doesn't leave stale
        // semantic tokens / diagnostics around.
        let initial_text = {
            let mut doc = self.lock_doc();
            doc.lsp_last_cmd = Some(cmd.to_string());
            doc.lsp_last_error = None;
            if doc.lsp.is_some() {
                doc.lsp_disable();
            }
            let _ = doc.apply_processing_edits(editor_core_lsp::lsp_clear_edits());
            doc.ws
                .buffer_text(doc.buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
        };

        let token_types = editor_core_lsp::CANONICAL_SEMANTIC_TOKEN_TYPES;
        let token_modifiers = editor_core_lsp::CANONICAL_SEMANTIC_TOKEN_MODIFIERS;

        // Build initialize params in the demo (caller-controlled). Consumers may override or
        // replace this entirely.
        let init_params = serde_json::json!({
            "processId": std::process::id(),
            "rootUri": root_uri,
            "capabilities": {
                "textDocument": {
                    "semanticTokens": {
                        "dynamicRegistration": false,
                        "requests": { "range": false, "full": { "delta": false } },
                        "tokenTypes": token_types,
                        "tokenModifiers": token_modifiers,
                        "formats": ["relative"],
                        "multilineTokenSupport": true,
                        "overlappingTokenSupport": false,
                    },
                    "foldingRange": {
                        "dynamicRegistration": false,
                        "lineFoldingOnly": true,
                    },
                    // Some servers gate these behind explicit capabilities.
                    "inlayHint": { "dynamicRegistration": false },
                    "codeLens": { "dynamicRegistration": false },
                    "documentLink": { "dynamicRegistration": false },
                },
            },
            "clientInfo": { "name": "editor-core ui" },
        });

        let mut cmd_proc = std::process::Command::new(cmd);
        cmd_proc.args(args);
        cmd_proc.stderr(Stdio::null());

        let start = LspSessionStartOptions {
            cmd: cmd_proc,
            // Single-document demo: keep workspace folder features disabled.
            workspace_folders: Vec::new(),
            initialize_params: init_params,
            initialize_timeout: Duration::from_secs(6),
            document: LspDocument {
                uri: doc_uri.to_string(),
                language_id: language_id.to_string(),
                version: 1,
            },
            initial_text: initial_text.clone(),
        };

        let key = SharedLspKey {
            cmd: cmd.to_string(),
            args: args.to_vec(),
            root_uri: root_uri.trim_end_matches('/').to_string(),
        };
        let shared = match get_or_start_shared_lsp_session(key, start) {
            Ok(shared) => shared,
            Err(err) => {
                let mut doc = self.lock_doc();
                doc.lsp_fail(err.to_string());
                return Err(err);
            }
        };

        // If this is not the first document in the shared session, open it explicitly.
        //
        // Note: for the very first document, `LspSession::start(...)` already didOpen'd it.
        let doc_uri = doc_uri.to_string();
        let language_id = language_id.to_string();
        let initial_text_clone = initial_text.clone();
        if let Err(err) = shared.with_session_mut(|session| {
            if session.document_for_uri(doc_uri.as_str()).is_some() {
                return Ok(());
            }
            session.open_document(
                LspDocument {
                    uri: doc_uri.clone(),
                    language_id,
                    version: 1,
                },
                initial_text_clone,
            )
        }) {
            let mut doc = self.lock_doc();
            doc.lsp_fail(err.clone());
            return Err(UiError::Processor(err));
        }

        {
            let mut doc = self.lock_doc();
            let buffer_id = doc.buffer_id;
            // Ensure the buffer is addressable by URI so workspace-wide LSP edits (formatting,
            // rename, code actions, workspace/applyEdit, ...) can be routed correctly.
            doc.ws
                .set_buffer_uri(buffer_id, Some(doc_uri.clone()))
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            doc.lsp = Some(shared);
            doc.lsp_document_uri = Some(doc_uri);
            doc.lsp_delta_calc = Some(DeltaCalculator::from_text(&initial_text));
            doc.lsp_aux_refresh_due = Some(Instant::now());
            doc.lsp_inlay_in_flight = false;
            doc.lsp_code_lens_in_flight = false;
            doc.lsp_document_links_in_flight = false;
            doc.lsp_client_requests.clear();
            doc.lsp_clear_result_state();
            doc.lsp_latest_on_type_formatting_request_id.clear();
        }
        Ok(())
    }

    pub fn lsp_disable(&mut self) {
        let mut doc = self.lock_doc();
        doc.lsp_disable();
    }

    pub fn lsp_is_enabled(&self) -> bool {
        let doc = self.lock_doc();
        doc.lsp_is_enabled()
    }

    /// Return a best-effort LSP status snapshot as a JSON string.
    ///
    /// This is intended for UI status bars and debugging overlays. The schema is stable-ish but
    /// not yet versioned; callers should treat unknown fields as optional.
    pub fn lsp_status_json(&self) -> String {
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
        })
        .to_string()
    }
}
