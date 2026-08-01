use super::super::super::*;

impl EditorUi {
    pub(crate) fn treesitter_prefetch_char_range(&mut self) -> Option<(usize, usize)> {
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

    pub(crate) fn flush_lsp_did_change_from_delta(&mut self) {
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
}
