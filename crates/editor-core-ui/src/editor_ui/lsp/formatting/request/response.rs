use super::*;

impl EditorUi {
    pub(super) fn wait_lsp_text_edit_response_and_apply(
        &mut self,
        shared: &Arc<SharedLspSession>,
        request_id: u64,
        timeout_ms: u32,
        error_context: &str,
        buffer_id: BufferId,
    ) -> Result<bool, UiError> {
        let resp = shared
            .with_session_mut(|lsp| {
                lsp.wait_for_response(request_id, Duration::from_millis(timeout_ms as u64))
            })
            .map_err(UiError::Processor)?;

        if let Some(err) = resp.get("error") {
            return Err(UiError::Processor(format!("{error_context} failed: {err}")));
        }

        let result = resp
            .get("result")
            .cloned()
            .unwrap_or(serde_json::Value::Null);
        self.lsp_apply_text_edits_value(buffer_id, &result)
    }
}
