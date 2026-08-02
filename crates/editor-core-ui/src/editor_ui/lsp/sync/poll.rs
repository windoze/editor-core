use super::super::super::*;

impl EditorUi {
    pub(crate) fn poll_lsp_best_effort(&mut self) -> Result<bool, UiError> {
        let (shared, doc_uri) = {
            let doc = self.lock_doc();
            let Some(shared) = doc.lsp.clone() else {
                return Ok(false);
            };
            (shared, doc.lsp_document_uri.clone())
        };
        let Some(doc_uri) = doc_uri else {
            self.fail_lsp_and_record_status("LSP document URI missing");
            return Ok(false);
        };

        let mut applied = false;
        {
            let mut doc = self.lock_doc();
            let line_index = match doc.ws.buffer_line_index(doc.buffer_id) {
                Ok(idx) => idx,
                Err(_) => {
                    drop(doc);
                    self.fail_lsp_and_record_status("LSP buffer line index unavailable");
                    return Ok(false);
                }
            };
            let edits = match shared.with_session_mut(|session| {
                session.set_active_document(doc_uri.as_str())?;
                session.poll_edits_with_line_index(line_index)
            }) {
                Ok(edits) => edits,
                Err(reason) => {
                    drop(doc);
                    self.fail_lsp_and_record_status(reason);
                    return Ok(false);
                }
            };
            match doc.apply_lsp_processing_edits(self.view_id, edits) {
                Ok(value) => applied |= value,
                Err(err) => {
                    drop(doc);
                    self.record_lsp_status_state_event();
                    return Err(err);
                }
            }
        }

        if let Err(err) = self.maybe_request_lsp_aux() {
            self.fail_lsp_and_record_status(err.to_string());
            return Ok(false);
        }

        let events = match shared.with_session_mut(|session| Ok(session.drain_events())) {
            Ok(events) => events,
            Err(reason) => {
                self.fail_lsp_and_record_status(reason);
                return Ok(false);
            }
        };
        applied |= self.handle_lsp_events(events)?;
        Ok(applied)
    }
}
