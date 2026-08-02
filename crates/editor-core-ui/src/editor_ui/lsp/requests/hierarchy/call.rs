use super::super::super::*;

impl EditorUi {
    pub fn lsp_request_prepare_call_hierarchy(
        &mut self,
        line: usize,
        column: usize,
    ) -> Result<u64, UiError> {
        self.lsp_request_position_result(
            LspResultSlot::PrepareCallHierarchy,
            line,
            column,
            |lsp, line_index, line, column| {
                lsp.request_prepare_call_hierarchy(line_index, line, column)
            },
        )
    }

    pub fn lsp_take_last_prepare_call_hierarchy_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::PrepareCallHierarchy)
    }

    pub fn lsp_request_call_hierarchy_incoming_calls(
        &mut self,
        item_json: &str,
    ) -> Result<u64, UiError> {
        let item: serde_json::Value =
            serde_json::from_str(item_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::CallHierarchyIncoming, |lsp| {
            lsp.request_call_hierarchy_incoming_calls(item)
        })
    }

    pub fn lsp_take_last_call_hierarchy_incoming_calls_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CallHierarchyIncoming)
    }

    pub fn lsp_request_call_hierarchy_outgoing_calls(
        &mut self,
        item_json: &str,
    ) -> Result<u64, UiError> {
        let item: serde_json::Value =
            serde_json::from_str(item_json).map_err(|e| UiError::Processor(e.to_string()))?;
        self.lsp_request_document_result(LspResultSlot::CallHierarchyOutgoing, |lsp| {
            lsp.request_call_hierarchy_outgoing_calls(item)
        })
    }

    pub fn lsp_take_last_call_hierarchy_outgoing_calls_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::CallHierarchyOutgoing)
    }
}
