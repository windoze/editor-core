use super::*;

impl EditorUi {
    pub(crate) fn maybe_request_lsp_on_type_formatting(
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

    pub(crate) fn maybe_apply_treesitter_indent_for_primary_caret_line(
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
}
