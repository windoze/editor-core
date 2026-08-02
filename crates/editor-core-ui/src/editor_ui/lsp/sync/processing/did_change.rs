use crate::*;

impl EditorUi {
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
        doc.record_state_event_from_text_changed(self.view_id);
        doc.record_state_event_from_derived_state_stale_if_needed(self.view_id, "text_changed");

        let Some(shared) = doc.lsp.clone() else {
            return;
        };
        let Some(doc_uri) = doc.lsp_document_uri.clone() else {
            doc.fail_lsp_and_record_status(self.view_id, "LSP document URI missing");
            return;
        };

        let Some(calc) = doc.lsp_delta_calc.as_mut() else {
            doc.fail_lsp_and_record_status(self.view_id, "LSP incremental sync state missing");
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
            doc.fail_lsp_and_record_status(self.view_id, err);
            return;
        }

        // Defer inlay hints / code lens refresh slightly to avoid spamming on rapid typing.
        doc.lsp_aux_refresh_due = Some(Instant::now() + Duration::from_millis(250));
    }
}
