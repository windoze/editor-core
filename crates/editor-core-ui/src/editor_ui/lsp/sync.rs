use super::*;

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

    pub(crate) fn poll_lsp_best_effort(&mut self) -> Result<bool, UiError> {
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
