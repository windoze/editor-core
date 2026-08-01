use super::super::super::*;

impl EditorUi {
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
}
