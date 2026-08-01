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

    fn lsp_request_position_result(
        &mut self,
        slot: LspResultSlot,
        line: usize,
        column: usize,
        request: impl FnOnce(
            &mut LspSession,
            &editor_core::LineIndex,
            usize,
            usize,
        ) -> Result<u64, String>,
    ) -> Result<u64, UiError> {
        self.flush_lsp_did_change_from_delta();

        let mut doc = self.lock_doc();
        let Some(shared) = doc.lsp.as_ref() else {
            return Err(UiError::Processor("LSP is not enabled".to_string()));
        };
        let Some(doc_uri) = doc.lsp_document_uri.as_deref() else {
            return Err(UiError::Processor("LSP document URI missing".to_string()));
        };

        let line_index = doc
            .ws
            .buffer_line_index(doc.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri)?;
                request(lsp, line_index, line, column)
            })
            .map_err(UiError::Processor)?;

        doc.lsp_client_requests.insert(
            id,
            LspClientRequest::Result {
                view: self.view_id,
                slot,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((self.view_id, slot), id);
        doc.lsp_last_result_json.remove(&(self.view_id, slot));
        Ok(id)
    }

    fn lsp_request_document_result(
        &mut self,
        slot: LspResultSlot,
        request: impl FnOnce(&mut LspSession) -> Result<u64, String>,
    ) -> Result<u64, UiError> {
        self.flush_lsp_did_change_from_delta();

        let mut doc = self.lock_doc();
        let Some(shared) = doc.lsp.as_ref() else {
            return Err(UiError::Processor("LSP is not enabled".to_string()));
        };
        let Some(doc_uri) = doc.lsp_document_uri.as_deref() else {
            return Err(UiError::Processor("LSP document URI missing".to_string()));
        };

        let id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri)?;
                request(lsp)
            })
            .map_err(UiError::Processor)?;

        doc.lsp_client_requests.insert(
            id,
            LspClientRequest::Result {
                view: self.view_id,
                slot,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((self.view_id, slot), id);
        doc.lsp_last_result_json.remove(&(self.view_id, slot));
        Ok(id)
    }

    fn lsp_request_with_line_index_result(
        &mut self,
        slot: LspResultSlot,
        request: impl FnOnce(&mut LspSession, &editor_core::LineIndex) -> Result<u64, String>,
    ) -> Result<u64, UiError> {
        self.flush_lsp_did_change_from_delta();

        let mut doc = self.lock_doc();
        let Some(shared) = doc.lsp.as_ref() else {
            return Err(UiError::Processor("LSP is not enabled".to_string()));
        };
        let Some(doc_uri) = doc.lsp_document_uri.as_deref() else {
            return Err(UiError::Processor("LSP document URI missing".to_string()));
        };

        let line_index = doc
            .ws
            .buffer_line_index(doc.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri)?;
                request(lsp, line_index)
            })
            .map_err(UiError::Processor)?;

        doc.lsp_client_requests.insert(
            id,
            LspClientRequest::Result {
                view: self.view_id,
                slot,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((self.view_id, slot), id);
        doc.lsp_last_result_json.remove(&(self.view_id, slot));
        Ok(id)
    }

    fn lsp_take_last_result_json(&mut self, slot: LspResultSlot) -> Option<String> {
        let mut doc = self.lock_doc();
        doc.lsp_last_result_json.remove(&(self.view_id, slot))
    }

    /// Request LSP hover information for a given logical position (0-based line/column in Unicode scalars).
    ///
    /// The result is delivered asynchronously via `poll_processing` and can be read by calling
    /// [`Self::lsp_take_last_hover_result_json`].
    pub fn lsp_request_hover(&mut self, line: usize, column: usize) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::Hover,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_hover(line_index, line, column),
        )
    }

    pub fn lsp_take_last_hover_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::Hover)
    }

    /// Request LSP go-to-definition for a given logical position (0-based line/column in Unicode scalars).
    ///
    /// The result is delivered asynchronously via `poll_processing` and can be read by calling
    /// [`Self::lsp_take_last_definition_result_json`].
    pub fn lsp_request_definition(&mut self, line: usize, column: usize) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::Definition,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_definition(line_index, line, column),
        )
    }

    pub fn lsp_take_last_definition_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::Definition)
    }

    pub fn lsp_request_declaration(&mut self, line: usize, column: usize) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::Declaration,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_declaration(line_index, line, column),
        )
    }

    pub fn lsp_take_last_declaration_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::Declaration)
    }

    pub fn lsp_request_type_definition(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::TypeDefinition,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_type_definition(line_index, line, column),
        )
    }

    pub fn lsp_take_last_type_definition_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::TypeDefinition)
    }

    pub fn lsp_request_implementation(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::Implementation,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_implementation(line_index, line, column),
        )
    }

    pub fn lsp_take_last_implementation_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::Implementation)
    }

    pub fn lsp_request_references(
        &mut self,
        line: usize,
        column: usize,
        include_declaration: bool,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::References,
            line,
            column,
            |lsp, line_index, line, column| {
                lsp.request_references(line_index, line, column, include_declaration)
            },
        )
    }

    pub fn lsp_take_last_references_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::References)
    }

    pub fn lsp_request_completion(&mut self, line: usize, column: usize) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::Completion,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_completion(line_index, line, column),
        )
    }

    pub fn lsp_take_last_completion_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::Completion)
    }

    pub fn lsp_request_completion_item_resolve(&mut self, item_json: &str) -> Result<u64, UiError> {
        let item: serde_json::Value =
            serde_json::from_str(item_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::CompletionResolve, |lsp| {
            lsp.request_completion_item_resolve(item)
        })
    }

    pub fn lsp_take_last_completion_item_resolve_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CompletionResolve)
    }

    pub fn lsp_request_signature_help(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::SignatureHelp,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_signature_help(line_index, line, column),
        )
    }

    pub fn lsp_take_last_signature_help_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::SignatureHelp)
    }

    pub fn lsp_request_prepare_rename(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::PrepareRename,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_prepare_rename(line_index, line, column),
        )
    }

    pub fn lsp_take_last_prepare_rename_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::PrepareRename)
    }

    pub fn lsp_request_rename(
        &mut self,
        line: usize,
        column: usize,
        new_name: &str,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::Rename,
            line,
            column,
            |lsp, line_index, line, column| lsp.request_rename(line_index, line, column, new_name),
        )
    }

    pub fn lsp_take_last_rename_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::Rename)
    }

    pub fn lsp_request_code_action(
        &mut self,
        start_offset: usize,
        end_offset: usize,
        context_json: &str,
    ) -> Result<u64, UiError> {
        self.flush_lsp_did_change_from_delta();

        let context: serde_json::Value = if context_json.trim().is_empty() {
            serde_json::json!({ "diagnostics": [] })
        } else {
            serde_json::from_str(context_json).map_err(|e| UiError::Processor(e.to_string()))?
        };

        let mut doc = self.lock_doc();
        let Some(shared) = doc.lsp.as_ref() else {
            return Err(UiError::Processor("LSP is not enabled".to_string()));
        };
        let Some(doc_uri) = doc.lsp_document_uri.as_deref() else {
            return Err(UiError::Processor("LSP document URI missing".to_string()));
        };

        let line_index = doc
            .ws
            .buffer_line_index(doc.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let start = start_offset.min(end_offset);
        let end = start_offset.max(end_offset);
        let id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri)?;
                lsp.request_code_action(line_index, start, end, context)
            })
            .map_err(UiError::Processor)?;

        doc.lsp_client_requests.insert(
            id,
            LspClientRequest::Result {
                view: self.view_id,
                slot: LspResultSlot::CodeAction,
            },
        );
        doc.lsp_latest_result_request_id
            .insert((self.view_id, LspResultSlot::CodeAction), id);
        doc.lsp_last_result_json
            .remove(&(self.view_id, LspResultSlot::CodeAction));
        Ok(id)
    }

    pub fn lsp_take_last_code_action_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CodeAction)
    }

    pub fn lsp_request_code_action_resolve(&mut self, action_json: &str) -> Result<u64, UiError> {
        let action: serde_json::Value =
            serde_json::from_str(action_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::CodeActionResolve, |lsp| {
            lsp.request_code_action_resolve(action)
        })
    }

    pub fn lsp_take_last_code_action_resolve_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CodeActionResolve)
    }

    pub fn lsp_request_execute_command(&mut self, command_json: &str) -> Result<u64, UiError> {
        let value: serde_json::Value =
            serde_json::from_str(command_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let command = value
            .get("command")
            .and_then(serde_json::Value::as_str)
            .filter(|s| !s.trim().is_empty())
            .ok_or_else(|| UiError::Processor("workspace command missing".to_string()))?;
        let arguments = value
            .get("arguments")
            .and_then(serde_json::Value::as_array)
            .cloned()
            .unwrap_or_default();
        let command = command.to_string();

        self.lsp_request_document_result(LspResultSlot::ExecuteCommand, |lsp| {
            lsp.request_execute_command(command, arguments)
        })
    }

    pub fn lsp_take_last_execute_command_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::ExecuteCommand)
    }

    pub fn lsp_request_code_lens(&mut self) -> Result<u64, UiError> {
        let id = self
            .lsp_request_document_result(LspResultSlot::CodeLens, |lsp| lsp.request_code_lens())?;
        let mut doc = self.lock_doc();
        doc.lsp_code_lens_in_flight = true;
        doc.lsp_aux_refresh_due = None;
        Ok(id)
    }

    pub fn lsp_take_last_code_lens_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CodeLens)
    }

    pub fn lsp_request_code_lens_resolve(&mut self, lens_json: &str) -> Result<u64, UiError> {
        let lens: serde_json::Value =
            serde_json::from_str(lens_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::CodeLensResolve, |lsp| {
            lsp.request_code_lens_resolve(lens)
        })
    }

    pub fn lsp_take_last_code_lens_resolve_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CodeLensResolve)
    }

    pub fn lsp_request_document_symbols(&mut self) -> Result<u64, UiError> {
        self.lsp_request_document_result(LspResultSlot::DocumentSymbols, |lsp| {
            lsp.request_document_symbols()
        })
    }

    pub fn lsp_take_last_document_symbols_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::DocumentSymbols)
    }

    pub fn lsp_request_workspace_symbols(&mut self, query: &str) -> Result<u64, UiError> {
        self.lsp_request_document_result(LspResultSlot::WorkspaceSymbols, |lsp| {
            lsp.request_workspace_symbol(query)
        })
    }

    pub fn lsp_take_last_workspace_symbols_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::WorkspaceSymbols)
    }

    pub fn lsp_request_folding_ranges(&mut self) -> Result<u64, UiError> {
        self.lsp_request_document_result(LspResultSlot::FoldingRanges, |lsp| {
            lsp.request_folding_ranges()
        })
    }

    pub fn lsp_take_last_folding_ranges_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::FoldingRanges)
    }

    pub fn lsp_request_selection_range(&mut self, positions_json: &str) -> Result<u64, UiError> {
        let positions = parse_lsp_position_list_json(positions_json)?;
        self.lsp_request_with_line_index_result(LspResultSlot::SelectionRange, |lsp, line_index| {
            lsp.request_selection_range(line_index, &positions)
        })
    }

    pub fn lsp_take_last_selection_range_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::SelectionRange)
    }

    pub fn lsp_request_linked_editing_range(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::LinkedEditingRange,
            line,
            column,
            |lsp, line_index, line, column| {
                lsp.request_linked_editing_range(line_index, line, column)
            },
        )
    }

    pub fn lsp_take_last_linked_editing_range_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::LinkedEditingRange)
    }

    pub fn lsp_request_document_diagnostic(
        &mut self,
        previous_result_id: Option<&str>,
    ) -> Result<u64, UiError> {
        self.lsp_request_document_result(LspResultSlot::DocumentDiagnostic, |lsp| {
            lsp.request_document_diagnostic(previous_result_id.map(str::to_string))
        })
    }

    pub fn lsp_take_last_document_diagnostic_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::DocumentDiagnostic)
    }

    pub fn lsp_request_workspace_diagnostic(
        &mut self,
        previous_result_ids_json: &str,
    ) -> Result<u64, UiError> {
        let previous_result_ids = parse_lsp_json_array(
            previous_result_ids_json,
            "workspace diagnostic previousResultIds",
        )?;
        self.lsp_request_document_result(LspResultSlot::WorkspaceDiagnostic, |lsp| {
            lsp.request_workspace_diagnostic(previous_result_ids)
        })
    }

    pub fn lsp_take_last_workspace_diagnostic_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::WorkspaceDiagnostic)
    }

    pub fn lsp_request_document_color(&mut self) -> Result<u64, UiError> {
        self.lsp_request_document_result(LspResultSlot::DocumentColor, |lsp| {
            lsp.request_document_color()
        })
    }

    pub fn lsp_take_last_document_color_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::DocumentColor)
    }

    pub fn lsp_request_color_presentation(
        &mut self,
        start_offset: usize,
        end_offset: usize,
        color_json: &str,
    ) -> Result<u64, UiError> {
        let color: serde_json::Value =
            serde_json::from_str(color_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_with_line_index_result(
            LspResultSlot::ColorPresentation,
            |lsp, line_index| {
                let range = lsp.lsp_range_for_editor_offsets(line_index, start_offset, end_offset);
                lsp.request_color_presentation(&range, color)
            },
        )
    }

    pub fn lsp_take_last_color_presentation_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::ColorPresentation)
    }

    pub fn lsp_request_prepare_call_hierarchy(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::PrepareCallHierarchy,
            line,
            column,
            |lsp, line_index, line, column| {
                lsp.request_prepare_call_hierarchy(line_index, line, column)
            },
        )
    }

    pub fn lsp_take_last_prepare_call_hierarchy_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::PrepareCallHierarchy)
    }

    pub fn lsp_request_call_hierarchy_incoming_calls(
        &mut self,
        item_json: &str,
    ) -> Result<u64, UiError> {
        let item: serde_json::Value =
            serde_json::from_str(item_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::CallHierarchyIncoming, |lsp| {
            lsp.request_call_hierarchy_incoming_calls(item)
        })
    }

    pub fn lsp_take_last_call_hierarchy_incoming_calls_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CallHierarchyIncoming)
    }

    pub fn lsp_request_call_hierarchy_outgoing_calls(
        &mut self,
        item_json: &str,
    ) -> Result<u64, UiError> {
        let item: serde_json::Value =
            serde_json::from_str(item_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::CallHierarchyOutgoing, |lsp| {
            lsp.request_call_hierarchy_outgoing_calls(item)
        })
    }

    pub fn lsp_take_last_call_hierarchy_outgoing_calls_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CallHierarchyOutgoing)
    }

    pub fn lsp_request_prepare_type_hierarchy(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::PrepareTypeHierarchy,
            line,
            column,
            |lsp, line_index, line, column| {
                lsp.request_prepare_type_hierarchy(line_index, line, column)
            },
        )
    }

    pub fn lsp_take_last_prepare_type_hierarchy_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::PrepareTypeHierarchy)
    }

    pub fn lsp_request_type_hierarchy_supertypes(
        &mut self,
        item_json: &str,
    ) -> Result<u64, UiError> {
        let item: serde_json::Value =
            serde_json::from_str(item_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::TypeHierarchySupertypes, |lsp| {
            lsp.request_type_hierarchy_supertypes(item)
        })
    }

    pub fn lsp_take_last_type_hierarchy_supertypes_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::TypeHierarchySupertypes)
    }

    pub fn lsp_request_type_hierarchy_subtypes(&mut self, item_json: &str) -> Result<u64, UiError> {
        let item: serde_json::Value =
            serde_json::from_str(item_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::TypeHierarchySubtypes, |lsp| {
            lsp.request_type_hierarchy_subtypes(item)
        })
    }

    pub fn lsp_take_last_type_hierarchy_subtypes_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::TypeHierarchySubtypes)
    }

    pub(super) fn maybe_request_lsp_on_type_formatting(
        &mut self,
        ch: &str,
    ) -> Result<bool, UiError> {
        self.flush_lsp_did_change_from_delta();

        let (shared, doc_uri, line_index, line, column, options, request_version) = {
            let mut doc = self.lock_doc();
            let Some(shared) = doc.lsp.clone() else {
                return Ok(false);
            };
            let Some(doc_uri) = doc.lsp_document_uri.clone() else {
                doc.lsp_fail("LSP document URI missing");
                return Ok(false);
            };

            let line_index = doc
                .ws
                .buffer_line_index(doc.buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
                .clone();

            let pos = doc
                .ws
                .cursor_position_for_view(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;

            let indent_config = doc
                .ws
                .indentation_config_for_view(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            let tab_width = doc.ws.tab_width_for_view(self.view_id).unwrap_or(4);
            let options = editor_core_lsp::lsp_formatting_options_for_indentation_config(
                &indent_config,
                tab_width,
            );

            (
                shared,
                doc_uri,
                line_index,
                pos.line,
                pos.column,
                options,
                doc.text_version,
            )
        };

        let supports =
            match shared.with_session_mut(|lsp| Ok(lsp.supports_on_type_formatting_trigger(ch))) {
                Ok(v) => v,
                Err(reason) => {
                    let mut doc = self.lock_doc();
                    doc.lsp_fail(reason);
                    return Ok(false);
                }
            };
        if !supports {
            return Ok(false);
        }

        let request_id = match shared.with_session_mut(|lsp| {
            lsp.set_active_document(doc_uri.as_str())?;
            lsp.request_on_type_formatting(&line_index, line, column, ch.to_string(), options)
        }) {
            Ok(id) => id,
            Err(reason) => {
                let mut doc = self.lock_doc();
                doc.lsp_fail(reason);
                return Ok(false);
            }
        };

        let mut doc = self.lock_doc();
        doc.lsp_client_requests.insert(
            request_id,
            LspClientRequest::OnTypeFormatting {
                view: self.view_id,
                version: request_version,
            },
        );
        doc.lsp_latest_on_type_formatting_request_id
            .insert(self.view_id, request_id);

        Ok(true)
    }

    pub(super) fn maybe_apply_treesitter_indent_for_primary_caret_line(
        &mut self,
    ) -> Result<bool, UiError> {
        let applied = {
            let mut doc = self.lock_doc();
            if doc.treesitter_indenter.is_none() {
                return Ok(false);
            }

            let buffer_id = doc.buffer_id;
            let version = doc.text_version;
            let text = doc
                .ws
                .buffer_text(buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;

            let pos = doc
                .ws
                .cursor_position_for_view(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            let indent_config = doc
                .ws
                .indentation_config_for_view(self.view_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            let indent_style = indent_config.style;

            let Some(indenter) = doc.treesitter_indenter.as_mut() else {
                return Ok(false);
            };

            indenter
                .sync_to_text(version, text.as_str())
                .map_err(|e| UiError::Processor(e.to_string()))?;

            let Some(edit) = indenter.reindent_text_edit_for_line(pos.line, indent_style) else {
                return Ok(false);
            };

            doc.ws
                .apply_text_edits(vec![(buffer_id, vec![edit])])
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
            true
        };

        if applied {
            self.refresh_processing()?;
        }
        Ok(applied)
    }

    fn wait_lsp_text_edit_response_and_apply(
        &mut self,
        shared: &Arc<SharedLspSession>,
        request_id: u64,
        timeout_ms: u32,
        error_context: &str,
        buffer_id: BufferId,
    ) -> Result<bool, UiError> {
        let resp = shared
            .with_session_mut(|lsp| {
                lsp.wait_for_response(request_id, Duration::from_millis(timeout_ms as u64))
            })
            .map_err(UiError::Processor)?;

        if let Some(err) = resp.get("error") {
            return Err(UiError::Processor(format!("{error_context} failed: {err}")));
        }

        let result = resp
            .get("result")
            .cloned()
            .unwrap_or(serde_json::Value::Null);
        self.lsp_apply_text_edits_value(buffer_id, &result)
    }

    /// Format the active document via LSP (`textDocument/formatting`) and apply edits locally.
    ///
    /// This is a "turnkey" helper intended for editor commands (explicit user actions).
    /// It blocks for up to `timeout_ms` while waiting for the response.
    ///
    /// Returns `true` if any text edits were applied.
    pub fn lsp_format_document(
        &mut self,
        formatting_options_json: &str,
        timeout_ms: u32,
    ) -> Result<bool, UiError> {
        self.flush_lsp_did_change_from_delta();
        let options = parse_lsp_formatting_options(formatting_options_json)?;

        let (shared, doc_uri, buffer_id) = {
            let doc = self.lock_doc();
            let Some(shared) = doc.lsp.clone() else {
                return Err(UiError::Processor("LSP is not enabled".to_string()));
            };
            let Some(doc_uri) = doc.lsp_document_uri.clone() else {
                return Err(UiError::Processor("LSP document URI missing".to_string()));
            };
            (shared, doc_uri, doc.buffer_id)
        };

        // 1) Issue request.
        let request_id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri.as_str())?;
                lsp.request_formatting(options)
            })
            .map_err(UiError::Processor)?;

        self.wait_lsp_text_edit_response_and_apply(
            &shared,
            request_id,
            timeout_ms,
            "LSP formatting",
            buffer_id,
        )
    }

    /// Format a range in the active document via LSP (`textDocument/rangeFormatting`).
    ///
    /// Offsets are editor-core char offsets. The response is applied to the current buffer.
    pub fn lsp_format_range(
        &mut self,
        start_offset: usize,
        end_offset: usize,
        formatting_options_json: &str,
        timeout_ms: u32,
    ) -> Result<bool, UiError> {
        self.flush_lsp_did_change_from_delta();
        let options = parse_lsp_formatting_options(formatting_options_json)?;
        let (start_offset, end_offset) = if start_offset <= end_offset {
            (start_offset, end_offset)
        } else {
            (end_offset, start_offset)
        };

        let (shared, doc_uri, buffer_id, line_index) = {
            let doc = self.lock_doc();
            let Some(shared) = doc.lsp.clone() else {
                return Err(UiError::Processor("LSP is not enabled".to_string()));
            };
            let Some(doc_uri) = doc.lsp_document_uri.clone() else {
                return Err(UiError::Processor("LSP document URI missing".to_string()));
            };
            let line_index = doc
                .ws
                .buffer_line_index(doc.buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
                .clone();
            (shared, doc_uri, doc.buffer_id, line_index)
        };

        let request_id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri.as_str())?;
                lsp.request_range_formatting(&line_index, start_offset, end_offset, options)
            })
            .map_err(UiError::Processor)?;

        self.wait_lsp_text_edit_response_and_apply(
            &shared,
            request_id,
            timeout_ms,
            "LSP range formatting",
            buffer_id,
        )
    }

    /// Request on-type formatting via LSP (`textDocument/onTypeFormatting`) and apply edits.
    ///
    /// `line` and `column` are logical editor positions after the trigger character was inserted.
    pub fn lsp_format_on_type(
        &mut self,
        line: usize,
        column: usize,
        ch: &str,
        formatting_options_json: &str,
        timeout_ms: u32,
    ) -> Result<bool, UiError> {
        if ch.is_empty() {
            return Err(UiError::Processor(
                "LSP on-type formatting trigger is empty".to_string(),
            ));
        }

        self.flush_lsp_did_change_from_delta();
        let options = parse_lsp_formatting_options(formatting_options_json)?;

        let (shared, doc_uri, buffer_id, line_index) = {
            let doc = self.lock_doc();
            let Some(shared) = doc.lsp.clone() else {
                return Err(UiError::Processor("LSP is not enabled".to_string()));
            };
            let Some(doc_uri) = doc.lsp_document_uri.clone() else {
                return Err(UiError::Processor("LSP document URI missing".to_string()));
            };
            let line_index = doc
                .ws
                .buffer_line_index(doc.buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
                .clone();
            (shared, doc_uri, doc.buffer_id, line_index)
        };

        let supports = shared
            .with_session_mut(|lsp| Ok(lsp.supports_on_type_formatting_trigger(ch)))
            .map_err(UiError::Processor)?;
        if !supports {
            return Ok(false);
        }

        let request_id = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri.as_str())?;
                lsp.request_on_type_formatting(&line_index, line, column, ch.to_string(), options)
            })
            .map_err(UiError::Processor)?;

        self.wait_lsp_text_edit_response_and_apply(
            &shared,
            request_id,
            timeout_ms,
            "LSP on-type formatting",
            buffer_id,
        )
    }

    pub fn poll_processing(&mut self) -> Result<ProcessingPollResult, UiError> {
        let prefetch_char_range = self.treesitter_prefetch_char_range();
        let (treesitter_pending, latest_to_apply) = {
            let mut doc = self.lock_doc();
            if doc.treesitter.is_none() {
                drop(doc);
                let lsp_applied = self.poll_lsp_best_effort()?;
                return Ok(ProcessingPollResult {
                    applied: lsp_applied,
                    pending: self.lsp_is_enabled(),
                });
            }

            let mut latest: Option<(u64, Vec<ProcessingEdit>, TreeSitterUpdateMode)> = None;
            let mut need_full_sync = false;

            loop {
                let ev = {
                    let Some(worker) = doc.treesitter.as_mut() else {
                        return Err(UiError::Processor(
                            "tree-sitter worker missing during processing poll".to_string(),
                        ));
                    };
                    worker.rx.try_recv()
                };
                match ev {
                    Ok(TreeSitterWorkerEvent::Processed {
                        version,
                        edits,
                        update_mode,
                    }) => {
                        latest = Some((version, edits, update_mode));
                    }
                    Ok(TreeSitterWorkerEvent::NeedFullSync) => {
                        need_full_sync = true;
                    }
                    Ok(TreeSitterWorkerEvent::Error(msg)) => {
                        return Err(UiError::Processor(format!(
                            "tree-sitter worker error: {msg}"
                        )));
                    }
                    Err(mpsc::TryRecvError::Empty) => break,
                    Err(mpsc::TryRecvError::Disconnected) => {
                        return Err(UiError::Processor(
                            "tree-sitter worker disconnected".to_string(),
                        ));
                    }
                }
            }

            if need_full_sync {
                let text = doc
                    .ws
                    .buffer_text(doc.buffer_id)
                    .map_err(|e| UiError::Processor(format!("{e:?}")))?;
                doc.treesitter_doc_version = doc.treesitter_doc_version.saturating_add(1);
                let version = doc.treesitter_doc_version;
                let Some(worker) = doc.treesitter.as_mut() else {
                    return Err(UiError::Processor(
                        "tree-sitter worker missing during full sync".to_string(),
                    ));
                };
                worker.requested_version = Some(version);
                worker
                    .tx
                    .send(TreeSitterWorkerMsg::FullSync {
                        version,
                        text,
                        prefetch_char_range,
                    })
                    .map_err(|_| {
                        UiError::Processor("failed to full-sync tree-sitter worker".to_string())
                    })?;
            }

            let (requested, pending) = {
                let Some(worker) = doc.treesitter.as_ref() else {
                    return Err(UiError::Processor(
                        "tree-sitter worker missing after processing poll".to_string(),
                    ));
                };
                (worker.requested_version, worker.is_pending())
            };

            let to_apply = latest.and_then(|(version, edits, update_mode)| {
                if requested.is_some_and(|requested| version < requested) {
                    None
                } else {
                    Some((version, edits, update_mode))
                }
            });

            (pending, to_apply)
        };

        let mut treesitter_applied = false;
        if let Some((version, edits, update_mode)) = latest_to_apply {
            {
                let mut doc = self.lock_doc();
                doc.apply_processing_edits(edits)?;
                if let Some(worker) = doc.treesitter.as_mut() {
                    worker.applied_version = Some(version);
                    worker.last_update_mode = Some(update_mode);
                }
            }
            treesitter_applied = true;
        }

        let lsp_applied = self.poll_lsp_best_effort()?;

        Ok(ProcessingPollResult {
            applied: treesitter_applied || lsp_applied,
            pending: treesitter_pending || self.lsp_is_enabled(),
        })
    }

    pub fn treesitter_last_update_mode(&self) -> Option<TreeSitterUpdateMode> {
        let doc = self.lock_doc();
        doc.treesitter.as_ref().and_then(|w| w.last_update_mode)
    }

    pub fn treesitter_capture_for_style_id(&self, style_id: u32) -> Option<String> {
        let doc = self.lock_doc();
        doc.treesitter_capture_mapper
            .capture_for_style_id(style_id)
            .map(|s| s.to_string())
    }

    pub fn treesitter_style_id_for_capture(&mut self, capture_name: &str) -> u32 {
        let mut doc = self.lock_doc();
        doc.treesitter_capture_mapper
            .style_id_for_capture(capture_name)
    }

    pub fn lsp_apply_publish_diagnostics_json(&mut self, params_json: &str) -> Result<(), UiError> {
        let params_value: serde_json::Value =
            serde_json::from_str(params_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let notif = LspNotification::from_method_and_params(
            "textDocument/publishDiagnostics",
            &params_value,
        )
        .ok_or_else(|| UiError::Processor("invalid publishDiagnostics params".to_string()))?;

        let LspNotification::PublishDiagnostics(params) = notif else {
            return Err(UiError::Processor(
                "failed to parse publishDiagnostics params".to_string(),
            ));
        };

        let edits = self.with_line_index(|line_index| {
            lsp_diagnostics_to_processing_edits(line_index, &params)
        })?;
        self.apply_processing_edits(edits)?;
        Ok(())
    }

    pub fn lsp_apply_semantic_tokens(&mut self, data: &[u32]) -> Result<(), UiError> {
        let intervals = self.with_line_index(|line_index| {
            semantic_tokens_to_intervals(data, line_index, encode_semantic_style_id)
                .map_err(|e| UiError::Processor(e.to_string()))
        })??;
        self.apply_processing_edits([ProcessingEdit::ReplaceStyleLayer {
            layer: StyleLayerId::SEMANTIC_TOKENS,
            intervals,
        }])?;
        Ok(())
    }

    /// Apply an LSP `TextEdit[] | null` payload to the current buffer.
    ///
    /// This is primarily intended for applying LSP formatting results in a UI-friendly way.
    ///
    /// Returns `true` if any edits were applied.
    pub fn lsp_apply_text_edits_json(&mut self, text_edits_json: &str) -> Result<bool, UiError> {
        let value: serde_json::Value =
            serde_json::from_str(text_edits_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let buffer_id = {
            let doc = self.lock_doc();
            doc.buffer_id
        };
        self.lsp_apply_text_edits_value(buffer_id, &value)
    }

    fn lsp_apply_text_edits_value(
        &mut self,
        buffer_id: BufferId,
        value: &serde_json::Value,
    ) -> Result<bool, UiError> {
        let edits = text_edits_from_value(value);
        self.lsp_apply_lsp_text_edits(buffer_id, &edits)
    }

    pub fn lsp_apply_workspace_edit_json(
        &mut self,
        workspace_edit_json: &str,
        document_uri: Option<&str>,
    ) -> Result<String, UiError> {
        let value: serde_json::Value = serde_json::from_str(workspace_edit_json)
            .map_err(|e| UiError::Processor(e.to_string()))?;

        let (buffer_id, current_uri) = {
            let doc = self.lock_doc();
            let uri = document_uri
                .map(str::trim)
                .filter(|s| !s.is_empty())
                .map(str::to_string)
                .or_else(|| doc.lsp_document_uri.clone())
                .ok_or_else(|| UiError::Processor("document URI missing".to_string()))?;
            (doc.buffer_id, uri)
        };

        let by_uri = workspace_edit_text_edits(&value);
        let target_edits = by_uri
            .get(current_uri.as_str())
            .cloned()
            .unwrap_or_default();
        let applied = self.lsp_apply_lsp_text_edits(buffer_id, &target_edits)?;

        let mut skipped_uris = by_uri
            .keys()
            .filter(|uri| uri.as_str() != current_uri.as_str())
            .cloned()
            .collect::<Vec<_>>();
        skipped_uris.sort();

        let summary = summarize_workspace_edit(&value);
        let documents = summary
            .documents
            .into_iter()
            .map(|doc| {
                serde_json::json!({
                    "uri": doc.uri,
                    "edit_count": doc.edit_count,
                    "has_overlapping_edits": doc.has_overlapping_edits,
                })
            })
            .collect::<Vec<_>>();

        Ok(serde_json::json!({
            "applied": applied,
            "applied_uri": current_uri,
            "applied_edit_count": target_edits.len(),
            "skipped_uris": skipped_uris,
            "documents": documents,
        })
        .to_string())
    }

    fn lsp_apply_lsp_text_edits(
        &mut self,
        buffer_id: BufferId,
        edits: &[LspTextEdit],
    ) -> Result<bool, UiError> {
        if edits.is_empty() {
            return Ok(false);
        }

        {
            let mut doc = self.lock_doc();
            let line_index = doc
                .ws
                .buffer_line_index(buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;

            let mut specs = edits
                .iter()
                .map(|edit| {
                    let (start, end) = char_offsets_for_lsp_range(line_index, &edit.range);
                    editor_core::TextEditSpec {
                        start,
                        end,
                        text: edit.new_text.clone(),
                    }
                })
                .collect::<Vec<_>>();

            // Match `Workspace::apply_text_edits` behavior (descending by start).
            specs.sort_by_key(|e| std::cmp::Reverse(e.start));

            doc.ws
                .apply_text_edits(vec![(buffer_id, specs)])
                .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        }

        self.refresh_processing()?;
        self.ensure_primary_caret_visible_after_edit();
        Ok(true)
    }

    /// Apply LSP document highlight result payload (`DocumentHighlight[] | null`) as a style layer.
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/documentHighlight`.
    pub fn lsp_apply_document_highlights_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edit = self.with_line_index(|line_index| {
            lsp_document_highlights_to_processing_edit(line_index, &result_value)
        })?;
        self.apply_processing_edits([edit])?;
        Ok(())
    }

    /// Apply LSP document symbol result payload (`DocumentSymbol[] | SymbolInformation[] | null`).
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/documentSymbol`.
    pub fn lsp_apply_document_symbols_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edit = self.with_line_index(|line_index| {
            lsp_document_symbols_to_processing_edit(line_index, &result_value)
        })?;
        self.apply_processing_edits([edit])?;
        Ok(())
    }

    /// Apply LSP folding range result payload (`FoldingRange[] | null`) to core fold regions.
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/foldingRange`.
    pub fn lsp_apply_folding_ranges_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edit = folding_ranges_result_to_processing_edit(&result_value);
        self.apply_processing_edits([edit])?;
        Ok(())
    }

    /// Apply LSP inlay hints result payload (`InlayHint[] | null`) as decorations.
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/inlayHint`.
    pub fn lsp_apply_inlay_hints_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edit = self.with_line_index(|line_index| {
            lsp_inlay_hints_to_processing_edit(line_index, &result_value)
        })?;
        self.apply_processing_edits([edit])?;
        Ok(())
    }

    /// Apply LSP code lens result payload (`CodeLens[] | null`) as decorations.
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/codeLens`.
    pub fn lsp_apply_code_lens_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edit = self.with_line_index(|line_index| {
            lsp_code_lens_to_processing_edit(line_index, &result_value)
        })?;
        self.apply_processing_edits([edit])?;
        Ok(())
    }

    /// Apply LSP document links result payload (`DocumentLink[] | null`) as:
    /// - decorations (payload / click targets)
    /// - style intervals (rendering underline)
    ///
    /// The caller should pass the raw `result` JSON from `textDocument/documentLink`.
    pub fn lsp_apply_document_links_json(&mut self, result_json: &str) -> Result<(), UiError> {
        let result_value: serde_json::Value =
            serde_json::from_str(result_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let edits = self.with_line_index(|line_index| {
            lsp_document_links_to_processing_edits(line_index, &result_value)
        })?;
        self.apply_processing_edits(edits)?;
        Ok(())
    }

    pub(super) fn treesitter_prefetch_char_range(&mut self) -> Option<(usize, usize)> {
        let viewport = self.viewport_state();
        let lines = viewport.prefetch_lines;
        if lines.is_empty() {
            return None;
        }

        let start_visual = lines.start;
        let end_visual = lines.end.saturating_sub(1);

        let mut doc = self.lock_doc();
        let (start_line, _) = doc
            .ws
            .visual_to_logical_for_view(self.view_id, start_visual)
            .ok()?;
        let (end_line, _) = doc
            .ws
            .visual_to_logical_for_view(self.view_id, end_visual)
            .ok()?;
        let end_line_excl = end_line.saturating_add(1);

        let line_index = doc.ws.buffer_line_index(self.buffer_id).ok()?;
        let start = line_index.position_to_char_offset(start_line, 0);
        let end = line_index.position_to_char_offset(end_line_excl, 0);
        if end > start {
            Some((start, end))
        } else {
            None
        }
    }

    pub(super) fn refresh_processing(&mut self) -> Result<(), UiError> {
        let prefetch_char_range = self.treesitter_prefetch_char_range();
        let mut doc = self.lock_doc();
        let buffer_id = doc.buffer_id;

        if doc.sublime.is_some() {
            // Clone the line index to avoid keeping an immutable borrow of `doc.ws` alive while we
            // mutably borrow the processor.
            let line_index = doc
                .ws
                .buffer_line_index(buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
                .clone();
            let proc = doc
                .sublime
                .as_mut()
                .ok_or_else(|| UiError::Processor("sublime processor missing".to_string()))?;
            let edits = proc
                .compute_processing_edits(&line_index)
                .map_err(|e| UiError::Processor(e.to_string()))?;
            doc.apply_processing_edits(edits)?;
        }

        let delta = doc
            .ws
            .take_last_text_delta_for_buffer(buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;
        let Some(delta) = delta else {
            return Ok(());
        };
        if delta.is_empty() {
            return Ok(());
        }

        // Monotonic version for "text has changed" events (used to drop stale async results).
        doc.text_version = doc.text_version.saturating_add(1);

        if doc.treesitter.is_some() {
            doc.treesitter_doc_version = doc.treesitter_doc_version.saturating_add(1);
            let version = doc.treesitter_doc_version;
            if let Some(worker) = doc.treesitter.as_mut() {
                worker.requested_version = Some(version);
                worker
                    .tx
                    .send(TreeSitterWorkerMsg::ApplyDelta {
                        version,
                        delta: (*delta).clone(),
                        prefetch_char_range,
                    })
                    .map_err(|_| {
                        UiError::Processor("failed to send delta to tree-sitter worker".to_string())
                    })?;
            }
        }

        // Keep LSP (if enabled) in sync with incremental edits.
        if doc.lsp.is_some() {
            let Some(doc_uri) = doc.lsp_document_uri.clone() else {
                doc.lsp_fail("LSP document URI missing");
                return Ok(());
            };
            let Some(shared) = doc.lsp.clone() else {
                return Ok(());
            };

            let changes = {
                let Some(calc) = doc.lsp_delta_calc.as_mut() else {
                    doc.lsp_fail("LSP incremental sync state missing");
                    return Ok(());
                };
                Self::lsp_changes_for_text_delta(calc, delta.as_ref())
            };
            if changes.is_empty() {
                return Ok(());
            }

            if let Err(err) = shared.with_session_mut(|session| {
                session.set_active_document(doc_uri.as_str())?;
                session.did_change_many(changes)
            }) {
                doc.lsp_fail(err);
                return Ok(());
            }

            // Defer inlay hints / code lens refresh slightly to avoid spamming on rapid typing.
            doc.lsp_aux_refresh_due = Some(Instant::now() + Duration::from_millis(250));
        }
        Ok(())
    }

    fn flush_lsp_did_change_from_delta(&mut self) {
        let mut doc = self.lock_doc();
        let buffer_id = doc.buffer_id;
        let delta = doc
            .ws
            .take_last_text_delta_for_buffer(buffer_id)
            .unwrap_or_default();
        let Some(delta) = delta else {
            return;
        };
        if delta.is_empty() {
            return;
        }

        // Keep the UI-side monotonic text version consistent with `refresh_processing`.
        doc.text_version = doc.text_version.saturating_add(1);

        let Some(shared) = doc.lsp.clone() else {
            return;
        };
        let Some(doc_uri) = doc.lsp_document_uri.clone() else {
            doc.lsp_fail("LSP document URI missing");
            return;
        };

        let Some(calc) = doc.lsp_delta_calc.as_mut() else {
            doc.lsp_fail("LSP incremental sync state missing");
            return;
        };

        let changes = Self::lsp_changes_for_text_delta(calc, delta.as_ref());
        if changes.is_empty() {
            return;
        }

        if let Err(err) = shared.with_session_mut(|session| {
            session.set_active_document(doc_uri.as_str())?;
            session.did_change_many(changes)
        }) {
            doc.lsp_fail(err);
            return;
        }

        // Defer inlay hints / code lens refresh slightly to avoid spamming on rapid typing.
        doc.lsp_aux_refresh_due = Some(Instant::now() + Duration::from_millis(250));
    }

    fn lsp_changes_for_text_delta(
        calc: &mut DeltaCalculator,
        delta: &editor_core::delta::TextDelta,
    ) -> Vec<LspContentChange> {
        fn position_for_char_offset(calc: &DeltaCalculator, mut offset: usize) -> (usize, usize) {
            let line_count = calc.line_count().max(1);
            for line in 0..line_count {
                let text = calc.get_line(line).unwrap_or("");
                let len = text.chars().count();
                if offset <= len {
                    return (line, offset);
                }
                offset = offset.saturating_sub(len + 1);
            }

            let last_line = line_count.saturating_sub(1);
            let last_len = calc.get_line(last_line).unwrap_or("").chars().count();
            (last_line, last_len)
        }

        let mut out = Vec::<LspContentChange>::with_capacity(delta.edits.len());
        for edit in &delta.edits {
            let (start_line, start_char) = position_for_char_offset(calc, edit.start);
            let (end_line, end_char) = position_for_char_offset(calc, edit.end());
            let change = calc.calculate_replace_change(
                start_line,
                start_char,
                end_line,
                end_char,
                edit.inserted_text.as_str(),
            );
            calc.apply_change(&change);
            out.push(LspContentChange {
                range: change.range,
                text: change.text,
            });
        }
        out
    }

    fn poll_lsp_best_effort(&mut self) -> Result<bool, UiError> {
        let (shared, doc_uri) = {
            let mut doc = self.lock_doc();
            let Some(shared) = doc.lsp.clone() else {
                return Ok(false);
            };
            let Some(doc_uri) = doc.lsp_document_uri.clone() else {
                doc.lsp_fail("LSP document URI missing");
                return Ok(false);
            };
            (shared, doc_uri)
        };

        let mut applied = false;
        {
            let mut doc = self.lock_doc();
            let line_index = match doc.ws.buffer_line_index(doc.buffer_id) {
                Ok(idx) => idx,
                Err(_) => {
                    doc.lsp_fail("LSP buffer line index unavailable");
                    return Ok(false);
                }
            };
            let edits = match shared.with_session_mut(|session| {
                session.set_active_document(doc_uri.as_str())?;
                session.poll_edits_with_line_index(line_index)
            }) {
                Ok(edits) => edits,
                Err(reason) => {
                    doc.lsp_fail(reason);
                    return Ok(false);
                }
            };
            applied |= doc.apply_lsp_processing_edits(edits)?;
        }

        if let Err(err) = self.maybe_request_lsp_aux() {
            let mut doc = self.lock_doc();
            doc.lsp_fail(err.to_string());
            return Ok(false);
        }

        let events = match shared.with_session_mut(|session| Ok(session.drain_events())) {
            Ok(events) => events,
            Err(reason) => {
                let mut doc = self.lock_doc();
                doc.lsp_fail(reason);
                return Ok(false);
            }
        };
        applied |= self.handle_lsp_events(events)?;
        Ok(applied)
    }

    pub(crate) fn handle_lsp_events(&mut self, events: Vec<LspEvent>) -> Result<bool, UiError> {
        if events.is_empty() {
            return Ok(false);
        }

        let mut applied = false;
        // Avoid re-entrant locking: collect text edits while holding the doc lock and apply
        // them after releasing it.
        let mut on_type_formatting_results: Vec<serde_json::Value> = Vec::new();

        let mut doc = self.lock_doc();
        for ev in events {
            let LspEvent::Response(resp) = ev else {
                continue;
            };

            if let Some(slot) = LspResultSlot::from_response_method(resp.method.as_str()) {
                if let Some(LspClientRequest::Result {
                    view,
                    slot: request_slot,
                }) = doc.lsp_client_requests.remove(&resp.id)
                {
                    if request_slot != slot {
                        continue;
                    }
                    if doc.lsp_latest_result_request_id.get(&(view, slot)) != Some(&resp.id) {
                        continue;
                    }

                    if let Some(error) = resp.error {
                        if slot == LspResultSlot::CodeLens {
                            doc.lsp_code_lens_in_flight = false;
                        }
                        if let Some(json) = stored_lsp_error_result_json(slot, error) {
                            doc.lsp_last_result_json.insert((view, slot), json);
                        } else {
                            doc.lsp_last_result_json.remove(&(view, slot));
                        }
                        continue;
                    }

                    let result = resp.result.unwrap_or(serde_json::Value::Null);
                    match slot {
                        LspResultSlot::DocumentSymbols => {
                            let edit = match doc.ws.buffer_line_index(doc.buffer_id) {
                                Ok(line_index) => {
                                    lsp_document_symbols_to_processing_edit(line_index, &result)
                                }
                                Err(_) => {
                                    doc.lsp_fail("LSP buffer line index unavailable");
                                    return Ok(false);
                                }
                            };
                            applied |= doc.apply_lsp_processing_edits([edit])?;
                        }
                        LspResultSlot::FoldingRanges => {
                            let edit = folding_ranges_result_to_processing_edit(&result);
                            applied |= doc.apply_lsp_processing_edits([edit])?;
                        }
                        LspResultSlot::CodeLens => {
                            doc.lsp_code_lens_in_flight = false;
                            let edit = match doc.ws.buffer_line_index(doc.buffer_id) {
                                Ok(line_index) => {
                                    lsp_code_lens_to_processing_edit(line_index, &result)
                                }
                                Err(_) => {
                                    doc.lsp_fail("LSP buffer line index unavailable");
                                    return Ok(false);
                                }
                            };
                            applied |= doc.apply_lsp_processing_edits([edit])?;
                        }
                        _ => {}
                    }

                    if let Some(json) = stored_lsp_success_result_json(slot, result) {
                        doc.lsp_last_result_json.insert((view, slot), json);
                    } else {
                        doc.lsp_last_result_json.remove(&(view, slot));
                    }
                    continue;
                }
            }

            match resp.method.as_str() {
                "textDocument/inlayHint" => {
                    doc.lsp_inlay_in_flight = false;
                    let result = resp.result.unwrap_or(serde_json::Value::Null);
                    let edit = match doc.ws.buffer_line_index(doc.buffer_id) {
                        Ok(line_index) => lsp_inlay_hints_to_processing_edit(line_index, &result),
                        Err(_) => {
                            doc.lsp_fail("LSP buffer line index unavailable");
                            return Ok(false);
                        }
                    };
                    applied |= doc.apply_lsp_processing_edits([edit])?;
                }
                "textDocument/codeLens" => {
                    doc.lsp_code_lens_in_flight = false;
                    let result = resp.result.unwrap_or(serde_json::Value::Null);
                    let edit = match doc.ws.buffer_line_index(doc.buffer_id) {
                        Ok(line_index) => lsp_code_lens_to_processing_edit(line_index, &result),
                        Err(_) => {
                            doc.lsp_fail("LSP buffer line index unavailable");
                            return Ok(false);
                        }
                    };
                    applied |= doc.apply_lsp_processing_edits([edit])?;
                }
                "textDocument/documentLink" => {
                    doc.lsp_document_links_in_flight = false;
                    let result = resp.result.unwrap_or(serde_json::Value::Null);
                    let edits = match doc.ws.buffer_line_index(doc.buffer_id) {
                        Ok(line_index) => {
                            lsp_document_links_to_processing_edits(line_index, &result)
                        }
                        Err(_) => {
                            doc.lsp_fail("LSP buffer line index unavailable");
                            return Ok(false);
                        }
                    };
                    applied |= doc.apply_lsp_processing_edits(edits)?;
                }
                "textDocument/onTypeFormatting" => {
                    if let Some(LspClientRequest::OnTypeFormatting { view, version }) =
                        doc.lsp_client_requests.remove(&resp.id)
                    {
                        if doc.lsp_latest_on_type_formatting_request_id.get(&view) != Some(&resp.id)
                        {
                            continue;
                        }
                        if doc.text_version != version {
                            continue;
                        }
                        if let Some(error) = resp.error {
                            doc.lsp_fail(format!(
                                "LSP on-type formatting failed: {} (code {})",
                                error.message, error.code
                            ));
                            return Ok(false);
                        }

                        let result = resp.result.unwrap_or(serde_json::Value::Null);
                        if !result.is_null() {
                            on_type_formatting_results.push(result);
                        }
                    }
                }
                _ => {}
            }
        }

        drop(doc);
        for result in on_type_formatting_results {
            match self.lsp_apply_text_edits_value(self.buffer_id, &result) {
                Ok(did_apply) => {
                    if did_apply {
                        applied = true;
                    }
                }
                Err(_err) => {
                    let mut doc = self.lock_doc();
                    doc.lsp_fail(_err.to_string());
                    return Ok(false);
                }
            }
        }

        Ok(applied)
    }

    fn maybe_request_lsp_aux(&mut self) -> Result<(), UiError> {
        let (shared, doc_uri, allow_inlay, request_code_lens, request_document_links) = {
            let mut doc = self.lock_doc();
            let Some(due) = doc.lsp_aux_refresh_due else {
                return Ok(());
            };
            if Instant::now() < due {
                return Ok(());
            }
            doc.lsp_aux_refresh_due = None;

            let Some(shared) = doc.lsp.clone() else {
                return Ok(());
            };
            let Some(doc_uri) = doc.lsp_document_uri.clone() else {
                return Ok(());
            };

            let allow_inlay = !doc.lsp_inlay_in_flight;
            let request_code_lens = !doc.lsp_code_lens_in_flight;
            let request_document_links = !doc.lsp_document_links_in_flight;
            (
                shared,
                doc_uri,
                allow_inlay,
                request_code_lens,
                request_document_links,
            )
        };

        let inlay_range = if allow_inlay {
            self.treesitter_prefetch_char_range()
        } else {
            None
        };
        let request_inlay_range = inlay_range.and_then(|(start, end)| {
            if end > start {
                Some((start, end))
            } else {
                None
            }
        });

        let mut doc = self.lock_doc();
        let line_index = doc
            .ws
            .buffer_line_index(doc.buffer_id)
            .map_err(|e| UiError::Processor(format!("{e:?}")))?;

        shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri.as_str())?;

                // Inlay hints: prefer the viewport prefetch range (good UX + avoids huge payloads).
                if let Some((start, end)) = request_inlay_range {
                    lsp.request_inlay_hints(line_index, start, end)?;
                }

                if request_code_lens {
                    lsp.request_code_lens()?;
                }

                if request_document_links {
                    lsp.request_document_links()?;
                }

                Ok(())
            })
            .map_err(UiError::Processor)?;

        if request_inlay_range.is_some() {
            doc.lsp_inlay_in_flight = true;
        }
        if request_code_lens {
            doc.lsp_code_lens_in_flight = true;
        }
        if request_document_links {
            doc.lsp_document_links_in_flight = true;
        }

        Ok(())
    }
}
