use super::super::super::*;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
struct AuxRequest {
    slot: LspResultSlot,
    id: u64,
}

impl EditorUi {
    pub(super) fn maybe_request_lsp_aux(&mut self) -> Result<(), UiError> {
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

        let requests = shared
            .with_session_mut(|lsp| {
                lsp.set_active_document(doc_uri.as_str())?;
                let mut requests = Vec::<AuxRequest>::new();

                // Inlay hints: prefer the viewport prefetch range (good UX + avoids huge payloads).
                if let Some((start, end)) = request_inlay_range {
                    let id = lsp.request_inlay_hints(line_index, start, end)?;
                    requests.push(AuxRequest {
                        slot: LspResultSlot::InlayHints,
                        id,
                    });
                }

                if request_code_lens {
                    let id = lsp.request_code_lens()?;
                    requests.push(AuxRequest {
                        slot: LspResultSlot::CodeLens,
                        id,
                    });
                }

                if request_document_links {
                    let id = lsp.request_document_links()?;
                    requests.push(AuxRequest {
                        slot: LspResultSlot::DocumentLinks,
                        id,
                    });
                }

                Ok(requests)
            })
            .map_err(UiError::Processor)?;

        for request in requests {
            doc.track_lsp_result_request(self.view_id, request.slot, request.id);
            match request.slot {
                LspResultSlot::InlayHints => doc.lsp_inlay_in_flight = true,
                LspResultSlot::CodeLens => doc.lsp_code_lens_in_flight = true,
                LspResultSlot::DocumentLinks => doc.lsp_document_links_in_flight = true,
                _ => {}
            }
        }

        Ok(())
    }
}
