use super::*;

impl EditorUi {
    pub fn lsp_request_document_diagnostic(
        &mut self,
        previous_result_id: Option<&str>,
    ) -> Result<u64, UiError> {
        self.lsp_request_document_result(LspResultSlot::DocumentDiagnostic, |lsp| {
            lsp.request_document_diagnostic(previous_result_id.map(str::to_string))
        })
    }

    pub fn lsp_take_last_document_diagnostic_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::DocumentDiagnostic)
    }

    pub fn lsp_request_workspace_diagnostic(
        &mut self,
        previous_result_ids_json: &str,
    ) -> Result<u64, UiError> {
        let previous_result_ids = parse_lsp_json_array(
            previous_result_ids_json,
            "workspace diagnostic previousResultIds",
        )?;
        self.lsp_request_document_result(LspResultSlot::WorkspaceDiagnostic, |lsp| {
            lsp.request_workspace_diagnostic(previous_result_ids)
        })
    }

    pub fn lsp_take_last_workspace_diagnostic_result_json(&mut self) -> Option<String> {
        self.lsp_take_last_result_json(LspResultSlot::WorkspaceDiagnostic)
    }
}
