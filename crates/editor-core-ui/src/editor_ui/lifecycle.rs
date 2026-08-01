use super::*;

impl Drop for EditorUi {
    fn drop(&mut self) {
        let is_last_handle = Arc::strong_count(&self.doc) == 1;
        let mut doc = self.doc.lock().unwrap_or_else(|e| e.into_inner());

        if is_last_handle {
            if doc.lsp.is_some() {
                doc.lsp_disable();
            }
        } else {
            doc.lsp_clear_result_state_for_view(self.view_id);
            doc.lsp_latest_on_type_formatting_request_id
                .remove(&self.view_id);
        }

        let _ = doc.ws.close_view(self.view_id);
    }
}
