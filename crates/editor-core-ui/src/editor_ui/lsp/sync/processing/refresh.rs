use crate::*;

impl EditorUi {
    pub(crate) fn refresh_processing(&mut self) -> Result<(), UiError> {
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
        doc.record_state_event_from_text_changed(self.view_id);

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
}
