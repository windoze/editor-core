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

        shared
            .with_session_mut(|lsp| lsp.did_change_workspace_folders(added, removed))
            .map_err(UiError::Processor)
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
