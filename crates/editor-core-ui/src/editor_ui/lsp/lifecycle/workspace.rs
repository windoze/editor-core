use super::*;

impl EditorUi {
    pub fn lsp_did_change_workspace_folders_json(
        &mut self,
        added_json: &str,
        removed_json: &str,
    ) -> Result<(), UiError> {
        let added = parse_workspace_folders_json(added_json, "added")?;
        let removed = parse_workspace_folders_json(removed_json, "removed")?;
        let shared = {
            let doc = self.lock_doc();
            doc.lsp.clone()
        };
        let Some(shared) = shared else {
            return Err(UiError::Processor("LSP is not enabled".to_string()));
        };

        let added_for_session = added.clone();
        let removed_for_session = removed.clone();
        shared
            .with_session_mut(|lsp| {
                lsp.did_change_workspace_folders(added_for_session, removed_for_session)
            })
            .map_err(UiError::Processor)?;
        shared.update_root_aliases(&added, &removed);
        self.record_lsp_status_state_event();
        Ok(())
    }
}

fn parse_workspace_folders_json(raw: &str, label: &str) -> Result<Vec<serde_json::Value>, UiError> {
    let value: serde_json::Value =
        serde_json::from_str(raw).map_err(|err| UiError::Processor(err.to_string()))?;
    match value {
        serde_json::Value::Array(items) => Ok(items),
        _ => Err(UiError::Processor(format!(
            "workspace folder {label} payload must be a JSON array"
        ))),
    }
}
