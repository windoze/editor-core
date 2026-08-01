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
}
