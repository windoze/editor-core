use super::super::super::*;

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
