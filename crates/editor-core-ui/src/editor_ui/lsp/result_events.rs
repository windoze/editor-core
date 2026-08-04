use super::*;

impl EditorUi {
    pub fn lsp_result_events_latest_sequence(&self) -> u64 {
        let doc = self.lock_doc();
        doc.lsp_result_events_latest_sequence()
    }

    pub fn lsp_result_events_after(&self, after_sequence: u64) -> EditorLspResultEventsSnapshot {
        let doc = self.lock_doc();
        doc.lsp_result_events_after(after_sequence)
    }

    pub fn lsp_result_events_json(&self, after_sequence: u64) -> Result<String, UiError> {
        serde_json::to_string(&self.lsp_result_events_after(after_sequence))
            .map_err(|e| UiError::Processor(e.to_string()))
    }
}
