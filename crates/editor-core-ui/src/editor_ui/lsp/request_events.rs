use super::*;

impl EditorUi {
    pub fn lsp_request_events_latest_sequence(&self) -> u64 {
        let doc = self.lock_doc();
        doc.lsp_request_events_latest_sequence()
    }

    pub fn lsp_request_events_after(&self, after_sequence: u64) -> EditorLspRequestEventsSnapshot {
        let doc = self.lock_doc();
        doc.lsp_request_events_after(after_sequence)
    }

    pub fn lsp_request_events_json(&self, after_sequence: u64) -> Result<String, UiError> {
        serde_json::to_string(&self.lsp_request_events_after(after_sequence))
            .map_err(|e| UiError::Processor(e.to_string()))
    }

    pub fn lsp_cancel_request(&mut self, request_id: u64) -> Result<bool, UiError> {
        let shared = {
            let doc = self.lock_doc();
            if !doc.lsp_client_requests.contains_key(&request_id) {
                return Ok(false);
            }
            doc.lsp.clone()
        };

        let cancel_result = shared
            .map(|shared| shared.with_session_mut(|lsp| lsp.cancel_request(request_id)))
            .unwrap_or(Ok(()));

        let recorded = {
            let mut doc = self.lock_doc();
            doc.record_lsp_request_finished_without_response(
                request_id,
                EditorLspRequestEventStatus::Canceled,
            )
        };

        cancel_result.map_err(UiError::Processor)?;
        Ok(recorded)
    }

    pub fn lsp_mark_request_timed_out(&mut self, request_id: u64) -> bool {
        let mut doc = self.lock_doc();
        doc.record_lsp_request_finished_without_response(
            request_id,
            EditorLspRequestEventStatus::Timeout,
        )
    }
}
