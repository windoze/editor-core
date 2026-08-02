use super::*;

mod capabilities;

use capabilities::{default_initialize_params, default_workspace_folders};

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
        let initial_text = {
            let mut doc = self.lock_doc();
            doc.lsp_last_cmd = Some(cmd.to_string());
            doc.lsp_last_error = None;
            if doc.lsp.is_some() {
                doc.lsp_disable();
            }
            let _ =
                doc.apply_processing_edits_without_state_event(editor_core_lsp::lsp_clear_edits());
            doc.ws
                .buffer_text(doc.buffer_id)
                .map_err(|e| UiError::Processor(format!("{e:?}")))?
        };

        let workspace_folders = default_workspace_folders(root_uri);
        let init_params = default_initialize_params(root_uri);

        let mut cmd_proc = std::process::Command::new(cmd);
        cmd_proc.args(args);
        cmd_proc.stderr(Stdio::null());

        let start = LspSessionStartOptions {
            cmd: cmd_proc,
            workspace_folders,
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
}
