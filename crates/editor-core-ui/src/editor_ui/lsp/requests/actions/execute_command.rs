use super::*;

impl EditorUi {
    pub fn lsp_request_execute_command(&mut self, command_json: &str) -> Result<u64, UiError> {
        let value: serde_json::Value =
            serde_json::from_str(command_json).map_err(|e| UiError::Processor(e.to_string()))?;
        let command = value
            .get("command")
            .and_then(serde_json::Value::as_str)
            .filter(|s| !s.trim().is_empty())
            .ok_or_else(|| UiError::Processor("workspace command missing".to_string()))?;
        let arguments = value
            .get("arguments")
            .and_then(serde_json::Value::as_array)
            .cloned()
            .unwrap_or_default();
        let command = command.to_string();

        self.lsp_request_document_result(LspResultSlot::ExecuteCommand, |lsp| {
            lsp.request_execute_command(command, arguments)
        })
    }

    pub fn lsp_take_last_execute_command_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::ExecuteCommand)
    }
}
